import XCTest
@testable import LifeOS

@MainActor final class VaultServiceTests: XCTestCase {
    func fixture() throws -> (LifeStore,LifeVault,URL) {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Dayisle-Service-" + UUID().uuidString)
        let root = parent.appendingPathComponent("SyntheticVault",isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try FileManager.default.removeItem(at:parent) }
        let store = LifeStore(inMemory:true), service = LifeVault(store:store,directory:parent.appendingPathComponent("Settings",isDirectory:true))
        service.bind(root); XCTAssertNotNil(service.binding,service.message)
        return (store,service,root)
    }
    func select(_ task: LifeTask, store: LifeStore) {
        XCTAssertTrue(store.commit(kind:"fixture.consent",id:task.id) { $0.disclosure.grants = [DisclosureGrant(entityType:"Task",entityID:task.id,text:true)] })
    }
    func testPreviewChangeCannotPublishUnreviewedSourceValues() async throws {
        let (store,service,root) = try fixture()
        XCTAssertTrue(store.addTask(title:"示例：预览的文字",note:"",goalID:nil)); let task = try XCTUnwrap(store.data.tasks.first); select(task,store:store)
        await service.makePreview(); XCTAssertTrue(service.publicationReady,service.message)
        XCTAssertTrue(store.editTask(task,title:"示例：预览后修改",note:"",goalID:nil,due:nil,priority:0))
        await service.publish(); XCTAssertFalse(service.publicationReady)
        XCTAssertTrue(try VaultFiles.disk(root:root,includeLarge:false).commits.isEmpty)
        XCTAssertEqual(store.data.tasks.first?.title,"示例：预览后修改")
    }
    func testWithdrawCheckpointsAndRetiresOldPayloadsThenUpdatesRegisteredNote() async throws {
        let (store,service,root) = try fixture()
        XCTAssertTrue(store.addTask(title:"示例：仅在授权时出现的文字",note:"不会同步的说明",goalID:nil)); let task = try XCTUnwrap(store.data.tasks.first); select(task,store:store)
        service.setProjection(true); await service.makePreview(); XCTAssertTrue(service.publicationReady,service.message)
        await service.publish(); XCTAssertNotNil(store.data.disclosure.lastCommitID,service.message)
        await service.prepareProjection(); XCTAssertTrue(service.projectionReady,service.message); await service.writeProjection()
        let day = LifeSnapshot.dayKey(Date()), noteURL = root.appendingPathComponent("Dayisle/" + day + ".md")
        var note = try String(contentsOf:noteURL,encoding:.utf8); XCTAssertTrue(note.contains(task.title))
        note = "用户正文\r\n" + note; try Data(note.utf8).write(to:noteURL)
        XCTAssertTrue(store.commit(kind:"fixture.withdraw",id:task.id) { $0.disclosure.grants = [] })
        await service.makePreview(); XCTAssertTrue(service.publicationReady,service.message); XCTAssertTrue(service.previewRecords.isEmpty)
        await service.publish(); XCTAssertEqual(store.data.disclosure.lastSequence,3,service.message)
        XCTAssertFalse(store.data.disclosure.privacyCleanupPending == true,service.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("LifeOSExchange/generations/e1/g1/snapshot.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("LifeOSExchange/generations/e1/g1/generation-manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("LifeOSExchange/generations/e1/g2/snapshot.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("LifeOSExchange/generations/e1/g3/snapshot.json").path))
        XCTAssertEqual(service.pendingMappedBlocksCount,1)
        await service.prepareProjection(); XCTAssertTrue(service.projectionReady,service.message); await service.writeProjection()
        let redacted = try String(contentsOf:noteURL,encoding:.utf8); XCTAssertTrue(redacted.hasPrefix("用户正文\r\n")); XCTAssertFalse(redacted.contains(task.title)); XCTAssertEqual(service.pendingMappedBlocksCount,0)
        XCTAssertEqual(store.data.tasks.first?.title,task.title)
    }
    func testWithdrawLeavesHandEditedManagedBlockAsVisibleConflict() async throws {
        let (store,service,root) = try fixture()
        XCTAssertTrue(store.addTask(title:"示例：手改冲突",note:"",goalID:nil)); let task = try XCTUnwrap(store.data.tasks.first); select(task,store:store)
        service.setProjection(true); await service.makePreview(); await service.publish(); await service.prepareProjection(); await service.writeProjection()
        let noteURL = root.appendingPathComponent("Dayisle/" + LifeSnapshot.dayKey(Date()) + ".md")
        let edited = try String(contentsOf:noteURL,encoding:.utf8).replacingOccurrences(of:task.title,with:task.title + "（用户手改）"); try Data(edited.utf8).write(to:noteURL)
        XCTAssertTrue(store.commit(kind:"fixture.withdraw",id:task.id) { $0.disclosure.grants = [] })
        await service.makePreview(); await service.publish(); await service.prepareProjection()
        XCTAssertFalse(service.projectionReady); XCTAssertFalse(service.projectionIssues.isEmpty); XCTAssertEqual(service.pendingMappedBlocksCount,1)
        await service.writeProjection(); XCTAssertEqual(try String(contentsOf:noteURL,encoding:.utf8),edited)
        XCTAssertEqual(store.data.tasks.count,1)
    }
}
