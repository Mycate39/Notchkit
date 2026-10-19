import Foundation
import Testing
@testable import Notchkit

struct MascotInteractionTests {
    @Test func reactionsSEnchainentEnBoucle() {
        #expect(MascotReaction.jump.next == .spin)
        #expect(MascotReaction.wiggle.next == .jump)
    }

    @Test func reactionTermineeNeChangePasLaPosture() {
        for reaction in MascotReaction.allCases {
            var pose = MascotPose()
            MascotMotion.apply(reaction, at: reaction.duration + 0.01, to: &pose)
            #expect(pose == MascotPose())
        }
    }

    @Test func toupieFaitUnTourComplet() {
        var pose = MascotPose()
        MascotMotion.apply(.spin, at: MascotReaction.spin.duration * 0.999, to: &pose)
        #expect(pose.turn > 359)
    }

    @Test func attitudeDeDiscussion() {
        #expect(MascotChat.phase(isResponding: true, answerIsEmpty: true, isComposing: false) == .thinking)
        #expect(MascotChat.phase(isResponding: true, answerIsEmpty: false, isComposing: true) == .talking)
        #expect(MascotChat.phase(isResponding: false, answerIsEmpty: true, isComposing: true) == .listening)
        #expect(MascotChat.phase(isResponding: false, answerIsEmpty: true, isComposing: false) == nil)
    }

    @Test func sonsAudiblesEtSansSaturation() {
        for effect in MascotSounds.Effect.allCases {
            let variants = MascotSounds.variants(of: effect)
            #expect(!variants.isEmpty)
            for notes in variants {
                let samples = MascotSounds.render(notes, sampleRate: 44_100)
                #expect(samples.count > 1_000)
                #expect(samples.contains { abs($0) > 0.05 })
                #expect(samples.allSatisfy { abs($0) <= 1 })
            }
        }
    }

    @Test func deploiementTermineDetecte() {
        let start = Date()
        let old = [VercelDeployment(id: "a", project: "site", state: .building, created: start, message: nil),
                   VercelDeployment(id: "b", project: "site", state: .ready, created: start, message: nil)]
        let new = [VercelDeployment(id: "a", project: "site", state: .ready, created: start, message: nil),
                   VercelDeployment(id: "b", project: "site", state: .ready, created: start, message: nil),
                   VercelDeployment(id: "c", project: "site", state: .error, created: start, message: nil)]
        #expect(ServiceParsing.finishedDeployments(old: old, new: new) == [.ready])
    }
}
