import Foundation
import Testing
@testable import Notchkit

struct YTDLPTests {
    let directory = URL(fileURLWithPath: "/Users/moi/Downloads")

    @Test func argumentsAvecEtSansFFmpeg() {
        let withFFmpeg = YTDLP.arguments(url: "https://example.com/v", format: .video1080, directory: directory,
                                         hasFFmpeg: true, ffmpegLocation: URL(fileURLWithPath: "/usr/local/bin/ffmpeg"))
        #expect(withFFmpeg.contains("--merge-output-format"))
        // H.264 d'abord (lisible partout), puis le meilleur MP4.
        #expect(withFFmpeg.contains("bv*[height<=1080][vcodec^=avc1]+ba[ext=m4a]/b[height<=1080][vcodec^=avc1]/"
                                    + "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/b[height<=1080]"))
        #expect(withFFmpeg.suffix(2) == ["--", "https://example.com/v"])
        #expect(withFFmpeg.contains("/Users/moi/Downloads/%(title)s.%(ext)s"))

        let withoutFFmpeg = YTDLP.arguments(url: "https://example.com/v", format: .bestVideo, directory: directory,
                                            hasFFmpeg: false, ffmpegLocation: nil)
        #expect(!withoutFFmpeg.contains("--merge-output-format"))
        #expect(withoutFFmpeg.contains("b[vcodec^=avc1]/b[ext=mp4]/b"))

        let mp3 = YTDLP.arguments(url: "https://example.com/v", format: .audioMP3, directory: directory, hasFFmpeg: true, ffmpegLocation: nil)
        #expect(mp3.contains("--audio-format"))
    }

    @Test func lectureDeLaSortie() {
        #expect(YTDLP.parse("NOTCHKIT_TITLE Ma vidéo") == .title("Ma vidéo"))
        #expect(YTDLP.parse("NOTCHKIT_FILE /tmp/Ma vidéo.mp4") == .file("/tmp/Ma vidéo.mp4"))
        #expect(YTDLP.parse("ERROR: Video unavailable") == .error("Video unavailable"))
        guard case let .progress(percent, detail) = YTDLP.parse("[download]  42.3% of   12.34MiB at    2.10MiB/s ETA 00:05") else {
            Issue.record("progression non reconnue"); return
        }
        #expect(abs(percent - 0.423) < 0.0001)
        #expect(detail.contains("2.10MiB/s"))
        #expect(YTDLP.parse("[youtube] Extracting URL") == nil)
    }

    @Test func formatIndisponibleSansFFmpegExplique() {
        let raw = "[youtube] njX2bu-_Vw4: Requested format is not available. Use --list-formats for a list of available formats"
        // Sans ffmpeg : la marche à suivre remplace l'erreur brute.
        #expect(YTDLP.displayError(raw, hasFFmpeg: false).contains("brew install ffmpeg"))
        // Avec ffmpeg, ou pour une autre erreur : message d'origine.
        #expect(YTDLP.displayError(raw, hasFFmpeg: true) == raw)
        #expect(YTDLP.displayError("Video unavailable", hasFFmpeg: false) == "Video unavailable")
    }

    @Test func resolutionsDisponibles() {
        let json = """
        {"formats": [
          {"format_id": "sb0", "ext": "mhtml", "vcodec": "none", "height": 180},
          {"format_id": "140", "ext": "m4a", "vcodec": "none", "acodec": "mp4a.40.2"},
          {"format_id": "299", "ext": "mp4", "vcodec": "avc1.64002A", "height": 1080},
          {"format_id": "303", "ext": "webm", "vcodec": "vp9", "height": 1080},
          {"format_id": "701", "ext": "mp4", "vcodec": "av01.0.13M.10", "height": 2160},
          {"format_id": "135", "ext": "mp4", "vcodec": "avc1.4D401F", "height": 480}
        ]}
        """
        #expect(YTDLP.availableHeights(json: Data(json.utf8)) == [2160, 1080, 480])
        #expect(YTDLP.availableHeights(json: Data("pas du JSON".utf8)).isEmpty)
        #expect(YTDLP.label(height: 2160) == "2160p")
    }

    @Test func resolutionChoisie() {
        let args1080 = YTDLP.arguments(url: "https://example.com/v", format: .bestVideo, directory: directory,
                                       hasFFmpeg: true, ffmpegLocation: nil, height: 1080)
        // Jusqu'en 1080p : H.264 d'abord.
        #expect(args1080.contains { $0.hasPrefix("bv*[height=1080][vcodec^=avc1]+ba[ext=m4a]/") })
        let args4K = YTDLP.arguments(url: "https://example.com/v", format: .bestVideo, directory: directory,
                                     hasFFmpeg: true, ffmpegLocation: nil, height: 2160)
        // Au-delà : pas de H.264 chez YouTube, SDR de préférence puis repli.
        #expect(args4K.contains("bv*[height=2160][dynamic_range=SDR]+ba[ext=m4a]/bv*[height=2160]+ba[ext=m4a]/"
                                + "bv*[height=2160]+ba/b[height<=2160]"))
        #expect(args4K.contains("--merge-output-format"))
    }

    @Test func codecEtDureeLusDansLaSortie() {
        #expect(YTDLP.parse("NOTCHKIT_VCODEC av01.0.13M.10") == .videoCodec("av01.0.13M.10"))
        #expect(YTDLP.parse("NOTCHKIT_VCODEC none") == nil)
        #expect(YTDLP.parse("NOTCHKIT_DURATION 126.0") == .duration(126))
    }

    @Test func conversionHEVCSeulementPourAV1EtVP9() {
        #expect(YTDLP.needsConversion(videoCodec: "av01.0.13M.10"))
        #expect(YTDLP.needsConversion(videoCodec: "vp09.00.51.08"))
        #expect(YTDLP.needsConversion(videoCodec: "vp9"))
        #expect(!YTDLP.needsConversion(videoCodec: "avc1.64002A"))
        #expect(!YTDLP.needsConversion(videoCodec: nil))

        let args = YTDLP.conversionArguments(input: URL(fileURLWithPath: "/tmp/a.mp4"),
                                             output: URL(fileURLWithPath: "/tmp/a.hevc-partial.mp4"), height: 2160)
        #expect(args.contains("hevc_videotoolbox"))
        #expect(args.contains("hvc1"))
        #expect(args.contains("20M"))
        #expect(args.last == "/tmp/a.hevc-partial.mp4")

        #expect(YTDLP.conversionProgress("out_time_us=63000000", duration: 126) == 0.5)
        #expect(YTDLP.conversionProgress("speed=2.1x", duration: 126) == nil)
        #expect(YTDLP.conversionProgress("out_time_us=999000000", duration: 126) == 1)
    }

    @Test func avancementGlobalAvecConversion() {
        #expect(VideoDownload.overallProgress(download: 0.5, conversion: nil, willConvert: false) == 0.5)
        #expect(VideoDownload.overallProgress(download: 0.5, conversion: nil, willConvert: true) == 0.3)
        #expect(VideoDownload.overallProgress(download: 1, conversion: 0.5, willConvert: true) == 0.8)
    }

    @Test func liensValides() {
        #expect(YTDLP.isValidLink("https://www.youtube.com/watch?v=abc"))
        #expect(YTDLP.isValidLink("  http://example.com/video  "))
        #expect(!YTDLP.isValidLink("pas un lien"))
        #expect(!YTDLP.isValidLink("file:///etc/passwd"))
    }
}

struct YTDLPInstallerTests {
    @Test func empreinteTrouveeDansLaListe() {
        let sums = """
        0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202  yt-dlp_macos
        07e54b0865303c864006925913bce2604f8ee8cc6f18699bac9c309f9328a6d8  yt-dlp_macos.zip
        """
        #expect(YTDLPInstaller.expectedHash(for: "yt-dlp_macos", in: sums) == "0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202")
        #expect(YTDLPInstaller.expectedHash(for: "yt-dlp_linux", in: sums) == nil)
    }

    @Test func empreinteSHA256() {
        #expect(YTDLPInstaller.sha256(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
