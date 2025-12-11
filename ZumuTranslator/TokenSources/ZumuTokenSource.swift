import LiveKit
import Foundation

/// Token source that calls Zumu backend API for LiveKit tokens
public class ZumuTokenSource: TokenSourceConfigurable {
    private let apiKey: String
    private let baseURL: String
    private let config: TranslationConfig

    public struct TranslationConfig {
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
        let token = try await fetchToken()
        return TokenSourceResponse(token: token)
    }

    // MARK: - Private Implementation

    private func fetchToken() async throws -> String {
        let url = URL(string: "\(baseURL)/api/conversations/start")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "driver_name": config.driverName,
            "driver_language": config.driverLanguage,
            "passenger_name": config.passengerName,
            "passenger_language": config.passengerLanguage as Any,
            "trip_id": config.tripId as Any,
            "pickup_location": config.pickupLocation as Any,
            "dropoff_location": config.dropoffLocation as Any
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenSourceError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw TokenSourceError.networkError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let livekit = json["livekit"] as? [String: Any],
              let token = livekit["token"] as? String else {
            throw TokenSourceError.invalidResponse("Missing LiveKit token in response")
        }

        print("✅ Received LiveKit token from Zumu backend")

        return token
    }
}

enum TokenSourceError: Error {
    case networkError(String)
    case invalidResponse(String)
}
