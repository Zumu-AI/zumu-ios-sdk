import LiveKit
import Foundation

/// Token source that calls Zumu backend API for LiveKit tokens
public final class ZumuTokenSource: TokenSourceConfigurable, Sendable {
    private let apiKey: String
    private let baseURL: String
    private let config: TranslationConfig

    public struct TranslationConfig: Sendable {
        public let driverName: String
        public let driverLanguage: String
        public let passengerName: String
        public let passengerLanguage: String?
        public let tripId: String?
        public let pickupLocation: String?
        public let dropoffLocation: String?

        public init(driverName: String,
                    driverLanguage: String,
                    passengerName: String,
                    passengerLanguage: String? = nil,
                    tripId: String? = nil,
                    pickupLocation: String? = nil,
                    dropoffLocation: String? = nil) {
            self.driverName = driverName
            self.driverLanguage = driverLanguage
            self.passengerName = passengerName
            self.passengerLanguage = passengerLanguage
            self.tripId = tripId
            self.pickupLocation = pickupLocation
            self.dropoffLocation = dropoffLocation
        }
    }

    public init(apiKey: String,
                config: TranslationConfig,
                baseURL: String = "https://translator.zumu.ai") {
        self.apiKey = apiKey
        self.config = config
        self.baseURL = baseURL
    }

    // MARK: - TokenSourceConfigurable Protocol Implementation

    public func fetch(_ options: TokenRequestOptions) async throws -> TokenSourceResponse {
        let (serverURL, token) = try await fetchTokenAndURL()
        return TokenSourceResponse(
            serverURL: serverURL,
            participantToken: token
        )
    }

    // MARK: - Private Implementation

    private func fetchTokenAndURL() async throws -> (URL, String) {
        let url = URL(string: "\(baseURL)/api/conversations/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "session_id": config.tripId as Any,  // Backend now uses session_id
            "driver_name": config.driverName,
            "driver_language": config.driverLanguage,
            "passenger_name": config.passengerName,
            "passenger_language": config.passengerLanguage as Any,
            "pickup_location": config.pickupLocation as Any,
            "dropoff_location": config.dropoffLocation as Any
        ]

        print("📡 Requesting LiveKit token from: \(url.absoluteString)")
        print("📡 API Key: \(apiKey.prefix(15))...")
        print("📡 Driver: \(config.driverName) (\(config.driverLanguage))")
        print("📡 Passenger: \(config.passengerName) (\(config.passengerLanguage ?? "Auto"))")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response type")
            throw TokenSourceError.networkError("Invalid response")
        }

        print("📡 HTTP Status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ HTTP \(httpResponse.statusCode)")
            print("❌ Response body: \(responseBody)")
            throw TokenSourceError.networkError("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        // Try to parse response
        let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("📡 Response: \(responseString)")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to parse JSON response")
            throw TokenSourceError.invalidResponse("Invalid JSON format")
        }

        guard let livekit = json["livekit"] as? [String: Any] else {
            print("❌ Missing 'livekit' field in response")
            print("❌ Available keys: \(json.keys.joined(separator: ", "))")
            throw TokenSourceError.invalidResponse("Missing 'livekit' field")
        }

        guard let token = livekit["token"] as? String else {
            print("❌ Missing 'token' field in livekit object")
            print("❌ Available keys: \(livekit.keys.joined(separator: ", "))")
            throw TokenSourceError.invalidResponse("Missing token")
        }

        guard let urlString = livekit["url"] as? String else {
            print("❌ Missing 'url' field in livekit object")
            throw TokenSourceError.invalidResponse("Missing URL")
        }

        guard let serverURL = URL(string: urlString) else {
            print("❌ Invalid server URL: \(urlString)")
            throw TokenSourceError.invalidResponse("Invalid server URL format")
        }

        print("✅ Received LiveKit token from Zumu backend")
        print("🔗 LiveKit server URL: \(serverURL.absoluteString)")

        return (serverURL, token)
    }
}

enum TokenSourceError: Error {
    case networkError(String)
    case invalidResponse(String)
}
