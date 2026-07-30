# MoveWindow

MoveWindow uses live hourly weather to recommend safe, comfortable times for walking,
running, cycling, hiking, fishing, and camping.

## MoveDNA

MoveDNA learns a separate weather comfort profile for every activity while keeping all
feedback on the device.

1. Choose a city, forecast day, activity, and optional time frame.
2. Tap **Plan this slot** on a recommendation.
3. After the activity, complete the MoveDNA check-in.
4. After five completed check-ins for one activity, a personalized profile and
   shareable card unlock.

Personalization never disables severe-weather, daylight, wind, rain, or other safety
rules. Shared cards contain no city or location.

## Run it in Xcode

1. Open `MoveWindow.xcodeproj`.
2. Select the **MoveWindow** scheme and an iPhone simulator in the toolbar.
3. Press the triangular Run button, or press `Command-R`.

Run the automated tests with **Product → Test** or `Command-U`.

## Files to explore

- `MoveWindowApp.swift` starts the app and chooses the first screen.
- `HomeView.swift` describes the screen using SwiftUI views.
- `MoveDNA.swift` stores planned activities and calculates personalized profiles.
- `RecommendationService.swift` applies activity, safety, and MoveDNA scoring rules.
