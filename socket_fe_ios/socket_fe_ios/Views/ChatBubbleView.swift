//
//  ChatBubbleView.swift
//  socket_fe_ios
//
//  Created by Siddhant Kumar on 19/09/25.
//

import SwiftUI

/// A chat bubble that mimics the iOS Messages style.
/// - Displays left-aligned gray bubbles for incoming messages.
/// - Displays right-aligned blue bubbles for the current user.
struct ChatBubbleView: View {
    let text: String
    let isCurrentUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser {
                Spacer(minLength: 24)
                bubble
            } else {
                bubble
                Spacer(minLength: 24)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var bubble: some View {
        Text(text)
            .font(.system(.body))
            .foregroundColor(isCurrentUser ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ChatBubbleShape(isCurrentUser: isCurrentUser)
                    .fill(isCurrentUser ? Color.blue : Color(UIColor.systemGray5))
            )
            .overlay(
                ChatBubbleShape(isCurrentUser: isCurrentUser)
                    .stroke(isCurrentUser ? Color.blue.opacity(0.8) : Color(UIColor.systemGray4), lineWidth: 0.5)
            )
            .frame(maxWidth: UIScreen.main.bounds.width * 0.66, alignment: isCurrentUser ? .trailing : .leading)
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
            .animation(.default, value: text)
            .accessibilityLabel(isCurrentUser ? "Outgoing message" : "Incoming message")
            .accessibilityValue(text)
    }
}

/// A rounded bubble with asymmetric corners to resemble iMessage bubbles.
struct ChatBubbleShape: Shape {
    let isCurrentUser: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Corner radii tuned to resemble iMessage bubbles.
        // Incoming (left): smaller radius on bottom-left (tail side)
        // Outgoing (right): smaller radius on bottom-right (tail side)
        let large: CGFloat = 16
        let small: CGFloat = 6

        let topLeft: CGFloat = large
        let topRight: CGFloat = large
        let bottomLeft: CGFloat = isCurrentUser ? large : small
        let bottomRight: CGFloat = isCurrentUser ? small : large

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        // Clamp radii so they don't exceed half of respective dimensions
        let width = rect.width
        let height = rect.height
        let tl = min(topLeft, min(width, height) / 2)
        let tr = min(topRight, min(width, height) / 2)
        let bl = min(bottomLeft, min(width, height) / 2)
        let br = min(bottomRight, min(width, height) / 2)

        // Start at top-left corner (after radius)
        path.move(to: CGPoint(x: minX + tl, y: minY))

        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: maxX - tr, y: minY))
        // Top-right corner arc
        path.addArc(
            center: CGPoint(x: maxX - tr, y: minY + tr),
            radius: tr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right edge to bottom-right corner
        path.addLine(to: CGPoint(x: maxX, y: maxY - br))
        // Bottom-right corner arc
        path.addArc(
            center: CGPoint(x: maxX - br, y: maxY - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: minX + bl, y: maxY))
        // Bottom-left corner arc
        path.addArc(
            center: CGPoint(x: minX + bl, y: maxY - bl),
            radius: bl,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Left edge to top-left corner
        path.addLine(to: CGPoint(x: minX, y: minY + tl))
        // Top-left corner arc
        path.addArc(
            center: CGPoint(x: minX + tl, y: minY + tl),
            radius: tl,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()

        return path
    }
}

struct ChatBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 2) {
            ChatBubbleView(text: "Hey! Are we still on for today?", isCurrentUser: false)
            ChatBubbleView(text: "Yes, see you at 5 PM.", isCurrentUser: true)
            ChatBubbleView(text: "Great!", isCurrentUser: false)
        }
        .background(Color(UIColor.systemBackground))
        .previewLayout(.sizeThatFits)
    }
}
