import Foundation
import Testing
@testable import Notchkit

struct YTDLPTests {
    let directory = URL(fileURLWithPath: "/Users/moi/Downloads")

    @Test func argumentsAvecEtSansFFmpeg() {
        let withFFmpeg = YTDLP.arguments(url: "https://example.com/v", format: .video1080, directory: directory,
                                         hasFFmpeg: true, ffmpegLocation: URL(fileURLWithPath: "/usr/local/bin/ffmpeg"))
        #expect(withFFmpeg.contains("--merge-output-format"))
        #expect(withFFmpeg.contains("bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/b[height<=1080]"))
        #expect(withFFmpeg.suffix(2) == ["--", "https://example.com/v"])
        #expect(withFFmpeg.contains("/Users/moi/Downloads/%(title)s.%(ext)s"))

        let withoutFFmpeg = YTDLP.arguments(url: "https://example.com/v", format: .bestVideo, directory: directory,
                                            hasFFmpeg: false, ffmpegLocation: nil)
        #expect(!withoutFFmpeg.contains("--merge-output-format"))
        #expect(withoutFFmpeg.contains("b[ext=mp4]/b"))

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
