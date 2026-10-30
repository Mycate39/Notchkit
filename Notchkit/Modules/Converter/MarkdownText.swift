import AppKit

/// Markdown mis en forme pour la conversion (PDF, Word, RTF…) : titres, gras, italique, code, liens,
/// listes, citations et tableaux (cellules séparées par des tabulations). L'analyse vient de Foundation
/// (`AttributedString`, syntaxe complète) ; seule la mise en forme est faite ici.
enum MarkdownText {
    static let bodySize: CGFloat = 12

    /// Taille d'un titre selon son niveau (fonction pure, testée).
    static func headerSize(level: Int) -> CGFloat {
        switch level {
        case 1: 22
        case 2: 17
        case 3: 14
        default: bodySize
        }
    }

    static func attributed(_ source: String) -> NSAttributedString? {
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        ) else { return nil }
        let output = NSMutableAttributedString()
        var previous: PresentationIntent?
        var startedItems = Set<Int>()
        for run in parsed.runs {
            var text = String(parsed[run.range].characters)
            let intent = run.presentationIntent
            let components = intent?.components ?? []
            let isCode = components.contains { if case .codeBlock = $0.kind { true } else { false } }
            // Nouveau bloc : retour à la ligne, ou tabulation entre deux cellules d'une même ligne.
            if intent != previous {
                if !output.string.isEmpty {
                    output.append(NSAttributedString(string: separator(from: previous, to: intent)))
                }
                text = listPrefix(components, started: &startedItems) + text
                previous = intent
            }
            if isCode, text.hasSuffix("\n") { text.removeLast() }
            output.append(NSAttributedString(string: text, attributes: attributes(for: run, components: components)))
        }
        return output
    }

    /// Ce qui sépare deux blocs : une tabulation entre deux cellules d'une même ligne de tableau,
    /// sinon un retour à la ligne.
    private static func separator(from old: PresentationIntent?, to new: PresentationIntent?) -> String {
        func row(_ intent: PresentationIntent?) -> Int? {
            intent?.components.first { if case .tableRow = $0.kind { true } else { false } }?.identity
                ?? intent?.components.first { if case .tableHeaderRow = $0.kind { true } else { false } }?.identity
        }
        if let oldRow = row(old), oldRow == row(new) { return "\t" }
        return "\n"
    }

    /// Puce (« • ») ou numéro (« 2. ») au début du premier paragraphe d'un élément de liste,
    /// en retrait selon la profondeur de la liste.
    private static func listPrefix(_ components: [PresentationIntent.IntentType], started: inout Set<Int>) -> String {
        guard let index = components.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
              case let .listItem(ordinal) = components[index].kind,
              started.insert(components[index].identity).inserted
        else { return "" }
        let depth = components.filter { if case .listItem = $0.kind { true } else { false } }.count
        let ordered = components[index...].first {
            switch $0.kind {
            case .orderedList, .unorderedList: true
            default: false
            }
        }.map { if case .orderedList = $0.kind { true } else { false } } ?? false
        return String(repeating: "\t", count: depth - 1) + (ordered ? "\(ordinal). " : "• ")
    }

    private static func attributes(for run: AttributedString.Runs.Run,
                                   components: [PresentationIntent.IntentType]) -> [NSAttributedString.Key: Any] {
        var size = bodySize
        var traits: NSFontDescriptor.SymbolicTraits = []
        var monospaced = false
        var quoted = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        for component in components {
            switch component.kind {
            case let .header(level):
                size = headerSize(level: level)
                traits.insert(.bold)
                paragraph.paragraphSpacingBefore = level <= 2 ? 10 : 6
            case .codeBlock:
                monospaced = true
                size = bodySize - 1
                // Les lignes d'un bloc de code se suivent sans espace.
                paragraph.paragraphSpacing = 0
            case .blockQuote:
                quoted = true
                paragraph.headIndent = 14
                paragraph.firstLineHeadIndent = 14
            case .listItem:
                paragraph.headIndent = 18
            case .tableHeaderRow:
                traits.insert(.bold)
            default:
                break
            }
        }
        let inline = run.inlinePresentationIntent ?? []
        if inline.contains(.stronglyEmphasized) { traits.insert(.bold) }
        if inline.contains(.emphasized) { traits.insert(.italic) }
        if inline.contains(.code) { monospaced = true }

        var font = monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size)
        if !traits.isEmpty, let styled = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: size) {
            font = styled
        }
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        if quoted { attributes[.foregroundColor] = NSColor.darkGray }
        if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = run.link { attributes[.link] = link }
        return attributes
    }
}
