import Foundation

struct NWSAlertResponse: Decodable {
    let features: [NWSAlertFeature]
}

struct NWSAlertFeature: Decodable {
    let id: String
    let properties: NWSAlertProperties
}

struct NWSAlertProperties: Decodable {
    let event: String
    let severity: String
    let headline: String?
    let onset: String?
    let expires: String?
}

struct WeatherAlert: Identifiable {
    let id: String
    let event: String
    let severity: String
    let headline: String?
    let onset: Date?
    let expires: Date?

    var blocksOutdoorRecommendations: Bool {
        if severity == "Extreme" || severity == "Severe" {
            return true
        }

        let blockingEvents = [
            "Tornado",
            "Severe Thunderstorm",
            "Flash Flood",
            "High Wind",
            "Winter Storm",
            "Blizzard",
            "Ice Storm",
            "Red Flag Warning",
            "Extreme Heat Warning"
        ]
        return blockingEvents.contains { event.localizedCaseInsensitiveContains($0) }
    }

    func overlaps(start: Date, end: Date) -> Bool {
        let alertStart = onset ?? .distantPast
        let alertEnd = expires ?? .distantFuture
        return alertStart < end && alertEnd > start
    }
}

enum WeatherAlertServiceError: Error {
    case invalidURL
    case invalidResponse
}

struct WeatherAlertService {
    func fetchActiveAlerts(latitude: Double, longitude: Double) async throws -> [WeatherAlert] {
        var components = URLComponents(string: "https://api.weather.gov/alerts/active")
        components?.queryItems = [
            URLQueryItem(name: "point", value: "\(latitude),\(longitude)")
        ]

        guard let url = components?.url else {
            throw WeatherAlertServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("MoveWindow/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherAlertServiceError.invalidResponse
        }

        let decodedResponse = try JSONDecoder().decode(NWSAlertResponse.self, from: data)
        let dateFormatter = ISO8601DateFormatter()

        return decodedResponse.features.map { feature in
            WeatherAlert(
                id: feature.id,
                event: feature.properties.event,
                severity: feature.properties.severity,
                headline: feature.properties.headline,
                onset: feature.properties.onset.flatMap(dateFormatter.date),
                expires: feature.properties.expires.flatMap(dateFormatter.date)
            )
        }
    }
}
