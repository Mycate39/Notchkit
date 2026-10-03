import Foundation
import Testing
@testable import Notchkit

struct MediaRemoteStreamTests {
    func line(_ json: String) -> Data { Data(json.utf8) }

    @Test func etatCompletPuisDifferences() throws {
        var stream = MediaRemoteStream()
        let fullResult = stream.apply(line: line(
            #"{"type":"data","diff":false,"payload":{"title":"Her","artist":"The American Dawn","playing":true}}"#
        ))
        let full = try #require(fullResult)
        #expect(full["title"] as? String == "Her")

        // Une différence ne contient que les clés modifiées ; null = clé supprimée.
        let updatedResult = stream.apply(line: line(
            #"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#
        ))
        let updated = try #require(updatedResult)
        #expect(updated["title"] as? String == "Her")
        #expect(updated["playing"] as? Bool == false)
        #expect(updated["artist"] == nil)
    }

    @Test func ligneInvalideIgnoree() {
        var stream = MediaRemoteStream()
        #expect(stream.apply(line: line("pas du json")) == nil)
        #expect(stream.apply(line: line(#"{"type":"autre","payload":{}}"#)) == nil)
    }

    @Test func aucunLecteurDonneUneChargeVide() throws {
        var stream = MediaRemoteStream()
        let result = stream.apply(line: line(#"{"type":"data","diff":false,"payload":{}}"#))
        let payload = try #require(result)
        #expect(NowPlayingInfo(mediaRemotePayload: payload) == nil)
    }
}

struct NowPlayingInfoTests {
    @Test func lectureChargeMediaRemote() throws {
        let payload: [String: Any] = [
            "title": "Her", "artist": "The American Dawn", "album": "Her",
            "bundleIdentifier": "com.brave.Browser", "playing": true,
            "durationMicros": 214_000_000.0, "elapsedTimeMicros": 38_000_000.0,
            "timestampEpochMicros": 1_790_000_000_000_000.0, "playbackRate": 1.0,
        ]
        let info = try #require(NowPlayingInfo(mediaRemotePayload: payload))
        #expect(info.origin == .mediaRemote)
        #expect(info.bundleIdentifier == "com.brave.Browser")
        #expect(info.duration == 214)
        #expect(info.elapsed == 38)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func positionEstimeeAvanceSeulementEnLecture() {
        let start = Date(timeIntervalSince1970: 1000)
        var info = NowPlayingInfo(origin: .mediaRemote, title: "T", isPlaying: true,
                                  duration: 100, elapsed: 10, timestamp: start)
        #expect(info.elapsed(at: start.addingTimeInterval(5)) == 15)
        // Plafonnée à la durée du morceau.
        #expect(info.elapsed(at: start.addingTimeInterval(500)) == 100)
        info.isPlaying = false
        #expect(info.elapsed(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func notificationsMusicEtSpotify() throws {
        let music = try #require(NowPlayingInfo(appleMusicUserInfo: [
            "Name": "Titre", "Artist": "Artiste", "Player State": "Playing", "Total Time": 180_000.0,
        ]))
        #expect(music.origin == .appleMusic)
        #expect(music.duration == 180)
        #expect(music.elapsed == nil)

        let spotify = try #require(NowPlayingInfo(spotifyUserInfo: [
            "Name": "Titre", "Player State": "Paused", "Duration": 200_000.0, "Playback Position": 42.0,
        ]))
        #expect(!spotify.isPlaying)
        #expect(spotify.elapsed == 42)

        #expect(NowPlayingInfo(spotifyUserInfo: ["Name": "Titre", "Player State": "Stopped"]) == nil)
    }
}

struct NowPlayingArbiterTests {
    func info(_ origin: NowPlayingInfo.Origin, playing: Bool, at seconds: TimeInterval) -> NowPlayingInfo {
        NowPlayingInfo(origin: origin, title: "T", isPlaying: playing, receivedAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func mediaRemotePrioritaire() {
        let selected = NowPlayingArbiter.select(
            mediaRemote: info(.mediaRemote, playing: false, at: 1),
            publicSources: [info(.spotify, playing: true, at: 2)]
        )
        #expect(selected?.origin == .mediaRemote)
    }

    @Test func repliSurLecteurPublicEnLecture() {
        let selected = NowPlayingArbiter.select(
            mediaRemote: nil,
            publicSources: [info(.appleMusic, playing: false, at: 5), info(.spotify, playing: true, at: 2)]
        )
        #expect(selected?.origin == .spotify)
    }

    @Test func sinonLePlusRecentEnPause() {
        let selected = NowPlayingArbiter.select(
            mediaRemote: nil,
            publicSources: [info(.appleMusic, playing: false, at: 5), info(.spotify, playing: false, at: 2)]
        )
        #expect(selected?.origin == .appleMusic)
        #expect(NowPlayingArbiter.select(mediaRemote: nil, publicSources: []) == nil)
    }
}
