import Foundation

/// Disposition prête à l'emploi : modules activés, pages et tailles.
struct LayoutPreset: Identifiable, Sendable {
    let id: String
    let name: LocalizedStringResource
    let summary: LocalizedStringResource
    let symbol: String
    /// Modules avec carte à activer (les autres modules avec carte sont masqués ;
    /// les modules sans carte, comme les animations de déverrouillage, ne sont pas touchés).
    let pages: [[String]]
    let sizes: [String: WidgetSize]

    var enabledIDs: Set<String> { Set(pages.flatMap { $0 }) }

    static let all: [LayoutPreset] = [
        LayoutPreset(
            id: "essential", name: "Essentiel", summary: "Musique, heure et batterie, rien de plus.",
            symbol: "circle.grid.2x1",
            pages: [["music", "clock", "battery"]],
            sizes: ["music": .large, "clock": .small, "battery": .small]
        ),
        LayoutPreset(
            id: "music", name: "Musique", summary: "Lecture en grand, casque et volume à portée de main.",
            symbol: "music.note.list",
            pages: [["music", "airpods", "systemhud"], ["shelf", "clock", "battery"]],
            sizes: ["music": .large, "airpods": .small, "systemhud": .small, "shelf": .large, "clock": .mini, "battery": .mini]
        ),
        LayoutPreset(
            id: "productivity", name: "Productivité", summary: "Agenda, minuteurs, presse-papiers et étagère.",
            symbol: "calendar.badge.clock",
            pages: [["calendar", "activities"], ["clipboard", "shelf"], ["weather", "clock", "battery", "music"]],
            sizes: ["calendar": .large, "activities": .large, "clipboard": .large, "shelf": .large,
                    "weather": .small, "clock": .mini, "battery": .mini, "music": .medium]
        ),
        LayoutPreset(
            id: "developer", name: "Développeur", summary: "Claude Code, assistant IA, activités et étagère.",
            symbol: "chevron.left.forwardslash.chevron.right",
            pages: [["claude", "activities"], ["assistant", "shelf"], ["music", "clock", "battery"]],
            sizes: ["claude": .large, "activities": .large, "assistant": .large, "shelf": .large,
                    "music": .large, "clock": .mini, "battery": .mini]
        ),
        LayoutPreset(
            id: "everything", name: "Tout-en-un", summary: "Tous les modules, en version Mini quand c'est possible.",
            symbol: "square.grid.3x3.fill",
            pages: [
                ["music", "clock", "battery", "weather", "calendar"],
                ["claude", "assistant"],
                ["activities", "shelf"],
                ["clipboard", "airpods", "systemhud", "videodownload", "back"],
            ],
            sizes: ["music": .large, "clock": .mini, "battery": .mini, "weather": .mini, "calendar": .mini,
                    "claude": .large, "assistant": .large, "activities": .large, "shelf": .large,
                    "clipboard": .medium, "airpods": .mini, "systemhud": .mini, "videodownload": .mini, "back": .mini]
        ),
    ]
}
