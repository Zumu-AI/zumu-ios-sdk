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

    // Cache session properties to prevent reading during disconnect
    @State private var cachedAvatarTrack: VideoTrack?
    @State private var cachedAudioTrack: AudioTrack?
    @State private var cachedAgentState: AgentState?
    @State private var cachedIsConnected: Bool = false

    // Flag to stop polling synchronously without accessing session properties
    @State private var isPollingActive: Bool = true

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(minHeight: 40) // Top spacing

            // Waveform visualization - moved higher
            ZStack {
            if let avatarVideoTrack = cachedAvatarTrack {
                SwiftUIVideoView(avatarVideoTrack)
                    .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusPerPlatform))
                    .aspectRatio(avatarVideoTrack.aspectRatio, contentMode: .fit)
                    .padding(.horizontal, cachedAvatarTrack?.aspectRatio == 1 ? 4 * .grid : .zero)
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
            } else if let audioTrack = cachedAudioTrack {
                // Clean, minimal waveform - professional proportions
                BarAudioVisualizer(audioTrack: audioTrack,
                                   agentState: cachedAgentState ?? .listening,
                                   barCount: 5,
                                   barSpacingFactor: 0.08,
                                   barMinOpacity: 0.15)
                    .frame(maxWidth: .infinity, maxHeight: 240) // Reduced height
                    .padding(.horizontal, 60)
                    .transition(.opacity)
            } else if cachedIsConnected {
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
            // REMOVED: .animation(.snappy, value: session.agent.audioTrack?.id) - causes mutex deadlock
            .modifier(NamespaceEffectModifier(namespace: namespace))

            // Agent state indicator - with dark mode support
            Text(stateText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.6)) // Adaptive color for dark mode
                .tracking(0.8)
                .textCase(.uppercase)
                // REMOVED: .animation(.easeInOut(duration: 0.3), value: session.agent.agentState) - causes mutex deadlock
                .padding(.bottom, 8) // Extra spacing above transcript

            Spacer()
                .frame(minHeight: 80) // Bottom spacing - prevents overlap with transcript
        }
        .onAppear {
            // Populate cache on appear (safe initial read)
            isPollingActive = true
            updateCache()
        }
        .onDisappear {
            // CRITICAL: Stop polling immediately to prevent mutex access during disconnect
            isPollingActive = false
            print("🛑 AgentView polling stopped")
        }
        .task {
            // Monitor for changes and update cache (runs in background)
            // This prevents view body from directly reading session during mutations
            while !Task.isCancelled {
                updateCache()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func updateCache() {
        // CRITICAL: Check polling flag FIRST, before accessing ANY session properties
        // This prevents mutex access during disconnect
        guard isPollingActive else {
            // Clear cache immediately when polling stops
            cachedAvatarTrack = nil
            cachedAudioTrack = nil
            cachedAgentState = nil
            cachedIsConnected = false
            return
        }

        // Safe to access session properties only if polling is active
        cachedAvatarTrack = session.agent.avatarVideoTrack
        cachedAudioTrack = session.agent.audioTrack
        cachedAgentState = session.agent.agentState
        cachedIsConnected = session.isConnected
    }

    private var stateText: String {
        guard let state = cachedAgentState else {
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
