import Foundation

class HookServer {
    private let onEvent: (HookEvent) -> Void
    private(set) var port: UInt16 = 19280
    private var serverSocket: Int32 = -1
    private var running = false
    private let serverQueue = DispatchQueue(label: "ccani.server", qos: .userInitiated)

    init(onEvent: @escaping (HookEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() throws {
        // Check if another ccani instance is already running
        if let existingPort = readExistingPortFile(), isPortListening(existingPort) {
            throw ServerError.anotherInstanceRunning(port: existingPort)
        }

        // Try to bind to a port in range
        for candidatePort in UInt16(19280)...UInt16(19289) {
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
        defer { close(sock) }

        // Set short read timeout
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Read request — curl sends everything in one go, so one read is enough
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = buffer.withUnsafeMutableBytes { ptr in
            read(sock, ptr.baseAddress!, 65536)
        }
        guard bytesRead > 0 else { return }

        let data = Data(buffer[0..<bytesRead])

        // Parse HTTP body
        var responseStr = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

        if let bodyRange = data.range(of: Data("\r\n\r\n".utf8)) {
            let body = data[bodyRange.upperBound...]
            if let event = try? JSONDecoder().decode(HookEvent.self, from: body) {
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent(event)
                }
                responseStr = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
            }
        }

        // Send response
        if let responseData = responseStr.data(using: .utf8) {
            responseData.withUnsafeBytes { ptr in
                _ = Foundation.write(sock, ptr.baseAddress!, responseData.count)
            }
        }
    }

    // MARK: - Single Instance Detection

    private func readExistingPortFile() -> UInt16? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ccani/port")
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
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ccani")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("port")
        try? "\(port)".write(to: file, atomically: true, encoding: .utf8)
    }

    private func removePortFile() {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ccani/port")
        try? FileManager.default.removeItem(at: file)
    }

    enum ServerError: Error, LocalizedError {
        case noAvailablePort
        case anotherInstanceRunning(port: UInt16)

        var errorDescription: String? {
            switch self {
            case .noAvailablePort:
                return "No available port in range 19280-19289"
            case .anotherInstanceRunning(let port):
                return "Another ccani instance is already running on port \(port)"
            }
        }
    }
}
