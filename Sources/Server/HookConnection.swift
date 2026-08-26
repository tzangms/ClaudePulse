import Foundation

/// One in-flight hook request.
///
/// Claude Code's HTTP hooks read the response body as the hook's output, so the
/// socket is kept open until `respond` is called. Most events answer instantly
/// with `{}`; a permission prompt is answered when the user clicks a button.
final class HookConnection {
    /// Safety net so an unanswered request can never leak a file descriptor.
    static let hardTimeout: TimeInterval = 900

    private let sock: Int32
    private let lock = NSLock()
    private var responded = false

    init(sock: Int32) {
        self.sock = sock
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.hardTimeout) { [weak self] in
            self?.respondEmpty()
        }
    }

    /// Answer with no hook output — Claude Code proceeds as if no hook ran.
    func respondEmpty() {
        respond(body: "{}")
    }

    func respond(json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let body = String(data: data, encoding: .utf8) else {
            respondEmpty()
            return
        }
        respond(body: body)
    }

    /// The status line prints this reply verbatim, so it must not be JSON.
    func respondPlainText(_ text: String) {
        respond(contentType: "text/plain; charset=utf-8", body: text)
    }

    func respond(status: String = "200 OK", contentType: String = "application/json", body: String) {
        lock.lock()
        if responded {
            lock.unlock()
            return
        }
        responded = true
        lock.unlock()

        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(bodyData)
        out.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var sent = 0
            while sent < out.count {
                let n = Foundation.write(sock, base.advanced(by: sent), out.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
        close(sock)
    }
}
