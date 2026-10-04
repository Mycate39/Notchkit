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

    @Test func batterieLueDansSystemProfiler() throws {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods de Tom":{"device_address":"30:0E:43:2E:78:ED","device_minorType":"Headphones",
            "device_batteryLevelLeft":"100%","device_batteryLevelRight":"62%","device_batteryLevelCase":"40%"}},
          {"MX Anywhere 3":{"device_address":"D4:0B:01:5F:92:08","device_minorType":"Mouse","device_batteryLevelMain":"15%"}}
        ],"device_not_connected":[{"JBL":{"device_address":"74:2A:8A:98:48:B6"}}]}]}
        """
        let devices = BluetoothInventory.parse(Data(json.utf8))
        #expect(devices.count == 2)
        let airpods = try #require(devices.first { $0.name == "AirPods de Tom" })
        #expect(airpods.battery == BluetoothBattery(left: 100, right: 62, caseLevel: 40, main: nil))
        #expect(airpods.battery.summary == 62)
        #expect(BluetoothDeviceInfo.normalized("30-0E-43-2E-78-ED:output").contains(airpods.address))
        let mouse = try #require(devices.first { $0.name == "MX Anywhere 3" })
        #expect(mouse.battery.summary == 15)
        #expect(mouse.symbol == "computermouse")
    }

    @Test func sortieInvalideSansPlantage() {
        #expect(BluetoothInventory.parse(Data("pas du json".utf8)).isEmpty)
    }
}
