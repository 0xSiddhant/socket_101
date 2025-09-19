//
//  ChatViewModel.swift
//  socket_fe_ios
//
//  Created by Siddhant Kumar on 19/09/25.
//

import Foundation
import Combine

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isCurrentUser: Bool
}

class ChatViewModel: ObservableObject {
    
    let chatClient = ChatClient()
    
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    
    func connect() {
        chatClient.connect()
        
        chatClient.onMessageReceiveCallback = { [weak self] value in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.messages.append(ChatMessage(text: value, isCurrentUser: false))
            }
        }
        
        // Start the first receive
        chatClient.receive()
    }
    
    func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        messages.append(ChatMessage(text: trimmed, isCurrentUser: true))
        if let data = trimmed.data(using: .utf8) {
            chatClient.send(data)
        }
        inputText = ""
    }
    
    func disconnect() {
        chatClient.disconnect()
    }
}
