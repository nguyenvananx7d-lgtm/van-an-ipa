import Foundation
import Network

/// Serves a generated `.mobileconfig` to Safari over a loopback HTTP socket.
///
/// iOS installs configuration profiles by *downloading* them in Safari;
/// `UIApplication.open` on a `file://` URL does not start the profile flow.
/// A `127.0.0.1` listener is the only entitlement-free way to hand Safari the
/// bytes. The socket is closed as soon as the serving window ends.
final class LoopbackProfileServer {
    private let queue = DispatchQueue(label: "com.vortexarena.dns.profile")
    private let lock = NSLock()

    private var listener: NWListener?
    private var payload = Data()
    private var generation = 0
    private var finished = false

    /// Starts a fresh listener. The completion runs exactly once, on an
    /// arbitrary queue; callers hop back to the main actor themselves.
    func start(payload: Data, completion: @escaping (Result<UInt16, Error>) -> Void) {
        stop()

        lock.lock()
        generation += 1
        let gen = generation
        self.payload = payload
        finished = false
        lock.unlock()

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)

            let listener = try NWListener(using: params)
            lock.lock()
            self.listener = listener
            lock.unlock()

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.finish(.success(self.listener?.port?.rawValue ?? 0),
                                generation: gen,
                                completion: completion)
                case .failed(let error):
                    self.finish(.failure(error), generation: gen, completion: completion)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.start(queue: queue)
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        lock.lock()
        let current = listener
        listener = nil
        lock.unlock()
        current?.cancel()
    }

    // MARK: - serving

    private func finish(
        _ result: Result<UInt16, Error>,
        generation gen: Int,
        completion: @escaping (Result<UInt16, Error>) -> Void
    ) {
        lock.lock()
        let current = gen == generation
        let alreadyDone = finished
        if current && !alreadyDone { finished = true }
        lock.unlock()

        guard current, !alreadyDone else { return }
        completion(result)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let path = request.split(separator: " ").dropFirst().first.map { String($0) } ?? "/"

            if path == "/" || path.hasSuffix(".mobileconfig") {
                self.respond(connection,
                             body: self.payload,
                             contentType: "application/x-apple-aspen-config")
            } else {
                let html = """
                <!doctype html><meta name="viewport" content="width=device-width">
                <body style="font: -apple-system; padding: 24px">
                <h2>Vortex Arena DNS Shield</h2>
                <p>Open <code>/VortexArena-DNS.mobileconfig</code> in Safari.</p>
                </body>
                """
                self.respond(connection,
                             body: Data(html.utf8),
                             contentType: "text/html; charset=utf-8")
            }
        }
    }

    private func respond(_ connection: NWConnection, body: Data, contentType: String) {
        var response = Data()
        response.append(Data("HTTP/1.1 200 OK\r\n".utf8))
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        if contentType.contains("apple-aspen-config") {
            response.append(Data("Content-Disposition: attachment; filename=\"VortexArena-DNS.mobileconfig\"\r\n".utf8))
        }
        response.append(Data("Cache-Control: no-store\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
