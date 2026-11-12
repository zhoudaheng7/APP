import XCTest
import CoreData
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import LifeOS

@MainActor final class V2StoreTests: XCTestCase {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dayisle-Test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }; return url
    }
    func fixture(_ name: String) throws -> Data { try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))) }
    func testActualLegacySQLitePayloadMigratesAndReopensWithoutChangingIDs() throws {
        let parent = try temporaryDirectory(), bytes = try fixture("legacy-v1")
        do {
            let legacy = LifeStore(directory: parent)
            let row = NSEntityDescription.insertNewObject(forEntityName: "LifeOSSnapshot", into: legacy.container.viewContext)
            row.setValue("current", forKey: "key"); row.setValue(bytes, forKey: "payload"); try legacy.container.viewContext.save()
            try legacy.close()
        }
        let upgraded = LifeStore(directory: parent); XCTAssertTrue(upgraded.ready, upgraded.error ?? "")
        XCTAssertEqual(upgraded.data.schemaVersion,2); XCTAssertEqual(upgraded.data.tasks[0].revision,3)
        XCTAssertEqual(upgraded.data.tasks[0].note,"迁移前的原文"); XCTAssertEqual(upgraded.data.keyResults[0].id,upgraded.data.goals[0].id)
        XCTAssertEqual(upgraded.data.measurements[0].keyResultID,upgraded.data.goals[0].id); XCTAssertEqual(upgraded.data.routes[0].points.count,2)
        XCTAssertEqual(try Data(contentsOf: parent.appendingPathComponent("before-v2-migration.json")),bytes)
        XCTAssertTrue(upgraded.addTask(title:"示例：升级后新任务",note:"",goalID:nil))
        let reopened = LifeStore(directory:parent); XCTAssertTrue(reopened.ready); XCTAssertEqual(reopened.data.tasks.count,2); XCTAssertEqual(reopened.data.reviews[0].reflection,"示例：旧版日复盘原文")
        try reopened.close(); try upgraded.close()
    }
    func testCurrentOutcomeUsesObservedTimeAndWeightsWithoutSumming() throws {
        let store=LifeStore(inMemory:true),goal=LifeGoal(title:"示例方向",intention:"",target:10,unit:"本",due:Date())
        XCTAssertTrue(store.addGoal(goal));let second=LifeKeyResult(objectiveID:goal.id,title:"示例递减",baseline:100,target:80,unit:"分",weight:3)
        XCTAssertTrue(store.addKeyResult(second));XCTAssertNil(store.data.objectiveProgress(goal.id))
        var latest=LifeMeasurement(goalID:goal.id,value:5,note:"用户累计读数");latest.keyResultID=goal.id;latest.observedAt=Date(timeIntervalSince1970:2000)
        var older=LifeMeasurement(goalID:goal.id,value:9,note:"晚录入的旧读数");older.keyResultID=goal.id;older.observedAt=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.addMeasurement(latest));XCTAssertTrue(store.addMeasurement(older));XCTAssertEqual(store.data.currentMeasurement(for:goal.id)?.value,5)
        var down=LifeMeasurement(goalID:goal.id,value:90,note:"");down.keyResultID=second.id;XCTAssertTrue(store.addMeasurement(down))
        XCTAssertEqual(try XCTUnwrap(store.data.objectiveProgress(goal.id)),0.5,accuracy:0.0001)
        store.rejectMeasurement(latest);XCTAssertEqual(store.data.currentMeasurement(for:goal.id)?.value,9)
    }
    func testOverlappingActualsUseUnionAndDoNotCreateResults() {
        let store=LifeStore(inMemory:true),start=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.commit(kind:"fixture.synthetic",id:UUID()){ state in
            state.sessions=[LifeSession(title:"示例A",start:start,end:start.addingTimeInterval(3600),confirmed:true),LifeSession(title:"示例B",start:start.addingTimeInterval(1800),end:start.addingTimeInterval(5400),confirmed:true)]
        })
        XCTAssertEqual(store.data.unionActualSeconds(from:start,to:start.addingTimeInterval(7200)),5400)
        XCTAssertTrue(store.data.measurements.isEmpty);XCTAssertTrue(store.data.tasks.isEmpty)
    }
    func testLateVisitIdentityDeduplicatesAndNeverRevivesDeletedObservation() throws {
        let store=LifeStore(inMemory:true),start=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.setVisitCollection(true,at:start))
        var observation=VisitObservation(latitude:30,longitude:120,accuracy:100,arrival:start.addingTimeInterval(10),departure:nil,receivedAt:start.addingTimeInterval(20))
        XCTAssertTrue(store.receiveVisit(observation));let id=try XCTUnwrap(store.data.visits.first?.id)
        observation.departure=start.addingTimeInterval(30);observation.receivedAt=start.addingTimeInterval(40)
        XCTAssertTrue(store.receiveVisit(observation));XCTAssertEqual(store.data.visits.count,1);XCTAssertEqual(store.data.visits[0].id,id)
        let candidate=store.data.visits[0];XCTAssertTrue(store.reviseVisit(candidate,placeID:nil,arrival:candidate.arrival,departure:candidate.departure,note:"本人核对",state:"confirmed"))
        observation.departure=start.addingTimeInterval(60);observation.receivedAt=start.addingTimeInterval(70);XCTAssertTrue(store.receiveVisit(observation));XCTAssertEqual(store.data.visits[0].departure,start.addingTimeInterval(30))
        store.deleteVisit(store.data.visits[0]);XCTAssertFalse(store.receiveVisit(observation));XCTAssertTrue(store.data.visits.isEmpty)
    }
    func testPausedCollectionRejectsNewLateFactsAndKeepsUnknownTimes() {
        let store=LifeStore(inMemory:true),start=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.setVisitCollection(true,at:start))
        let unknown=VisitObservation(latitude:30,longitude:120,accuracy:100,arrival:nil,departure:start.addingTimeInterval(10),receivedAt:start.addingTimeInterval(20))
        XCTAssertTrue(store.receiveVisit(unknown));XCTAssertNil(store.data.visits[0].arrival)
        XCTAssertTrue(store.setVisitCollection(false,at:start.addingTimeInterval(30)))
        let late=VisitObservation(latitude:31,longitude:121,accuracy:100,arrival:start.addingTimeInterval(1),departure:start.addingTimeInterval(20),receivedAt:start.addingTimeInterval(60))
        XCTAssertFalse(store.receiveVisit(late));XCTAssertEqual(store.data.visits.count,1)
    }
    func testAlreadyKnownLateDepartureCanEnrichOnlyInsideApprovedWindow() {
        let store=LifeStore(inMemory:true),start=Date(timeIntervalSince1970:1000)
        XCTAssertTrue(store.setVisitCollection(true,at:start))
        var observation=VisitObservation(latitude:30,longitude:120,accuracy:100,arrival:start.addingTimeInterval(5),departure:nil,receivedAt:start.addingTimeInterval(6))
        XCTAssertTrue(store.receiveVisit(observation));XCTAssertTrue(store.setVisitCollection(false,at:start.addingTimeInterval(30)))
        observation.departure=start.addingTimeInterval(20);observation.receivedAt=start.addingTimeInterval(40)
        XCTAssertTrue(store.receiveVisit(observation));XCTAssertEqual(store.data.visits[0].departure,observation.departure)
        observation.departure=start.addingTimeInterval(35);XCTAssertFalse(store.receiveVisit(observation));XCTAssertEqual(store.data.visits[0].departure,start.addingTimeInterval(20))
    }
    func testRestoringOpenTimerRequiresExplicitTimeResolution() throws {
        let store=LifeStore(inMemory:true),start=Date().addingTimeInterval(-3600)
        XCTAssertTrue(store.commit(kind:"fixture.synthetic",id:UUID()){ $0.sessions=[LifeSession(title:"示例：旧计时",start:start)] })
        let backup=LifeBackup(snapshot:store.data,media:[:]);store.stopSession()
        XCTAssertTrue(store.restoreBackup(backup));let pending=try XCTUnwrap(store.runningSession)
        XCTAssertEqual(pending.restorePending,true);store.stopSession();XCTAssertNil(store.runningSession?.end)
        XCTAssertTrue(store.editSession(pending,title:pending.title,start:start,end:start.addingTimeInterval(900),note:"本人确认的结束时间",confirmed:false))
        XCTAssertNil(store.runningSession);XCTAssertFalse(store.data.sessions[0].confirmed);XCTAssertEqual(store.data.sessions[0].end,start.addingTimeInterval(900))
    }
    func preparedPhoto() throws -> PreparedPhoto {
        let renderer=UIGraphicsImageRenderer(size:CGSize(width:30,height:20))
        let raw=renderer.jpegData(withCompressionQuality:0.8){ context in UIColor.systemTeal.setFill();context.cgContext.fill(CGRect(x:0,y:0,width:30,height:20)) }
        return try PhotoProcessor.prepare(raw)
    }
    func testPhotoSnapshotAndBlobAreAtomicAndReopenAsOneStore() throws {
        let parent=try temporaryDirectory(),store=LifeStore(directory:parent),image=try preparedPhoto()
        XCTAssertTrue(PhotoProcessor.isSanitizedJPEG(image.data,width:image.width,height:image.height))
        let photo=LifePhoto(caption:"示例照片",capturedAt:Date(),sha256:LifeStore.fingerprint(image.data),width:image.width,height:image.height,bytes:image.data.count)
        let before=store.data.pendingChanges.count
        XCTAssertFalse(store.addPhoto(photo,bytes:Data("wrong".utf8)));XCTAssertTrue(store.data.photos.isEmpty);XCTAssertEqual(store.data.pendingChanges.count,before)
        XCTAssertTrue(store.addPhoto(photo,bytes:image.data));let reopened=LifeStore(directory:parent)
        defer { try? reopened.close(); try? store.close() }
        XCTAssertTrue(reopened.ready,reopened.error ?? "");XCTAssertEqual(reopened.photoData(photo.id),image.data)
        let backupURL=try XCTUnwrap(reopened.exportBackup());defer{try? PrivateArtifacts.finishExport(backupURL)}
        let backup=try LifeStore.decodeBackup(Data(contentsOf:backupURL));XCTAssertEqual(backup.media[photo.id.uuidString],image.data)
        reopened.deletePhoto(photo);XCTAssertTrue(reopened.restoreBackup(backup));XCTAssertTrue(reopened.data.photos.isEmpty);XCTAssertNil(reopened.photoData(photo.id))
    }
    func testCorruptBackupRefusesBeforeAnyMutation() throws {
        let store=LifeStore(inMemory:true);XCTAssertTrue(store.addTask(title:"示例原任务",note:"",goalID:nil))
        var damaged=LifeBackup(snapshot:store.data,media:[:]);damaged.format="unknown"
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .millisecondsSince1970
        XCTAssertThrowsError(try LifeStore.decodeBackup(encoder.encode(damaged)));XCTAssertEqual(store.data.tasks[0].title,"示例原任务")
    }
    func testPhotoProcessingRemovesPrivateMetadataAndBackupRejectsItsReintroduction() throws {
        let image = try preparedPhoto(), output = NSMutableData()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(image.data as CFData,nil))
        let target = try XCTUnwrap(CGImageDestinationCreateWithData(output,UTType.jpeg.identifier as CFString,1,nil))
        CGImageDestinationAddImageFromSource(target,source,0,[kCGImagePropertyExifDictionary:[kCGImagePropertyExifDateTimeOriginal:"2001:02:03 04:05:06"],kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:12.34,kCGImagePropertyGPSLatitudeRef:"N"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(target))
        XCTAssertFalse(PhotoProcessor.isSanitizedJPEG(output as Data,width:image.width,height:image.height))
        let cleaned = try PhotoProcessor.prepare(output as Data)
        XCTAssertTrue(PhotoProcessor.isSanitizedJPEG(cleaned.data,width:cleaned.width,height:cleaned.height))
        let store = LifeStore(inMemory:true), descriptor = LifePhoto(caption:"恶意元数据合成样例",capturedAt:Date(),sha256:LifeStore.fingerprint(output as Data),width:image.width,height:image.height,bytes:output.length)
        var snapshot = store.data; snapshot.photos = [descriptor]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        XCTAssertThrowsError(try LifeStore.decodeBackup(encoder.encode(LifeBackup(snapshot:snapshot,media:[descriptor.id.uuidString:output as Data]))))
    }
    func testStaleEditorsCannotOverwriteOrReviveRecords() throws {
        let store = LifeStore(inMemory:true), place = KnownPlace(title:"示例地点",latitude:1,longitude:1), trip = LifeTrip(title:"示例行程",start:Date(),end:Date())
        XCTAssertTrue(store.saveKnownPlace(place)); var changed = place; changed.city = "示例城市"; XCTAssertTrue(store.saveKnownPlace(changed)); XCTAssertFalse(store.saveKnownPlace(place)); XCTAssertEqual(store.data.knownPlaces.first?.city,"示例城市")
        store.deleteKnownPlace(try XCTUnwrap(store.data.knownPlaces.first)); XCTAssertFalse(store.saveKnownPlace(place)); XCTAssertTrue(store.data.knownPlaces.isEmpty)
        XCTAssertTrue(store.saveTrip(trip)); var newer = trip; newer.note = "新版内容"; XCTAssertTrue(store.saveTrip(newer)); XCTAssertFalse(store.saveTrip(trip)); XCTAssertEqual(store.data.trips.first?.note,"新版内容")
        let goal = LifeGoal(title:"示例方向",intention:"",target:10,unit:"本",due:Date()); XCTAssertTrue(store.addGoal(goal))
        XCTAssertTrue(store.editGoal(goal,title:"新方向",intention:"",due:goal.due,assessment:"")); XCTAssertFalse(store.editGoal(goal,title:"旧版覆盖",intention:"",due:goal.due,assessment:"")); XCTAssertEqual(store.data.goals.first?.title,"新方向")
    }
    func testSplittingAndMergingActualsPreservesUnionAndRejectsFillingGaps() throws {
        let store = LifeStore(inMemory:true), start = Date(timeIntervalSince1970:10000), original = LifeSession(title:"示例投入",start:start,end:start.addingTimeInterval(3600),confirmed:true)
        XCTAssertTrue(store.addClosedSession(original)); XCTAssertTrue(store.splitSession(original,at:start.addingTimeInterval(1800))); XCTAssertEqual(store.data.sessions.count,2)
        XCTAssertEqual(store.data.unionActualSeconds(from:start,to:start.addingTimeInterval(7200)),3600)
        XCTAssertTrue(store.data.tombstones.contains { $0.id == original.id && $0.kind == "actual" })
        let first = store.data.sessions[0],second = store.data.sessions[1]
        XCTAssertTrue(store.mergeSessions(first,second)); XCTAssertEqual(store.data.sessions.count,1)
        var separated = original; separated.id = UUID(); separated.start = start.addingTimeInterval(4000); separated.end = start.addingTimeInterval(5000)
        XCTAssertTrue(store.addClosedSession(separated)); XCTAssertFalse(store.mergeSessions(try XCTUnwrap(store.data.sessions.first),separated)); XCTAssertEqual(store.data.sessions.count,2)
    }
    func testMalformedPhotoByteCountsThrowWithoutOverflow() {
        var state=LifeSnapshot()
        state.photos=(0..<3).map{ _ in LifePhoto(caption:"恶意容量样例",capturedAt:Date(),sha256:String(repeating:"a",count:64),width:1,height:1,bytes:Int.max) }
        XCTAssertThrowsError(try state.validate())
    }
    func testDecimalInputsRejectTrailingGarbage() {
        XCTAssertNil(decimalValue("12abc"));XCTAssertNil(decimalValue("--2"));XCTAssertEqual(decimalValue("-2.5"),-2.5);XCTAssertEqual(decimalValue("1e3"),1000)
    }
    func testCompetingStoreNeverOverwritesAConcurrentCommit() throws {
        let parent=try temporaryDirectory(),first=LifeStore(directory:parent)
        XCTAssertTrue(first.addTask(title:"示例A",note:"",goalID:nil));let second=LifeStore(directory:parent)
        defer { try? second.close(); try? first.close() }
        XCTAssertTrue(second.addTask(title:"示例B",note:"",goalID:nil));XCTAssertFalse(first.addTask(title:"示例C",note:"",goalID:nil))
        XCTAssertEqual(Set(first.data.tasks.map(\.title)),Set(["示例A","示例B"]))
        XCTAssertTrue(first.addTask(title:"示例C",note:"",goalID:nil));XCTAssertEqual(first.data.tasks.count,3)
    }
    func testTwoInitiallyEmptyWritersRecoverAfterConflict() throws {
        let parent=try temporaryDirectory(),first=LifeStore(directory:parent),second=LifeStore(directory:parent)
        defer { try? second.close(); try? first.close() }
        XCTAssertTrue(first.addTask(title:"示例A",note:"",goalID:nil))
        XCTAssertFalse(second.addTask(title:"示例B",note:"",goalID:nil))
        XCTAssertEqual(second.data.tasks.first?.title,"示例A")
        XCTAssertTrue(second.addTask(title:"示例B",note:"",goalID:nil));XCTAssertEqual(second.data.tasks.count,2)
    }
    func testCalendarSaveKeepsPrivatePlanAndMapsActualCommitmentIdempotently() throws {
        let store=LifeStore(inMemory:true),now=Date(),plan=LifePlan(title:"示例私人计划",start:now,end:now.addingTimeInterval(3600))
        XCTAssertTrue(store.addPlan(plan));XCTAssertTrue(store.recordCalendarSave(plan:plan,eventIdentifier:"synthetic-event",calendarIdentifier:"synthetic-calendar"))
        XCTAssertEqual(store.data.plans.count,2);XCTAssertFalse(store.data.plans.first{ $0.id==plan.id }!.isCommitment)
        XCTAssertTrue(store.recordCalendarSave(plan:plan,eventIdentifier:"synthetic-event",calendarIdentifier:"synthetic-calendar"));XCTAssertEqual(store.data.plans.count,2);XCTAssertEqual(store.data.calendarLinks.count,1)
    }
    func testVaultFactAndTerminalRegistryAreAtomicAndNeverRepeat() throws {
        let store=LifeStore(inMemory:true),review=LifeReview(day:"2026-11-12",reflection:"示例：确认草稿",mood:nil),id=UUID()
        let record=VaultOperation(id:id,datasetID:store.data.disclosure.datasetID,clientID:UUID(),payloadHash:String(repeating:"a",count:64),status:"accepted",receipt:Data("synthetic receipt".utf8),finalEntityID:review.id)
        XCTAssertTrue(store.recordVaultResult(record,review:review));XCTAssertTrue(store.recordVaultResult(record,review:review));XCTAssertEqual(store.data.reviews.count,1);XCTAssertEqual(store.data.vaultOperations.count,1)
        let conflict=VaultOperation(id:UUID(),datasetID:record.datasetID,clientID:record.clientID,payloadHash:record.payloadHash,status:"accepted",receipt:record.receipt,finalEntityID:UUID())
        XCTAssertFalse(store.recordVaultResult(conflict,review:LifeReview(day:review.day,reflection:"覆盖",mood:nil)));XCTAssertEqual(store.data.vaultOperations.count,1)
    }
}
