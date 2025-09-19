//
//  ChatClient.swift
//  socket_fe_ios
//
//  Created by Siddhant Kumar on 19/09/25.
//

import Foundation
import Network
import OSLog

class ChatClient {
    private let queue = DispatchQueue(label: "com.socket_fe_ios.nw.queue")
    private let logger = Logger(subsystem: "com.socket_fe_ios.nw.logger", category: "Socket")
    
    private let host: String
    private let port: UInt16
    
    private var connection: NWConnection?
    private var opCode: NWProtocolWebSocket.Opcode?
    public var onMessageReceiveCallback: ((String) -> Void)?
    
    init(host: String = "localhost", port: UInt16 = 3000) {
        self.host = host
        self.port = port
    }
    
    func connect() {
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: self.port) else {
            logger.error("Invalid port: \(self.port)")
            return
        }
        
        // Base TCP parameters
        let params = NWParameters.tcp
        // Insert WebSocket application protocol
        let wsOptions = NWProtocolWebSocket.Options()
        // If you need to set subprotocols or custom headers, configure wsOptions here (platform dependent).
        wsOptions.autoReplyPing = true
        let headers: [String: String] = ["platform": "iOS"]
        wsOptions.setAdditionalHeaders(headers.map {(name: $0, value: $1) })
        
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        connection = NWConnection(host: nwHost, port: nwPort, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("WebSocket connection ready")
                self?.receive()
            case .failed(let error):
                self?.logger.error("Failed to connect: \(error.localizedDescription)")
            case .setup:
                self?.logger.debug("Connection setup")
            case .waiting(_):
                self?.logger.debug("Connection waiting")
            case .preparing:
                self?.logger.debug("Connection preparing")
            case .cancelled:
                self?.logger.info("Connection cancelled")
            @unknown default:
                fatalError()
            }
        }
        connection?.start(queue: queue)
    }
    
    func send(_ content: Data) {
        guard let connection,
              let opCode else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: opCode)
        let context = NWConnection.ContentContext(identifier: UUID().uuidString, metadata: [meta])
        
        connection.send(content: content, contentContext: context, isComplete: true, completion: .contentProcessed({ [weak self] error in
            if let error {
                self?.logger.error("Send error: \(error.localizedDescription)")
            }
        }))
    }
    
    func receive() {
        connection?.receiveMessage { [weak self] data, context, isComplete, error in
            self?.logger.debug("Receive context - isFinal: \(context?.isFinal ?? false), isComplete: \(isComplete)")
            if let isFinal = context?.isFinal,
               isFinal,
               isComplete {
                self?.disconnect()
                return
            }
            if let error = error {
                self?.logger.error("NWWebSocket receive error: \(error.localizedDescription)")
                return
            }
            
            // Inspect metadata (opcode etc.)
            if let ctx = context,
               let wsMeta = ctx.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                self?.opCode = wsMeta.opcode
                switch wsMeta.opcode {
                case .text:
                    if let d = data, let text = String(data: d, encoding: .utf8) {
                        self?.logger.info("Received text message: \(text)")
                        self?.onMessageReceiveCallback?(text)
                    } else {
                        self?.logger.warning("Received empty text frame")
                    }
                case .binary:
                    self?.logger.info("Received binary message: \(data?.count ?? 0) bytes")
                case .ping:
                    self?.logger.debug("Received ping (responding with pong)")
                    self?.sendPong()
                case .pong:
                    self?.logger.debug("Received pong")
                case .close:
                    self?.logger.info("Received close frame — closing local")
                    self?.close() // server asked to close
                default:
                    self?.logger.debug("Received opcode: \(wsMeta.opcode.rawValue)")
                }
            } else if let d = data, !d.isEmpty {
                // If no metadata, attempt to treat as text
                if let text = String(data: d, encoding: .utf8) {
                    self?.logger.info("Received (no meta) text: \(text)")
                } else {
                    self?.logger.info("Received (no meta) binary: \(d.count) bytes")
                }
            } else {
                self?.logger.debug("Received empty frame")
            }
            
            // Continue receiving next message (unless connection closed)
            self?.receive()
        }
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
    }
    
    /// Close politely (send close frame then cancel)
    func close() {
        guard let connection else {
            logger.warning("Close: no connection")
            return
        }
        let closeMeta = NWProtocolWebSocket.Metadata(opcode: .close)
        let ctx = NWConnection.ContentContext(identifier: UUID().uuidString, metadata: [closeMeta])
        connection.send(content: nil, contentContext: ctx, isComplete: true, completion: .contentProcessed({ [weak self] error in
            self?.disconnect()
            self?.logger.info("NWWebSocket closed")
        }))
    }
    
    /// Send a pong (in response to ping)
    private func sendPong() {
        guard let conn = connection else { return }
        let wsMeta = NWProtocolWebSocket.Metadata(opcode: .pong)
        let ctx = NWConnection.ContentContext(identifier: UUID().uuidString, metadata: [wsMeta])
        conn.send(content: nil, contentContext: ctx, isComplete: true, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.logger.error("NWWebSocket pong send error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("Sent pong")
            }
        }))
    }
}
