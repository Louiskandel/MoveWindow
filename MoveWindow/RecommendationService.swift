import Foundation

struct ActivityRecommendation {
    let activity: Activity
    let forecast: HourlyForecast
    let score: Int
    let reasons: [String]

    var timeWindow: String {
        let window = "\(forecast.hourLabel) – \(forecast.endHourLabel)"
        return activity == .camping ? "Set up \(window)" : window
    }

    var briefExplanation: String {
        let mostUsefulReasons = reasons.prefix(4)
        return mostUsefulReasons.joined(separator: " • ") + "."
    }
}

extension Activity {
    var preferredTemperatureRange: ClosedRange<Double> {
        switch self {
        case .walking:
            return 55...78
        case .running:
            return 45...68
        case .cycling:
            return 50...78
        case .hiking:
            return 45...75
        case .fishing:
            return 45...82
        case .camping:
            return 40...85
        }
    }

    var maximumComfortableWindSpeed: Double {
        switch self {
        case .walking, .running:
            return 10
        case .cycling:
            return 16
        case .fishing:
            return 12
        case .hiking:
            return 5
        case .camping:
            return 15
        }
    }
}

struct RecommendationService {
    func bestRecommendation(
        for activity: Activity,
        from forecasts: [HourlyForecast],
        hikingDayKey: String? = nil,
        allForecasts: [HourlyForecast] = [],
        preferredHour: Int? = nil,
        profile: MoveDNAProfile? = nil
    ) -> ActivityRecommendation? {
        recommendations(
            for: activity,
            from: forecasts,
            limit: 1,
            hikingDayKey: hikingDayKey,
            allForecasts: allForecasts,
            preferredHour: preferredHour,
            profile: profile
        ).first
    }

    func recommendations(
        for activity: Activity,
        from forecasts: [HourlyForecast],
        limit: Int = 3,
        hikingDayKey: String? = nil,
        allForecasts: [HourlyForecast] = [],
        preferredHour: Int? = nil,
        profile: MoveDNAProfile? = nil
    ) -> [ActivityRecommendation] {
        let forecastContext = allForecasts.isEmpty ? forecasts : allForecasts
        let activeProfile = profile?.activity == activity ? profile : nil
        var candidates: [ActivityRecommendation] = []

        for forecast in forecasts where isEligible(
            forecast,
            for: activity,
            hikingDayKey: hikingDayKey,
            allForecasts: forecastContext,
            profile: activeProfile
        ) {
            candidates.append(
                makeRecommendation(
                    for: activity,
                    forecast: forecast,
                    preferredHour: preferredHour,
                    profile: activeProfile
                )
            )
        }

        let rankedCandidates = candidates.sorted { first, second in
            if first.score == second.score {
                return first.forecast.time < second.forecast.time
            }
            return first.score > second.score
        }

        return Array(rankedCandidates.prefix(max(0, limit)))
    }

    func coolestSafeHikingDay(from forecasts: [HourlyForecast]) -> String? {
        var discoveredDays: Set<String> = []
        var bestDayKey: String?
        var lowestAverageTemperature = Double.greatestFiniteMagnitude

        for forecast in forecasts {
            guard discoveredDays.insert(forecast.dayKey).inserted else {
                continue
            }

            let safeDaylightHours = forecasts.filter { candidate in
                candidate.dayKey == forecast.dayKey
                    && candidate.isCurrentOrFutureHour
                    && candidate.isDay == 1
                    && candidate.windSpeed <= Activity.hiking.maximumComfortableWindSpeed
                    && candidate.precipitationProbability <= 20
                    && !candidate.hasSevereWeather
            }

            guard !safeDaylightHours.isEmpty else {
                continue
            }

            let totalTemperature = safeDaylightHours.reduce(0.0) {
                $0 + $1.apparentTemperature
            }
            let averageTemperature = totalTemperature / Double(safeDaylightHours.count)

            if averageTemperature < lowestAverageTemperature {
                lowestAverageTemperature = averageTemperature
                bestDayKey = forecast.dayKey
            }
        }

        return bestDayKey
    }

    func unavailabilityExplanation(
        for activity: Activity,
        from forecasts: [HourlyForecast],
        hikingDayKey: String? = nil,
        allForecasts: [HourlyForecast] = [],
        profile: MoveDNAProfile? = nil
    ) -> String {
        guard !forecasts.isEmpty else {
            return "No forecast hours are available inside the selected time frame."
        }

        let forecastContext = allForecasts.isEmpty ? forecasts : allForecasts
        var problemCounts: [String: Int] = [:]

        for forecast in forecasts {
            let problems = eligibilityProblems(
                for: forecast,
                activity: activity,
                hikingDayKey: hikingDayKey,
                allForecasts: forecastContext,
                profile: profile?.activity == activity ? profile : nil
            )

            for problem in problems {
                problemCounts[problem, default: 0] += 1
            }
        }

        let mainProblems = problemCounts
            .sorted { first, second in
                if first.value == second.value {
                    return first.key < second.key
                }
                return first.value > second.value
            }
            .prefix(3)
            .map(\.key)

        guard !mainProblems.isEmpty else {
            return "No hour passed all of the activity and weather-safety checks."
        }

        return "No hour qualifies because "
            + mainProblems.joined(separator: ", ")
            + ". Try a wider time frame or another forecast day."
    }

    private func isEligible(
        _ forecast: HourlyForecast,
        for activity: Activity,
        hikingDayKey: String?,
        allForecasts: [HourlyForecast],
        profile: MoveDNAProfile?
    ) -> Bool {
        eligibilityProblems(
            for: forecast,
            activity: activity,
            hikingDayKey: hikingDayKey,
            allForecasts: allForecasts,
            profile: profile
        ).isEmpty
    }

    private func eligibilityProblems(
        for forecast: HourlyForecast,
        activity: Activity,
        hikingDayKey: String?,
        allForecasts: [HourlyForecast],
        profile: MoveDNAProfile?
    ) -> [String] {
        var problems: [String] = []
        let preferredTemperature = profile?.preferredTemperatureRange
            ?? activity.preferredTemperatureRange

        if forecast.hasSevereWeather {
            problems.append("severe weather is forecast")
        }

        switch activity {
        case .walking, .running:
            if forecast.isDay != 1 {
                problems.append("it is outside daylight hours")
            }
            if !preferredTemperature.contains(forecast.apparentTemperature) {
                problems.append("the feels-like temperature is outside the comfortable range")
            }
            if forecast.windSpeed > activity.maximumComfortableWindSpeed {
                problems.append("wind is too strong")
            }
            if forecast.relativeHumidity > 85 {
                problems.append("humidity is too high")
            }
        case .cycling:
            if forecast.isDay != 1 {
                problems.append("it is outside daylight hours")
            }
            if !preferredTemperature.contains(forecast.apparentTemperature) {
                problems.append("the feels-like temperature is outside the comfortable range")
            }
            if forecast.windSpeed > activity.maximumComfortableWindSpeed {
                problems.append("wind is too strong")
            }
            if forecast.precipitationProbability > 30 {
                problems.append("rain chance is above 30%")
            }
        case .fishing:
            if let hour = forecast.localHour {
                if !(18...22).contains(hour) {
                    problems.append("it is outside the preferred 6–10 PM fishing period")
                }
            } else {
                problems.append("the forecast time is unavailable")
            }
            if !preferredTemperature.contains(forecast.apparentTemperature) {
                problems.append("the feels-like temperature is outside the comfortable range")
            }
            if forecast.windSpeed > activity.maximumComfortableWindSpeed {
                problems.append("wind is too strong")
            }
        case .hiking:
            if forecast.dayKey != hikingDayKey {
                problems.append("this is not the coolest safe hiking day")
            }
            if forecast.isDay != 1 {
                problems.append("it is outside daylight hours")
            }
            if forecast.windSpeed > activity.maximumComfortableWindSpeed {
                problems.append("wind is above the 5 mph hiking limit")
            }
            if forecast.precipitationProbability > 20 {
                problems.append("rain chance is above 20%")
            }
        case .camping:
            if let hour = forecast.localHour {
                if !(14...18).contains(hour) {
                    problems.append("it is outside the 2–6 PM campsite setup period")
                }
            } else {
                problems.append("the forecast time is unavailable")
            }
            if forecast.isDay != 1 {
                problems.append("it is outside daylight hours")
            }
            if !preferredTemperature.contains(forecast.apparentTemperature) {
                problems.append("the feels-like temperature is outside the comfortable range")
            }
            if forecast.windSpeed > activity.maximumComfortableWindSpeed {
                problems.append("wind is too strong")
            }
            if forecast.precipitationProbability > 30 {
                problems.append("rain chance is above 30%")
            }
            if !hasSafeCampingWindow(startingAt: forecast, within: allForecasts) {
                problems.append("the following hours are not safe enough for camping")
            }
        }

        return problems
    }

    private func hasSafeCampingWindow(
        startingAt forecast: HourlyForecast,
        within forecasts: [HourlyForecast]
    ) -> Bool {
        guard let startingIndex = forecasts.firstIndex(where: { $0.id == forecast.id }) else {
            return false
        }

        let endingIndex = min(startingIndex + 6, forecasts.endIndex)
        let campingWindow = forecasts[startingIndex..<endingIndex]

        guard campingWindow.count >= 4 else {
            return false
        }

        return campingWindow.allSatisfy { hour in
            !hour.hasSevereWeather
                && hour.windSpeed <= 20
                && hour.precipitationProbability <= 40
                && (35...90).contains(hour.apparentTemperature)
        }
    }

    private func makeRecommendation(
        for activity: Activity,
        forecast: HourlyForecast,
        preferredHour: Int?,
        profile: MoveDNAProfile?
    ) -> ActivityRecommendation {
        var score = 100
        var reasons: [String] = []

        switch activity {
        case .walking, .running:
            reasons.append("After sunrise")
        case .fishing:
            reasons.append("Late evening")
        case .hiking:
            reasons.append("Coolest safe day")
        case .cycling:
            break
        case .camping:
            reasons.append("Set up before dark")
            reasons.append("Safe six-hour outlook")
        }

        let preferredTemperature = profile?.preferredTemperatureRange
            ?? activity.preferredTemperatureRange
        if forecast.apparentTemperature < preferredTemperature.lowerBound {
            let difference = preferredTemperature.lowerBound - forecast.apparentTemperature
            score -= min(Int((difference * 2).rounded()), 35)
            reasons.append("Cooler than ideal")
        } else if forecast.apparentTemperature > preferredTemperature.upperBound {
            let difference = forecast.apparentTemperature - preferredTemperature.upperBound
            score -= min(Int((difference * 2).rounded()), 35)
            reasons.append("Warmer than ideal")
        } else {
            if let profile {
                reasons.append("Matches your MoveDNA \(profile.temperatureRangeLabel)")
            } else {
                reasons.append("Comfortable feels-like temperature")
            }
        }

        if forecast.relativeHumidity >= 85 {
            score -= 20
            reasons.append("Very humid")
        } else if forecast.relativeHumidity >= 70 {
            score -= 10
            reasons.append("High humidity")
        }

        if forecast.uvIndex >= 8 {
            score -= 20
            reasons.append("Very high UV")
        } else if forecast.uvIndex >= 6 {
            score -= 10
            reasons.append("High UV")
        } else if forecast.uvIndex >= 3 {
            score -= 5
            reasons.append("Sun protection needed")
        } else {
            reasons.append("Low UV")
        }

        switch forecast.precipitationProbability {
        case 70...100:
            score -= 45
            reasons.append("High rain chance")
        case 40..<70:
            score -= 25
            reasons.append("Possible rain")
        case 20..<40:
            score -= 10
            reasons.append("Slight rain chance")
        default:
            reasons.append("Low rain chance")
        }

        let comfortableWind = activity.maximumComfortableWindSpeed
        if forecast.windSpeed > comfortableWind + 10 {
            score -= 35
            reasons.append("Strong wind")
        } else if forecast.windSpeed > comfortableWind {
            score -= 20
            reasons.append("Windy")
        } else {
            reasons.append("Light wind")
        }

        switch forecast.weatherCode {
        case 95, 96, 99:
            score -= 60
            reasons.append("Thunderstorms expected")
        case 66, 67:
            score -= 30
            reasons.append("Freezing rain possible")
        case 71...77, 85, 86:
            score -= 25
            reasons.append("Snow possible")
        default:
            break
        }

        if let profile {
            let adjustment = profile.sensitivityAdjustment(for: forecast)
            score -= adjustment.penalty
            reasons.append(contentsOf: adjustment.reasons)
        }

        if let preferredHour, let forecastHour = forecast.localHour {
            let hourDifference = abs(forecastHour - preferredHour)
            score -= min(hourDifference * 4, 24)

            if hourDifference == 0 {
                reasons.append("Matches desired start time")
            } else if hourDifference == 1 {
                reasons.append("Near desired start time")
            }
        }

        return ActivityRecommendation(
            activity: activity,
            forecast: forecast,
            score: max(0, min(score, 100)),
            reasons: reasons
        )
    }
}
