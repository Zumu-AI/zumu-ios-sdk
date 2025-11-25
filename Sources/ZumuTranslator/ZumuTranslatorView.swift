import SwiftUI
import AVFoundation

/// Ready-to-use Zumu Translator UI Component
/// Drop this view into your app for instant translation UI
public struct ZumuTranslatorView: View {
    @StateObject private var translator: ZumuTranslator
    @State private var errorMessage: String?
    @State private var isAnimating = false
    @State private var waveformPhase: CGFloat = 0
    @State private var showingCloseConfirmation = false

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

                // Session Info
                if translator.state == .active {
                    sessionInfoView
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
                    onDismiss?()
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
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .foregroundColor(.green)
                            .font(.system(size: 16, weight: .semibold))
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

                // Enhanced waveform visualization (iOS 15+ compatible)
                if translator.state == .active {
                    ZStack {
                        // Multiple animated bars creating waveform effect
                        ForEach(0..<5, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.8),
                                            Color.blue.opacity(0.6),
                                            Color.purple.opacity(0.6)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 4, height: waveformHeight(for: index))
                                .offset(x: CGFloat(index - 2) * 12)
                        }
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            waveformPhase = 1.0
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

    // MARK: - Helper Functions

    private func waveformHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 20
        let maxHeight: CGFloat = 50

        // Create different animation patterns for each bar
        let offset = CGFloat(index) * 0.2
        let phase = waveformPhase + offset
        let normalizedPhase = sin(phase * .pi * 2)

        return baseHeight + (maxHeight - baseHeight) * abs(normalizedPhase)
    }

    // MARK: - Actions

    private func handleCloseAction() {
        if translator.state == .active {
            // Show confirmation if session is active
            showingCloseConfirmation = true
        } else {
            // Dismiss immediately if not in session
            onDismiss?()
        }
    }

    private func handleCallAction() {
        switch translator.state {
        case .idle, .disconnected, .error:
            startSession()
        case .active:
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
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
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
