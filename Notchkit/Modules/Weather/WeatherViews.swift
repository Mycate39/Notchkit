import CoreLocation
import SwiftUI

struct WeatherExpandedView: View {
    let module: WeatherModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        Group {
            if let snapshot = module.snapshot {
                content(snapshot)
            } else {
                placeholder
            }
        }
        .padding(12)
    }

    private func content(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: WeatherCondition.symbol(code: snapshot.code, isDay: snapshot.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 0) {
                    Text(TemperatureFormat.string(snapshot.temperature))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(WeatherCondition.description(code: snapshot.code))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(detailLine(snapshot))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            if size != .small {
            HStack(spacing: 0) {
                ForEach(snapshot.hours.prefix(size == .large ? 6 : 5)) { hour in
                    VStack(spacing: 3) {
                        Text(hour.date, format: .dateTime.hour())
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Image(systemName: WeatherCondition.symbol(code: hour.code, isDay: hour.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 11))
                            .frame(height: 13)
                        Text(TemperatureFormat.string(hour.temperature))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ex. « Villers-les-Bois · ↑24° ↓11° · 💧20 % ».
    private func detailLine(_ snapshot: WeatherSnapshot) -> String {
        var parts: [String] = []
        if let name = snapshot.locationName { parts.append(name) }
        if let high = snapshot.high, let low = snapshot.low {
            parts.append("↑\(TemperatureFormat.string(high)) ↓\(TemperatureFormat.string(low))")
        }
        if let rain = snapshot.precipitationChance, rain > 0 {
            parts.append("☂︎ \(rain) %")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 8) {
            switch module.status {
            case .needsLocation:
                Image(systemName: "location.circle")
                    .font(.system(size: 20))
                Text("Position nécessaire pour la météo")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                if module.locationMode == .automatic && module.locationStatus == .notDetermined {
                    Button("Utiliser ma position", action: module.requestLocationAccess)
                        .controlSize(.small)
                }
                Button("Choisir une ville…", action: module.openSettings)
                    .controlSize(.small)
            case .failed:
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 20))
                Text("Météo indisponible")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                Button("Réessayer", action: module.refreshNow)
                    .controlSize(.small)
            case .idle, .loading:
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Réglages

struct WeatherSettingsView: View {
    @Bindable var module: WeatherModule

    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Afficher la température quand l'encoche est repliée", isOn: $module.showInCompact)

            Picker("Position", selection: $module.locationMode) {
                Text("Automatique").tag(WeatherModule.LocationMode.automatic)
                Text("Ville choisie").tag(WeatherModule.LocationMode.manual)
            }
            .pickerStyle(.segmented)

            if module.locationMode == .automatic {
                locationStatusRow
            }

            // Ville : utilisée en mode « Ville choisie », et en repli en mode automatique.
            LabeledContent("Ville") {
                Text(module.manualPlace?.fullName ?? String(localized: "Aucune"))
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Rechercher une ville", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Rechercher", action: search)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }

            if isSearching {
                ProgressView().controlSize(.small)
            } else if searchFailed {
                Text("La recherche a échoué. Vérifiez votre connexion.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(results) { place in
                Button {
                    module.manualPlace = place
                    results = []
                    query = ""
                } label: {
                    Label(place.fullName, systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.notch)
            }

            Text("Données météo : Open-Meteo.com (licence CC BY 4.0).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var locationStatusRow: some View {
        switch module.locationStatus {
        case .authorizedAlways:
            Label("Localisation autorisée", systemImage: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .notDetermined:
            Button("Autoriser la localisation…", action: module.requestLocationAccess)
        default:
            Text("Localisation refusée : la ville choisie ci-dessous est utilisée. Vous pouvez l'autoriser dans Réglages Système > Confidentialité et sécurité > Service de localisation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        searchFailed = false
        Task {
            do {
                results = try await OpenMeteoClient.searchPlaces(text)
            } catch {
                results = []
                searchFailed = true
            }
            isSearching = false
        }
    }
}
