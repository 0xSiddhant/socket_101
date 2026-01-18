//
//  NWWebSocketClient.swift
//  socket_fe_ios
//
//  Created by Siddhant Kumar on 18/01/26.
//


import Foundation
import Network

final class NWWebSocketClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "nw.websocket.client.queue")
    
    // readiness + send queue to avoid sending before .ready
    private var isReady: Bool = false
    private var pendingSends: [(data: Data?, meta: NWProtocolWebSocket.Metadata, isFinal: Bool)] = []
    private let pendingSendsLock = DispatchQueue(label: "nw.websocket.pendingSends.lock")
    
    private let host: String
    private let port: UInt16

    init(host: String = "localhost", port: UInt16 = 3000) {
        self.host = host
        self.port = port
    }

    // MARK: - Connect / lifecycle

    func connect() {
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            print("❌ invalid port")
            return
        }

        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        // You can configure subprotocols / request path etc on wsOptions if needed (platform dependent)
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        connection = NWConnection(host: nwHost, port: nwPort, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .setup:
                print("NWWebSocket: setup")
            case .waiting(let error):
                self.isReady = false
                print("NWWebSocket: waiting — \(error)")
            case .preparing:
                print("NWWebSocket: preparing")
            case .ready:
                self.isReady = true
                print("✅ NWWebSocket: ready")
                self.flushPendingSends()
                self.receiveLoop()
            case .failed(let error):
                self.isReady = false
                print("❌ NWWebSocket: failed — \(error)")
                // consider reconnection/backoff here
            case .cancelled:
                self.isReady = false
                print("🔌 NWWebSocket: cancelled")
            @unknown default:
                print("NWWebSocket: unknown state")
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isReady = false
        pendingSendsLock.sync { pendingSends.removeAll() }
        print("🔌 disconnected")
    }

    // MARK: - Send helpers

    /// low-level send that always calls the Network framework send API correctly
    private func sendInternal(data: Data?, opcode: NWProtocolWebSocket.Opcode, isFinal: Bool = true) {
        guard let conn = connection else {
            print("❌ sendInternal: connection is nil")
            return
        }

        let meta = NWProtocolWebSocket.Metadata(opcode: opcode)
        let ctx = NWConnection.ContentContext(identifier: UUID().uuidString, metadata: [meta])

        // Important: use NWConnection.SendCompletion (.contentProcessed)
        conn.send(content: data, contentContext: ctx, isComplete: isFinal, completion: .contentProcessed({ [weak self] sendError in
            if let err = sendError {
                print("❌ send error (opcode=\(opcode)): \(err)")
                // optionally handle retry/backoff here
            } else {
                let size = data?.count ?? 0
                print("📤 sent (opcode=\(opcode)) bytes: \(size) (final:\(isFinal))")
                // you could notify caller via delegate/closure here
            }

            // If you want to enforce backpressure, you could wait for this completion
            // before sending the next queued fragment.
            self?.flushPendingSends()
        }))
    }

    /// queue or send immediately depending on readiness
    private func enqueueOrSend(data: Data?, meta: NWProtocolWebSocket.Metadata, isFinal: Bool) {
        pendingSendsLock.sync {
            if isReady {
                // send directly
                sendInternal(data: data, opcode: meta.opcode, isFinal: isFinal)
            } else {
                // queue for later when connection becomes ready
                pendingSends.append((data: data, meta: meta, isFinal: isFinal))
                print("⏳ queued send (opcode=\(meta.opcode), bytes=\(data?.count ?? 0))")
            }
        }
    }

    private func flushPendingSends() {
        // called when connection becomes ready or after a send completes
        pendingSendsLock.sync {
            guard isReady, let conn = connection else { return }
            while !pendingSends.isEmpty {
                let item = pendingSends.removeFirst()
                // send each queued item using the correct opcode and isFinal flag
                let meta = item.meta
                sendInternal(data: item.data, opcode: meta.opcode, isFinal: item.isFinal)
                // Note: this loop will call sendInternal many times quickly. If you need
                // strict backpressure, avoid sending next until completion; implement that.
            }
        }
    }

    // MARK: - Public send APIs

    func sendText(_ text: String) {
        let data = text.data(using: .utf8)
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        enqueueOrSend(data: data, meta: meta, isFinal: true)
    }

    func sendBinary(_ data: Data) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .binary)
        enqueueOrSend(data: data, meta: meta, isFinal: true)
    }

    /// Send ping control frame (optional payload allowed)
    func sendPing(payload: Data? = nil) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .ping)
        enqueueOrSend(data: payload, meta: meta, isFinal: true)
    }

    /// Send pong control frame (optional payload allowed)
    func sendPong(payload: Data? = nil) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .pong)
        enqueueOrSend(data: payload, meta: meta, isFinal: true)
    }

    // MARK: - Fragmented send (example)
    /// Fragment a large binary into multiple frames (first: .binary, middle: .cont, last: .cont with isFinal true)
    func sendLargeBinary(_ data: Data, chunkSize: Int = 16 * 1024) {
        guard data.count > 0 else { return }
        if data.count <= chunkSize {
            sendBinary(data)
            return
        }

        var offset = 0
        var isFirst = true
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let slice = data[offset..<end]
            let sliceData = Data(slice)
            let opcode: NWProtocolWebSocket.Opcode = isFirst ? .binary : .cont
            let isFinal = (end == data.count)
            let meta = NWProtocolWebSocket.Metadata(opcode: opcode)
            enqueueOrSend(data: sliceData, meta: meta, isFinal: isFinal)
            isFirst = false
            offset = end
            // For stronger backpressure, wait for .contentProcessed of each fragment before sending next
        }
    }

    // MARK: - Receive

    private func receiveLoop() {
        guard let conn = connection else {
            print("❌ receiveLoop: connection is nil")
            return
        }

        // receiveMessage yields logical websocket messages and associated metadata
        conn.receiveMessage { [weak self] data, context, isComplete, error in
            if let error = error {
                print("❌ receive error: \(error)")
                return
            }

            // Inspect metadata to determine opcode
            if let ctx = context,
               let wsMeta = ctx.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch wsMeta.opcode {
                case .text:
                    if let d = data, let text = String(data: d, encoding: .utf8) {
                        print("📥 received text: \(text)")
                    } else {
                        print("📥 received empty text frame")
                    }
                case .binary:
                    print("📥 received binary bytes: \(data?.count ?? 0)")
                case .ping:
                    print("📥 received ping -> sending pong")
                    self?.sendPong() // respond with pong
                case .pong:
                    print("📥 received pong")
                case .close:
                    print("📥 received close frame -> closing locally")
                    self?.close() // remote requested close
                case .cont:
                    print("📥 received continuation frame (cont)")
                default:
                    print("📥 received opcode: \(wsMeta.opcode)")
                }
            } else if let d = data, !d.isEmpty {
                // fallback: no metadata, treat as text if decodable
                if let text = String(data: d, encoding: .utf8) {
                    print("📥 received (no meta) text: \(text)")
                } else {
                    print("📥 received (no meta) binary: \(d.count) bytes")
                }
            } else {
                print("📥 received empty frame")
            }

            // Continue receiving next message unless connection closed
            // (If remote closed, above .connectionClose branch will call close())
            self?.receiveLoop()
        }
    }

    // MARK: - Close

    /// polite close: send close frame then cancel connection
    func close() {
        guard let conn = connection else {
            print("close: no connection")
            return
        }

        let closeMeta = NWProtocolWebSocket.Metadata(opcode: .close)
        let ctx = NWConnection.ContentContext(identifier: UUID().uuidString, metadata: [closeMeta])

        conn.send(content: nil, contentContext: ctx, isComplete: true, completion: .contentProcessed({ [weak conn] _ in
            // delay a bit to let the close frame be sent across the network
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                conn?.cancel()
            }
            print("🔌 sent close frame & cancelled")
        }))
    }
}


