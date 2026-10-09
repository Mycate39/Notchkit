import AppKit
import ApplicationServices
import NaturalLanguage
import SwiftUI
import Observation
import Translation

/// Module Traduction : traduit instantanément le texte sélectionné (ou copié), français ↔ anglais,
/// avec le moteur d'Apple (framework Translation, gratuit, sur l'appareil). macOS 15 ou plus.
@MainActor
@Observable
final class TranslationModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "translation",
        name: "Traduction",
        summary: "Traduit le texte sélectionné, du français vers l'anglais et inversement, sur le Mac.",
        systemImage: "translate",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    var source = ""
    private(set) var result = ""
    private(set) var isTranslating = false
    private(set) var errorMessage: String?
    /// Demande de traduction (incrémentée à chaque fois) : la vue relance alors la session.
    private(set) var request = 0

    init(context: ModuleContext) {}

    /// Texte sélectionné dans l'app au premier plan (Accessibilité), sinon le presse-papiers.
    func translateSelection() {
        let text = SelectedText.current() ?? NSPasteboard.general.string(forType: .string) ?? ""
        source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        translate()
    }

    func translate() {
        guard !source.isEmpty else { return }
        errorMessage = nil
        isTranslating = true
        request += 1
    }

    func finish(_ text: String?, error: String? = nil) {
        isTranslating = false
        result = text ?? ""
        errorMessage = error
    }

    func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "translate", value: nil, caption: String(localized: "Traduction")))
    }

    func expandedView() -> AnyView { AnyView(TranslationExpandedView(module: self)) }
}

/// Sens de traduction : la langue détectée (français ou anglais) vers l'autre.
enum TranslationDirection {
    static func languages(for text: String) -> (source: String, target: String) {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.french, .english]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .french ? ("fr", "en") : ("en", "fr")
    }
}

/// Texte sélectionné dans l'élément actif de l'app au premier plan (API d'accessibilité publique).
enum SelectedText {
    static func current() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String, !text.isEmpty
        else { return nil }
        return text
    }
}

struct TranslationExpandedView: View {
    @Bindable var module: TranslationModule

    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                TranslatorView(module: module)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "translate").font(.system(size: 22))
                    Text("La traduction nécessite macOS 15 ou plus.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
    }
}

@available(macOS 15.0, *)
private struct TranslatorView: View {
    @Bindable var module: TranslationModule
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                let pair = TranslationDirection.languages(for: module.source)
                Text("\(pair.source.uppercased()) → \(pair.target.uppercased())")
                    .font(.system(size: 10, weight: .bold).monospaced())
                    .foregroundStyle(.tint)
                Spacer()
                Button(action: module.translateSelection) {
                    Label("Traduire la sélection", systemImage: "text.cursor")
                }
                .buttonStyle(.standBy(.small))
                if !module.result.isEmpty {
                    Button(action: module.copyResult) { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.standBy(.small, circle: true))
                        .help("Copier la traduction")
                }
            }
            Text(module.source.isEmpty ? String(localized: "Sélectionnez du texte dans une app, puis touchez « Traduire la sélection ».") : module.source)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
            ScrollView {
                Group {
                    if module.isTranslating {
                        ProgressView().controlSize(.small)
                    } else if let error = module.errorMessage {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text(module.result).textSelection(.enabled)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .onChange(of: module.request) { _, _ in
            let pair = TranslationDirection.languages(for: module.source)
            let next = TranslationSession.Configuration(source: Locale.Language(identifier: pair.source),
                                                        target: Locale.Language(identifier: pair.target))
            if configuration?.source == next.source, configuration?.target == next.target {
                configuration?.invalidate()
            } else {
                configuration = next
            }
        }
        .translationTask(configuration) { session in
            let text = module.source
            // La session n'est utilisée que dans cette tâche, l'une après l'autre : pas d'accès concurrent.
            nonisolated(unsafe) let session = session
            do {
                let response = try await session.translate(text)
                module.finish(response.targetText)
            } catch {
                module.finish(nil, error: String(localized: "Traduction impossible pour le moment."))
            }
        }
    }
}
