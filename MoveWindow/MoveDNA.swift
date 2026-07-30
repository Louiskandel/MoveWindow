import Foundation
import SwiftData

enum ActivitySessionStatus: String, Codable {
    case planned
    case completed
    case skipped
}

enum TemperatureFeedback: String, CaseIterable, Identifiable, Codable {
    case tooCold = "Too cold"
    case justRight = "Just right"
    case tooHot = "Too hot"

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .tooCold:
            return "thermometer.snowflake"
        case .justRight:
            return "checkmark.circle.fill"
        case .tooHot:
            return "thermometer.sun.fill"
        }
    }
}

enum ConditionIssue: Int, CaseIterable, Identifiable {
    case windy = 1
    case wet = 2
    case humid = 4
    case harshUV = 8

    var id: Self { self }

    var label: String {
        switch self {
        case .windy:
            return "Too windy"
        case .wet:
            return "Too wet"
        case .humid:
            return "Too humid"
        case .harshUV:
            return "UV too harsh"
        }
    }

    var symbolName: String {
        switch self {
        case .windy:
            return "wind"
        case .wet:
            return "cloud.rain.fill"
        case .humid:
            return "humidity.fill"
        case .harshUV:
            return "sun.max.trianglebadge.exclamationmark.fill"
        }
    }
}

@Model
final class ActivitySession {
    @Attribute(.unique) var id: UUID
    var activityRawValue: String
    var cityName: String
    var plannedStart: Date
    var plannedEnd: Date
    var forecastTemperature: Double
    var forecastApparentTemperature: Double
    var forecastRelativeHumidity: Int
    var forecastPrecipitationProbability: Int
    var forecastWindSpeed: Double
    var forecastUVIndex: Double
    var forecastWeatherCode: Int
    var forecastIsDay: Int
    var originalScore: Int
    var createdAt: Date
    var statusRawValue: String
    var feedbackAt: Date?
    var temperatureFeedbackRawValue: String?
    var conditionIssueMask: Int

    init(
        id: UUID = UUID(),
        activity: Activity,
        city: City,
        recommendation: ActivityRecommendation,
        createdAt: Date = Date()
    ) {
        let start = recommendation.forecast.date ?? createdAt

        self.id = id
        self.activityRawValue = activity.rawValue
        self.cityName = city.displayName
        self.plannedStart = start
        self.plannedEnd = start.addingTimeInterval(60 * 60)
        self.forecastTemperature = recommendation.forecast.temperature
        self.forecastApparentTemperature = recommendation.forecast.apparentTemperature
        self.forecastRelativeHumidity = recommendation.forecast.relativeHumidity
        self.forecastPrecipitationProbability = recommendation.forecast.precipitationProbability
        self.forecastWindSpeed = recommendation.forecast.windSpeed
        self.forecastUVIndex = recommendation.forecast.uvIndex
        self.forecastWeatherCode = recommendation.forecast.weatherCode
        self.forecastIsDay = recommendation.forecast.isDay
        self.originalScore = recommendation.score
        self.createdAt = createdAt
        self.statusRawValue = ActivitySessionStatus.planned.rawValue
        self.feedbackAt = nil
        self.temperatureFeedbackRawValue = nil
        self.conditionIssueMask = 0
    }

    var activity: Activity {
        Activity(rawValue: activityRawValue) ?? .walking
    }

    var status: ActivitySessionStatus {
        get { ActivitySessionStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue }
    }

    var temperatureFeedback: TemperatureFeedback? {
        guard let temperatureFeedbackRawValue else {
            return nil
        }
        return TemperatureFeedback(rawValue: temperatureFeedbackRawValue)
    }

    var selectedIssues: Set<ConditionIssue> {
        Set(ConditionIssue.allCases.filter { conditionIssueMask & $0.rawValue != 0 })
    }

    var isDueForCheckIn: Bool {
        status == .planned && plannedEnd <= Date()
    }

    func complete(
        with temperatureFeedback: TemperatureFeedback,
        issues: Set<ConditionIssue>,
        at date: Date = Date()
    ) {
        self.temperatureFeedbackRawValue = temperatureFeedback.rawValue
        self.conditionIssueMask = issues.reduce(0) { $0 | $1.rawValue }
        self.feedbackAt = date
        self.status = .completed
    }

    func skip(at date: Date = Date()) {
        feedbackAt = date
        status = .skipped
    }
}

struct MoveDNAProfile {
    let activity: Activity
    let name: String
    let preferredTemperatureRange: ClosedRange<Double>
    let checkInCount: Int
    let badges: [String]
    let windSensitivityThreshold: Double?
    let rainSensitivityThreshold: Int?
    let humiditySensitivityThreshold: Int?
    let uvSensitivityThreshold: Double?

    var temperatureRangeLabel: String {
        "\(Int(preferredTemperatureRange.lowerBound.rounded()))–\(Int(preferredTemperatureRange.upperBound.rounded()))°F"
    }

    func sensitivityAdjustment(for forecast: HourlyForecast) -> (penalty: Int, reasons: [String]) {
        var penalty = 0
        var reasons: [String] = []

        if let windSensitivityThreshold, forecast.windSpeed >= windSensitivityThreshold {
            penalty += 8
            reasons.append("Wind may exceed your comfort history")
        }
        if let rainSensitivityThreshold,
           forecast.precipitationProbability >= rainSensitivityThreshold {
            penalty += 8
            reasons.append("Rain chance is above your comfort history")
        }
        if let humiditySensitivityThreshold,
           forecast.relativeHumidity >= humiditySensitivityThreshold {
            penalty += 8
            reasons.append("Humidity is above your comfort history")
        }
        if let uvSensitivityThreshold, forecast.uvIndex >= uvSensitivityThreshold {
            penalty += 8
            reasons.append("UV is above your comfort history")
        }

        return (penalty, reasons)
    }
}

struct MoveDNAService {
    static let requiredCheckIns = 5

    func existingSession(
        for activity: Activity,
        startingAt start: Date,
        sessions: [ActivitySession]
    ) -> ActivitySession? {
        sessions.first { session in
            session.activity == activity
                && abs(session.plannedStart.timeIntervalSince(start)) < 1
        }
    }

    func completedCheckInCount(for activity: Activity, sessions: [ActivitySession]) -> Int {
        completedSessions(for: activity, sessions: sessions).count
    }

    func profile(for activity: Activity, sessions: [ActivitySession]) -> MoveDNAProfile? {
        let completed = completedSessions(for: activity, sessions: sessions)
        guard completed.count >= Self.requiredCheckIns else {
            return nil
        }

        let defaultRange = activity.preferredTemperatureRange
        let defaultMidpoint = (defaultRange.lowerBound + defaultRange.upperBound) / 2
        let halfWidth = (defaultRange.upperBound - defaultRange.lowerBound) / 2

        let justRightTemperatures = completed.compactMap { session -> Double? in
            session.temperatureFeedback == .justRight
                ? session.forecastApparentTemperature
                : nil
        }
        let observedMidpoint: Double
        if justRightTemperatures.isEmpty {
            observedMidpoint = defaultMidpoint
        } else {
            observedMidpoint = justRightTemperatures.reduce(0, +)
                / Double(justRightTemperatures.count)
        }

        let tooColdCount = completed.filter { $0.temperatureFeedback == .tooCold }.count
        let tooHotCount = completed.filter { $0.temperatureFeedback == .tooHot }.count
        let responseAdjustment = Double(tooColdCount - tooHotCount) * 2
        let proposedMidpoint = observedMidpoint + responseAdjustment
        let learnedMidpoint = min(
            max(proposedMidpoint, defaultMidpoint - 8),
            defaultMidpoint + 8
        )
        let learnedRange = (learnedMidpoint - halfWidth)...(learnedMidpoint + halfWidth)

        let name: String
        if learnedMidpoint <= defaultMidpoint - 3 {
            name = "Cool-Weather \(activity.rawValue)"
        } else if learnedMidpoint >= defaultMidpoint + 3 {
            name = "Warm-Weather \(activity.rawValue)"
        } else {
            name = "Balanced \(activity.rawValue)"
        }

        let sensitivityMinimum = max(2, Int(ceil(Double(completed.count) * 0.3)))
        let windySessions = completed.filter { $0.selectedIssues.contains(.windy) }
        let wetSessions = completed.filter { $0.selectedIssues.contains(.wet) }
        let humidSessions = completed.filter { $0.selectedIssues.contains(.humid) }
        let harshUVSessions = completed.filter { $0.selectedIssues.contains(.harshUV) }

        var badges: [String] = []
        if windySessions.count >= sensitivityMinimum {
            badges.append("Calm-wind fan")
        }
        if wetSessions.count >= sensitivityMinimum {
            badges.append("Dry-weather fan")
        }
        if humidSessions.count >= sensitivityMinimum {
            badges.append("Low-humidity fan")
        }
        if harshUVSessions.count >= sensitivityMinimum {
            badges.append("Shade seeker")
        }
        if badges.isEmpty {
            badges.append("Comfort calibrated")
        }

        return MoveDNAProfile(
            activity: activity,
            name: name,
            preferredTemperatureRange: learnedRange,
            checkInCount: completed.count,
            badges: badges,
            windSensitivityThreshold: threshold(
                from: windySessions,
                minimumCount: sensitivityMinimum,
                value: \.forecastWindSpeed
            ),
            rainSensitivityThreshold: integerThreshold(
                from: wetSessions,
                minimumCount: sensitivityMinimum,
                value: \.forecastPrecipitationProbability
            ),
            humiditySensitivityThreshold: integerThreshold(
                from: humidSessions,
                minimumCount: sensitivityMinimum,
                value: \.forecastRelativeHumidity
            ),
            uvSensitivityThreshold: threshold(
                from: harshUVSessions,
                minimumCount: sensitivityMinimum,
                value: \.forecastUVIndex
            )
        )
    }

    private func completedSessions(
        for activity: Activity,
        sessions: [ActivitySession]
    ) -> [ActivitySession] {
        sessions.filter { session in
            session.activity == activity
                && session.status == .completed
                && session.temperatureFeedback != nil
        }
    }

    private func threshold(
        from sessions: [ActivitySession],
        minimumCount: Int,
        value: KeyPath<ActivitySession, Double>
    ) -> Double? {
        guard sessions.count >= minimumCount else {
            return nil
        }
        return sessions.map { $0[keyPath: value] }.min()
    }

    private func integerThreshold(
        from sessions: [ActivitySession],
        minimumCount: Int,
        value: KeyPath<ActivitySession, Int>
    ) -> Int? {
        guard sessions.count >= minimumCount else {
            return nil
        }
        return sessions.map { $0[keyPath: value] }.min()
    }
}
