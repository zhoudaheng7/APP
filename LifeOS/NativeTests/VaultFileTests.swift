import XCTest
@testable import LifeOS

final class VaultFileTests: XCTestCase {
    func recoveryFixture() throws -> (URL,PendingVaultWrite,[String:Data]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Dayisle-Recovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try FileManager.default.removeItem(at:root) }
        let c = "commits/e1-g1-" + String(repeating:"a",count:64) + ".json"
        let files = [c:Data("synthetic commit".utf8),"generations/e1/g1/generation-manifest.json":Data("synthetic manifest".utf8),"generations/e1/g1/snapshot.json":Data("synthetic owned snapshot".utf8)]
        let receipt = PendingVaultWrite(bindingID:UUID(),datasetID:UUID(),writerID:UUID(),commitPath:c,fileHashes:files.mapValues(hashBytes),parentHashes:[])
        return (root,receipt,files)
    }
    func testInterruptedWriteCleanupPreservesUnownedFiles() throws {
        let (root,receipt,files) = try recoveryFixture()
        for (path,bytes) in files where path != receipt.commitPath { try VaultFiles.immutableWrite(bytes,relative:"LifeOSExchange/" + path,root:root) }
        try VaultFiles.immutableWrite(Data("用户外来文件".utf8),relative:"LifeOSExchange/generations/e1/g1/user-note.txt",root:root)
        XCTAssertFalse(try VaultFiles.recoverUncommitted(root:root,receipt:receipt))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("LifeOSExchange/generations/e1/g1/snapshot.json").path))
        XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("LifeOSExchange/generations/e1/g1/user-note.txt"),encoding:.utf8),"用户外来文件")
    }
    func testInterruptedWriteCleanupRefusesChangedFilesBeforeAnyDeletion() throws {
        let (root,receipt,files) = try recoveryFixture()
        for (path,bytes) in files where path != receipt.commitPath { try VaultFiles.immutableWrite(bytes,relative:"LifeOSExchange/" + path,root:root) }
        try Data("别人改过的内容".utf8).write(to:root.appendingPathComponent("LifeOSExchange/generations/e1/g1/snapshot.json"))
        XCTAssertThrowsError(try VaultFiles.recoverUncommitted(root:root,receipt:receipt))
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("LifeOSExchange/generations/e1/g1/generation-manifest.json").path))
    }
    func testExistingCommitAlwaysProtectsItsGenerationFromRecoveryCleanup() throws {
        let (root,receipt,files) = try recoveryFixture()
        for (path,bytes) in files { try VaultFiles.immutableWrite(bytes,relative:"LifeOSExchange/" + path,root:root) }
        XCTAssertTrue(try VaultFiles.recoverUncommitted(root:root,receipt:receipt))
        XCTAssertEqual(try VaultFiles.read("LifeOSExchange/generations/e1/g1/snapshot.json",root:root),files["generations/e1/g1/snapshot.json"])
    }
    func testPhysicalGuardRejectsTraversalCaseAliasesAndSymlinks() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("Dayisle-FS-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        XCTAssertThrowsError(try VaultFiles.path("../outside.json",root:root))
        let target=root.appendingPathComponent("actual");try FileManager.default.createDirectory(at:target,withIntermediateDirectories:false)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("linked"),withDestinationURL:target)
        XCTAssertThrowsError(try VaultFiles.path("linked/new.json",root:root,createParents:true))
        XCTAssertThrowsError(try VaultFiles.path("Actual/new.json",root:root,createParents:true))
        XCTAssertFalse(FileManager.default.fileExists(atPath:target.appendingPathComponent("new.json").path))
    }
    func testImmutableCommitWriteAndNoteCASProtectOriginalBytes() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("Dayisle-FS-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let bytes=Data("first".utf8)
        try VaultFiles.immutableWrite(bytes,relative:"LifeOSExchange/commits/example.json",root:root)
        XCTAssertThrowsError(try VaultFiles.immutableWrite(Data("second".utf8),relative:"LifeOSExchange/commits/example.json",root:root))
        XCTAssertEqual(try VaultFiles.read("LifeOSExchange/commits/example.json",root:root),bytes)
        let url=try VaultFiles.path("Dayisle/2026-11-12.md",root:root,createParents:true);try Data("用户新正文".utf8).write(to:url)
        XCTAssertThrowsError(try VaultFiles.writeNote(root:root,relative:"Dayisle/2026-11-12.md",bytes:Data("replacement".utf8),originalHash:hashBytes(Data()),ledgerCommits:[bytes.base64EncodedString()]))
        XCTAssertEqual(try String(contentsOf:url,encoding:.utf8),"用户新正文")
    }
}
