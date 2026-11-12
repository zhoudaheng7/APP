import XCTest
import PDFKit
import UIKit
@testable import LifeOS

@MainActor final class CompletionTests: XCTestCase {
    func directory() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dayisle-Completion-" + UUID().uuidString); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); addTeardownBlock { try FileManager.default.removeItem(at:url) }; return url }
    func syntheticPhoto() throws -> PreparedPhoto {
        let renderer = UIGraphicsImageRenderer(size:CGSize(width:80,height:60))
        let image = renderer.image { _ in UIColor.systemTeal.setFill(); UIRectFill(CGRect(x:0,y:0,width:80,height:60)) }
        return try PhotoProcessor.prepare(XCTUnwrap(image.jpegData(compressionQuality:0.8)))
    }
    func testStorySelectionMasksKnownPeoplePlacesAndKeepsSourceUnchanged() throws {
        let store = LifeStore(inMemory:true)
        var memory = LifePlace(title:"示例私密地点",note:"与示例人物在示例私密地点见面",latitude:30.1234,longitude:120.5678); memory.people = ["示例人物"]
        XCTAssertTrue(store.addPlace(memory))
        var selection = StorySelection(); selection.sources = ["memory:" + memory.id.uuidString]; selection.narrative = "与示例人物告别"
        let privateTextOff = try store.makeStory(selection)
        XCTAssertEqual(privateTextOff.sections[0].text,"原文未带出。"); XCTAssertFalse(privateTextOff.sections[0].title.contains("示例私密地点"))
        selection.sourceText = true
        let masked = try store.makeStory(selection),rendered = try XCTUnwrap(PDFDocument(data:StoryPDF.render(masked)))
        let text = rendered.string ?? ""
        XCTAssertFalse(text.contains("示例人物")); XCTAssertFalse(text.contains("示例私密地点")); XCTAssertFalse(text.contains(memory.id.uuidString)); XCTAssertFalse(text.contains("30.1234"))
        XCTAssertEqual(store.data.places[0].note,memory.note); XCTAssertTrue(store.data.stories.isEmpty)
    }
    func testStoryPDFPaginatesChineseAndReopensSavedSnapshotAfterSourceDeletion() throws {
        let root = try directory(),store = LifeStore(directory:root),photo = try syntheticPhoto()
        var selection = StorySelection(); selection.title = "虚构示例 · 平凡日子"; selection.narrative = String(repeating:"虚构示例：清晨整理书桌，傍晚写下一段记忆。这是排版验证，不代表真实经历。\n",count:110) + "分页结束核对文字"
        var story = try store.makeStory(selection)
        story.photos = [StoryPhoto(jpeg:photo.data,caption:"虚构示例：纯色测试图",width:photo.width,height:photo.height)]
        XCTAssertTrue(store.saveStory(story),store.error ?? "")
        let pdf = try StoryPDF.render(story),document = try XCTUnwrap(PDFDocument(data:pdf))
        XCTAssertGreaterThan(document.pageCount,2); XCTAssertTrue((document.string ?? "").contains("分页结束核对文字"))
        let attachment = XCTAttachment(data:pdf,uniformTypeIdentifier:"com.adobe.pdf"); attachment.name = "Dayisle-synthetic-story.pdf"; attachment.lifetime = .keepAlways; add(attachment)
        for index in [0,1,document.pageCount - 1] {
            let page = try XCTUnwrap(document.page(at:index)); let image = page.thumbnail(of:CGSize(width:900,height:1274),for:.mediaBox)
            let item = XCTAttachment(image:image); item.name = "Dayisle-story-page-\(index + 1)"; item.lifetime = .keepAlways; add(item)
        }
        let reopened = LifeStore(directory:root); XCTAssertEqual(reopened.data.stories.first,story)
        let oldBackup = LifeBackup(snapshot:reopened.data,media:[:]); reopened.deleteStory(story)
        XCTAssertTrue(reopened.restoreBackup(oldBackup)); XCTAssertTrue(reopened.data.stories.isEmpty)
        try reopened.close(); try store.close()
    }
    func testMigrationCopyExpiresOnlyWithUnchangedOwnedBytes() throws {
        let root = try directory(),bytes = Data("synthetic legacy snapshot".utf8),now = Date()
        try MigrationProtection.preserve(bytes,root:root,now:now)
        let copy = root.appendingPathComponent("before-v2-migration.json")
        let receipt = root.appendingPathComponent("before-v2-migration-owner.json"),originalReceipt = try Data(contentsOf:receipt)
        try FileManager.default.removeItem(at:copy)
        try MigrationProtection.preserve(bytes,root:root,now:now.addingTimeInterval(86400))
        XCTAssertEqual(try Data(contentsOf:copy),bytes); XCTAssertEqual(try Data(contentsOf:receipt),originalReceipt)
        try MigrationProtection.sweep(root:root,now:now.addingTimeInterval(6 * 86400)); XCTAssertTrue(FileManager.default.fileExists(atPath:copy.path))
        try Data("changed by user".utf8).write(to:copy)
        XCTAssertThrowsError(try MigrationProtection.sweep(root:root,now:now.addingTimeInterval(8 * 86400)))
        XCTAssertEqual(try Data(contentsOf:copy),Data("changed by user".utf8))
        try bytes.write(to:copy); try MigrationProtection.sweep(root:root,now:now.addingTimeInterval(8 * 86400)); XCTAssertFalse(FileManager.default.fileExists(atPath:copy.path))
    }
    func testDeletingRecordInvalidatesUnwrittenEditorLeaseButKeepsNewComposerAssociation() throws {
        let id = UUID(),key = "task:" + id.uuidString,composer = "compose:task:" + id.uuidString
        let before = EditorDrafts.version(key); try EditorDrafts.write(composer,fields:["title":"人工未保存的新任务"])
        EditorDrafts.remove(deleted:[LocalTombstone(id:id,kind:"task")])
        XCTAssertGreaterThan(EditorDrafts.version(key),before); XCTAssertEqual(EditorDrafts.load(composer)?["title"],"人工未保存的新任务")
        EditorDrafts.remove(composer); EditorDrafts.remove(key)
    }
    func testExtremeOutcomeNumbersRemainFiniteAndRespectDirection() throws {
        var snapshot = LifeSnapshot(),result = LifeKeyResult(objectiveID:UUID(),title:"虚构数值边界",baseline:-1e-308,target:-2e-308,unit:"")
        var value = LifeMeasurement(goalID:result.objectiveID,value:1e308,note:""); value.keyResultID = result.id; snapshot.measurements = [value]
        XCTAssertEqual(snapshot.progress(for:result),0)
        result.baseline = -1e308; result.target = 1e308; value.value = 0; snapshot.measurements = [value]
        XCTAssertEqual(try XCTUnwrap(snapshot.progress(for:result)),0.5,accuracy:0.00001)
    }
    func testHealthOverlapAndWeatherRequestKeepUnknownAndCoarseLocation() throws {
        let start = Date(timeIntervalSince1970:1000)
        XCTAssertNil(HealthContextMath.unionSeconds([],from:start,to:start.addingTimeInterval(3600)))
        XCTAssertEqual(HealthContextMath.unionSeconds([(start,start.addingTimeInterval(1800)),(start.addingTimeInterval(900),start.addingTimeInterval(5400))],from:start,to:start.addingTimeInterval(3600)),3600)
        let url = try WeatherRequest.url(latitude:30.12345,longitude:120.56789,day:"2026-01-02",zone:"Asia/Shanghai",historical:true)
        let fields = Dictionary(uniqueKeysWithValues:URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.map { ($0.name,$0.value ?? "") })
        XCTAssertEqual(fields["latitude"],"30.1"); XCTAssertEqual(fields["longitude"],"120.6"); XCTAssertEqual(fields["models"],"era5")
        let bytes = Data(#"{"daily":{"time":["2026-01-02"],"weather_code":[null],"temperature_2m_max":[null],"temperature_2m_min":[1.5],"precipitation_sum":[null]},"daily_units":{"temperature_2m_max":"°C","temperature_2m_min":"°C","precipitation_sum":"mm"}}"#.utf8)
        let response = try JSONDecoder().decode(WeatherDay.self,from:bytes)
        XCTAssertTrue(try response.text(expectedDay:"2026-01-02").contains("未知")); XCTAssertThrowsError(try response.text(expectedDay:"2026-01-03"))
    }
    func testHistoryRestoreUsesNewRevisionAndRejectsStaleConfirmation() throws {
        let store = LifeStore(inMemory:true); XCTAssertTrue(store.addTask(title:"虚构：原始任务",note:"旧文字",goalID:nil))
        let task = try XCTUnwrap(store.data.tasks.first)
        XCTAssertTrue(store.editTask(task,title:"虚构：新任务",note:"新文字",goalID:nil,due:nil,priority:1))
        let prior = try XCTUnwrap(store.data.amendments.first),fingerprint = try NewStoryView.fingerprint(store.data)
        XCTAssertTrue(store.restoreRevision(prior,expectedFingerprint:fingerprint)); XCTAssertEqual(store.data.tasks[0].revision,3); XCTAssertEqual(store.data.tasks[0].note,"旧文字")
        XCTAssertFalse(store.restoreRevision(prior,expectedFingerprint:fingerprint)); XCTAssertTrue(store.data.measurements.isEmpty)
    }
    func testPhotoCaptionDraftAndStaleEditPreserveOriginalMedia() throws {
        let store = LifeStore(inMemory:true),prepared = try syntheticPhoto(),photo = LifePhoto(caption:"虚构说明",capturedAt:Date(),sha256:LifeStore.fingerprint(prepared.data),width:prepared.width,height:prepared.height,bytes:prepared.data.count)
        XCTAssertTrue(store.addPhoto(photo,bytes:prepared.data)); var edited = photo; edited.caption = "修订说明"
        XCTAssertTrue(store.editPhoto(photo,edited:edited)); XCTAssertFalse(store.editPhoto(photo,edited:edited)); XCTAssertEqual(store.photoData(photo.id),prepared.data)
        let draft = PhotoEditorDraft(jpeg:prepared.data,width:prepared.width,height:prepared.height,caption:"未保存说明",date:Date(),memoryID:nil,tripID:nil,timeZone:"Asia/Shanghai")
        let decoded = try JSONDecoder().decode(PhotoEditorDraft.self,from:JSONEncoder().encode(draft)); XCTAssertEqual(decoded.jpeg,prepared.data); XCTAssertEqual(decoded.caption,"未保存说明")
    }
    func testShareFileStaysUntilSystemCompletionAndChangedExportIsNeverDeleted() async throws {
        let bytes = Data("synthetic share lifecycle".utf8),url = try PrivateArtifacts.export(bytes,name:"Dayisle-readable.md")
        let controller = PrivateShareSheet.controller(for:url)
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        let callback = try XCTUnwrap(controller.completionWithItemsHandler); callback(nil,true,nil,nil)
        for _ in 0..<100 { if !FileManager.default.fileExists(atPath:url.path) { break }; await Task.yield() }
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        let changed = try PrivateArtifacts.export(bytes,name:"Dayisle-readable.md")
        try Data("edited by user".utf8).write(to:changed)
        XCTAssertThrowsError(try PrivateArtifacts.finishExport(changed)); XCTAssertEqual(try Data(contentsOf:changed),Data("edited by user".utf8))
        try bytes.write(to:changed); try PrivateArtifacts.finishExport(changed)
    }
}
