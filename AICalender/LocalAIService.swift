import Foundation

class LocalAIService {
    // 修改API地址
    private let apiURL = "http://121.48.164.125/v1/chat-messages"
    // 添加认证token
    private let authToken = "Bearer app-yg1oJwj78IjMcUTDBKh2K9Yo"
    // 使用的模型名称，预留
    private let modelName: String
    
    // 系统提示词，与原AIService保持一致
    private let systemPrompt = """
     你是一个日程安排助手，根据用户的需求，给出日程安排。   
    你需要以 JSON 格式返回数据，支持以下操作：
    1. 添加日程：创建新的日程
    2. 修改日程：更新现有日程的信息
    3. 删除日程：删除指定的日程
    
    JSON 格式示例：
    1. 添加日程：
    {
        "operation": "add",
        "schedule": {
            "title": "项目评审",
            "startTime": "2024-04-02T14:30:00",
            "endTime": "2024-04-02T16:00:00"
        }
    }
    
    2. 修改日程：
    {
        "operation": "update",
        "oldSchedule": {
            "title": "项目评审",
            "startTime": "2024-04-02T14:30:00",
            "endTime": "2024-04-02T16:00:00"
        },
        "newSchedule": {
            "title": "项目评审会议",
            "startTime": "2024-04-02T15:00:00",
            "endTime": "2024-04-02T16:30:00"
        }
    }
    
    3. 删除日程：
    {
        "operation": "delete",
        "schedule": {
            "title": "项目评审",
            "startTime": "2024-04-02T14:30:00",
            "endTime": "2024-04-02T16:00:00"
        }
    } 
    
    注意事项：
    1. 所有时间都使用 ISO 8601 格式
    2. 标题不能为空
    3. 结束时间必须晚于开始时间
    4. 查询时返回当天所有日程
    5. 修改和删除时需要提供完整的日程信息以准确定位
    6. 日程安排不能与现有日程冲突
    7. 在安排新日程时，请考虑用户已有的日程安排，避免时间冲突
    8. 如果用户没有指定具体时间，请根据已有日程合理安排时间
    9. 如果用户要求的时间段已被占用，请建议其他合适的时间
    
    注意：如果识别到用户增删改日程，则只允许返回json字符串 不需要返回任何其他思考信息。其他问题则保持正常回答
    """
    
    // 存储对话历史
    private var chatHistory: [(role: String, content: String)] = []
    // 最大历史消息数量
    private let maxHistoryMessages = 10
    
    // 定义回调类型
    typealias CompletionHandler = (String?, Error?) -> Void
    typealias StreamHandler = (String) -> Void
    typealias ThinkingHandler = (String) -> Void
    typealias LoadingHandler = (Bool) -> Void
    
    // 初始化方法
    init(modelName: String) {
        self.modelName = modelName
    }
    
    // 清除对话历史
    func clearChatHistory() {
        chatHistory.removeAll()
    }
    
    // 添加获取上下文的方法
    private func getContextPrompt() -> String {
        // 获取当前日期前后30天的日程
        let calendar = Calendar.current
        let now = Date()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        let thirtyDaysLater = calendar.date(byAdding: .day, value: 30, to: now)!
        
        let schedules = ScheduleManager.shared.fetchSchedules(for: thirtyDaysAgo, to: thirtyDaysLater)
        
        if schedules.isEmpty {
            return "用户目前没有已安排的日程。"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        var context = "用户已有的日程安排：\n"
        for schedule in schedules {
            let startTime = dateFormatter.string(from: schedule.startTime)
            let endTime = dateFormatter.string(from: schedule.endTime)
            context += "- \(schedule.title): \(startTime) 到 \(endTime)\n"
        }
        
        return context
    }
    
    // 发送消息到AI并获取流式回复
    func sendMessageStream(prompt: String, 
                         onReceive: @escaping StreamHandler, 
                         onThinking: @escaping ThinkingHandler, 
                         onLoading: @escaping LoadingHandler,
                         onComplete: @escaping CompletionHandler) {
        print("开始流式请求，提示词: \(prompt)")
        
        // 添加用户消息到历史记录
        addMessageToHistory(role: "user", content: prompt)
        
        // 获取上下文信息
        let context = getContextPrompt()
        
        // 创建新的请求体格式，包含上下文
        let requestBody: [String: Any] = [
            "inputs": [:],
            "query": "\(context)\n\n用户需求：\(prompt)",
            "response_mode": "streaming",
            "conversation_id": "",
            "user": "abc-123"
        ]
        
        // 创建URL
        guard let url = URL(string: apiURL) else {
            onComplete(nil, NSError(domain: "LocalAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "无效的URL"]))
            return
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(authToken, forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            print("请求体已准备: \(String(data: request.httpBody!, encoding: .utf8) ?? "")")
        } catch {
            print("请求体序列化失败: \(error)")
            onComplete(nil, error)
            return
        }
        
        // 创建自定义的流式处理委托
        let streamDelegate = StreamDelegate(
            onReceive: onReceive,
            onThinking: onThinking,
            onLoading: onLoading,
            onComplete: { content, error in
                // 如果成功接收到完整回复，添加到历史记录
                if let content = content, error == nil {
                    self.addMessageToHistory(role: "assistant", content: content)
                }
                onComplete(content, error)
            }
        )
        
        // 创建会话并设置委托
        let session = URLSession(configuration: .default, delegate: streamDelegate, delegateQueue: .main)
        
        // 创建数据任务
        let task = session.dataTask(with: request)
        
        // 保存任务引用到委托中，以便可以在需要时取消
        streamDelegate.task = task
        
        // 开始任务
        task.resume()
        print("流式请求已发送")
    }
    
    // 添加消息到历史记录
    private func addMessageToHistory(role: String, content: String) {
        chatHistory.append((role: role, content: content))
        
        // 如果历史记录超过最大数量，移除最早的非系统消息
        if chatHistory.count > maxHistoryMessages {
            if let index = chatHistory.firstIndex(where: { $0.role != "system" }) {
                chatHistory.remove(at: index)
            }
        }
    }
    
    // StreamDelegate类实现
    private class StreamDelegate: NSObject, URLSessionDataDelegate {
        private let onReceive: (String) -> Void
        private let onThinking: (String) -> Void
        private let onComplete: (String?, Error?) -> Void
        private let onLoading: (Bool) -> Void
        private var fullResponse = ""
        private var tmpAnswer = ""  // 用于存储临时答案
        private var buffer = Data()
        private var messageId: String?
        private var conversationId: String?
        private var lastPingTime: Date?
        
        var task: URLSessionDataTask?
        
        init(onReceive: @escaping (String) -> Void, 
             onThinking: @escaping (String) -> Void, 
             onLoading: @escaping (Bool) -> Void,
             onComplete: @escaping (String?, Error?) -> Void) {
            self.onReceive = onReceive
            self.onThinking = onThinking
            self.onLoading = onLoading
            self.onComplete = onComplete
            super.init()
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            processBuffer()
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            DispatchQueue.main.async {
                self.onLoading(false)
                
                if let error = error {
                    self.onComplete(nil, error)
                    return
                }
                
                self.processBuffer(isComplete: true)
                self.onComplete(self.fullResponse, nil)
            }
        }
        
        private func processBuffer(isComplete: Bool = false) {
            guard let bufferString = String(data: buffer, encoding: .utf8) else {
                return
            }
            
            // 按照SSE格式分割数据流
            let chunks = bufferString.components(separatedBy: "\n\n")
            
            for chunk in chunks {
                guard !chunk.isEmpty else { continue }
                
                // 处理 ping 事件
                if chunk.trimmingCharacters(in: .whitespaces) == "event: ping" {
                    handlePingEvent()
                    continue
                }
                
                // 移除"data: "前缀
                guard chunk.hasPrefix("data: ") else { continue }
                let jsonString = String(chunk.dropFirst(6))
                
                do {
                    guard let data = jsonString.data(using: .utf8),
                          let json = try JSONSerialization.jsonObject(with: data, options: [.allowFragments]) as? [String: Any],
                          let event = json["event"] as? String else {
                        continue
                    }

                    // 处理不同类型的事件
                    switch event {
                    case "agent_message":
                        if let answer = json["answer"] as? String {
                            self.fullResponse += answer
                            DispatchQueue.main.async {
                                self.onReceive(answer)
                            }
                            
                            // 检查是否是合法的 JSON 字符串
                            if !answer.isEmpty,
                               let jsonData = answer.data(using: .utf8),
                               (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
                                tmpAnswer = answer
                            }
                        }
                    case "agent_thought":
                        // do nothing
                        continue
                    case "message_end":
                        self.messageId = json["message_id"] as? String
                        self.conversationId = json["conversation_id"] as? String
                        print("++++++++++11111json: \(tmpAnswer)")
                        
                        // 检查是否是合法的 JSON 字符串
                        if !tmpAnswer.isEmpty,
                           let jsonData = tmpAnswer.data(using: .utf8),
                           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            print("++++++++++json: \(jsonObject)")
                            self.handleScheduleJSON(jsonObject)
                        }
                        
                    case "error":
                        if let errorMessage = json["message"] as? String {
                            DispatchQueue.main.async {
                                let error = NSError(domain: "LocalAIService",
                                                  code: json["status"] as? Int ?? 500,
                                                  userInfo: [NSLocalizedDescriptionKey: errorMessage])
                                self.onComplete(nil, error)
                            }
                        }
                        
                    case "message_replace":
                        if let answer = json["answer"] as? String {
                            self.fullResponse = answer
                            DispatchQueue.main.async {
                                self.onReceive(answer)
                            }
                        }
                        
                    default:
                        break
                    }
                    
                } catch {
                    print("解析流式数据出错: \(error)")
                    print("原始数据: \(chunk)")
                }
            }
            
            if !isComplete {
                buffer = Data()
            }
        }
        
        private func handlePingEvent() {
            let currentTime = Date()
            lastPingTime = currentTime
            
            DispatchQueue.main.async {
                self.onLoading(true)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self else { return }
                    if let lastPing = self.lastPingTime,
                       currentTime == lastPing {
                        self.onLoading(false)
                    }
                }
            }
        }
        
        // 处理 JSON 数据并更新 CoreData
        private func handleScheduleJSON(_ json: [String: Any]) {
            print("++++++++++11111222222json operation: \(json["operation"])")
            
            // 支持 operation 和 action 两种字段名
            guard let operation = (json["operation"] as? String) ?? (json["action"] as? String) else {
                print("操作类型解析失败")
                return
            }
            
            // 创建日期格式化器
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            
            switch operation {
            case "add":
                print("开始处理添加日程")
                if let schedule = json["schedule"] as? [String: Any] {
                    print("找到 schedule 对象: \(schedule)")
                    if let title = schedule["title"] as? String,
                       let startTimeStr = schedule["startTime"] as? String,
                       let endTimeStr = schedule["endTime"] as? String {
                        print("找到所有必需字段")
                        print("title: \(title)")
                        print("startTimeStr: \(startTimeStr)")
                        print("endTimeStr: \(endTimeStr)")
                        
                        if let startTime = dateFormatter.date(from: startTimeStr),
                           let endTime = dateFormatter.date(from: endTimeStr) {
                            print("成功解析日期")
                            print("startTime: \(startTime)")
                            print("endTime: \(endTime)")
                            let newSchedule = Schedule(startTime: startTime, endTime: endTime, title: title)
                            ScheduleManager.shared.saveSchedule(newSchedule)
                            print("成功添加日程: \(title)")
                        } else {
                            print("日期解析失败")
                            print("尝试解析的 startTimeStr: \(startTimeStr)")
                            print("尝试解析的 endTimeStr: \(endTimeStr)")
                        }
                    } else {
                        print("缺少必需字段")
                    }
                } else {
                    print("schedule 对象解析失败")
                }
                
            case "update":
                if let oldSchedule = json["oldSchedule"] as? [String: Any],
                   let newSchedule = json["newSchedule"] as? [String: Any],
                   let oldTitle = oldSchedule["title"] as? String,
                   let oldStartTimeStr = oldSchedule["startTime"] as? String,
                   let oldEndTimeStr = oldSchedule["endTime"] as? String,
                   let newTitle = newSchedule["title"] as? String,
                   let newStartTimeStr = newSchedule["startTime"] as? String,
                   let newEndTimeStr = newSchedule["endTime"] as? String,
                   let oldStartTime = dateFormatter.date(from: oldStartTimeStr),
                   let oldEndTime = dateFormatter.date(from: oldEndTimeStr),
                   let newStartTime = dateFormatter.date(from: newStartTimeStr),
                   let newEndTime = dateFormatter.date(from: newEndTimeStr) {
                    
                    let oldSchedule = Schedule(startTime: oldStartTime, endTime: oldEndTime, title: oldTitle)
                    let updatedSchedule = Schedule(startTime: newStartTime, endTime: newEndTime, title: newTitle)
                    
                    // 先删除旧日程，再添加新日程
                    ScheduleManager.shared.deleteSchedule(oldSchedule)
                    ScheduleManager.shared.saveSchedule(updatedSchedule)
                    print("成功更新日程: \(oldTitle) -> \(newTitle)")
                }
                
            case "delete":
                if let schedule = json["schedule"] as? [String: Any],
                   let title = schedule["title"] as? String,
                   let startTimeStr = schedule["startTime"] as? String,
                   let endTimeStr = schedule["endTime"] as? String,
                   let startTime = dateFormatter.date(from: startTimeStr),
                   let endTime = dateFormatter.date(from: endTimeStr) {
                    
                    let scheduleToDelete = Schedule(startTime: startTime, endTime: endTime, title: title)
                    ScheduleManager.shared.deleteSchedule(scheduleToDelete)
                    print("成功删除日程: \(title)")
                }
                
            default:
                print("未知的操作类型: \(operation)")
            }
        }
    }
    
    // 发送请求的通用方法
    private func sendRequest(requestBody: [String: Any], isStreaming: Bool, completion: @escaping (Data?, Error?) -> Void) {
        guard let url = URL(string: apiURL) else {
            completion(nil, NSError(domain: "LocalAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "无效的URL"]))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            completion(nil, error)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            completion(data, nil)
        }
        
        task.resume()
    }
    
    // 添加这个辅助方法来构建 prompt
    private func buildPrompt(messages: [[String: String]]) -> String {
        return messages.map { message in
            switch message["role"] {
                case "system":
                    return "System: \(message["content"] ?? "")"
                case "assistant":
                    return "Assistant: \(message["content"] ?? "")"
                case "user":
                    return "Human: \(message["content"] ?? "")"
                default:
                    return message["content"] ?? ""
            }
        }.joined(separator: "\n")
    }
} 
