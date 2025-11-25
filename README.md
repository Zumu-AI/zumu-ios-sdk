# Zumu Driver Translator - iOS SDK

Enterprise-grade real-time translation SDK for driver-passenger conversations.

## Features

- 🎯 **Real-time Translation**: Instant voice-to-voice translation
- 🔐 **Secure Authentication**: API key-based authentication
- 📱 **SwiftUI Integration**: Reactive state management with Combine
- 🎤 **Microphone Control**: Built-in mute/unmute functionality
- 💬 **Text Messaging**: Send text messages alongside voice
- 📊 **Session Management**: Track and manage conversation sessions
- 🔄 **Automatic Reconnection**: Built-in connection resilience

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Zumu-AI/zumu-ios-sdk", from: "1.0.0")
]
```

Or add it in Xcode:
1. File → Add Package Dependencies
2. Enter package URL: `https://github.com/Zumu-AI/zumu-ios-sdk`
3. Select version and add to your target

**Note**: This SDK requires no external dependencies. Everything is handled through Zumu's secure infrastructure.

## Quick Start

### 1. Get Your API Key

1. Log in to the [Zumu Dashboard](https://translator.zumu.ai/dashboard)
2. Navigate to **API Keys**
3. Click **Create API Key**
4. Copy your key (format: `zumu_xxxxxxxxxxxx`)

⚠️ **Important**: Never commit API keys to your repository. Store them securely.

### 2. Initialize the SDK

```swift
import ZumuTranslator

let translator = ZumuTranslator(apiKey: "zumu_your_api_key_here")
```

### 3. Start a Translation Session

```swift
let config = SessionConfig(
    driverName: "John Doe",
    driverLanguage: "English",
    passengerName: "María García",
    passengerLanguage: "Spanish",
    tripId: "TRIP-12345",
    pickupLocation: "123 Main St",
    dropoffLocation: "456 Oak Ave"
)

Task {
    do {
        let session = try await translator.startSession(config: config)
        print("Session started: \(session.id)")
    } catch {
        print("Error starting session: \(error)")
    }
}
```

### 4. Build Your UI

```swift
import SwiftUI

struct TranslatorView: View {
    @StateObject private var translator: ZumuTranslator

    var body: some View {
        VStack {
            // Status indicator
            StatusView(state: translator.state)

            // Messages list
            ScrollView {
                ForEach(translator.messages) { message in
                    MessageRow(message: message)
                }
            }

            // Controls
            HStack {
                Button(action: {
                    Task { translator.toggleMute() }
                }) {
                    Image(systemName: translator.isMuted ? "mic.slash" : "mic")
                }

                Button("End Session") {
                    Task { await translator.endSession() }
                }
                .foregroundColor(.red)
            }
        }
    }
}
```

## Complete Example

```swift
import SwiftUI
import ZumuTranslator

@main
struct DriverApp: App {
    var body: some Scene {
        WindowGroup {
            DriverView()
        }
    }
}

struct DriverView: View {
    @StateObject private var translator = ZumuTranslator(
        apiKey: ProcessInfo.processInfo.environment["ZUMU_API_KEY"]!
    )

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Session status
                SessionStatusCard(state: translator.state)

                // Start session button
                if translator.state == .idle {
                    Button("Start Translation") {
                        startNewSession()
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Active conversation
                if translator.state == .active {
                    ConversationView(translator: translator)
                }
            }
            .navigationTitle("Zumu Translator")
        }
    }

    private func startNewSession() {
        let config = SessionConfig(
            driverName: UserDefaults.standard.string(forKey: "driverName") ?? "Driver",
            driverLanguage: "English",
            passengerName: "Passenger",
            tripId: UUID().uuidString
        )

        Task {
            do {
                _ = try await translator.startSession(config: config)
            } catch {
                print("Failed to start session: \(error)")
            }
        }
    }
}

struct ConversationView: View {
    @ObservedObject var translator: ZumuTranslator

    var body: some View {
        VStack {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack {
                        ForEach(translator.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .onChange(of: translator.messages.count) { _ in
                    if let lastMessage = translator.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Controls
            HStack(spacing: 20) {
                Button(action: { translator.toggleMute() }) {
                    Image(systemName: translator.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 32))
                        .foregroundColor(translator.isMuted ? .red : .blue)
                }

                Button(action: {
                    Task { await translator.endSession() }
                }) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
    }
}

struct MessageBubble: View {
    let message: TranslationMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
            }

            VStack(alignment: message.role == "user" ? .trailing : .leading) {
                Text(message.content)
                    .padding()
                    .background(message.role == "user" ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(message.role == "user" ? .white : .primary)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if message.role != "user" {
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}

struct SessionStatusCard: View {
    let state: SessionState

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(statusText)
                .font(.headline)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        switch state {
        case .idle: return .gray
        case .connecting: return .orange
        case .active: return .green
        case .disconnected: return .red
        case .ending: return .orange
        case .error: return .red
        }
    }

    private var statusText: String {
        switch state {
        case .idle: return "Ready"
        case .connecting: return "Connecting..."
        case .active: return "Active"
        case .disconnected: return "Disconnected"
        case .ending: return "Ending..."
        case .error(let message): return "Error: \(message)"
        }
    }
}
```

## API Reference

### ZumuTranslator

Main SDK class for managing translation sessions.

#### Properties

```swift
@Published var state: SessionState       // Current session state
@Published var messages: [TranslationMessage]  // Conversation messages
@Published var isMuted: Bool            // Microphone mute state
@Published var session: TranslationSession?    // Active session
```

#### Methods

```swift
// Initialize translator
init(apiKey: String, baseURL: String = "https://translator.zumu.ai")

// Start a new session
func startSession(config: SessionConfig) async throws -> TranslationSession

// End current session
func endSession() async

// Send text message
func sendMessage(_ text: String) async throws

// Toggle microphone mute
func toggleMute()
```

### SessionConfig

Configuration for starting a translation session.

```swift
struct SessionConfig {
    let driverName: String         // Required: Driver's full name
    let driverLanguage: String     // Required: Driver's language (e.g., "English")
    let passengerName: String      // Required: Passenger's name
    let passengerLanguage: String? // Optional: Passenger's language (auto-detected if nil)
    let tripId: String             // Required: Unique trip identifier
    let pickupLocation: String?    // Optional: Pickup address
    let dropoffLocation: String?   // Optional: Dropoff address
}
```

### SessionState

```swift
enum SessionState {
    case idle          // No active session
    case connecting    // Establishing connection
    case active        // Session in progress
    case disconnected  // Connection lost
    case ending        // Session terminating
    case error(String) // Error occurred
}
```

## Permissions

Add the following to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Zumu needs microphone access for real-time translation</string>
```

Request microphone permission before starting a session:

```swift
import AVFoundation

func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
}
```

## Best Practices

### 1. Secure API Key Storage

```swift
// ✅ Good: Use environment variables or secure keychain
let apiKey = ProcessInfo.processInfo.environment["ZUMU_API_KEY"]!

// ❌ Bad: Hardcode in source
let apiKey = "zumu_abc123..." // NEVER DO THIS
```

### 2. Handle Connection Errors

```swift
translator.$state
    .sink { state in
        if case .error(let message) = state {
            // Show error to user
            showAlert(message)

            // Attempt reconnection
            Task {
                try? await translator.startSession(config: lastConfig)
            }
        }
    }
    .store(in: &cancellables)
```

### 3. Manage Session Lifecycle

```swift
// End session when app goes to background
NotificationCenter.default.addObserver(
    forName: UIApplication.didEnterBackgroundNotification,
    object: nil,
    queue: .main
) { _ in
    Task {
        await translator.endSession()
    }
}
```

## Troubleshooting

### "Invalid API key" Error
- Verify your API key is correct
- Check that the key is active in the dashboard
- Ensure the key hasn't expired

### "Failed to create session" Error
- Check your network connection
- Verify all required fields in `SessionConfig`
- Check dashboard for quota limits

### No Audio
- Verify microphone permissions
- Check that device isn't muted
- Ensure AirPods/Bluetooth devices are connected properly

## Support

- Documentation: https://translator.zumu.ai/docs
- Dashboard: https://translator.zumu.ai/dashboard
- Email: support@zumu.ai

## License

Copyright © 2025 Zumu. All rights reserved.
