import Foundation

struct ForecastResponse: Decodable {
    let current: CurrentWeather
    let hourly: HourlyWeatherData
}

struct WeatherSnapshot {
    let current: CurrentWeather
    let hourly: [HourlyForecast]
}

struct HourlyWeatherData: Decodable {
    let time: [String]
    let temperature: [Double]
    let apparentTemperature: [Double]
    let relativeHumidity: [Int]
    let precipitationProbability: [Int?]
    let windSpeed: [Double]
    let uvIndex: [Double]
    let weatherCode: [Int]
    let isDay: [Int]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity = "relative_humidity_2m"
        case precipitationProbability = "precipitation_probability"
        case windSpeed = "wind_speed_10m"
        case uvIndex = "uv_index"
        case weatherCode = "weather_code"
        case isDay = "is_day"
    }
}

struct HourlyForecast: Identifiable {
    let time: String
    let temperature: Double
    let apparentTemperature: Double
    let relativeHumidity: Int
    let precipitationProbability: Int
    let windSpeed: Double
    let uvIndex: Double
    let weatherCode: Int
    let isDay: Int

    var id: String { time }

    var dayKey: String {
        String(time.prefix(10))
    }

    var dayLabel: String {
        guard let date = parsedDate else {
            return dayKey
        }

        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    var isCurrentOrFutureHour: Bool {
        guard let date = parsedDate else {
            return false
        }

        return date.addingTimeInterval(60 * 60) > Date()
    }

    var date: Date? {
        parsedDate
    }

    var localHour: Int? {
        guard let date = parsedDate else {
            return nil
        }

        return Calendar.current.component(.hour, from: date)
    }

    var hasSevereWeather: Bool {
        switch weatherCode {
        case 66, 67, 71...77, 85, 86, 95, 96, 99:
            return true
        default:
            return false
        }
    }

    var hourLabel: String {
        formattedHour(adding: 0)
    }

    var endHourLabel: String {
        formattedHour(adding: 60 * 60)
    }

    private func formattedHour(adding seconds: TimeInterval) -> String {
        guard let date = parsedDate else {
            return time
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "h a"
        return outputFormatter.string(from: date.addingTimeInterval(seconds))
    }

    private var parsedDate: Date? {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return inputFormatter.date(from: time)
    }

    var symbolName: String {
        switch weatherCode {
        case 0:
            return isDay == 1 ? "sun.max.fill" : "moon.stars.fill"
        case 1...3:
            return isDay == 1 ? "cloud.sun.fill" : "cloud.moon.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51...67, 80...82:
            return "cloud.rain.fill"
        case 71...77, 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}

struct CurrentWeather: Decodable {
    let temperature: Double
    let apparentTemperature: Double
    let weatherCode: Int
    let isDay: Int

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case weatherCode = "weather_code"
        case isDay = "is_day"
    }

    var condition: String {
        switch weatherCode {
        case 0:
            return "Clear"
        case 1...3:
            return "Partly Cloudy"
        case 45, 48:
            return "Foggy"
        case 51...57:
            return "Drizzle"
        case 61...67, 80...82:
            return "Rainy"
        case 71...77, 85, 86:
            return "Snowy"
        case 95, 96, 99:
            return "Thunderstorm"
        default:
            return "Unknown Conditions"
        }
    }

    var symbolName: String {
        switch weatherCode {
        case 0:
            return isDay == 1 ? "sun.max.fill" : "moon.stars.fill"
        case 1...3:
            return isDay == 1 ? "cloud.sun.fill" : "cloud.moon.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51...67, 80...82:
            return "cloud.rain.fill"
        case 71...77, 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}

enum WeatherServiceError: Error {
    case invalidURL
    case invalidResponse
}

struct WeatherService {
    func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,weather_code,is_day"
            ),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,wind_speed_10m,uv_index,weather_code,is_day"
            ),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw WeatherServiceError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherServiceError.invalidResponse
        }

        let forecastResponse = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let hourly = forecastResponse.hourly
        let count = [
            hourly.time.count,
            hourly.temperature.count,
            hourly.apparentTemperature.count,
            hourly.relativeHumidity.count,
            hourly.precipitationProbability.count,
            hourly.windSpeed.count,
            hourly.uvIndex.count,
            hourly.weatherCode.count,
            hourly.isDay.count
        ].min() ?? 0

        let forecasts = (0..<count).map { index in
            HourlyForecast(
                time: hourly.time[index],
                temperature: hourly.temperature[index],
                apparentTemperature: hourly.apparentTemperature[index],
                relativeHumidity: hourly.relativeHumidity[index],
                precipitationProbability: hourly.precipitationProbability[index] ?? 0,
                windSpeed: hourly.windSpeed[index],
                uvIndex: hourly.uvIndex[index],
                weatherCode: hourly.weatherCode[index],
                isDay: hourly.isDay[index]
            )
        }

        return WeatherSnapshot(current: forecastResponse.current, hourly: forecasts)
    }
}
