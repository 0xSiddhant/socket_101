//
//  ChatView.swift
//  socket_fe_ios
//
//  Created by Siddhant Kumar on 19/09/25.
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel = ChatViewModel()
    @State private var isScrolledToBottom: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.messages) { message in
                            ChatBubbleView(text: message.text, isCurrentUser: message.isCurrentUser)
                                .id(message.id)
                        }
                    }
                    .padding(.top, 8)
                }
                .onChange(of: viewModel.messages.count, { _, _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                })
            }

            Divider()

            inputBar
        }
        .onAppear {
            viewModel.connect()
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
            Button(action: viewModel.sendMessage) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color.blue)
                    .clipShape(Capsule())
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ChatView()
}
