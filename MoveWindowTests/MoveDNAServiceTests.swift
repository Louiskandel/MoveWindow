import XCTest
import SwiftData
@testable import MoveWindow

final class MoveDNAServiceTests: XCTestCase {
    func testProfileStaysLockedUntilFiveCompletedCheckIns() {
        let sessions = (0..<4).map { index in
            makeSession(index: index, feedback: .justRight)
        }

        XCTAssertNil(MoveDNAService().profile(for: .walking, sessions: sessions))

        let unlockedSessions = sessions + [makeSession(index: 4, feedback: .justRight)]
        XCTAssertNotNil(MoveDNAService().profile(for: .walking, sessions: unlockedSessions))
    }

    func testTooColdFeedbackMovesRangeWarmerAndClampsAtEightDegrees() throws {
        let sessions = (0..<5).map { index in
            makeSession(index: index, feedback: .tooCold)
        }

        let profile = try XCTUnwrap(
            MoveDNAService().profile(for: .walking, sessions: sessions)
        )

        XCTAssertEqual(profile.preferredTemperatureRange.lowerBound, 63, accuracy: 0.001)
        XCTAssertEqual(profile.preferredTemperatureRange.upperBound, 86, accuracy: 0.001)
        XCTAssertEqual(profile.name, "Warm-Weather Walking")
    }

    func testTooHotFeedbackMovesRangeCoolerAndClampsAtEightDegrees() throws {
        let sessions = (0..<5).map { index in
            makeSession(index: index, feedback: .tooHot)
        }

        let profile = try XCTUnwrap(
            MoveDNAService().profile(for: .walking, sessions: sessions)
        )

        XCTAssertEqual(profile.preferredTemperatureRange.lowerBound, 47, accuracy: 0.001)
        XCTAssertEqual(profile.preferredTemperatureRange.upperBound, 70, accuracy: 0.001)
        XCTAssertEqual(profile.name, "Cool-Weather Walking")
    }

    func testFeedbackDoesNotLeakBetweenActivities() {
        let walkingSessions = (0..<5).map { index in
            makeSession(index: index, activity: .walking, feedback: .justRight)
        }

        XCTAssertNotNil(
            MoveDNAService().profile(for: .walking, sessions: walkingSessions)
        )
        XCTAssertNil(
            MoveDNAService().profile(for: .running, sessions: walkingSessions)
        )
    }

    func testPersonalizationNeverOverridesSevereWeatherOrDarkness() throws {
        let sessions = (0..<5).map { index in
            makeSession(index: index, feedback: .justRight)
        }
        let profile = try XCTUnwrap(
            MoveDNAService().profile(for: .walking, sessions: sessions)
        )

        let severeForecast = makeForecast(weatherCode: 95, isDay: 1)
        let darkForecast = makeForecast(weatherCode: 0, isDay: 0)
        let service = RecommendationService()

        XCTAssertTrue(
            service.recommendations(
                for: .walking,
                from: [severeForecast],
                profile: profile
            ).isEmpty
        )
        XCTAssertTrue(
            service.recommendations(
                for: .walking,
                from: [darkForecast],
                profile: profile
            ).isEmpty
        )
    }

    func testReportedWindDiscomfortCanOnlyLowerFutureScore() throws {
        let sessions = (0..<5).map { index in
            makeSession(
                index: index,
                feedback: .justRight,
                issues: index < 2 ? [.windy] : []
            )
        }
        let profile = try XCTUnwrap(
            MoveDNAService().profile(for: .walking, sessions: sessions)
        )
        let forecast = makeForecast(windSpeed: 4)
        let service = RecommendationService()

        let normalScore = try XCTUnwrap(
            service.recommendations(for: .walking, from: [forecast]).first?.score
        )
        let personalizedScore = try XCTUnwrap(
            service.recommendations(
                for: .walking,
                from: [forecast],
                profile: profile
            ).first?.score
        )

        XCTAssertLessThan(personalizedScore, normalScore)
    }

    func testExistingSessionPreventsDuplicateActivityAndHour() throws {
        let session = makeSession(index: 0, feedback: nil)
        let match = MoveDNAService().existingSession(
            for: .walking,
            startingAt: session.plannedStart,
            sessions: [session]
        )

        XCTAssertEqual(try XCTUnwrap(match).id, session.id)
        XCTAssertNil(
            MoveDNAService().existingSession(
                for: .running,
                startingAt: session.plannedStart,
                sessions: [session]
            )
        )
    }

    @MainActor
    func testActivitySessionPersistsInAnOnDeviceModelContainer() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ActivitySession.self,
            configurations: configuration
        )
        let context = container.mainContext
        let session = makeSession(index: 0, feedback: nil)

        context.insert(session)
        try context.save()

        let storedSessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(storedSessions.count, 1)
        XCTAssertEqual(storedSessions.first?.id, session.id)
    }

    private func makeSession(
        index: Int,
        activity: Activity = .walking,
        feedback: TemperatureFeedback?,
        issues: Set<ConditionIssue> = []
    ) -> ActivitySession {
        let forecast = makeForecast(time: String(format: "2026-07-20T%02d:00", 8 + index))
        let recommendation = ActivityRecommendation(
            activity: activity,
            forecast: forecast,
            score: 90,
            reasons: ["Test recommendation"]
        )
        let session = ActivitySession(
            activity: activity,
            city: .sunnyvale,
            recommendation: recommendation
        )

        if let feedback {
            session.complete(with: feedback, issues: issues)
        }
        return session
    }

    private func makeForecast(
        time: String = "2026-07-20T10:00",
        windSpeed: Double = 3,
        weatherCode: Int = 0,
        isDay: Int = 1
    ) -> HourlyForecast {
        HourlyForecast(
            time: time,
            temperature: 65,
            apparentTemperature: 65,
            relativeHumidity: 50,
            precipitationProbability: 5,
            windSpeed: windSpeed,
            uvIndex: 2,
            weatherCode: weatherCode,
            isDay: isDay
        )
    }
}
