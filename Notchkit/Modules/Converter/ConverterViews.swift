import AppKit
import SwiftUI

// MARK: - Carte dans l'encoche dépliée

struct ConverterExpandedView: View {
    let module: ConverterModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            Group {
                if module.isConverting {
                    progress
                } else if !module.files.isEmpty {
                    formatChoice
                } else if !module.results.isEmpty {
                    results
                } else {
                    empty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
            if let error = module.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .overlay {
            // Fichier glissé au-dessus du widget : il sera déposé ici.
            if module.isDropTargeted {
                ZStack {
                    // Fond opaque : le message reste lisible au-dessus du contenu du widget.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.2))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(.orange)
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Déposer pour convertir")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(3)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: module.isConverting)
        .animation(.snappy, value: module.files)
        .animation(.snappy(duration: 0.2), value: module.isDropTargeted)
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 8) {
            Text("Convertisseur")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
            if !module.files.isEmpty || !module.results.isEmpty, !module.isConverting {
                Button(action: module.clear) { Image(systemName: "xmark") }
                    .help("Effacer")
            }
            Button(action: module.chooseFiles) { Image(systemName: "plus") }
                .help("Choisir des fichiers…")
                .disabled(module.isConverting)
        }
        .buttonStyle(.standBy(.small, circle: true))
    }

    // MARK: Aucun fichier

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            ViewThatFits(in: .vertical) {
                Text("Glissez des fichiers sur l'encoche, sur « Convertir », ou cliquez sur +.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Déposez des fichiers ici")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Choix du format

    private var formatChoice: some View {
        VStack(alignment: .leading, spacing: 7) {
            fileSummary
            if size != .small {
                Text("Convertir en")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            // Boutons de formats : ils passent à la ligne quand la carte est étroite.
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(module.formats) { format in
                    Button(format.title) { module.convert(to: format) }
                        .buttonStyle(.standBy(.small))
                        .fixedSize()
                }
            }
        }
    }

    private var fileSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: module.kind?.symbol ?? "doc")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(StandBy.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                if module.files.count == 1, let file = module.files.first {
                    Text(file.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(file.pathExtension.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Text("\(module.files.count) fichiers")
                        .font(.system(size: 12, weight: .medium))
                    Text(module.files.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: Conversion en cours

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            fileSummary
            HStack(spacing: 8) {
                StandByBar(value: Double(module.completed) / Double(max(1, module.files.count)), height: 6)
                Text(verbatim: "\(module.completed)/\(module.files.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("Conversion…")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: Résultat

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    if module.results.count == 1, let result = module.results.first {
                        Text(result.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("\(module.results.count) fichiers convertis")
                            .font(.system(size: 12, weight: .medium))
                    }
                    if module.failures > 0 {
                        Text("\(module.failures) échec(s)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    }
                }
            }
            HStack(spacing: 6) {
                if module.results.count == 1, let result = module.results.first {
                    Button("Ouvrir") { module.open(result) }
                        .buttonStyle(.standBy(.small, active: true))
                }
                Button("Afficher dans le Finder", action: module.revealResults)
                    .buttonStyle(.standBy(.small))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Mini

struct ConverterMiniView: View {
    let module: ConverterModule

    var body: some View {
        MiniWidget(value: value, caption: String(localized: "Convertisseur"), tint: module.results.isEmpty ? .white : .green) {
            ModuleIcon(symbol: module.isConverting ? "arrow.triangle.2.circlepath" : ConverterModule.descriptor.systemImage)
        }
    }

    private var value: String? {
        if module.isConverting { return "\(module.completed)/\(module.files.count)" }
        if !module.results.isEmpty { return "✓ \(module.results.count)" }
        if !module.files.isEmpty { return "\(module.files.count)" }
        return nil
    }
}

