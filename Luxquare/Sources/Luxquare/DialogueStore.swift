import Foundation
import SwiftUI
import CryptoKit

struct DialogueMessage: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var role: String
    var content: String
    var failure: String? = nil
}

struct DialogueQuestionItem: Codable, Identifiable, Equatable {
    struct Option: Codable, Equatable { var label: String; var description: String? }
    var questionId: String
    var header: String?
    var question: String
    var options: [Option]?
    var multiSelect: Bool?
    var id: String { questionId }
}

struct DialogueQuestion: Codable, Identifiable, Equatable {
    var id: String
    var questions: [DialogueQuestionItem]
    var expiresAtMs: Double?
}

struct DialoguePendingTurn: Codable, Equatable {
    var id: String
    var assistantMessageID: String
    var lastEventID: Int = 0
    var questions: [DialogueQuestion] = []
}

struct DialogueSession: Codable, Identifiable, Equatable {
    var id = "lux-" + UUID().uuidString.lowercased()
    var title = "新对话"
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [DialogueMessage] = []
    var pending: DialoguePendingTurn?
    var sessionKey: String?
}

/// Incremental SSE line parser. AsyncBytes.lines supplies correctly decoded UTF-8 lines.
/// JSON data may contain escaped newlines; several `data:` lines are joined per SSE.
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

@MainActor
final class DialogueStore: ObservableObject {
    @Published private(set) var sessions: [DialogueSession] = []
    @Published var currentSessionID: String?
    @Published private(set) var connected = false
    @Published private(set) var checking = false
    @Published private(set) var isBusy = false
    @Published private(set) var isStopping = false
    @Published private(set) var activity = ""
    @Published private(set) var notice = ""
    @Published private(set) var scrollRevision = 0
    @Published private(set) var isDemo = false

    private var origin: URL?
    private var identityID: String?
    private var client: WorkbenchHTTPClient?
    private var configured = false
    private var generation = UUID()
    private var streamTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var historyURL: URL?
    private var lastPersistedAt = Date.distantPast

    var current: DialogueSession? { sessions.first { $0.id == currentSessionID } }
    var messages: [DialogueMessage] { current?.messages ?? [] }
    var pendingQuestions: [DialogueQuestion] { current?.pending?.questions ?? [] }
    var canSend: Bool { (connected || isDemo) && !isBusy && current?.pending == nil }
    var hasPending: Bool { current?.pending != nil }

    func configure(origin: URL?, identityID: String?, client: WorkbenchHTTPClient) {
        if configured && self.origin == origin && self.identityID == identityID { return }
        persist()
        configured = true
        generation = UUID()
        streamTask?.cancel(); probeTask?.cancel()
        streamTask = nil; probeTask = nil
        self.origin = origin; self.identityID = identityID; self.client = client
        connected = false; checking = false; isBusy = false; isStopping = false
        activity = ""; notice = ""; sessions = []; currentSessionID = nil; historyURL = nil
        isDemo = origin == nil && ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if isDemo {
            var session = DialogueSession()
            session.title = "新的灵感"
            session.messages = [DialogueMessage(role: "assistant", content: "你好，我是你的创作助手。把想法写下来，我们一起把它变成下一步。")]
            sessions = [session]; currentSessionID = session.id; connected = true
            return
        }
        guard validOrigin(origin), let identityID, !identityID.isEmpty else {
            notice = "登录工作台后，连接团队创作工作台。"; return
        }
        prepareHistory(origin: origin!, identityID: identityID)
        if sessions.isEmpty { newSession() }
        else if let pending = sessions.first(where: { $0.pending != nil }) { currentSessionID = pending.id }
        else { currentSessionID = sessions.first?.id }
        probe()
    }

    func newSession() {
        guard !isBusy else { return }
        if let empty = sessions.first(where: { $0.messages.isEmpty && $0.pending == nil }) {
            currentSessionID = empty.id; notice = ""; activity = ""; return
        }
        let session = DialogueSession()
        sessions.insert(session, at: 0); currentSessionID = session.id
        notice = ""; activity = ""; persist(); scrollRevision += 1
    }

    func select(_ session: DialogueSession) {
        guard !isBusy else { return }
        currentSessionID = session.id; notice = ""; activity = ""
        if session.pending != nil { notice = "这轮对话等待核对，可以继续读取。" }
        scrollRevision += 1
    }

    func probe() {
        guard !isDemo, let client, validOrigin(origin), identityID != nil, !checking else { return }
        let expected = generation
        checking = true
        probeTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == expected { self.checking = false } }
            do {
                let (_, response) = try await client.response(for: self.request(path: "/api/status"))
                guard self.generation == expected else { return }
                self.connected = response.statusCode == 200
                self.notice = self.connected ? (self.hasPending ? "上次回复尚未核对，请继续读取。" : "") : self.loginMessage(response.statusCode)
            } catch {
                guard self.generation == expected, !Task.isCancelled else { return }
                self.connected = false; self.notice = "暂时无法连接，请检查网络后重试。"
            }
        }
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 50_000, canSend else { return }
        if current == nil { newSession() }
        guard let index = sessions.firstIndex(where: { $0.id == currentSessionID }) else { return }
        let assistant = DialogueMessage(role: "assistant", content: "")
        sessions[index].messages.append(DialogueMessage(role: "user", content: text))
        sessions[index].messages.append(assistant)
        if sessions[index].title == "新对话" { sessions[index].title = String(text.prefix(24)) }
        sessions[index].updatedAt = Date()
        let turn = DialoguePendingTurn(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), assistantMessageID: assistant.id)
        sessions[index].pending = turn
        notice = ""; activity = "正在连接…"; persist(); scrollRevision += 1
        let sessionID = sessions[index].id
        if isDemo {
            updateAssistant(sessionID, turnID: turn.id, text: "这是界面预览。正式对话会连接团队现有的创作工作台。", append: false)
            finish(sessionID, turnID: turn.id); return
        }
        guard let client else { return }
        var first: URLRequest
        do {
            first = request(path: "/api/chat/stream", method: "POST")
            first.httpBody = try JSONSerialization.data(withJSONObject: ["message": text, "sessionId": sessionID, "turnId": turn.id, "attachments": []])
        } catch { notice = "消息未能准备，请重试。"; finish(sessionID, turnID: turn.id); return }
        beginReading(sessionID: sessionID, turnID: turn.id, client: client, first: first)
    }

    func resume() {
        guard !isBusy, connected, let session = current, let turn = session.pending, let client else { return }
        notice = ""; activity = "正在核对上次回复…"
        beginReading(sessionID: session.id, turnID: turn.id, client: client, first: nil)
    }

    private func beginReading(sessionID: String, turnID: String, client: WorkbenchHTTPClient, first: URLRequest?) {
        let expected = generation
        isBusy = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == expected { self.isBusy = false; self.isStopping = false; self.persist() }
            }
            var next = first
            for attempt in 0..<4 {
                guard self.generation == expected, !Task.isCancelled, self.pending(sessionID, turnID) != nil else { return }
                do {
                    let cursor = self.pending(sessionID, turnID)?.lastEventID ?? 0
                    let req = next ?? self.request(path: "/api/chat/jobs/" + turnID + "/stream", query: [URLQueryItem(name: "after", value: String(cursor))])
                    let terminal = try await self.read(req, client: client, sessionID: sessionID, turnID: turnID, expected: expected)
                    if terminal { return }
                } catch let failure as DialogueFailure {
                    guard self.generation == expected, !Task.isCancelled else { return }
                    if case .http(let status, let message) = failure {
                        if status == 401 || status == 403 {
                            self.connected = false; self.notice = message; self.activity = ""; return
                        }
                        if status == 404 && next == nil {
                            await self.recoverSnapshot(sessionID: sessionID, turnID: turnID, expected: expected)
                            return
                        }
                        if next != nil && (400..<500).contains(status) {
                            self.recordFailure(sessionID, turnID: turnID, message: message)
                            self.notice = message; self.finish(sessionID, turnID: turnID); return
                        }
                    }
                } catch {
                    guard self.generation == expected, !Task.isCancelled else { return }
                }
                next = nil // A POST is never repeated: the backend might already be running.
                self.activity = "连接中断，正在继续读取…"
                if attempt < 3 { try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000) }
            }
            guard self.generation == expected, !Task.isCancelled else { return }
            await self.recoverSnapshot(sessionID: sessionID, turnID: turnID, expected: expected)
        }
    }

    private func read(_ request: URLRequest, client: WorkbenchHTTPClient, sessionID: String, turnID: String, expected: UUID) async throws -> Bool {
        let (bytes, response) = try await client.bytes(for: request)
        guard response.statusCode == 200 else {
            throw DialogueFailure.http(response.statusCode, loginMessage(response.statusCode))
        }
        guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
            throw DialogueFailure.message("回复连接格式未确认，请继续读取或到创作工作台核对。")
        }
        var parser = DialogueSSEParser()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard generation == expected else { throw CancellationError() }
            if let event = try parser.consume(line), apply(event, sessionID: sessionID, turnID: turnID) { return true }
        }
        if let event = parser.finish() { return apply(event, sessionID: sessionID, turnID: turnID) }
        return false
    }

    private func apply(_ event: DialogueSSEParser.Event, sessionID: String, turnID: String) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }), sessions[index].pending?.id == turnID else { return true }
        let cursor = sessions[index].pending?.lastEventID ?? 0
        if let id = event.id, id > 0 {
            guard id > cursor else { return false }
            sessions[index].pending?.lastEventID = id
        }
        let data = Data(event.data.utf8)
        let decodedString = try? JSONDecoder().decode(String.self, from: data)
        if ["token", "thinking", "activity", "heartbeat", "error"].contains(event.name), decodedString == nil {
            notice = "回复格式尚未确认，已有内容已保留。请继续读取最终结果。"
            activity = ""; persist(); return true
        }
        let string = decodedString ?? ""
        switch event.name {
        case "token":
            updateAssistant(sessionID, turnID: turnID, text: string, append: true)
            activity = "正在回复…"
        case "thinking": activity = "正在思考…"
        case "activity": activity = String(string.prefix(500))
        case "heartbeat", "ping": break
        case "question":
            if let question = try? JSONDecoder().decode(DialogueQuestion.self, from: data),
               !question.id.isEmpty, !question.questions.isEmpty,
               question.questions.count <= 8, question.questions.allSatisfy({ !$0.questionId.isEmpty && !$0.question.isEmpty }) {
                if !(sessions[index].pending?.questions.contains(where: { $0.id == question.id }) ?? false) {
                    sessions[index].pending?.questions.append(question)
                }
                activity = "等待你的选择"
            } else { notice = "有一项问题暂时无法显示，请到创作工作台继续。" }
        case "error":
            let failure = String(string.prefix(700))
            recordFailure(sessionID, turnID: turnID, message: failure)
            notice = failure; finish(sessionID, turnID: turnID); return true
        case "done":
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["sessionKey"] is String || object["sessionKey"] is NSNull else {
                notice = "完成状态尚未确认，请继续读取最终结果。"
                activity = ""; persist(); return true
            }
            sessions[index].sessionKey = object["sessionKey"] as? String
            finish(sessionID, turnID: turnID); return true
        default: break
        }
        if Date().timeIntervalSince(lastPersistedAt) > 0.75 { persist() }
        return false
    }

    private func recoverSnapshot(sessionID: String, turnID: String, expected: UUID) async {
        guard let client else { return }
        do {
            let (data, response) = try await client.response(for: request(path: "/api/chat/last/" + sessionID, query: [URLQueryItem(name: "turn_id", value: turnID)]))
            guard generation == expected else { return }
            if response.statusCode == 401 || response.statusCode == 403 {
                connected = false; notice = loginMessage(response.statusCode); activity = ""; return
            }
            if response.statusCode == 200, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               value["turn_id"] as? String == turnID, value["status"] as? String == "done" {
                if let text = value["text"] as? String { updateAssistant(sessionID, turnID: turnID, text: text, append: false) }
                if value["clean_end"] as? Bool == false {
                    notice = value["stop_reason"] as? String == "stopped" ? "本轮已停止。" : "本轮未正常完成，已保留当前回复。"
                    recordFailure(sessionID, turnID: turnID, message: notice)
                }
                finish(sessionID, turnID: turnID); return
            }
        } catch { if Task.isCancelled || generation != expected { return } }
        activity = ""
        notice = "本轮结果尚未确认，消息与已有回复已保留。可继续读取，或到创作工作台核对。"
        persist()
    }

    func stop() {
        guard !isDemo, !isStopping, let session = current, let turn = session.pending, let client else { return }
        isStopping = true
        let expected = generation
        Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == expected { self.isStopping = false } }
            do {
                var req = self.request(path: "/api/chat/stop", method: "POST")
                req.httpBody = try JSONSerialization.data(withJSONObject: ["sessionId": session.id])
                let (data, response) = try await client.response(for: req)
                guard self.generation == expected else { return }
                if response.statusCode == 200, let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], result["stopped"] as? Bool == true {
                    self.activity = "已请求停止，正在核对结果…"
                } else { self.notice = "停止结果尚未确认，请继续读取当前回复。" }
                if !self.isBusy, self.pending(session.id, turn.id) != nil { self.resume() }
            } catch {
                guard self.generation == expected else { return }
                self.notice = "停止结果尚未确认，请继续读取或到创作工作台核对。"
            }
        }
    }

    func answer(_ question: DialogueQuestion, answers: [String: [String]]) async -> String? {
        guard let session = current, let turn = session.pending, let client, connected,
              Set(answers.keys) == Set(question.questions.map(\.questionId)),
              answers.values.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) }) else {
            return "请完成每个问题后再提交。"
        }
        let expected = generation
        do {
            var req = request(path: "/api/chat/question/answer", method: "POST")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["sessionId": session.id, "questionId": question.id, "answers": answers])
            let (data, response) = try await client.response(for: req)
            guard generation == expected else { return "账号已切换，请重新核对。" }
            if response.statusCode == 200, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["ok"] as? Bool == true {
                if let index = sessions.firstIndex(where: { $0.id == session.id }), sessions[index].pending?.id == turn.id {
                    sessions[index].pending?.questions.removeAll { $0.id == question.id }
                }
                activity = "已提交你的选择，正在继续…"; persist(); return nil
            }
            return "选择尚未确认，可能已过期。可到创作工作台核对。"
        } catch { return "提交结果尚未确认，请到创作工作台核对后再操作。" }
    }

    private func pending(_ sessionID: String, _ turnID: String) -> DialoguePendingTurn? {
        guard let turn = sessions.first(where: { $0.id == sessionID })?.pending, turn.id == turnID else { return nil }
        return turn
    }

    private func recordFailure(_ sessionID: String, turnID: String, message: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }), let turn = sessions[index].pending, turn.id == turnID,
              let item = sessions[index].messages.firstIndex(where: { $0.id == turn.assistantMessageID }) else { return }
        sessions[index].messages[item].failure = message
    }

    private func updateAssistant(_ sessionID: String, turnID: String, text: String, append: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }), let turn = sessions[index].pending, turn.id == turnID,
              let message = sessions[index].messages.firstIndex(where: { $0.id == turn.assistantMessageID }) else { return }
        if append { sessions[index].messages[message].content += text }
        else { sessions[index].messages[message].content = text }
        sessions[index].updatedAt = Date(); scrollRevision += 1
    }

    private func finish(_ sessionID: String, turnID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }), sessions[index].pending?.id == turnID else { return }
        sessions[index].pending = nil; sessions[index].updatedAt = Date(); activity = ""; persist(); scrollRevision += 1
    }

    private func validOrigin(_ value: URL?) -> Bool {
        guard let value, let c = URLComponents(url: value, resolvingAgainstBaseURL: false) else { return false }
        return c.scheme == "https" && c.host != nil && c.user == nil && c.password == nil && (c.port == nil || c.port == 443)
            && (c.path.isEmpty || c.path == "/") && c.query == nil && c.fragment == nil
    }

    private func request(path: String, method: String = "GET", query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: origin!, resolvingAgainstBaseURL: false)!
        components.path = path; components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.httpMethod = method
        request.setValue(origin!.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func loginMessage(_ status: Int) -> String {
        switch status {
        case 401: return "请先连接创作工作台，再回到这里对话。"
        case 403: return "当前账号没有创作工作台权限，或会话已失效。"
        case 409: return "当前会话暂时不能接收消息，请等待上一轮结束或新建对话。"
        case 400, 422: return "这条消息未被接受，请检查内容后重试。"
        default: return "对话服务暂时不可用，请稍后继续读取。"
        }
    }

    private struct History: Codable { var schema = 1; var sessions: [DialogueSession] }

    private func prepareHistory(origin: URL, identityID: String) {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Dialogue", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var protected = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true; try protected.setResourceValues(values)
            let key = SHA256.hash(data: Data((origin.absoluteString + "\n" + identityID).utf8)).map { String(format: "%02x", $0) }.joined()
            let url = root.appendingPathComponent(key + ".json")
            historyURL = url
            if let data = try? Data(contentsOf: url), data.count <= 32 * 1024 * 1024,
               let value = try? JSONDecoder().decode(History.self, from: data), value.schema == 1 {
                sessions = value.sessions.sorted { $0.updatedAt > $1.updatedAt }
            }
        } catch { notice = "本机历史暂时无法读取，本轮内容请保持在当前页面。" }
    }

    private func persist() {
        guard let url = historyURL, !isDemo else { return }
        do {
            let retained = sessions.filter { $0.pending != nil }
                + Array(sessions.filter { $0.pending == nil }.sorted { $0.updatedAt > $1.updatedAt }.prefix(100))
            let data = try JSONEncoder().encode(History(sessions: retained))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastPersistedAt = Date()
        } catch { notice = "本机历史暂时无法保存，请保留当前页面并先复制重要内容。" }
    }
}
