import Foundation

class HookServer {
    /// Preferred port. Claude Code's hook config stores an absolute URL, so the
    /// app tries hard to come back on the same port every launch.
    static let preferredPort: UInt16 = 19280
    static let portRange = UInt16(19280)...UInt16(19289)

    private let onEvent: (HookEvent, HookConnection) -> Void
    private let onStatusLine: (StatusLinePayload) -> Void
    private let portRange: ClosedRange<UInt16>
    private let portFileURL: URL
    private(set) var port: UInt16 = HookServer.preferredPort
    private var serverSocket: Int32 = -1
    private var running = false
    private let serverQueue = DispatchQueue(label: "ccani.server", qos: .userInitiated)

    static let defaultPortFileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".ccani/port")

    init(
        portRange: ClosedRange<UInt16> = HookServer.portRange,
        portFileURL: URL = HookServer.defaultPortFileURL,
        onEvent: @escaping (HookEvent, HookConnection) -> Void,
        onStatusLine: @escaping (StatusLinePayload) -> Void = { _ in }
    ) {
        self.portRange = portRange
        self.portFileURL = portFileURL
        self.onEvent = onEvent
        self.onStatusLine = onStatusLine
    }

    func start() throws {
        // Check if another ccani instance is already running
        if let existingPort = readExistingPortFile(), isPortListening(existingPort) {
            throw ServerError.anotherInstanceRunning(port: existingPort)
        }

        // Try to bind to a port in range
        for candidatePort in portRange {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { continue }

            var yes: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = candidatePort.bigEndian
            addr.sin_addr.s_addr = UInt32(0x7f000001).bigEndian // 127.0.0.1

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if bindResult != 0 {
                close(sock)
                continue
            }

            if listen(sock, 128) != 0 {
                close(sock)
                continue
            }

            self.serverSocket = sock
            self.port = candidatePort
            Self.currentPort = candidatePort
            self.running = true
            writePortFile()

            print("ccani server listening on port \(candidatePort)")

            // Accept connections in background
            serverQueue.async { [weak self] in
                self?.acceptLoop()
            }
            return
        }
        throw ServerError.noAvailablePort
    }

    func stop() {
        running = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        removePortFile()
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while running {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientSock = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverSocket, sockPtr, &clientLen)
                }
            }

            guard clientSock >= 0 else {
                if !running { break }
                continue
            }

            // Handle each connection on a concurrent queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientSock)
            }
        }
    }

    private func handleClient(_ sock: Int32) {
        // Reads must not hang forever, but the *response* may be deferred
        // indefinitely (a permission prompt waits for the user), so the socket
        // is owned by HookConnection from here on.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let connection = HookConnection(sock: sock)

        guard let request = readRequest(sock) else {
            connection.respond(status: "400 Bad Request", body: "{}")
            return
        }

        // The status line is a separate feed: it is the only place Claude Code
        // reports account-wide rate limits and the context window size.
        if request.path == Self.statusLinePath {
            guard let payload = try? JSONDecoder().decode(StatusLinePayload.self, from: request.body) else {
                connection.respondPlainText("")
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.onStatusLine(payload)
            }
            // Pulse owns the status line, so it renders what Claude Code prints.
            connection.respondPlainText(StatusLineRenderer.render(payload))
            return
        }

        guard var event = try? JSONDecoder().decode(HookEvent.self, from: request.body) else {
            connection.respondEmpty()
            return
        }
        let origin = TerminalOrigin(headers: request.headers)
        event.origin = origin.isEmpty ? nil : origin

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                connection.respondEmpty()
                return
            }
            self.onEvent(event, connection)
        }
    }

    /// Where the wrapped `statusLine` command posts Claude Code's payload.
    static let statusLinePath = "/statusline"

    /// The port the running server bound to, for code that needs to write it
    /// into a script or config without holding the server itself.
    private(set) static var currentPort: UInt16?

    private struct ParsedRequest {
        let path: String
        let headers: [String: String]
        let body: Data
    }

    /// Reads a full HTTP request, honouring Content-Length so large
    /// `tool_input` payloads are not truncated across TCP segments.
    private func readRequest(_ sock: Int32) -> ParsedRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        var headerEnd: Range<Data.Index>?

        while headerEnd == nil {
            let n = buffer.withUnsafeMutableBytes { read(sock, $0.baseAddress!, 16384) }
            guard n > 0 else { return nil }
            data.append(contentsOf: buffer[0..<n])
            headerEnd = data.range(of: Data("\r\n\r\n".utf8))
            if data.count > 8 * 1024 * 1024 { return nil }
        }
        guard let headerEnd else { return nil }

        let headerText = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        let lines = headerText.split(separator: "\r\n")
        // "POST /statusline HTTP/1.1" — the middle field, query stripped.
        let path = lines.first?.split(separator: " ").dropFirst().first
            .map { String($0.split(separator: "?").first ?? "") } ?? "/"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        var body = data[headerEnd.upperBound...]
        if let lengthString = headers["content-length"], let contentLength = Int(lengthString) {
            while body.count < contentLength {
                let n = buffer.withUnsafeMutableBytes { read(sock, $0.baseAddress!, 16384) }
                guard n > 0 else { break }
                data.append(contentsOf: buffer[0..<n])
                body = data[headerEnd.upperBound...]
            }
            if body.count > contentLength {
                body = body.prefix(contentLength)
            }
        }
        return ParsedRequest(path: path, headers: headers, body: Data(body))
    }

    // MARK: - Single Instance Detection

    private func readExistingPortFile() -> UInt16? {
        let file = portFileURL
        guard let content = try? String(contentsOf: file, encoding: .utf8),
              let port = UInt16(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return port
    }

    private func isPortListening(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = UInt32(0x7f000001).bigEndian

        // Set connect timeout
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    // MARK: - Port File

    private func writePortFile() {
        let dir = portFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "\(port)".write(to: portFileURL, atomically: true, encoding: .utf8)
    }

    private func removePortFile() {
        try? FileManager.default.removeItem(at: portFileURL)
    }

    enum ServerError: Error, LocalizedError {
        case noAvailablePort
        case anotherInstanceRunning(port: UInt16)

        var errorDescription: String? {
            switch self {
            case .noAvailablePort:
                return "No available port in range 19280-19289"
            case .anotherInstanceRunning(let port):
                return "Another Pulse instance is already running on port \(port)"
            }
        }
    }
}
