import Foundation
import Testing
@testable import Notchkit

struct GitStatusTests {
    @Test func decodeBrancheAvanceEtFichiers() {
        let output = """
        # branch.oid 1234567890abcdef
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +2 -1
        1 .M N... 100644 100644 100644 abc abc Notchkit/App/AppDelegate.swift
        1 A. N... 000000 100644 100644 000 abc Nouveau fichier.swift
        2 R. N... 100644 100644 100644 abc abc R100 Nouveau.swift\tAncien.swift
        ? docs/brouillon.md
        """
        let status = GitStatus.parse(output)
        #expect(status.branch == "main")
        #expect(status.ahead == 2 && status.behind == 1 && status.hasUpstream)
        #expect(status.changes.map(\.path) == ["Notchkit/App/AppDelegate.swift", "Nouveau fichier.swift", "Nouveau.swift", "docs/brouillon.md"])
        #expect(status.changes.map(\.kind) == [.modified, .added, .renamed, .untracked])
    }

    @Test func depotPropreSansAmont() {
        let status = GitStatus.parse("# branch.oid abc\n# branch.head feature\n")
        #expect(status.isClean && !status.hasUpstream && status.branch == "feature")
    }

    @Test func vraiDepotNotchkit() async throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let root = try #require(await GitCommand.repositoryRoot(containing: repo))
        #expect(root.lastPathComponent == "Notchkit")
        let output = try #require(await GitCommand.run(["status", "--porcelain=v2", "--branch"], in: root))
        #expect(!GitStatus.parse(output).branch.isEmpty)
    }
}

struct PullRequestChecksTests {
    @Test func echecPuisEnCoursPuisSucces() {
        #expect(PullRequestChecks.summary(statuses: [], conclusions: ["success", "failure"]) == .failure)
        #expect(PullRequestChecks.summary(statuses: ["error"], conclusions: ["success"]) == .failure)
        #expect(PullRequestChecks.summary(statuses: [], conclusions: ["success", nil]) == .pending)
        #expect(PullRequestChecks.summary(statuses: ["pending"], conclusions: []) == .pending)
        #expect(PullRequestChecks.summary(statuses: ["success"], conclusions: ["success", "skipped", "neutral"]) == .success)
        #expect(PullRequestChecks.summary(statuses: [], conclusions: []) == PullRequest.Checks.none)
    }
}
