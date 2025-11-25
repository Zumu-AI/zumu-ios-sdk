# Zumu iOS SDK - Integration Tests

Automated integration tests to validate SDK functionality before release.

## Prerequisites

- Xcode 14.0+
- iOS 15.0+ SDK
- Valid Zumu API key

## Running Tests

### Option 1: Xcode
1. Open the package in Xcode:
   ```bash
   open Package.swift
   ```
2. Select the test target
3. Press ⌘+U to run all tests

### Option 2: Command Line
```bash
# Run all tests
swift test

# Run specific test
swift test --filter ZumuTranslatorIntegrationTests.testSessionCreation

# Run with verbose output
swift test --verbose
```

### Option 3: With Custom API Key
```bash
# Set your test API key
export ZUMU_TEST_API_KEY="zumu_your_test_key_here"

# Run tests
swift test
```

## Test Coverage

### ✅ Connection Stability
- `testWebSocketConnectionStability` - Validates connection remains stable for 5+ seconds
- `testNoSocketNotConnectedErrors` - Ensures 500ms settling period prevents race conditions
- `testSessionReconnection` - Tests reconnection after disconnect

### ✅ Session Management
- `testSessionCreation` - Validates session creation flow
- `testStateTransitions` - Verifies proper state machine behavior

### ✅ Audio Features
- `testAudioMuteUnmute` - Tests microphone control

### ✅ Error Handling
- `testInvalidAPIKeyHandling` - Validates authentication error handling
- `testEmptyConfigFieldsHandling` - Tests input validation

### ✅ Security
- `testNoElevenLabsLogging` - Ensures trade secret protection (no ElevenLabs references)

### ✅ Performance
- `testSessionCreationPerformance` - Validates session creation < 10 seconds

## CI/CD Integration

### GitHub Actions Example
```yaml
name: iOS SDK Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run Integration Tests
        env:
          ZUMU_TEST_API_KEY: ${{ secrets.ZUMU_TEST_API_KEY }}
        run: swift test
```

## Expected Results

All tests should pass with output similar to:

```
✅ Session created: sess_abc123...
✅ WebSocket connection remained stable for 5 seconds
✅ No premature disconnection errors detected
✅ Audio mute/unmute works correctly
✅ State transitions work correctly
✅ Trade secret protection: No ElevenLabs references
✅ Session created in 2.34s

Test Suite 'All tests' passed
```

## Troubleshooting

### "Invalid API key" errors
- Ensure `ZUMU_TEST_API_KEY` environment variable is set
- Verify key is active in Zumu dashboard
- Check key has required scopes: `sessions:create`, `sessions:read`

### Connection timeout errors
- Check network connectivity
- Verify firewall isn't blocking WebSocket connections (wss://)
- Ensure no VPN/proxy interfering with connections

### Build errors
- Run `swift package reset` to clear cache
- Verify Xcode Command Line Tools are installed
- Check Swift version: `swift --version` (should be 5.7+)

## Adding New Tests

1. Add test method to `IntegrationTests.swift`
2. Follow naming convention: `test[Feature][Scenario]()`
3. Use XCTest assertions for validation
4. Add descriptive print statements for clarity
5. Run tests locally before committing

Example:
```swift
func testNewFeature() async throws {
    // GIVEN initial conditions
    let config = SessionConfig(...)

    // WHEN performing action
    let result = try await translator.someAction()

    // THEN validate result
    XCTAssertNotNil(result)
    print("✅ New feature works correctly")
}
```

## Contact

For test failures or questions:
- GitHub Issues: https://github.com/Zumu-AI/zumu-ios-sdk/issues
- Email: support@zumu.ai
