import Foundation
import Testing
@testable import Notchkit

struct SystemMathTests {
    @Test func chargeDUnCoeurEntreDeuxReleves() {
        let old = SystemMath.CoreTicks(user: 100, system: 50, idle: 850, nice: 0)
        let new = SystemMath.CoreTicks(user: 150, system: 100, idle: 950, nice: 0)
        #expect(SystemMath.usage(from: old, to: new) == 0.5)
        #expect(SystemMath.usage(from: new, to: new) == 0)
    }

    @Test func debitEtCompteurRemisAZero() {
        #expect(SystemMath.rate(from: 1000, to: 3000, interval: 2) == 1000)
        #expect(SystemMath.rate(from: 3000, to: 10, interval: 2) == 0)
        #expect(SystemMath.rate(from: 0, to: 10, interval: 0) == 0)
    }
}

struct SystemReadersTests {
    @Test func lecturesReellesPlausibles() {
        #expect(!SystemReaders.coreTicks().isEmpty)
        let memory = SystemReaders.memoryUsed()
        #expect(memory > 0 && memory <= ProcessInfo.processInfo.physicalMemory)
        let disk = SystemReaders.disk()
        #expect(disk.total > 0 && disk.free >= 0 && disk.free <= disk.total)
        let processes = SystemReaders.processes()
        #expect(processes.count > 10)
        #expect(processes[ProcessInfo.processInfo.processIdentifier] != nil)
    }
}
