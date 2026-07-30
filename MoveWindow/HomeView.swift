import SwiftUI
import SwiftData

enum Activity: String, CaseIterable, Identifiable {
    case walking = "Walking"
    case running = "Running"
    case cycling = "Cycling"
    case hiking = "Hiking"
    case fishing = "Fishing"
    case camping = "Camping"

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .walking:
            return "figure.walk"
        case .running:
            return "figure.run"
        case .cycling:
            return "figure.outdoor.cycle"
        case .hiking:
            return "figure.hiking"
        case .fishing:
            return "figure.fishing"
        case .camping:
            return "tent.fill"
        }
    }
}

struct ForecastDay: Identifiable {
    let id: String
    let label: String
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivitySession.plannedStart, order: .reverse)
    private var activitySessions: [ActivitySession]

    @State private var selectedCity = City.sunnyvale
    @State private var selectedActivity = Activity.walking
    @State private var currentWeather: CurrentWeather?
    @State private var hourlyForecasts: [HourlyForecast] = []
    @State private var isLoadingWeather = false
    @State private var weatherErrorMessage: String?
    @State private var usePreferredTimeFrame = false
    @State private var preferredStartTime = Calendar.current.date(
        bySettingHour: 8,
        minute: 0,
        second: 0,
        of: Date()
    ) ?? Date()
    @State private var preferredEndTime = Calendar.current.date(
        bySettingHour: 20,
        minute: 0,
        second: 0,
        of: Date()
    ) ?? Date()
    @State private var activeAlerts: [WeatherAlert] = []
    @State private var alertsUnavailable = false
    @State private var checkInSession: ActivitySession?
    @State private var shareItem: MoveDNAShareItem?
    @State private var appMessage: String?

    private var moveDNAProfile: MoveDNAProfile? {
        MoveDNAService().profile(for: selectedActivity, sessions: activitySessions)
    }

    private var moveDNACheckInCount: Int {
        MoveDNAService().completedCheckInCount(
            for: selectedActivity,
            sessions: activitySessions
        )
    }

    private var dueSession: ActivitySession? {
        activitySessions
            .filter(\.isDueForCheckIn)
            .sorted { $0.plannedEnd < $1.plannedEnd }
            .first
    }

    private var recommendations: [ActivityRecommendation] {
        guard blockingAlert == nil else {
            return []
        }

        return RecommendationService().recommendations(
            for: selectedActivity,
            from: forecastsInsidePreferredTimeFrame,
            limit: 3,
            hikingDayKey: hikingDayKey,
            allForecasts: hourlyForecasts,
            profile: moveDNAProfile
        )
    }

    private var blockingAlert: WeatherAlert? {
        guard let start = selectedDayForecasts.first?.date,
              let lastDate = selectedDayForecasts.last?.date else {
            return nil
        }

        let end = lastDate.addingTimeInterval(60 * 60)
        return activeAlerts.first { alert in
            alert.blocksOutdoorRecommendations && alert.overlaps(start: start, end: end)
        }
    }

    private var preferredStartMinute: Int {
        minuteOfDay(for: preferredStartTime)
    }

    private var preferredEndMinute: Int {
        minuteOfDay(for: preferredEndTime)
    }

    private var hasValidPreferredTimeFrame: Bool {
        !usePreferredTimeFrame || preferredEndMinute - preferredStartMinute >= 60
    }

    private var preferredTimeFrameLabel: String {
        "\(formattedTime(preferredStartTime))–\(formattedTime(preferredEndTime))"
    }

    private var forecastsInsidePreferredTimeFrame: [HourlyForecast] {
        guard usePreferredTimeFrame else {
            return selectedDayForecasts
        }

        guard hasValidPreferredTimeFrame else {
            return []
        }

        return selectedDayForecasts.filter { forecast in
            guard let hour = forecast.localHour else {
                return false
            }

            let slotStart = hour * 60
            let slotEnd = slotStart + 60
            return slotStart >= preferredStartMinute && slotEnd <= preferredEndMinute
        }
    }

    private var hikingDayKey: String? {
        RecommendationService().coolestSafeHikingDay(from: hourlyForecasts)
    }

    private var hikingDayLabel: String? {
        guard let hikingDayKey else {
            return nil
        }

        return forecastDays.first(where: { $0.id == hikingDayKey })?.label
    }

    private var unavailableRecommendationMessage: String {
        if let blockingAlert {
            return "Official NWS \(blockingAlert.event) conditions overlap this day. Outdoor recommendations are paused."
        }

        if usePreferredTimeFrame && !hasValidPreferredTimeFrame {
            return "Choose an end time that is at least one hour after the start time."
        }

        if usePreferredTimeFrame && forecastsInsidePreferredTimeFrame.isEmpty {
            return "No complete one-hour forecast slot remains inside \(preferredTimeFrameLabel) on \(selectedDayLabel). Try a wider or later time frame."
        }

        let serviceExplanation = RecommendationService().unavailabilityExplanation(
            for: selectedActivity,
            from: forecastsInsidePreferredTimeFrame,
            hikingDayKey: hikingDayKey,
            allForecasts: hourlyForecasts,
            profile: moveDNAProfile
        )

        if !serviceExplanation.isEmpty {
            return serviceExplanation
        }

        switch selectedActivity {
        case .walking, .running:
            return "No remaining hour meets the daylight, moderate-temperature, and light-wind rules."
        case .fishing:
            return "No late-evening hour from 6 PM through 10 PM is available for this day."
        case .hiking:
            if let hikingDayLabel {
                return "The coolest safe hiking day this week is \(hikingDayLabel)."
            }
            return "No daylight hour this week has very light wind and safe weather."
        case .cycling:
            return "No suitable hour is available because severe weather is forecast."
        case .camping:
            return "No daylight setup hour has suitable weather followed by at least four safe forecast hours."
        }
    }

    private var forecastDays: [ForecastDay] {
        var discoveredDays: Set<String> = []

        return hourlyForecasts.compactMap { forecast in
            guard discoveredDays.insert(forecast.dayKey).inserted else {
                return nil
            }

            return ForecastDay(id: forecast.dayKey, label: forecast.dayLabel)
        }
    }

    private var selectedDayForecasts: [HourlyForecast] {
        hourlyForecasts.filter { forecast in
            forecast.dayKey == selectedDayKey && forecast.isCurrentOrFutureHour
        }
    }

    private var selectedDayLabel: String {
        forecastDays.first(where: { $0.id == selectedDayKey })?.label ?? "Forecast"
    }

    @State private var selectedDayKey = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCity.displayName)
                            .font(.title2.bold())
                        Text("7-day outdoor forecast")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("City", systemImage: "mappin.and.ellipse")
                        Spacer()
                        Picker("City", selection: $selectedCity) {
                            ForEach(City.availableCities) { city in
                                Text(city.displayName)
                                    .tag(city)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    if let blockingAlert {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(blockingAlert.event, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                            Text(blockingAlert.headline ?? "An official severe weather alert is active.")
                                .font(.subheadline)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.white)
                        .background(.red, in: RoundedRectangle(cornerRadius: 14))
                    } else if alertsUnavailable {
                        Label(
                            "Official NWS alerts are temporarily unavailable.",
                            systemImage: "wifi.exclamationmark"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    } else if let advisory = activeAlerts.first {
                        Label(advisory.event, systemImage: "info.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if let dueSession {
                        MoveDNACheckInBanner(session: dueSession) {
                            checkInSession = dueSession
                        }
                    }

                    if !forecastDays.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose a forecast day")
                                .font(.subheadline.weight(.semibold))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(forecastDays) { day in
                                        Button {
                                            selectedDayKey = day.id
                                        } label: {
                                            Text(day.label)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .foregroundStyle(
                                                    selectedDayKey == day.id ? .white : .primary
                                                )
                                                .background(
                                                    selectedDayKey == day.id
                                                        ? Color.blue
                                                        : Color.gray.opacity(0.15),
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose an activity")
                            .font(.subheadline.weight(.semibold))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Activity.allCases) { activity in
                                    Button {
                                        selectedActivity = activity
                                    } label: {
                                        Label(activity.rawValue, systemImage: activity.symbolName)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .foregroundStyle(
                                                selectedActivity == activity ? .white : .primary
                                            )
                                            .background(
                                                selectedActivity == activity
                                                    ? Color.blue
                                                    : Color.gray.opacity(0.15),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    MoveDNAStatusCard(
                        activity: selectedActivity,
                        completedCheckIns: moveDNACheckInCount,
                        profile: moveDNAProfile,
                        onShare: shareMoveDNA
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "Choose an activity time frame",
                            isOn: $usePreferredTimeFrame
                        )

                        if usePreferredTimeFrame {
                            DatePicker(
                                "From",
                                selection: $preferredStartTime,
                                displayedComponents: .hourAndMinute
                            )

                            DatePicker(
                                "Until",
                                selection: $preferredEndTime,
                                displayedComponents: .hourAndMinute
                            )

                            if hasValidPreferredTimeFrame {
                                Text("Only complete one-hour slots inside \(preferredTimeFrameLabel) will be considered.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label(
                                    "The end time must be at least one hour after the start.",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(12)
                    .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    Text("Current conditions")
                        .font(.subheadline.weight(.semibold))

                    Group {
                        if let currentWeather {
                            HStack(spacing: 14) {
                                Image(systemName: currentWeather.symbolName)
                                    .font(.system(size: 46))
                                    .foregroundStyle(.yellow)

                                VStack(alignment: .leading) {
                                    Text("\(Int(currentWeather.temperature.rounded()))°F")
                                        .font(.system(size: 36, weight: .bold))
                                    Text(currentWeather.condition)
                                        .font(.subheadline)
                                    Text(
                                        "Feels like \(Int(currentWeather.apparentTemperature.rounded()))°F"
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        } else if isLoadingWeather {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Loading live weather…")
                            }
                            .frame(maxWidth: .infinity, minHeight: 100)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(
                                    weatherErrorMessage ?? "Weather is unavailable.",
                                    systemImage: "exclamationmark.triangle"
                                )
                                Button("Try Again") {
                                    Task {
                                        await loadWeather()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

                    if !selectedDayForecasts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(selectedDayLabel) hourly forecast")
                                .font(.subheadline.weight(.semibold))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(selectedDayForecasts) { forecast in
                                        HourlyForecastCard(
                                            forecast: forecast,
                                            recommendationRank: recommendationRank(for: forecast)
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if !recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                "Best times for \(selectedActivity.rawValue.lowercased())",
                                systemImage: selectedActivity.symbolName
                            )
                            .font(.subheadline.weight(.semibold))

                            if usePreferredTimeFrame {
                                Text("Inside your \(preferredTimeFrameLabel) time frame")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(
                                Array(recommendations.enumerated()),
                                id: \.element.forecast.id
                            ) { index, recommendation in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("#\(index + 1)  \(recommendation.timeWindow)")
                                            .font(.headline)
                                        Spacer()
                                        Text("\(recommendation.score)/100")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(
                                                scoreColor(for: recommendation.score)
                                            )
                                    }

                                    Text(recommendation.briefExplanation)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    if let session = existingSession(for: recommendation) {
                                        Label(
                                            sessionStatusLabel(session.status),
                                            systemImage: sessionStatusSymbol(session.status)
                                        )
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    } else {
                                        Button {
                                            plan(recommendation)
                                        } label: {
                                            Label("Plan this slot", systemImage: "calendar.badge.plus")
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    scoreColor(for: recommendation.score).opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                            }

                            if recommendations.count < 3 {
                                Text("Only \(recommendations.count) suitable one-hour \(recommendations.count == 1 ? "slot was" : "slots were") found. Unsafe hours are never added just to reach three results.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if !selectedDayForecasts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                "No suitable time for \(selectedActivity.rawValue.lowercased())",
                                systemImage: "exclamationmark.circle"
                            )
                            .font(.subheadline.weight(.semibold))

                            if usePreferredTimeFrame {
                                Text("Requested time frame: \(preferredTimeFrameLabel)")
                                    .font(.caption.weight(.semibold))
                            }

                            Text(unavailableRecommendationMessage)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            .orange.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                    }

                    if !selectedDayForecasts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Best time by activity")
                                .font(.subheadline.weight(.semibold))

                            ForEach(Activity.allCases) { activity in
                                Button {
                                    selectedActivity = activity
                                    if activity == .hiking, let hikingDayKey {
                                        selectedDayKey = hikingDayKey
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: activity.symbolName)
                                            .frame(width: 28)
                                        Text(activity.rawValue)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            if let activityRecommendation = summaryRecommendation(
                                                for: activity
                                            ) {
                                                Text(activityRecommendation.timeWindow)
                                                Text("Score \(activityRecommendation.score)")
                                                    .font(.caption)
                                                    .foregroundStyle(
                                                        scoreColor(
                                                            for: activityRecommendation.score
                                                        )
                                                    )
                                            } else if activity == .hiking,
                                                      let hikingDayLabel {
                                                Text("Best on \(hikingDayLabel)")
                                                Text("Tap to view")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                Text("No suitable hour")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                        .background(
                            .gray.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                    }

                    Text("Recommendations use feels-like temperature, humidity, rain, wind, UV, daylight, and severe-weather checks. Camping means the best time to set up before dark and requires a safe short-term outlook. These scores are guidance, not a safety guarantee.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Link(
                        "Weather data by Open-Meteo",
                        destination: URL(string: "https://open-meteo.com/")!
                    )
                    .font(.footnote)

                    Link(
                        "Official alerts by the National Weather Service",
                        destination: URL(string: "https://www.weather.gov/")!
                    )
                    .font(.footnote)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("MoveWindow")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: selectedCity) {
            await loadWeather()
        }
        .sheet(
            isPresented: Binding(
                get: { checkInSession != nil },
                set: { isPresented in
                    if !isPresented {
                        checkInSession = nil
                    }
                }
            )
        ) {
            if let checkInSession {
                MoveDNACheckInView(
                    session: checkInSession,
                    onSubmit: completeCheckIn,
                    onSkip: skipCheckIn
                )
            }
        }
        .sheet(item: $shareItem) { item in
            MoveDNAShareSheet(fileURL: item.fileURL)
        }
        .alert(
            "MoveWindow",
            isPresented: Binding(
                get: { appMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        appMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                appMessage = nil
            }
        } message: {
            Text(appMessage ?? "")
        }
    }

    @MainActor
    private func loadWeather() async {
        isLoadingWeather = true
        weatherErrorMessage = nil
        currentWeather = nil
        hourlyForecasts = []
        selectedDayKey = ""
        activeAlerts = []
        alertsUnavailable = false

        do {
            let snapshot = try await WeatherService().fetchWeather(
                latitude: selectedCity.latitude,
                longitude: selectedCity.longitude
            )
            currentWeather = snapshot.current
            hourlyForecasts = snapshot.hourly
            selectedDayKey = snapshot.hourly.first?.dayKey ?? ""

            do {
                activeAlerts = try await WeatherAlertService().fetchActiveAlerts(
                    latitude: selectedCity.latitude,
                    longitude: selectedCity.longitude
                )
            } catch {
                activeAlerts = []
                alertsUnavailable = true
            }
        } catch {
            currentWeather = nil
            hourlyForecasts = []
            weatherErrorMessage = "Couldn’t load weather. Check your connection."
        }

        isLoadingWeather = false
    }

    private func scoreColor(for score: Int) -> Color {
        if score >= 80 {
            return .green
        } else if score >= 60 {
            return .orange
        } else {
            return .red
        }
    }

    private func minuteOfDay(for date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func existingSession(
        for recommendation: ActivityRecommendation
    ) -> ActivitySession? {
        guard let forecastDate = recommendation.forecast.date else {
            return nil
        }

        return MoveDNAService().existingSession(
            for: recommendation.activity,
            startingAt: forecastDate,
            sessions: activitySessions
        )
    }

    private func plan(_ recommendation: ActivityRecommendation) {
        guard existingSession(for: recommendation) == nil else {
            return
        }

        let session = ActivitySession(
            activity: recommendation.activity,
            city: selectedCity,
            recommendation: recommendation
        )
        modelContext.insert(session)

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(session)
            appMessage = "The activity could not be saved. Please try again."
            return
        }

        Task { @MainActor in
            let reminderService = ActivityReminderService()
            if await reminderService.requestAuthorizationIfNeeded() {
                try? await reminderService.scheduleCheckInReminder(for: session)
            }
        }
    }

    private func completeCheckIn(
        _ session: ActivitySession,
        _ feedback: TemperatureFeedback,
        _ issues: Set<ConditionIssue>
    ) {
        session.complete(with: feedback, issues: issues)

        do {
            try modelContext.save()
            ActivityReminderService().cancelReminder(for: session)
            checkInSession = nil
        } catch {
            appMessage = "Your check-in could not be saved. Please try again."
        }
    }

    private func skipCheckIn(_ session: ActivitySession) {
        session.skip()

        do {
            try modelContext.save()
            ActivityReminderService().cancelReminder(for: session)
            checkInSession = nil
        } catch {
            appMessage = "The activity could not be skipped. Please try again."
        }
    }

    private func shareMoveDNA() {
        guard let moveDNAProfile else {
            return
        }

        do {
            shareItem = try MoveDNAShareService().makeShareItem(for: moveDNAProfile)
        } catch {
            appMessage = "Your MoveDNA card could not be created. Please try again."
        }
    }

    private func sessionStatusLabel(_ status: ActivitySessionStatus) -> String {
        switch status {
        case .planned:
            return "Planned"
        case .completed:
            return "Checked in"
        case .skipped:
            return "Skipped"
        }
    }

    private func sessionStatusSymbol(_ status: ActivitySessionStatus) -> String {
        switch status {
        case .planned:
            return "calendar.badge.checkmark"
        case .completed:
            return "checkmark.seal.fill"
        case .skipped:
            return "minus.circle"
        }
    }

    private func recommendationRank(for forecast: HourlyForecast) -> Int? {
        guard let index = recommendations.firstIndex(
            where: { $0.forecast.id == forecast.id }
        ) else {
            return nil
        }

        return index + 1
    }

    private func summaryRecommendation(for activity: Activity) -> ActivityRecommendation? {
        guard blockingAlert == nil else {
            return nil
        }

        let profile = MoveDNAService().profile(for: activity, sessions: activitySessions)

        return RecommendationService().bestRecommendation(
            for: activity,
            from: forecastsInsidePreferredTimeFrame,
            hikingDayKey: hikingDayKey,
            allForecasts: hourlyForecasts,
            profile: profile
        )
    }
}

struct MoveDNACheckInBanner: View {
    let session: ActivitySession
    let onCheckIn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile.fill")
                .font(.title2)
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 2) {
                Text("MoveDNA check-in ready")
                    .font(.subheadline.weight(.semibold))
                Text(
                    "How did your \(session.activity.rawValue.lowercased()) at \(session.plannedStart.formatted(date: .omitted, time: .shortened)) feel?"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Check in", action: onCheckIn)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct MoveDNAStatusCard: View {
    let activity: Activity
    let completedCheckIns: Int
    let profile: MoveDNAProfile?
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MoveDNA", systemImage: "brain.head.profile.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()

                if profile != nil {
                    Button(action: onShare) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let profile {
                Text(profile.name)
                    .font(.headline)
                Text("Your learned comfort range: \(profile.temperatureRangeLabel)")
                    .font(.subheadline)

                HStack(spacing: 6) {
                    ForEach(Array(profile.badges.prefix(2)), id: \.self) { badge in
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.indigo.opacity(0.12), in: Capsule())
                    }
                }

                Text("Based on \(profile.checkInCount) completed \(activity.rawValue.lowercased()) outings. Safety limits always stay active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let progress = min(completedCheckIns, MoveDNAService.requiredCheckIns)
                Text("\(progress) of \(MoveDNAService.requiredCheckIns) outings until your \(activity.rawValue) MoveDNA")
                    .font(.subheadline)

                ProgressView(
                    value: Double(progress),
                    total: Double(MoveDNAService.requiredCheckIns)
                )
                .tint(.indigo)

                Text("Plan a recommended slot, complete the activity, then tell MoveWindow how the weather felt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct MoveDNACheckInView: View {
    @Environment(\.dismiss) private var dismiss

    let session: ActivitySession
    let onSubmit: (ActivitySession, TemperatureFeedback, Set<ConditionIssue>) -> Void
    let onSkip: (ActivitySession) -> Void

    @State private var selectedFeedback: TemperatureFeedback?
    @State private var selectedIssues: Set<ConditionIssue> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Your outing") {
                    Label(session.activity.rawValue, systemImage: session.activity.symbolName)
                    LabeledContent(
                        "Time",
                        value: session.plannedStart.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    LabeledContent(
                        "Forecast felt like",
                        value: "\(Int(session.forecastApparentTemperature.rounded()))°F"
                    )
                }

                Section("How did the temperature feel?") {
                    ForEach(TemperatureFeedback.allCases) { feedback in
                        Button {
                            selectedFeedback = feedback
                        } label: {
                            HStack {
                                Label(feedback.rawValue, systemImage: feedback.symbolName)
                                Spacer()
                                if selectedFeedback == feedback {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    ForEach(ConditionIssue.allCases) { issue in
                        Toggle(isOn: issueBinding(for: issue)) {
                            Label(issue.label, systemImage: issue.symbolName)
                        }
                    }
                } header: {
                    Text("Anything uncomfortable? (Optional)")
                } footer: {
                    Text("This can make future scores more conservative, but it never relaxes weather-safety rules.")
                }

                Section {
                    Button {
                        guard let selectedFeedback else {
                            return
                        }
                        onSubmit(session, selectedFeedback, selectedIssues)
                    } label: {
                        Text("Save MoveDNA check-in")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedFeedback == nil)

                    Button("I didn't do this activity", role: .destructive) {
                        onSkip(session)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("How did it feel?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func issueBinding(for issue: ConditionIssue) -> Binding<Bool> {
        Binding(
            get: { selectedIssues.contains(issue) },
            set: { isSelected in
                if isSelected {
                    selectedIssues.insert(issue)
                } else {
                    selectedIssues.remove(issue)
                }
            }
        )
    }
}

struct HourlyForecastCard: View {
    let forecast: HourlyForecast
    let recommendationRank: Int?

    var body: some View {
        VStack(spacing: 6) {
            Text(forecast.hourLabel)
                .font(.subheadline.weight(.semibold))

            Image(systemName: forecast.symbolName)
                .font(.title2)
                .foregroundStyle(.yellow)

            Text("\(Int(forecast.temperature.rounded()))°")
                .font(.headline)

            Label(
                "\(forecast.precipitationProbability)%",
                systemImage: "drop.fill"
            )
            Label(
                "\(Int(forecast.windSpeed.rounded())) mph",
                systemImage: "wind"
            )
        }
        .font(.caption)
        .frame(width: 94)
        .padding(.vertical, 10)
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(outlineColor, lineWidth: recommendationRank == nil ? 0 : 2)
        }
    }

    private var outlineColor: Color {
        recommendationRank == 1 ? .green : .blue
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .modelContainer(for: ActivitySession.self, inMemory: true)
    }
}
