import Foundation

/// Unix domain socket server for receiving messages from the bridge binary
final class SocketServer {
    static let shared = SocketServer()

    private let socketPath: String
    private var serverFd: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.notchagent.socket", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "com.notchagent.socket.clients", qos: .userInitiated, attributes: .concurrent)
    var onMessage: ((SocketMessage) -> Void)?

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = supportDir.appendingPathComponent("NotchAgent")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.socketPath = appDir.appendingPathComponent("notch.sock").path
    }

    func start() {
        guard !isRunning else { return }
        // Remove stale socket
        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            print("[SocketServer] Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let raw = UnsafeMutableRawPointer(sunPath)
                raw.copyMemory(from: ptr, byteCount: min(socketPath.utf8.count, 104))
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            print("[SocketServer] Bind failed: \(errno)")
            return
        }

        listen(serverFd, 10)
        isRunning = true
        print("[SocketServer] Listening on \(socketPath)")

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if serverFd >= 0 { close(serverFd) }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFd, sockPtr, &clientLen)
                }
            }
            guard clientFd >= 0 else { continue }

            clientQueue.async { [weak self] in
                self?.handleClient(fd: clientFd)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }
        var buffer = Data()
        let chunkSize = 4096
        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { chunk.deallocate() }

        while true {
            let bytesRead = read(fd, chunk, chunkSize)
            if bytesRead <= 0 { break }
            buffer.append(chunk, count: bytesRead)

            // Try to parse newline-delimited JSON messages
            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let messageData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                let raw = String(data: messageData, encoding: .utf8) ?? "<invalid>"
                print("[SocketServer] Raw message: \(raw.prefix(200))")

                do {
                    let msg = try JSONDecoder().decode(SocketMessage.self, from: messageData)
                    print("[SocketServer] Parsed: type=\(msg.type.rawValue)")
                    DispatchQueue.main.async { [weak self] in
                        self?.onMessage?(msg)
                    }
                } catch {
                    print("[SocketServer] Decode error: \(error)")
                }
            }
        }
    }

    /// Send a response back through a new connection (for approval responses)
    func sendResponse(_ message: SocketMessage, toSessionSocket path: String) {
        queue.async {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return }
            defer { close(fd) }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            path.withCString { ptr in
                withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                    let raw = UnsafeMutableRawPointer(sunPath)
                    raw.copyMemory(from: ptr, byteCount: min(path.utf8.count, 104))
                }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connectResult == 0 else { return }

            if let data = try? JSONEncoder().encode(message) {
                var payload = data
                payload.append(0x0A) // newline delimiter
                payload.withUnsafeBytes { ptr in
                    _ = write(fd, ptr.baseAddress!, ptr.count)
                }
            }
        }
    }
}
