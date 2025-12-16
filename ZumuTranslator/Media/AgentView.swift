import LiveKitComponents

/// A view that combines the avatar camera view (if available)
/// or the audio visualizer (if available).
/// - Note: If both are unavailable, the view will show a placeholder visualizer.
struct AgentView: View {
    @EnvironmentObject private var session: Session

    @Environment(\.namespace) private var namespace
    @Environment(\.translationConfig) private var translationConfig
    /// Reveals the avatar camera view when true.
    @SceneStorage("videoTransition") private var videoTransition = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(minHeight: 40) // Top spacing

            // Waveform visualization - moved higher
            ZStack {
            if let avatarVideoTrack = session.agent.avatarVideoTrack {
                SwiftUIVideoView(avatarVideoTrack)
                    .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusPerPlatform))
                    .aspectRatio(avatarVideoTrack.aspectRatio, contentMode: .fit)
                    .padding(.horizontal, session.agent.avatarVideoTrack?.aspectRatio == 1 ? 4 * .grid : .zero)
                    .shadow(radius: 20, y: 10)
                    .mask(
                        GeometryReader { proxy in
                            let targetSize = max(proxy.size.width, proxy.size.height)
                            Circle()
                                .frame(width: videoTransition ? targetSize : 6 * .grid)
                                .position(x: 0.5 * proxy.size.width, y: 0.5 * proxy.size.height)
                                .scaleEffect(2)
                                .animation(.smooth(duration: 1.5), value: videoTransition)
                        }
                    )
                    .onAppear {
                        videoTransition = true
                    }
            } else if let audioTrack = session.agent.audioTrack {
                // Clean, minimal waveform - professional proportions
                BarAudioVisualizer(audioTrack: audioTrack,
                                   agentState: session.agent.agentState ?? .listening,
                                   barCount: 5,
                                   barSpacingFactor: 0.08,
                                   barMinOpacity: 0.15)
                    .frame(maxWidth: .infinity, maxHeight: 240) // Reduced height
                    .padding(.horizontal, 60)
                    .transition(.opacity)
            } else if session.isConnected {
                // Placeholder waveform - matches agent view configuration
                BarAudioVisualizer(audioTrack: nil,
                                   agentState: .listening,
                                   barCount: 5,
                                   barSpacingFactor: 0.08,
                                   barMinOpacity: 0.15)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .padding(.horizontal, 60)
                    .transition(.opacity)
            }
            }
            .animation(.snappy, value: session.agent.audioTrack?.id)
            .modifier(NamespaceEffectModifier(namespace: namespace))

            // Agent state indicator - with dark mode support
            Text(stateText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.6)) // Adaptive color for dark mode
                .tracking(0.8)
                .textCase(.uppercase)
                .animation(.easeInOut(duration: 0.3), value: session.agent.agentState)
                .padding(.bottom, 8) // Extra spacing above transcript

            Spacer()
                .frame(minHeight: 80) // Bottom spacing - prevents overlap with transcript
        }
    }

    private var stateText: String {
        guard let state = session.agent.agentState else {
            return "Connecting"
        }

        switch state {
        case .listening:
            return "Listening"
        case .thinking:
            return "Thinking"
        case .speaking:
            return "Translating"
        default:
            return ""
        }
    }
}

// MARK: - Namespace Effect Modifier

/// A modifier that conditionally applies matchedGeometryEffect only if namespace is provided
private struct NamespaceEffectModifier: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace = namespace {
            content.matchedGeometryEffect(id: "agent", in: namespace)
        } else {
            content
        }
    }
}
