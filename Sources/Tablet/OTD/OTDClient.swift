import Foundation

/// Minimal JSON-RPC client for the OpenTabletDriver daemon.
/// The daemon (StreamJsonRpc over a .NET named pipe) listens on the Unix socket
/// `$TMPDIR/CoreFxPipe_OpenTabletDriver.Daemon`; messages are framed with `Content-Length` headers.
enum OTDClient {
    static var socketPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("CoreFxPipe_OpenTabletDriver.Daemon")
    }

    /// True when a daemon accepts connections. Never blocks: a full listen queue (daemon busy) counts as running.
    static func isReachable() -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = socketPath
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { strcpy($0, path) }
        }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return r == 0 || errno == EAGAIN || errno == EINPROGRESS
    }

    /// Applies a complete settings object (the content of settings.json) to the running daemon.
    static func setSettings(_ settings: [String: Any]) -> Bool {
        (try? call("SetSettings", params: [settings])) != nil
    }

    /// Connected tablets as the daemon reports them (name, specifications, identifiers).
    static func tablets() -> [[String: Any]] {
        ((try? call("GetTablets", params: [])) as? [[String: Any]]) ?? []
    }

    // MARK: - transport

    struct RPCError: Error { var message: String }

    @discardableResult
    static func call(_ method: String, params: [Any], timeout: TimeInterval = 5) throws -> Any? {
        guard let fd = connect() else { throw RPCError(message: L("Ovladač neběží")) }
        defer { close(fd) }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let id = Int.random(in: 1...1_000_000)
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        var packet = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        packet.append(body)
        guard packet.withUnsafeBytes({ send(fd, $0.baseAddress, packet.count, 0) }) == packet.count else {
            throw RPCError(message: L("Nelze poslat zprávu ovladači"))
        }

        var buffer = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var chunk = [UInt8](repeating: 0, count: 65536)
        while Date() < deadline {
            // process every complete message already buffered (the daemon also pushes log notifications)
            while let (msg, rest) = takeMessage(buffer) {
                buffer = rest
                if let m = msg as? [String: Any], (m["id"] as? Int) == id {
                    if let e = m["error"] as? [String: Any] { throw RPCError(message: e["message"] as? String ?? L("Chyba ovladače")) }
                    return m["result"]
                }
            }
            let n = recv(fd, &chunk, chunk.count, 0)
            if n > 0 { buffer.append(chunk, count: n) }
            else if n == 0 { break }               // closed
        }
        throw RPCError(message: L("Ovladač neodpověděl"))
    }

    private static func takeMessage(_ buf: Data) -> (Any, Data)? {
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let header = String(decoding: buf[buf.startIndex..<sep.lowerBound], as: UTF8.self)
        guard let line = header.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length") }),
              let len = Int(line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") else { return nil }
        let start = sep.upperBound
        guard buf.distance(from: start, to: buf.endIndex) >= len else { return nil }
        let end = buf.index(start, offsetBy: len)
        let obj = (try? JSONSerialization.jsonObject(with: buf[start..<end])) ?? NSNull()
        return (obj, Data(buf[end...]))
    }

    private static func connect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = socketPath
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { close(fd); return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { strcpy($0, path) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        return fd
    }
}
