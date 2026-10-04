import SwiftUI

/// Taille d'un widget dans l'encoche dépliée (part de la largeur d'une page).
enum WidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Version miniature : l'essentiel en un coup d'œil (jusqu'à 8 par page).
    case mini
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Largeur relative : une page contient au plus `NotchLayout.pageCapacity` (4) unités.
    var weight: CGFloat {
        switch self {
        case .mini: 0.5
        case .small: 1
        case .medium: 1.5
        case .large: 2
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .mini: "Mini"
        case .small: "Petit"
        case .medium: "Moyen"
        case .large: "Grand"
        }
    }

    /// Taille la plus proche d'une largeur relative (taille par défaut d'un module).
    init(weight: CGFloat) {
        self = WidgetSize.allCases.min { abs($0.weight - weight) < abs($1.weight - weight) } ?? .medium
    }
}

/// Disposition choisie par l'utilisateur : quels widgets sur quelle page, dans quel ordre, et leur taille.
struct WidgetLayout: Codable, Equatable, Sendable {
    /// Identifiants des modules, page par page.
    var pages: [[String]]
    /// Tailles choisies (un module absent garde sa taille par défaut).
    var sizes: [String: WidgetSize] = [:]
}

/// Colonnes d'une page : deux widgets « Mini » consécutifs s'empilent verticalement.
enum WidgetColumns {
    /// Indices regroupés en colonnes (une colonne = 1 widget, ou 2 Mini empilés).
    static func make(sizes: [WidgetSize]) -> [[Int]] {
        var columns: [[Int]] = []
        var index = 0
        while index < sizes.count {
            if sizes[index] == .mini, index + 1 < sizes.count, sizes[index + 1] == .mini {
                columns.append([index, index + 1])
                index += 2
            } else {
                columns.append([index])
                index += 1
            }
        }
        return columns
    }

    /// Largeur occupée par chaque widget : le second Mini d'une paire ne prend pas de place en plus.
    static func effectiveWeights(sizes: [WidgetSize]) -> [CGFloat] {
        var weights = sizes.map(\.weight)
        for column in make(sizes: sizes) where column.count == 2 { weights[column[1]] = 0 }
        return weights
    }

    /// Taille déduite d'une largeur (0,5 = Mini).
    static func sizes(fromWeights weights: [CGFloat]) -> [WidgetSize] {
        weights.map { WidgetSize(weight: $0) }
    }
}

/// Règles de disposition (logique pure, testée).
enum WidgetLayoutEngine {
    /// Pages effectives : la disposition de l'utilisateur, limitée aux modules actifs, puis les modules
    /// actifs qu'elle ne mentionne pas encore (ex. nouveau module), répartis automatiquement à la fin.
    /// Sans disposition, tout est réparti automatiquement selon l'ordre des modules.
    static func pages(activeIDs: [String], weights: [String: CGFloat], layout: WidgetLayout?,
                      capacity: CGFloat = NotchLayout.pageCapacity) -> [[String]] {
        let active = Set(activeIDs)
        var result: [[String]] = []
        var placed = Set<String>()

        for page in layout?.pages ?? [] {
            let ids = page.filter { active.contains($0) && !placed.contains($0) }
            placed.formUnion(ids)
            if !ids.isEmpty { result.append(ids) }
        }

        let remaining = activeIDs.filter { !placed.contains($0) }
        let sizes = WidgetColumns.sizes(fromWeights: remaining.map { weights[$0] ?? 1 })
        let automatic = NotchLayout.paginate(weights: WidgetColumns.effectiveWeights(sizes: sizes), capacity: capacity)
        result += automatic.map { $0.map { remaining[$0] } }
        return result
    }

    /// Fige la disposition affichée pour pouvoir la modifier.
    static func materialize(activeIDs: [String], weights: [String: CGFloat], layout: WidgetLayout?) -> WidgetLayout {
        WidgetLayout(
            pages: pages(activeIDs: activeIDs, weights: weights, layout: layout),
            sizes: layout?.sizes ?? [:]
        )
    }

    /// Déplace un widget à une position donnée (page `page`, rang `index`). Une page au-delà
    /// de la dernière est créée. Les pages vides sont retirées.
    static func move(_ id: String, toPage page: Int, index: Int, in layout: WidgetLayout) -> WidgetLayout {
        var result = layout
        var originPage: Int?
        var originIndex: Int?
        for (pageIndex, ids) in result.pages.enumerated() {
            if let position = ids.firstIndex(of: id) {
                originPage = pageIndex
                originIndex = position
            }
        }
        if let originPage, let originIndex { result.pages[originPage].remove(at: originIndex) }

        var target = max(0, page)
        if target >= result.pages.count {
            result.pages.append([])
            target = result.pages.count - 1
        }
        // `index` désigne une position dans la page AVANT le retrait : dans la même page,
        // retirer l'élément décale d'un cran les positions suivantes.
        var insertAt = index
        if originPage == target, let originIndex, originIndex < index { insertAt -= 1 }
        insertAt = max(0, min(insertAt, result.pages[target].count))
        result.pages[target].insert(id, at: insertAt)
        result.pages.removeAll { $0.isEmpty }
        return result
    }

    /// Retire un widget de la disposition (ex. module masqué).
    static func remove(_ id: String, from layout: WidgetLayout) -> WidgetLayout {
        var result = layout
        result.pages = result.pages.map { $0.filter { $0 != id } }.filter { !$0.isEmpty }
        return result
    }

    /// Largeur occupée sur une page.
    static func usedCapacity(of page: [String], weights: [String: CGFloat]) -> CGFloat {
        let sizes = WidgetColumns.sizes(fromWeights: page.map { weights[$0] ?? 1 })
        return WidgetColumns.effectiveWeights(sizes: sizes).reduce(0, +)
    }
}
