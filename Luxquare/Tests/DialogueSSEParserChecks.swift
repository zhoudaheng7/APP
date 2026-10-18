// Generated from the actual DialogueStore.swift parser; no network or user data.
import Foundation
struct DialogueSSEParser {
    struct Event { var id: Int?; var name: String; var data: String }
    private var eventID: Int?
    private var name = ""
    private var lines: [String] = []
    private var size = 0

    mutating func consume(_ raw: String) throws -> Event? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.isEmpty { return finish() }
        if line.hasPrefix(":") { return nil }
        size += line.utf8.count
        guard size < 2_097_152 else { throw DialogueFailure.message("回复片段过大，本轮已保留，请到创作工作台核对。") }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count == 2 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "id": eventID = Int(value)
        case "event": name = value
        case "data": lines.append(value)
        default: break
        }
        return nil
    }

    mutating func finish() -> Event? {
        defer { eventID = nil; name = ""; lines = []; size = 0 }
        guard !lines.isEmpty else { return nil }
        return Event(id: eventID, name: name.isEmpty ? "message" : name, data: lines.joined(separator: "\n"))
    }
}

enum DialogueFailure: Error, LocalizedError {
    case http(Int, String)
    case message(String)
    var errorDescription: String? {
        switch self { case .http(_, let text), .message(let text): return text }
    }
}


var passed=0
func require(_ value: Bool, _ label: String) { precondition(value, label); passed += 1 }
func parse(_ lines: [String]) throws -> [DialogueSSEParser.Event] {
    var parser=DialogueSSEParser();var result:[DialogueSSEParser.Event]=[]
    for line in lines { if let event=try parser.consume(line) { result.append(event) } }
    if let event=parser.finish() { result.append(event) };return result
}
let token=try parse(["id: 1", "event: token", "data: \"光平方 🧊\\n你好\"", ""])
require(token.count==1, "token count")
require(token[0].id==1 && token[0].name=="token", "token identity")
require(try JSONDecoder().decode(String.self,from:Data(token[0].data.utf8))=="光平方 🧊\n你好", "UTF8 and escaped newline")
let multiple=try parse(["event: message", "data: first", "data: second", "", ":keepalive", "", "event: ping", "data: {}", ""])
require(multiple.count==2, "comments do not emit messages")
require(multiple[0].data=="first\nsecond", "multi-line data")
require(multiple[1].id==nil && multiple[1].name=="ping", "unnumbered ping")
let crlf=try parse(["id: 7\r", "event: done\r", "data: {\"sessionKey\":\"lux-example\"}\r", "\r"])
require(crlf.count==1 && crlf[0].id==7, "CRLF boundaries")
let final=try parse(["event: error", "data: \"连接失效\""])
require(final.count==1 && final[0].name=="error", "EOF dispatch")
let defaults=try parse(["data:no-space", ""])
require(defaults[0].name=="message" && defaults[0].data=="no-space", "default event and no space")
let question=try parse(["id: 5", "event: question", "data: {\"id\":\"harness_example\",\"questions\":[{\"questionId\":\"q1\",\"question\":\"选哪一个？\",\"options\":[{\"label\":\"由本人决定\"}]}]}", ""])
let value=try JSONSerialization.jsonObject(with:Data(question[0].data.utf8)) as? [String:Any]
require(value?["id"] as? String == "harness_example", "question JSON remains object")
var capped=DialogueSSEParser();var rejected=false
do { _=try capped.consume("data: "+String(repeating:"x",count:2_097_152)) } catch { rejected=true }
require(rejected, "unbounded event is rejected")
let several=try parse(["id: 1", "event: token", "data: \"A\"", "", "id: 2", "event: token", "data: \"B\"", "", "id: 3", "event: done", "data: {\"sessionKey\":null}", ""])
require(several.map(\.id)==[1,2,3], "sequential IDs are retained for Store deduplication")
print("Dialogue SSE parser: \(passed) protocol checks passed")
