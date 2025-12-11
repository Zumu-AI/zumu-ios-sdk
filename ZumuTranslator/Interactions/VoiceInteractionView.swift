import SwiftUI

/// A multiplatform view that shows the agent audio visualizer for translation.
///
/// This view focuses solely on the agent's audio visualization, displaying:
/// - Agent audio waveform (BarAudioVisualizer)
/// - Translation context overlay (driver/passenger names and languages)
///
/// - Note: The layout is determined by the horizontal size class.
struct VoiceInteractionView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            regular()
        } else {
            compact()
        }
    }

    @ViewBuilder
    private func regular() -> some View {
        AgentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding()
    }

    @ViewBuilder
    private func compact() -> some View {
        AgentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}
