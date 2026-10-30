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
            pages: [["clock", "battery"]],
            sizes: ["clock": .small, "battery": .small]
        ),
        LayoutPreset(
            id: "music", name: "Musique", summary: "Lecture en grand, casque et volume à portée de main.",
            symbol: "music.note.list",
            pages: [["airpods", "systemhud"], ["shelf", "clock", "battery"]],
            sizes: ["airpods": .small, "systemhud": .small, "shelf": .large, "clock": .mini, "battery": .mini]
        ),
        LayoutPreset(
            id: "productivity", name: "Productivité", summary: "Agenda, minuteurs, presse-papiers et étagère.",
            symbol: "calendar.badge.clock",
            pages: [["calendar", "activities"], ["clipboard", "shelf"], ["weather", "clock", "battery"]],
            sizes: ["calendar": .large, "activities": .large, "clipboard": .large, "shelf": .large,
                    "weather": .small, "clock": .mini, "battery": .mini]
        ),
        LayoutPreset(
            id: "developer", name: "Développeur", summary: "Agents IA, activités, presse-papiers et étagère.",
            symbol: "chevron.left.forwardslash.chevron.right",
            pages: [["agents"], ["activities", "shelf"], ["clipboard"], ["clock", "battery"]],
            sizes: ["agents": .large, "activities": .large, "clipboard": .large, "shelf": .large,
                    "clock": .mini, "battery": .mini]
        ),
        LayoutPreset(
            id: "everything", name: "Tout-en-un", summary: "Tous les modules, en version Mini quand c'est possible.",
            symbol: "square.grid.3x3.fill",
            pages: [
                ["clock", "battery", "weather", "calendar"],
                ["agents"],
                ["activities", "shelf"],
                ["clipboard", "airpods", "systemhud", "videodownload"],
            ],
            sizes: ["clock": .mini, "battery": .mini, "weather": .mini, "calendar": .mini,
                    "agents": .large, "activities": .large, "shelf": .large,
                    "clipboard": .medium, "airpods": .mini, "systemhud": .mini, "videodownload": .mini]
        ),
    ]
}
