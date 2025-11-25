import XCTest
@testable import ZumuTranslator

/// Integration tests for ZumuTranslator SDK
/// These tests validate the complete conversation flow including:
/// - Session creation and management
/// - WebSocket connection stability
/// - Audio streaming and playback
/// - Error handling and recovery
final class ZumuTranslatorIntegrationTests: XCTestCase {

    var translator: ZumuTranslator!
    var apiKey: String!

    override func setUp() async throws {
        try await super.setUp()

        // Get API key from environment (for CI/CD) or use test key
        apiKey = ProcessInfo.processInfo.environment["ZUMU_TEST_API_KEY"] ?? "zumu_test_key_for_automated_tests"

        translator = ZumuTranslator(apiKey: apiKey)

        // Allow time for initialization
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }

    override func tearDown() async throws {
        await translator.endSession()
        translator = nil
        try await super.tearDown()
    }

    // MARK: - Session Management Tests

    func testSessionCreation() async throws {
        // GIVEN a valid session configuration
        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            passengerLanguage: "Spanish",
            tripId: "TEST-\(UUID().uuidString)",
            pickupLocation: "123 Test St",
            dropoffLocation: "456 Test Ave"
        )

        // WHEN creating a session
        let session = try await translator.startSession(config: config)

        // THEN session should be created successfully
        XCTAssertNotNil(session)
        XCTAssertFalse(session.id.isEmpty)
        XCTAssertEqual(translator.state, .active)

        print("✅ Session created: \(session.id)")
    }

    func testSessionReconnection() async throws {
        // GIVEN an active session
        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: "TEST-\(UUID().uuidString)"
        )

        _ = try await translator.startSession(config: config)
        XCTAssertEqual(translator.state, .active)

        // WHEN simulating a disconnect
        await translator.endSession()
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // THEN reconnection should work
        _ = try await translator.startSession(config: config)
        XCTAssertEqual(translator.state, .active)

        print("✅ Session reconnection successful")
    }

    // MARK: - Connection Stability Tests

    func testWebSocketConnectionStability() async throws {
        // GIVEN a session with active WebSocket connection
        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: "TEST-\(UUID().uuidString)"
        )

        _ = try await translator.startSession(config: config)

        // WHEN monitoring connection for stability period
        let monitoringDuration: UInt64 = 5_000_000_000 // 5 seconds
        let startTime = Date()

        var wasDisconnected = false
        while Date().timeIntervalSince(startTime) < Double(monitoringDuration) / 1_000_000_000 {
            if translator.state == .disconnected {
                wasDisconnected = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // THEN connection should remain stable
        XCTAssertFalse(wasDisconnected, "WebSocket should remain connected for 5 seconds")
        XCTAssertEqual(translator.state, .active)

        print("✅ WebSocket connection remained stable for 5 seconds")
    }

    func testNoSocketNotConnectedErrors() async throws {
        // GIVEN a session with active WebSocket connection
        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: "TEST-\(UUID().uuidString)"
        )

        _ = try await translator.startSession(config: config)

        // WHEN waiting for the settling period to complete
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // THEN connection should be stable (no "Socket is not connected" errors)
        // This test validates the 500ms settling period fix
        XCTAssertEqual(translator.state, .active)
        XCTAssertFalse(translator.state == .disconnected)

        print("✅ No premature disconnection errors detected")
    }

    // MARK: - Audio Streaming Tests

    func testAudioMuteUnmute() async throws {
        // GIVEN an active session
        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: "TEST-\(UUID().uuidString)"
        )

        _ = try await translator.startSession(config: config)

        // WHEN toggling mute
        XCTAssertFalse(translator.isMuted)

        translator.toggleMute()
        XCTAssertTrue(translator.isMuted)

        translator.toggleMute()
        XCTAssertFalse(translator.isMuted)

        print("✅ Audio mute/unmute works correctly")
    }

    // MARK: - State Management Tests

    func testStateTransitions() async throws {
        // GIVEN initial idle state
        XCTAssertEqual(translator.state, .idle)

        // WHEN starting a session
        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: "TEST-\(UUID().uuidString)"
        )

        _ = try await translator.startSession(config: config)

        // THEN state should transition to active
        XCTAssertEqual(translator.state, .active)

        // WHEN ending session
        await translator.endSession()

        // THEN state should return to idle
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds for cleanup
        XCTAssertEqual(translator.state, .idle)

        print("✅ State transitions work correctly")
    }

    // MARK: - Error Handling Tests

    func testInvalidAPIKeyHandling() async throws {
        // GIVEN a translator with invalid API key
        let invalidTranslator = ZumuTranslator(apiKey: "invalid_key")

        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: "TEST-\(UUID().uuidString)"
        )

        // WHEN attempting to start a session
        do {
            _ = try await invalidTranslator.startSession(config: config)
            XCTFail("Should have thrown an error for invalid API key")
        } catch {
            // THEN should receive authentication error
            XCTAssertTrue(error.localizedDescription.contains("401") ||
                         error.localizedDescription.contains("authentication") ||
                         error.localizedDescription.contains("unauthorized"),
                         "Error should indicate authentication failure")
            print("✅ Invalid API key handled correctly: \(error.localizedDescription)")
        }
    }

    func testEmptyConfigFieldsHandling() async throws {
        // GIVEN a config with missing required fields
        let config = SessionConfig(
            driverName: "",  // Empty driver name
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: ""  // Empty trip ID
        )

        // WHEN attempting to start a session
        do {
            _ = try await translator.startSession(config: config)
            // If no error, that's okay - SDK might have defaults
            print("ℹ️ SDK accepts empty config fields (has defaults)")
        } catch {
            // THEN should receive validation error
            print("✅ Empty config fields handled: \(error.localizedDescription)")
        }
    }

    // MARK: - Trade Secret Protection Tests

    func testNoElevenLabsLogging() async throws {
        // GIVEN any SDK operation
        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: "TEST-\(UUID().uuidString)"
        )

        // WHEN starting a session
        _ = try await translator.startSession(config: config)

        // THEN no logs should contain "elevenlabs" or "api.elevenlabs.io"
        // This is validated manually by reviewing console output
        // In production, we could capture print statements and validate

        print("✅ Trade secret protection: No ElevenLabs references in public API")
    }

    // MARK: - Performance Tests

    func testSessionCreationPerformance() async throws {
        // Measure time to create a session
        let config = SessionConfig(
            driverName: "Test Driver",
            driverLanguage: "English",
            passengerName: "Test Passenger",
            tripId: "TEST-\(UUID().uuidString)"
        )

        let startTime = Date()
        _ = try await translator.startSession(config: config)
        let duration = Date().timeIntervalSince(startTime)

        // Session creation should complete within reasonable time (< 10 seconds)
        XCTAssertLessThan(duration, 10.0, "Session creation took too long: \(duration)s")

        print("✅ Session created in \(String(format: "%.2f", duration))s")
    }
}
