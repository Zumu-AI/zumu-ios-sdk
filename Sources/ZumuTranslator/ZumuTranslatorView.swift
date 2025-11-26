import SwiftUI
import AVFoundation

/// Ready-to-use Zumu Translator UI Component
/// Drop this view into your app for instant translation UI
public struct ZumuTranslatorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var translator: ZumuTranslator
    @State private var errorMessage: String?
    @State private var isAnimating = false
    @State private var waveformPhase: CGFloat = 0
    @State private var showingCloseConfirmation = false
    @State private var detectedLanguage: String?
    @State private var particlePhase: CGFloat = 0
    @State private var meshGradientPhase: CGFloat = 0

    private let config: SessionConfig
    private let onDismiss: (() -> Void)?

    /// Initialize with API key and session configuration
    /// - Parameters:
    ///   - apiKey: Your Zumu API key
    ///   - config: Session configuration with driver/passenger details
    ///   - baseURL: Optional custom base URL
    ///   - onDismiss: Optional callback when user closes the translator
    public init(
        apiKey: String,
        config: SessionConfig,
        baseURL: String = "https://translator.zumu.ai",
        onDismiss: (() -> Void)? = nil
    ) {
        self._translator = StateObject(wrappedValue: ZumuTranslator(apiKey: apiKey, baseURL: baseURL))
        self.config = config
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.05, blue: 0.11),
                    Color(red: 0.07, green: 0.09, blue: 0.13),
                    Color(red: 0.02, green: 0.05, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Status Text
                statusView

                // Audio Visualization Orb
                orbVisualization
                    .frame(width: 280, height: 280)

                // Call Button
                callButton
                    .frame(width: 120, height: 120)

                // Live Language Detection Badge
                if translator.state == .active {
                    languageDetectionBadge
                }

                // Session Info
                if translator.state == .active {
                    sessionInfoView
                }

                // Real-time transcription bubbles
                if translator.state == .active && !translator.messages.isEmpty {
                    transcriptionBubbles
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()
            }
            .padding()

            // Close button (top-left corner)
            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .alert("End Session?", isPresented: $showingCloseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Session", role: .destructive) {
                Task {
                    if translator.state == .active {
                        await translator.endSession()
                    }
                    // Dismiss the view
                    await MainActor.run {
                        onDismiss?()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Are you sure you want to end the translation session?")
        }
    }

    // MARK: - Status View

    private var statusView: some View {
        Group {
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                        .font(.system(size: 14, weight: .medium))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                switch translator.state {
                case .idle:
                    Text("Tap to start translating")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 16))
                case .connecting:
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        Text("Connecting...")
                            .foregroundColor(.blue)
                            .font(.system(size: 16, weight: .medium))
                    }
                case .active:
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(agentStateColor)
                                .frame(width: 8, height: 8)
                                .scaleEffect(translator.agentState == .speaking ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: translator.agentState == .speaking)
                            Text(agentStateText)
                                .foregroundColor(agentStateColor)
                                .font(.system(size: 16, weight: .semibold))
                        }

                        // Connection quality indicator
                        if let quality = translator.connectionQuality {
                            HStack(spacing: 4) {
                                connectionQualityIcon(quality.quality)
                                    .font(.system(size: 10))
                                Text("\(quality.latencyMs ?? 0)ms")
                                    .foregroundColor(.white.opacity(0.5))
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                    }
                case .disconnected:
                    Text("Disconnected - Tap to reconnect")
                        .foregroundColor(.orange.opacity(0.8))
                        .font(.system(size: 16))
                case .ending:
                    Text("Ending session...")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 16))
                case .error(let message):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .foregroundColor(.red)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: translator.state)
        .animation(.easeInOut(duration: 0.3), value: errorMessage)
    }

    // MARK: - Orb Visualization

    private var orbVisualization: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            isActive ? Color.purple.opacity(0.3) : Color.blue.opacity(0.2),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 140
                    )
                )
                .blur(radius: 40)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(
                    isActive ?
                        .easeInOut(duration: 2).repeatForever(autoreverses: true) :
                        .easeInOut(duration: 4).repeatForever(autoreverses: true),
                    value: isAnimating
                )

            // Rotating rings
            Circle()
                .stroke(
                    isActive ? Color.purple.opacity(0.5) : Color.blue.opacity(0.3),
                    lineWidth: 2
                )
                .frame(width: 220, height: 220)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: isAnimating)

            Circle()
                .stroke(
                    isActive ? Color.blue.opacity(0.4) : Color.purple.opacity(0.2),
                    lineWidth: 1
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(isAnimating ? -360 : 0))
                .animation(.linear(duration: 15).repeatForever(autoreverses: false), value: isAnimating)

            // Main orb
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.1),
                                Color.purple.opacity(0.1),
                                Color.blue.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 2)
                    )

                // Inner glow pulse
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                isActive ? Color.purple.opacity(0.3) : Color.blue.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 90
                        )
                    )
                    .scaleEffect(isAnimating ? 1.2 : 0.8)
                    .opacity(isAnimating ? 0.6 : 0.3)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)

                // Siri-style advanced waveform visualization
                if translator.state == .active {
                    ZStack {
                        // 24 bars for smooth, flowing Siri-style animation
                        ForEach(0..<24, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.9),
                                            sirikWaveColor(for: index, agentState: translator.agentState).opacity(0.8),
                                            sirikWaveColor(for: index, agentState: translator.agentState).opacity(0.6)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 3, height: advancedWaveformHeight(for: index))
                                .offset(x: CGFloat(index - 12) * 6)
                                .blur(radius: 0.3) // Subtle blur for smoothness
                        }
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            waveformPhase = 1.0
                        }
                    }
                }

                // Particle effects around orb when speaking
                if translator.agentState == .speaking || translator.agentState == .thinking {
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.purple.opacity(0.6),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 4
                                )
                            )
                            .frame(width: 8, height: 8)
                            .offset(particleOffset(for: index))
                            .opacity(particleOpacity(for: index))
                            .blur(radius: 1)
                    }
                    .onAppear {
                        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                            particlePhase = 1.0
                        }
                    }
                }
            }
            .frame(width: 180, height: 180)

            // Connection status ring
            if translator.state == .active {
                Circle()
                    .stroke(Color.green.opacity(0.5), lineWidth: 3)
                    .frame(width: 190, height: 190)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            }

            // Connecting animation
            if translator.state == .connecting {
                Circle()
                    .stroke(Color.blue.opacity(0.5), lineWidth: 3)
                    .frame(width: 200, height: 200)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .opacity(isAnimating ? 0.6 : 0.3)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: handleCloseAction) {
            ZStack {
                // Background blur
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .blur(radius: 0.5)

                // Icon
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 8)
    }

    // MARK: - Call Button

    private var callButton: some View {
        Button(action: handleCallAction) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                isActive ? Color.red.opacity(0.3) : Color.purple.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 60
                        )
                    )
                    .blur(radius: 20)
                    .scaleEffect(1.3)

                // Glassmorphic button
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isActive ? [
                                Color.red.opacity(0.8),
                                Color.red.opacity(0.7),
                                Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.8)
                            ] : [
                                Color.purple.opacity(0.7),
                                Color.blue.opacity(0.6),
                                Color.purple.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    )
                    .shadow(color: isActive ? Color.red.opacity(0.4) : Color.purple.opacity(0.3), radius: 20)

                // Glass effect overlay
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                // Icon
                Image(systemName: isActive ? "phone.down.fill" : "phone.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
        .disabled(translator.state == .connecting || translator.state == .ending)
        .scaleEffect(translator.state == .connecting || translator.state == .ending ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: translator.state)
    }

    // MARK: - Session Info

    private var sessionInfoView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                // Driver info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue.opacity(0.8))
                        Text("Driver")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Text(config.driverName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(config.driverLanguage)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Passenger info
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Passenger")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.purple.opacity(0.8))
                    }
                    Text(config.passengerName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(config.passengerLanguage ?? "Auto Detect")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            // Trip ID
            if !config.tripId.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green.opacity(0.8))
                    Text("Trip: \(config.tripId)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10)
        )
        .padding(.horizontal)
    }

    // MARK: - Language Detection Badge

    private var languageDetectionBadge: some View {
        HStack(spacing: 8) {
            if #available(iOS 17.0, *) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.purple)
                    .symbolEffect(.pulse, options: .repeating, value: detectedLanguage)
            } else {
                // iOS 15-16 fallback: manual scale animation
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.purple)
                    .scaleEffect(detectedLanguage != nil ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: detectedLanguage)
            }

            if let language = detectedLanguage {
                Text(language)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("Detecting...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.3),
                            Color.blue.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.purple.opacity(0.3), radius: 10)
        )
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: detectedLanguage)
        .task {
            // Poll for language detection every 2 seconds
            await pollLanguageDetection()
        }
    }

    // MARK: - Transcription Bubbles

    private var transcriptionBubbles: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(translator.messages.suffix(3)) { message in
                    transcriptionBubble(message: message)
                }
            }
            .padding(.horizontal)
        }
        .frame(maxHeight: 150)
    }

    private func transcriptionBubble(message: TranslationMessage) -> some View {
        HStack {
            if message.role == "user" {
                Spacer()
            }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                message.role == "user" ?
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(
                                color: message.role == "user" ? Color.blue.opacity(0.2) : Color.black.opacity(0.1),
                                radius: 8
                            )
                    )

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }

            if message.role != "user" {
                Spacer()
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Helper Functions

    private func advancedWaveformHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 15
        let maxHeight: CGFloat = 60

        // Create flowing wave pattern like Siri
        let offset = CGFloat(index) * 0.15
        let phase = waveformPhase + offset

        // Combine sine waves for organic movement
        let wave1 = sin(phase * .pi * 2)
        let wave2 = sin(phase * .pi * 3 + CGFloat.pi / 4) * 0.5
        let wave3 = sin(phase * .pi * 1.5 - CGFloat.pi / 3) * 0.3

        let combinedWave = wave1 + wave2 + wave3
        let normalizedWave = (combinedWave + 1.8) / 3.6 // Normalize to 0-1

        // Adjust height based on agent state
        let stateMultiplier: CGFloat = {
            switch translator.agentState {
            case .listening: return 0.7
            case .processing: return 0.9
            case .thinking: return 1.1
            case .speaking: return 1.3
            default: return 0.5
            }
        }()

        return baseHeight + (maxHeight - baseHeight) * normalizedWave * stateMultiplier
    }

    private func sirikWaveColor(for index: Int, agentState: AgentState) -> Color {
        switch agentState {
        case .listening:
            return index % 3 == 0 ? .green : (index % 3 == 1 ? .blue : .cyan)
        case .processing:
            return index % 3 == 0 ? .blue : (index % 3 == 1 ? .purple : .indigo)
        case .thinking:
            return index % 3 == 0 ? .purple : (index % 3 == 1 ? .pink : .purple)
        case .speaking:
            return index % 3 == 0 ? .orange : (index % 3 == 1 ? .yellow : .orange)
        default:
            return .blue
        }
    }

    private func particleOffset(for index: Int) -> CGSize {
        let angle = (CGFloat(index) / 8.0) * 2 * .pi + particlePhase * 2 * .pi
        let radius: CGFloat = 100

        let x = cos(angle) * radius
        let y = sin(angle) * radius

        return CGSize(width: x, height: y)
    }

    private func particleOpacity(for index: Int) -> Double {
        let phase = particlePhase + CGFloat(index) * 0.125
        return 0.3 + 0.4 * abs(sin(phase * 2 * .pi))
    }

    private func pollLanguageDetection() async {
        while translator.state == .active {
            do {
                // Call the API endpoint to get detected language
                guard let url = URL(string: "\(translator.baseURL)/api/latest-language") else { continue }

                let (data, _) = try await URLSession.shared.data(from: url)

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let language = json["language"] as? String,
                   let hasLanguage = json["hasLanguage"] as? Bool,
                   hasLanguage {
                    await MainActor.run {
                        if self.detectedLanguage != language {
                            // Trigger haptic feedback on language change
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()

                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                self.detectedLanguage = language
                            }
                        }
                    }
                }
            } catch {
                print("Failed to fetch language detection: \(error)")
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000) // Poll every 2 seconds
        }
    }

    // MARK: - Actions

    private func handleCloseAction() {
        if translator.state == .active {
            // Show confirmation if session is active
            showingCloseConfirmation = true
        } else {
            // Dismiss immediately if not in session
            onDismiss?()
            dismiss()
        }
    }

    private func handleCallAction() {
        // Haptic feedback for button press
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()

        switch translator.state {
        case .idle, .disconnected, .error:
            startSession()
        case .active:
            // Success haptic when ending session
            let endGenerator = UINotificationFeedbackGenerator()
            endGenerator.notificationOccurred(.success)

            Task {
                await translator.endSession()
            }
        case .connecting, .ending:
            break
        }
    }

    private func startSession() {
        errorMessage = nil

        Task {
            do {
                _ = try await translator.startSession(config: config)

                // Success haptic on connection
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription

                    // Error haptic
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)

                    // Auto-clear error after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        errorMessage = nil
                    }
                }
            }
        }
    }

    private var isActive: Bool {
        translator.state == .active
    }

    private var agentStateText: String {
        switch translator.agentState {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .thinking:
            return "Thinking..."
        case .speaking:
            return "Translating..."
        }
    }

    private var agentStateColor: Color {
        switch translator.agentState {
        case .idle:
            return .gray
        case .listening:
            return .green
        case .processing:
            return .blue
        case .thinking:
            return .purple
        case .speaking:
            return .orange
        }
    }

    private func connectionQualityIcon(_ quality: ConnectionQuality.Quality) -> some View {
        Group {
            switch quality {
            case .excellent:
                Image(systemName: "wifi")
                    .foregroundColor(.green)
            case .good:
                Image(systemName: "wifi")
                    .foregroundColor(.blue)
            case .fair:
                Image(systemName: "wifi")
                    .foregroundColor(.orange)
            case .poor:
                Image(systemName: "wifi.exclamationmark")
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ZumuTranslatorView_Previews: PreviewProvider {
    static var previews: some View {
        ZumuTranslatorView(
            apiKey: "zumu_preview_key",
            config: SessionConfig(
                driverName: "John Driver",
                driverLanguage: "English",
                passengerName: "María Passenger",
                passengerLanguage: "Spanish",
                tripId: "TRIP-12345",
                pickupLocation: "123 Main St",
                dropoffLocation: "456 Oak Ave"
            ),
            onDismiss: {
                print("Translator dismissed")
            }
        )
    }
}
#endif
