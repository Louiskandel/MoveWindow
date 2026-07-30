import Foundation

struct City: Identifiable, Hashable {
    let name: String
    let state: String
    let latitude: Double
    let longitude: Double

    var id: String {
        "\(name)-\(state)"
    }

    var displayName: String {
        "\(name), \(state)"
    }

    static let sunnyvale = City(
        name: "Sunnyvale",
        state: "CA",
        latitude: 37.3688,
        longitude: -122.0363
    )

    static let availableCities: [City] = [
        sunnyvale,
        City(name: "San Francisco", state: "CA", latitude: 37.7749, longitude: -122.4194),
        City(name: "San Jose", state: "CA", latitude: 37.3382, longitude: -121.8863),
        City(name: "Mountain View", state: "CA", latitude: 37.3861, longitude: -122.0839),
        City(name: "Palo Alto", state: "CA", latitude: 37.4419, longitude: -122.1430),
        City(name: "Cupertino", state: "CA", latitude: 37.3230, longitude: -122.0322)
    ]
}
