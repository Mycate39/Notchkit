import AppKit
import ApplicationServices
import NaturalLanguage
import SwiftUI
import Observation
import Translation

/// Module Traduction : traducteur intégré à l'encoche. On écrit (ou colle) un texte, il se traduit au
/// fil de la frappe dans la langue choisie ; la langue de départ est détectée ou choisie. La sélection
/// de l'app au premier plan (ou le presse-papiers) se traduit aussi d'un clic. Moteur d'Apple
/// (framework Translation, gratuit, sur l'appareil), macOS 15 ou plus.
@MainActor
@Observable
final class TranslationModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "translation",
        name: "Traduction",
        summary: "Un traducteur dans l'encoche : écrivez un texte, ou traduisez la sélection, dans la langue de votre choix.",
        systemImage: "translate",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    private enum Keys {
        static let source = "module.translation.source"
        static let target = "module.translation.target"
    }

    var source = ""
    private(set) var result = ""
    private(set) var isTranslating = false
    private(set) var errorMessage: String?
    /// Demande de traduction (incrémentée à chaque fois) : la vue relance alors la session.
    private(set) var request = 0

    /// Langue de départ (`nil` : détectée dans le texte) et langue d'arrivée.
    var sourceLanguage: String? {
        didSet { UserDefaults.standard.set(sourceLanguage, forKey: Keys.source) }
    }
    var targetLanguage: String {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: Keys.target) }
    }

    @ObservationIgnored private let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
        let stored = UserDefaults.standard.string(forKey: Keys.source)
        sourceLanguage = stored.flatMap { TranslationLanguages.codes.contains($0) ? $0 : nil }
        targetLanguage = UserDefaults.standard.string(forKey: Keys.target)
            .flatMap { TranslationLanguages.codes.contains($0) ? $0 : nil } ?? TranslationLanguages.defaultTarget
    }

    /// Langues de la traduction en cours (départ détecté si besoin).
    var direction: (source: String, target: String) {
        TranslationDirection.languages(for: source, source: sourceLanguage, target: targetLanguage)
    }

    /// Texte sélectionné dans l'app au premier plan (Accessibilité), sinon le presse-papiers.
    func translateSelection() {
        let text = SelectedText.current() ?? NSPasteboard.general.string(forType: .string) ?? ""
        source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        translate()
    }

    func translate() {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finish(nil)
            return
        }
        errorMessage = nil
        isTranslating = true
        request += 1
    }

    func finish(_ text: String?, error: String? = nil) {
        isTranslating = false
        result = text ?? ""
        errorMessage = error
    }

    /// Inverse les langues ; la traduction devient le texte de départ.
    func swapLanguages() {
        let current = direction
        sourceLanguage = current.target
        targetLanguage = current.source
        if !result.isEmpty { source = result }
        translate()
    }

    func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    func clear() {
        source = ""
        finish(nil)
    }

    func holdExpanded(_ hold: Bool) { context.holdExpanded(hold) }

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "translate", value: nil, caption: String(localized: "Traduction")))
    }

    func expandedView() -> AnyView { AnyView(TranslationExpandedView(module: self)) }
}

/// Langues proposées (codes BCP 47 pris en charge par le moteur de traduction d'Apple).
enum TranslationLanguages {
    static let codes = ["fr", "en", "es", "de", "it", "pt", "nl", "pl", "ru", "uk", "tr", "ar",
                        "hi", "ja", "ko", "zh-Hans", "zh-Hant", "th", "vi", "id"]

    /// Anglais par défaut, français pour qui utilise le Mac dans une autre langue.
    static var defaultTarget: String {
        Locale.current.language.languageCode?.identifier == "en" ? "fr" : "en"
    }

    /// Nom de la langue dans la langue du Mac (« Anglais », « English »).
    static func name(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code)?.localizedCapitalized ?? code
    }
}

/// Sens de traduction.
enum TranslationDirection {
    /// Départ choisi, sinon détecté parmi les langues proposées. Si le texte est déjà dans la langue
    /// d'arrivée, on traduit vers l'anglais (ou vers le français depuis l'anglais).
    static func languages(for text: String, source: String?, target: String) -> (source: String, target: String) {
        let from = source ?? detect(text) ?? (target == "en" ? "fr" : "en")
        guard from == target else { return (from, target) }
        return (from, from == "en" ? "fr" : "en")
    }

    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = TranslationLanguages.codes.map { NLLanguage($0) }
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
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
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            languageBar
            // Texte à traduire : il se traduit peu après la dernière frappe.
            ZStack(alignment: .topLeading) {
                TextField("", text: $module.source, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .focused($isEditing)
                    .onSubmit { module.translate() }
                if module.source.isEmpty {
                    Text("Saisissez ou collez un texte…")
                        .foregroundStyle(.white.opacity(0.55))
                        .allowsHitTesting(false)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if !module.source.isEmpty {
                    Button(action: module.clear) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(5)
                        .help("Effacer")
                        .accessibilityLabel(Text("Effacer"))
                }
            }

            // Traduction.
            ScrollView {
                Group {
                    if module.isTranslating && module.result.isEmpty {
                        ProgressView().controlSize(.small)
                    } else if let error = module.errorMessage {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text(module.result).textSelection(.enabled)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        // Traduction au fil de la frappe, une fois la saisie posée.
        .task(id: module.source) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            module.translate()
        }
        .onChange(of: module.sourceLanguage) { _, _ in module.translate() }
        .onChange(of: module.targetLanguage) { _, _ in module.translate() }
        // Pendant la saisie, l'encoche reste ouverte même si la souris s'éloigne.
        .onChange(of: isEditing) { _, editing in module.holdExpanded(editing) }
        .onDisappear { module.holdExpanded(false) }
        .onChange(of: module.request) { _, _ in
            let pair = module.direction
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
                // Le texte a changé entre-temps : une nouvelle demande suit déjà.
                guard text == module.source else { return }
                module.finish(response.targetText)
            } catch {
                module.finish(nil, error: String(localized: "Traduction impossible pour le moment."))
            }
        }
    }

    /// Langue de départ (ou détection), bouton d'inversion, langue d'arrivée, puis la sélection et la copie.
    private var languageBar: some View {
        let pair = module.direction
        return HStack(spacing: 6) {
            Menu {
                Button {
                    module.sourceLanguage = nil
                } label: {
                    Text("Détecter la langue")
                }
                Divider()
                ForEach(TranslationLanguages.codes, id: \.self) { code in
                    Button(TranslationLanguages.name(code)) { module.sourceLanguage = code }
                }
            } label: {
                Text(module.sourceLanguage == nil
                     ? String(localized: "Auto · \(TranslationLanguages.name(pair.source))")
                     : TranslationLanguages.name(pair.source))
                    .lineLimit(1)
            }
            .menuStyle(.button)
            .buttonStyle(.standBy(.small))
            .fixedSize()

            Button(action: module.swapLanguages) { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.standBy(.small, circle: true))
                .help("Inverser les langues")
                .accessibilityLabel(Text("Inverser les langues"))

            Menu {
                ForEach(TranslationLanguages.codes, id: \.self) { code in
                    Button(TranslationLanguages.name(code)) { module.targetLanguage = code }
                }
            } label: {
                Text(TranslationLanguages.name(pair.target)).lineLimit(1)
            }
            .menuStyle(.button)
            .buttonStyle(.standBy(.small, active: true))
            .fixedSize()

            Spacer(minLength: 0)
            Button(action: module.translateSelection) { Image(systemName: "text.cursor") }
                .buttonStyle(.standBy(.small, circle: true))
                .help("Traduire la sélection")
                .accessibilityLabel(Text("Traduire la sélection"))
            if !module.result.isEmpty {
                Button(action: module.copyResult) { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.standBy(.small, circle: true))
                    .help("Copier la traduction")
                    .accessibilityLabel(Text("Copier la traduction"))
            }
        }
        .font(.system(size: 11, weight: .semibold))
    }
}

#if DEBUG
extension TranslationModule {
    /// Traduction imposée (tournages de démonstration).
    func debugSetResult(source: String, result: String) {
        self.source = source
        finish(result)
    }
}
#endif
