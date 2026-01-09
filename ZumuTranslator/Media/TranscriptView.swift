import SwiftUI
import LiveKit
import LiveKitComponents

/// Transcript display showing conversation history with translations
/// Matches the agent-starter-swift pattern for message display
struct TranscriptView: View {
    @EnvironmentObject var session: Session
    @Environment(\.translationConfig) var config

    // Pass messages as parameter to prevent mutex access during disconnect
    let messages: [ReceivedMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show only last 2 messages for cleaner, more readable UI
            ForEach(Array(messages.suffix(2).enumerated()), id: \.element.id) { index, message in
                TranscriptMessageView(
                    message: message,
                    config: config,
                    isOlder: index == 0 && messages.count > 1
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5 * .grid)  // 20pt (grid-based)
        .padding(.top, 8 * .grid)          // 32pt top padding (clear separation from state text)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Individual transcript message view - Ultra minimal with just color-coded text
private struct TranscriptMessageView: View {
    let message: ReceivedMessage
    let config: ZumuTranslator.TranslationConfig?
    let isOlder: Bool

    @State private var opacity: Double = 0
    @State private var offset: CGFloat = 10

    var body: some View {
        // Clean, high-contrast text - larger for better readability with wrapping
        Text(messageText)
            .font(.system(size: isOlder ? 14 : 17, weight: isOlder ? .regular : .medium))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(opacity)
            .offset(y: offset)
            .lineSpacing(5)
            .onAppear {
                // Smooth fade-in and slide-up animation
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 1.0
                    offset = 0
                }
            }
    }

    private var messageText: String {
        switch message.content {
        case .agentTranscript(let text):
            return text
        case .userTranscript(let text):
            return text
        case .userInput(let text):
            return text
        }
    }

    private var textColor: some ShapeStyle {
        switch message.content {
        case .agentTranscript:
            // AI responses - primary color with reduced opacity for older messages
            return isOlder ? AnyShapeStyle(.primary.opacity(0.4)) : AnyShapeStyle(.primary)
        case .userTranscript, .userInput:
            // User input - secondary color (slightly dimmer than AI)
            return isOlder ? AnyShapeStyle(.secondary.opacity(0.5)) : AnyShapeStyle(.secondary)
        }
    }
}

// MARK: - Preview

struct TranscriptView_Previews: PreviewProvider {
    static var previews: some View {
        // Create mock config
        let config = ZumuTranslator.TranslationConfig(
            driverName: "John",
            driverLanguage: "English",
            passengerName: "Maria",
            passengerLanguage: "Spanish"
        )

        // Create mock token source
        let tokenConfig = ZumuTokenSource.TranslationConfig(
            driverName: config.driverName,
            driverLanguage: config.driverLanguage,
            passengerName: config.passengerName,
            passengerLanguage: config.passengerLanguage
        )

        let tokenSource = ZumuTokenSource(
            apiKey: "preview-key",
            config: tokenConfig
        )

        // Create mock session
        let session = Session(tokenSource: tokenSource.cached())

        TranscriptView(messages: [])
            .environmentObject(session)
            .environment(\.translationConfig, config)
            .background(.black)
            .preferredColorScheme(.dark)
    }
}
