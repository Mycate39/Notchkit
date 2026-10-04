import Foundation
import Testing
@testable import Notchkit

struct AirPodsTests {
    func device(_ uid: String, _ name: String) -> HeadphoneDevice {
        HeadphoneDevice(id: 1, uid: uid, name: name, isDefaultOutput: false)
    }

    @Test func modeleDeduitDuNom() {
        #expect(HeadphoneDevice.Kind(name: "AirPods Pro de Léa") == .airPodsPro)
        #expect(HeadphoneDevice.Kind(name: "AirPods Max") == .airPodsMax)
        #expect(HeadphoneDevice.Kind(name: "AirPods de Tom") == .airPods)
        #expect(HeadphoneDevice.Kind(name: "Powerbeats Pro") == .beats)
        #expect(HeadphoneDevice.Kind(name: "WH-1000XM5") == .other)
    }

    @Test func connexionsEtDeconnexions() {
        let pro = device("a", "AirPods Pro")
        let sony = device("b", "WH-1000XM5")
        #expect(HeadphoneEvent.events(from: [], to: [pro]) == [.connected(pro)])
        #expect(HeadphoneEvent.events(from: [pro], to: [sony]) == [.connected(sony), .disconnected(pro)])
        #expect(HeadphoneEvent.events(from: [pro], to: [pro]).isEmpty)
    }
}
