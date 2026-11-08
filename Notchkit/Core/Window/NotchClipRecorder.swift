import AVFoundation
import AppKit
import Observation
import ScreenCaptureKit

/// « Filmer l'encoche » : enregistre la zone autour de l'encoche (fond d'écran, verre et pointeur
/// compris) dans une vidéo H.264 à partager, rangée dans Vidéos › Notchkit. Au plus 30 secondes.
/// Demande l'autorisation « Enregistrement de l'écran ».
@MainActor
@Observable
final class NotchClipRecorder {
    enum State: Equatable {
        case idle
        case recording(since: Date)
        case saving
    }

    static let maxDuration: Duration = .seconds(30)
    static let fps = 60

    private(set) var state: State = .idle
    /// Dernière vidéo enregistrée, ou raison d'un échec.
    private(set) var lastClip: URL?
    private(set) var lastError: String?

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: ClipStreamOutput?
    @ObservationIgnored private var limitTask: Task<Void, Never>?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    func toggle(screen: NSScreen?, geometry: NotchGeometry) {
        switch state {
        case .idle: Task { await start(screen: screen, geometry: geometry) }
        case .recording: Task { await stop() }
        case .saving: break
        }
    }

    private func start(screen: NSScreen?, geometry: NotchGeometry) async {
        lastError = nil
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            lastError = String(localized: "Autorisez Notchkit dans Réglages Système > Confidentialité et sécurité > Enregistrement de l'écran, puis réessayez.")
            return
        }
        guard let screen,
              let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == screenID }) else { return }
            let region = NotchLayout.clipRegion(screenWidth: screen.frame.width,
                                                centerX: geometry.centerX - geometry.screenFrame.minX)
            let config = SCStreamConfiguration()
            config.sourceRect = region
            // Dimensions paires (exigées par H.264).
            config.width = Int(region.width * screen.backingScaleFactor) / 2 * 2
            config.height = Int(region.height * screen.backingScaleFactor) / 2 * 2
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Self.fps))
            config.queueDepth = 8

            let url = try Self.newClipURL()
            let output = try ClipStreamOutput(url: url, width: config.width, height: config.height)
            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try await stream.startCapture()
            self.stream = stream
            self.output = output
            lastClip = url
            state = .recording(since: Date())
            limitTask = Task { [weak self] in
                try? await Task.sleep(for: Self.maxDuration)
                guard !Task.isCancelled else { return }
                await self?.stop()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stop() async {
        guard isRecording else { return }
        limitTask?.cancel()
        limitTask = nil
        state = .saving
        try? await stream?.stopCapture()
        stream = nil
        await output?.finish()
        output = nil
        state = .idle
        if let lastClip, !AutomatedRun.isActive { NSWorkspace.shared.activateFileViewerSelecting([lastClip]) }
    }

    /// Vidéos › Notchkit › « Notchkit 2026-11-05 à 20.31.12.mov ».
    private static func newClipURL() throws -> URL {
        let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchkit", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return folder.appendingPathComponent("Notchkit \(formatter.string(from: Date())).mov")
    }
}

/// Reçoit les images de ScreenCaptureKit et les écrit en H.264 (file d'attente dédiée).
private final class ClipStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "notchkit.clip.recorder")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false

    init(url: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid, Self.isComplete(buffer) else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(buffer) }
    }

    /// Image entière (pas une image « inchangée » sans contenu).
    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }

    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard self.started else { return continuation.resume() }
                self.input.markAsFinished()
                self.writer.finishWriting { continuation.resume() }
            }
        }
    }
}
