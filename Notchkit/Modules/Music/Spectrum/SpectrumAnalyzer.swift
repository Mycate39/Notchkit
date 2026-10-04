import Accelerate
import Foundation

/// Découpe un signal audio en quelques bandes de fréquences (graves → aigus), avec une FFT
/// du framework Accelerate. Logique pure, sans Core Audio : facile à tester.
final class SpectrumAnalyzer {
    /// Bandes affichées par les barres de l'égaliseur (en Hz).
    static let bands: [ClosedRange<Float>] = [40...150, 150...600, 600...2_500, 2_500...10_000]

    let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]

    init(fftSize: Int = 1024) {
        precondition(fftSize.nonzeroBitCount == 1, "la taille de FFT doit être une puissance de 2")
        self.fftSize = fftSize
        log2n = vDSP_Length(log2(Double(fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Énergie moyenne de chaque bande pour `fftSize` échantillons mono.
    func bandEnergies(_ samples: [Float], sampleRate: Float) -> [Float] {
        precondition(samples.count == fftSize)
        let half = fftSize / 2

        // Fenêtre de Hann pour limiter les fuites spectrales.
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        let binWidth = sampleRate / Float(fftSize)
        return Self.bands.map { band in
            let low = max(1, Int(band.lowerBound / binWidth))
            let high = min(half - 1, max(low, Int(band.upperBound / binWidth)))
            var mean: Float = 0
            magnitudes.withUnsafeBufferPointer { pointer in
                vDSP_meanv(pointer.baseAddress! + low, 1, &mean, vDSP_Length(high - low + 1))
            }
            return sqrt(mean)
        }
    }
}

/// Transforme les énergies brutes en niveaux 0…1 agréables à regarder :
/// gain automatique par bande (le volume ne change pas l'amplitude des barres),
/// montée rapide et descente douce.
struct SpectrumSmoother {
    private var peaks: [Float]
    private(set) var levels: [Float]

    /// Plancher du gain automatique : évite d'amplifier le bruit quand le son est très faible.
    static let minimumPeak: Float = 0.02

    init(bandCount: Int) {
        peaks = [Float](repeating: Self.minimumPeak, count: bandCount)
        levels = [Float](repeating: 0, count: bandCount)
    }

    mutating func update(with energies: [Float]) -> [Float] {
        for index in energies.indices where index < levels.count {
            let energy = energies[index]
            // Le pic redescend lentement pour s'adapter aux passages plus calmes.
            peaks[index] = max(energy, peaks[index] * 0.995, Self.minimumPeak)
            let target = min(1, energy / peaks[index])
            let current = levels[index]
            levels[index] = target > current
                ? current + (target - current) * 0.6   // montée rapide
                : current + (target - current) * 0.18  // descente douce
        }
        return levels
    }
}
