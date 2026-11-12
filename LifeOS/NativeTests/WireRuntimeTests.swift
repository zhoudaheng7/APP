import XCTest
@testable import LifeOS

@MainActor final class WireRuntimeTests: XCTestCase {
    func testNativeJavaScriptCoreRunsFrozenMachineAndProjectionCorpus() throws {
        let url=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"corpus",withExtension:"json"))
        let corpus=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        let cases=try XCTUnwrap(corpus["cases"] as? [[String:Any]]),runtime=try WireRuntime()
        for candidate in cases {
            let id=try XCTUnwrap(candidate["id"] as? String),expected=try XCTUnwrap(candidate["expected"] as? [String:Any])
            var input:[String:Any]=["candidate":candidate]
            if let previous=candidate["previous"] as? String { input["previous"]=cases.first { $0["id"] as? String == previous } }
            input["projectionKey"]=candidate["projectionKey"];input["instanceID"]=candidate["instanceID"]
            let result=try runtime.call("vector",input)
            XCTAssertEqual(result["status"] as? String,expected["machine"] as? String,id)
            if let code=expected["machineCode"] as? String { XCTAssertEqual(result["code"] as? String,code,id) }
            if let projection=expected["projection"] as? String { XCTAssertEqual(result["projection"] as? String,projection,id) }
            if let code=expected["projectionCode"] as? String { XCTAssertEqual(result["projectionCode"] as? String,code,id) }
        }
    }
    func testNativeWireDisclosureNeverIncludesPrecisePrivateMedia() throws {
        var data=LifeSnapshot();data.places=[LifePlace(title:"示例秘密地点",note:"只存本机",latitude:30,longitude:120)]
        data.routes=[LifeRoute(title:"示例精确路线",end:Date(),points:[RoutePoint(latitude:30,longitude:120)])]
        data.tasks=[LifeTask(title:"示例任务",note:"私密说明")]
        let bytes=try JSONSerialization.data(withJSONObject:data.wireEntities())
        let text=try XCTUnwrap(String(data:bytes,encoding:.utf8))
        XCTAssertFalse(text.contains("latitude"));XCTAssertFalse(text.contains("longitude"));XCTAssertFalse(text.contains("只存本机"));XCTAssertFalse(text.contains("私密说明"));XCTAssertFalse(text.contains("示例精确路线"));XCTAssertTrue(text.contains("示例任务"))
    }
    func testNativePublishThenProjectionPreservesTextAndRefusesEdits() throws {
        let runtime=try WireRuntime(),data=LifeSnapshot(),now=Date(),dataset=data.disclosure.datasetID.wire,writer=data.disclosure.writerID.wire,binding=UUID().wire,day=LifeSnapshot.dayKey(now)
        let end=LifeSnapshot.dayKey(Calendar.current.date(byAdding:.day,value:1,to:now)!)
        let seed:[String:Any]=["datasetID":dataset,"writerID":writer,"bindingID":binding,"today":day,"startDay":day,"endDay":end,"now":wireInstant(now),"projectionEnabled":true,"projectionEpoch":1,"body":"hello\n","entities":[],"deleted":[],"disk":["commits":[],"files":[:]]]
        let built=try runtime.call("build",seed),commit=try XCTUnwrap(built["commit"] as? [String:Any]),id=try XCTUnwrap(commit["commitID"] as? String),key=try XCTUnwrap(built["projectionKey"] as? String)
        _=try runtime.call("adopt",["commitID":id])
        let path="Dayisle/"+day+".md",original=Data("用户正文\r\n".utf8).base64EncodedString()
        let projected=try runtime.call("project",["head":id,"projectionKey":key,"writerID":writer,"notes":[path:original]])
        let rendered=try XCTUnwrap(Data(base64Encoded:try XCTUnwrap(projected["bytes"] as? String))),text=try XCTUnwrap(String(data:rendered,encoding:.utf8))
        XCTAssertTrue(text.hasPrefix("用户正文\r\n"));XCTAssertTrue(text.contains("hello"))
        let changed=Data(text.replacingOccurrences(of:"hello",with:"用户修改了块内文字").utf8).base64EncodedString()
        XCTAssertThrowsError(try runtime.call("project",["head":id,"projectionKey":key,"writerID":writer,"notes":[path:changed]]))
    }
}
