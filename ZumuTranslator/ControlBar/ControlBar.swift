import LiveKitComponents

/// A multiplatform view that shows the control bar: audio/video and chat controls.
/// Available controls depend on the agent features and the track availability.
/// - SeeAlso: ``AgentFeatures``
struct ControlBar: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var localMedia: LocalMedia

    @Binding var chat: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.voiceEnabled) private var voiceEnabled
    @Environment(\.videoEnabled) private var videoEnabled
    @Environment(\.textEnabled) private var textEnabled
    @Environment(\.onDisconnect) private var onDisconnect

    private enum Constants {
        // Enlarged for better visibility in translation UI
        static let buttonWidth: CGFloat = 24 * .grid  // 192pt (was 128pt)
        static let buttonHeight: CGFloat = 16 * .grid // 128pt (was 88pt)
    }

    var body: some View {
        HStack(spacing: .zero) {
            biggerSpacer()
            // Voice-only controls for translation
            audioControls()
            flexibleSpacer()
            disconnectButton()
            biggerSpacer()
        }
        .buttonStyle(
            ControlBarButtonStyle(
                foregroundColor: .fg1,
                backgroundColor: .bg2,
                borderColor: .separator1
            )
        )
        .font(.system(size: 17, weight: .medium))
        .frame(height: 15 * .grid)
        #if !os(visionOS)
            .overlay(
                RoundedRectangle(cornerRadius: 7.5 * .grid)
                    .stroke(.separator1, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 7.5 * .grid)
                    .fill(.bg1)
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 10)
            )
            .safeAreaPadding(.bottom, 8 * .grid)
            .safeAreaPadding(.horizontal, 16 * .grid)
        #endif
    }

    @ViewBuilder
    private func flexibleSpacer() -> some View {
        Spacer()
            .frame(maxWidth: horizontalSizeClass == .regular ? 8 * .grid : 2 * .grid)
    }

    @ViewBuilder
    private func biggerSpacer() -> some View {
        Spacer()
            .frame(maxWidth: horizontalSizeClass == .regular ? 8 * .grid : .infinity)
    }

    @ViewBuilder
    private func separator() -> some View {
        Rectangle()
            .fill(.separator1)
            .frame(width: 1, height: 3 * .grid)
    }

    @ViewBuilder
    private func audioControls() -> some View {
        HStack(spacing: .zero) {
            Spacer()
            AsyncButton(action: localMedia.toggleMicrophone) {
                HStack(spacing: 1.5 * .grid) {
                    Image(systemName: localMedia.isMicrophoneEnabled ? "microphone.fill" : "microphone.slash.fill")
                        .font(.system(size: 32, weight: .medium)) // Enlarged icon
                        .transition(.symbolEffect)
                    BarAudioVisualizer(audioTrack: localMedia.microphoneTrack, barColor: .fg1, barCount: 3, barSpacingFactor: 0.15)
                        .frame(width: 4 * .grid, height: 0.6 * Constants.buttonHeight) // Larger waveform
                        .frame(maxHeight: .infinity)
                        .id(localMedia.microphoneTrack?.id)
                }
                .frame(height: Constants.buttonHeight)
                .padding(.horizontal, 3 * .grid)
                .contentShape(Rectangle())
            }
            #if os(macOS)
            separator()
            AudioDeviceSelector()
                .frame(height: Constants.buttonHeight)
            #endif
            Spacer()
        }
        .frame(width: Constants.buttonWidth)
    }

    @ViewBuilder
    private func disconnectButton() -> some View {
        AsyncButton {
            await session.end()
            session.restoreMessageHistory([])
            // Call dismiss callback if provided (for SDK integration)
            onDisconnect?()
        } label: {
            Image(systemName: "phone.down.fill")
                .font(.system(size: 32, weight: .medium)) // Enlarged icon to match microphone
                .frame(width: Constants.buttonWidth, height: Constants.buttonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(
            ControlBarButtonStyle(
                foregroundColor: .fgSerious,
                backgroundColor: .bgSerious,
                borderColor: .separatorSerious
            )
        )
        .disabled(!session.isConnected)
    }
}

// MARK: - Environment Extensions for SDK Integration

private struct OnDisconnectKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var onDisconnect: (() -> Void)? {
        get { self[OnDisconnectKey.self] }
        set { self[OnDisconnectKey.self] = newValue }
    }
}
