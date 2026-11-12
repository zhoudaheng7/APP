import XCTest
@testable import LifeOS

final class VaultFileTests: XCTestCase {
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
