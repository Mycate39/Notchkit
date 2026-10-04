import Foundation
import Testing
@testable import Notchkit

struct LiveActivityTests {
    let now = Date(timeIntervalSince1970: 1_000)

    @Test func minuteurAvanceEtSeMetEnPause() {
        var timer = LiveActivity.timer(duration: 300, now: now)
        #expect(timer.remaining(at: now.addingTimeInterval(60)) == 240)
        #expect(timer.fraction(at: now.addingTimeInterval(150)) == 0.5)

        timer.pausedRemaining = 100
        timer.endDate = nil
        #expect(timer.isPaused)
        #expect(timer.remaining(at: now.addingTimeInterval(1000)) == 100)
    }

    @Test func prioriteMinuteurQuiSonneSurLeReste() {
        var ringing = LiveActivity.timer(duration: 60, now: now)
        ringing.isFinished = true
        let soon = LiveActivity.timer(duration: 30, now: now)
        let later = LiveActivity.timer(duration: 600, now: now)
        let download = LiveActivity(id: "d", kind: .download, title: "film.mp4", symbol: "arrow.down.circle")

        #expect(LiveActivityRanking.mostRelevant([download, later, soon], at: now)?.id == soon.id)
        #expect(LiveActivityRanking.mostRelevant([download, soon, ringing], at: now)?.id == ringing.id)
        #expect(LiveActivityRanking.mostRelevant([download], at: now)?.id == "d")
        #expect(LiveActivityRanking.mostRelevant([], at: now) == nil)
    }

    @Test func liensNotchkit() {
        #expect(LiveActivityCommand(url: URL(string: "notchkit://activity/update?id=build&title=Compilation&progress=40")!)
                == .update(id: "build", title: "Compilation", progress: 0.4, symbol: nil, detail: nil))
        #expect(LiveActivityCommand(url: URL(string: "notchkit://activity/update?id=x&progress=0.25&symbol=hammer")!)
                == .update(id: "x", title: nil, progress: 0.25, symbol: "hammer", detail: nil))
        #expect(LiveActivityCommand(url: URL(string: "notchkit://activity/end?id=build")!) == .end(id: "build"))
        #expect(LiveActivityCommand(url: URL(string: "notchkit://timer/start?minutes=5&title=Th%C3%A9")!)
                == .startTimer(seconds: 300, title: "Thé"))
        #expect(LiveActivityCommand(url: URL(string: "notchkit://timer/start?minutes=-1")!) == nil)
        #expect(LiveActivityCommand(url: URL(string: "notchkit://inconnu")!) == nil)
        #expect(LiveActivityCommand(url: URL(string: "https://activity/end?id=x")!) == nil)
    }

    @Test func fichiersTemporairesDesNavigateurs() {
        #expect(DownloadFiles.isTemporary("film.mp4.crdownload"))
        #expect(DownloadFiles.isTemporary("page.html.download"))
        #expect(DownloadFiles.isTemporary("archive.zip.part"))
        #expect(!DownloadFiles.isTemporary("photo.jpg"))
        #expect(DownloadFiles.finalName(for: "film.mp4.crdownload") == "film.mp4")
    }
}

@MainActor
struct LiveActivitiesModuleTests {
    func makeModule() -> LiveActivitiesModule {
        LiveActivitiesModule(context: ModuleContext(presentAlert: { _ in }, openSettings: {}, holdExpanded: { _ in }))
    }

    @Test func plusieursActivitesEnMemeTemps() {
        let module = makeModule()
        module.startTimer(minutes: 5)
        module.handle(.update(id: "build", title: "Compilation", progress: 0.3, symbol: nil, detail: nil))
        module.handle(.update(id: "build", title: nil, progress: 0.6, symbol: nil, detail: "Étape 2"))
        #expect(module.activities.count == 2)
        let task = module.activities.first { $0.kind == .task }
        #expect(task?.progress == 0.6)
        #expect(task?.title == "Compilation")
        #expect(task?.detail == "Étape 2")
        #expect(module.compactPriority == .normal)
    }

    @Test func pauseEtAjoutDeTemps() throws {
        let module = makeModule()
        module.startTimer(seconds: 120)
        let id = try #require(module.activities.first?.id)
        module.togglePause(id)
        #expect(module.activities.first?.isPaused == true)
        module.extend(id, by: 60)
        let remaining = try #require(module.activities.first?.remaining())
        #expect(remaining > 170 && remaining <= 180)
        module.remove(id)
        #expect(module.activities.isEmpty)
    }
}
