import Foundation
import Testing
@testable import Notchkit

struct SpectrumAnalyzerTests {
    let sampleRate: Float = 48_000

    func sine(_ frequency: Float, count: Int = 1024) -> [Float] {
        (0..<count).map { sin(2 * .pi * frequency * Float($0) / sampleRate) }
    }

    func dominantBand(_ frequency: Float) -> Int {
        let energies = SpectrumAnalyzer().bandEnergies(sine(frequency), sampleRate: sampleRate)
        return energies.indices.max { energies[$0] < energies[$1] }!
    }

    @Test func chaqueFrequenceTombeDansSaBande() {
        #expect(dominantBand(90) == 0)     // graves
        #expect(dominantBand(400) == 1)    // bas médiums
        #expect(dominantBand(1_500) == 2)  // médiums
        #expect(dominantBand(6_000) == 3)  // aigus
    }

    @Test func silenceDonneDesEnergiesNulles() {
        let energies = SpectrumAnalyzer().bandEnergies([Float](repeating: 0, count: 1024), sampleRate: sampleRate)
        #expect(energies.allSatisfy { $0 == 0 })
    }

    @Test func lisseurMonteViteEtDescendDoucement() {
        var smoother = SpectrumSmoother(bandCount: 1)
        let up = smoother.update(with: [1])[0]
        #expect(up > 0.5)
        let down = smoother.update(with: [0])[0]
        #expect(down < up && down > up * 0.7, "la descente doit être progressive")
        // Gain automatique : le niveau ne dépasse jamais 1.
        #expect(smoother.update(with: [50])[0] <= 1)
    }
}
