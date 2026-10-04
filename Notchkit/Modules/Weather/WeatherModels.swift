import Foundation

/// Météo prête à afficher.
struct WeatherSnapshot: Equatable, Sendable {
    struct Hour: Equatable, Sendable, Identifiable {
        var id: Date { date }
        let date: Date
        let temperature: Double
        let code: Int
        let isDay: Bool
    }

    let temperature: Double
    let apparentTemperature: Double
    /// Code météo WMO (voir `WeatherCondition`).
    let code: Int
    let isDay: Bool
    let high: Double?
    let low: Double?
    let precipitationChance: Int?
    let hours: [Hour]
    var locationName: String?
    let fetchedAt: Date
}

/// Lieu choisi manuellement (résultat du géocodage Open-Meteo).
struct WeatherPlace: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let admin1: String?
    let country: String?
    let latitude: Double
    let longitude: Double

    /// Ex. « Villers-les-Bois, Bourgogne, France ».
    var fullName: String {
        [name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - Réponses Open-Meteo

/// Réponse de l'API de prévisions (https://open-meteo.com/en/docs).
struct OpenMeteoForecast: Decodable {
    // Clés explicites : la conversion automatique depuis le snake_case gère mal « _2m ».
    struct Current: Decodable {
        let temperature2m: Double
        let apparentTemperature: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature2m: [Double]
        let weatherCode: [Int]
        let isDay: [Int]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable {
        let temperature2mMax: [Double?]
        let temperature2mMin: [Double?]
        let precipitationProbabilityMax: [Int?]?

        enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }

    let utcOffsetSeconds: Int
    let current: Current
    let hourly: Hourly?
    let daily: Daily?

    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case current, hourly, daily
    }

    static func decode(_ data: Data) throws -> OpenMeteoForecast {
        try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
    }

    func snapshot(fetchedAt: Date = Date()) -> WeatherSnapshot {
        // Les heures sont en heure locale du lieu, sans fuseau : on applique le décalage fourni.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds)

        var hours: [WeatherSnapshot.Hour] = []
        if let hourly {
            let count = min(hourly.time.count, hourly.temperature2m.count, hourly.weatherCode.count, hourly.isDay.count)
            for index in 0..<count {
                guard let date = formatter.date(from: hourly.time[index]) else { continue }
                hours.append(WeatherSnapshot.Hour(
                    date: date,
                    temperature: hourly.temperature2m[index],
                    code: hourly.weatherCode[index],
                    isDay: hourly.isDay[index] == 1
                ))
            }
        }

        return WeatherSnapshot(
            temperature: current.temperature2m,
            apparentTemperature: current.apparentTemperature,
            code: current.weatherCode,
            isDay: current.isDay == 1,
            high: daily?.temperature2mMax.first ?? nil,
            low: daily?.temperature2mMin.first ?? nil,
            precipitationChance: daily?.precipitationProbabilityMax?.first ?? nil,
            hours: hours,
            locationName: nil,
            fetchedAt: fetchedAt
        )
    }
}

/// Réponse de l'API de géocodage.
struct OpenMeteoGeocoding: Decodable {
    let results: [WeatherPlace]?
}

// MARK: - Codes météo WMO

enum WeatherCondition {
    /// SF Symbol correspondant (version jour ou nuit).
    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(code: Int) -> LocalizedStringResource {
        switch code {
        case 0: "Ciel dégagé"
        case 1: "Peu nuageux"
        case 2: "Partiellement nuageux"
        case 3: "Couvert"
        case 45, 48: "Brouillard"
        case 51, 53, 55: "Bruine"
        case 56, 57: "Bruine verglaçante"
        case 61: "Pluie faible"
        case 63: "Pluie"
        case 65: "Forte pluie"
        case 66, 67: "Pluie verglaçante"
        case 71, 73: "Neige"
        case 75: "Fortes chutes de neige"
        case 77: "Grains de neige"
        case 80, 81: "Averses"
        case 82: "Fortes averses"
        case 85, 86: "Averses de neige"
        case 95: "Orage"
        case 96, 99: "Orage avec grêle"
        default: "Conditions inconnues"
        }
    }
}

/// Formatage des températures selon les préférences de l'utilisateur (°C ou °F).
enum TemperatureFormat {
    static func string(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
