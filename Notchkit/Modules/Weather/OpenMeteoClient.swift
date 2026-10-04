import Foundation

/// Client de l'API Open-Meteo (gratuite, sans clé ; données sous licence CC BY 4.0).
///
/// ⚠️ L'offre gratuite est réservée à un usage non commercial. Si Notchkit devient payant,
/// il faudra souscrire à l'offre commerciale d'Open-Meteo (ou changer de fournisseur).
enum OpenMeteoClient {
    enum ClientError: Error {
        case invalidResponse
    }

    static func forecast(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_hours", value: "6"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let data = try await fetch(components)
        return try OpenMeteoForecast.decode(data).snapshot()
    }

    static func searchPlaces(_ name: String) async throws -> [WeatherPlace] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "fr"),
        ]
        let data = try await fetch(components)
        return try JSONDecoder().decode(OpenMeteoGeocoding.self, from: data).results ?? []
    }

    private static func fetch(_ components: URLComponents) async throws -> Data {
        guard let url = components.url else { throw ClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClientError.invalidResponse
        }
        return data
    }
}
