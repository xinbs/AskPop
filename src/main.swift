import Cocoa
import KeychainAccess
import SwiftyJSON
import WebKit

class EditableTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) {
                    return true
                }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                    return true
                }
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                    return true
                }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) {
                    return true
                }
            case "z":
                if event.modifierFlags.contains(.shift) {
                    if let undoManager = self.window?.undoManager {
                        undoManager.redo()
                        return true
                    }
                } else {
                    if let undoManager = self.window?.undoManager {
                        undoManager.undo()
                        return true
                    }
                }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "copyText", let text = message.body as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow?
    var webView: WKWebView?
    var inputField: NSTextField?
    var messages: [[String: String]] = []
    var currentResponse: String = ""
    
    // 配置参数
    var apiURL: String = "https://aihubmix.com/v1/chat/completions"
    var model: String = "gemini-2.0-flash-exp-search"
    var temperature: Double = 0.7
    var apiKey: String = ""
    
    // API 请求任务
    var currentTask: Task<Void, Never>?
    
    static func main() {
        print("程序启动...")
        
        // 检查命令行参数
        guard CommandLine.arguments.count >= 3 else {
            print("用法: AskPop <prompt> <text>")
            exit(1)
        }
        
        let app = NSApplication.shared
        let delegate = AppDelegate()
        
        // 从 PopClip 环境变量获取配置
        if let apiKey = ProcessInfo.processInfo.environment["POPCLIP_OPTION_APIKEY"] {
            print("从 PopClip 获取到 API Key")
            delegate.apiKey = apiKey
        }
        
        if let apiUrl = ProcessInfo.processInfo.environment["POPCLIP_OPTION_API_URL"] {
            delegate.apiURL = apiUrl
        }
        
        if let model = ProcessInfo.processInfo.environment["POPCLIP_OPTION_MODEL"] {
            delegate.model = model
        }
        
        if let tempStr = ProcessInfo.processInfo.environment["POPCLIP_OPTION_TEMPERATURE"],
           let temp = Double(tempStr) {
            delegate.temperature = temp
        }
        
        // 验证必要的配置
        if delegate.apiKey.isEmpty {
            print("错误：未获取到 API Key")
            exit(1)
        }
        
        app.delegate = delegate
        
        // 确保应用程序作为前台应用程序运行
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("应用程序已启动...")
        
        // 从命令行参数获取提示词和文本
        let prompt = CommandLine.arguments[1]
        let text = CommandLine.arguments[2]
        print("接收到的提示词: \(prompt)")
        print("接收到的文本: \(text)")
        
        if !text.isEmpty {
            // 只显示用户的输入文本，不显示提示词
            messages.append(["role": "user", "content": text])
            createWindow()
            // 在 API 调用时组合提示词和文本
            callAPI(withPrompt: prompt, text: text)
        } else {
            print("错误：没有接收到文本")
            NSApp.terminate(nil)
        }
    }
    
    func createWindow() {
        print("创建窗口...")
        
        // 创建面板
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        //panel.title = "AI 助手"
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        // 设置圆角
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true
        
        // 创建标题栏视觉效果
        let titlebarVisualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: panel.contentView!.frame.height - 30, width: panel.contentView!.frame.width, height: 30))
        titlebarVisualEffect.material = .windowBackground
        titlebarVisualEffect.blendingMode = .behindWindow
        titlebarVisualEffect.state = .active
        titlebarVisualEffect.autoresizingMask = [.width, .minYMargin]
        titlebarVisualEffect.wantsLayer = true
        titlebarVisualEffect.layer?.backgroundColor = NSColor(white: 0.98, alpha: 0.8).cgColor
        panel.contentView?.addSubview(titlebarVisualEffect)
        
        // 创建标题标签
        let titleLabel = NSTextField(frame: NSRect(x: 12, y: 0, width: 200, height: 30))
        
        // 根据 Action ID 设置不同的标题
        let titleText: String
        if let actionId = ProcessInfo.processInfo.environment["POPCLIP_ACTION_IDENTIFIER"] {
            switch actionId {
            case "translate_action":
                titleText = "AI助手 - 翻译"
            case "qa_action":
                titleText = "AI助手 - 问答"
            default:
                titleText = "AI助手"
            }
        } else {
            titleText = "AI助手"
        }
        titleLabel.stringValue = titleText
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.cell?.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.isScrollable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titlebarVisualEffect.addSubview(titleLabel)
        
        // 添加约束使标题标签垂直居中
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: titlebarVisualEffect.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titlebarVisualEffect.leadingAnchor, constant: 8),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
        ])
        
        // 在标题栏创建按钮容器，靠近右边
        let titlebarButtonContainer = NSStackView(frame: NSRect(x: titlebarVisualEffect.frame.width - 63, y: 2, width: 65, height: 26))
        titlebarButtonContainer.orientation = .horizontal
        titlebarButtonContainer.spacing = -4
        titlebarButtonContainer.distribution = .fillEqually
        titlebarButtonContainer.alignment = .centerY
        titlebarButtonContainer.autoresizingMask = [.minXMargin]
        titlebarVisualEffect.addSubview(titlebarButtonContainer)
        
        // 创建复制按钮
        let copyButton = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyText)
        copyButton.title = "⧉"
        copyButton.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        copyButton.contentTintColor = NSColor.secondaryLabelColor
        copyButton.toolTip = "复制对话内容"
        
        // 创建关闭按钮
        let closeButton = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.title = "⊗"
        closeButton.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.toolTip = "关闭窗口"
        
        // 添加按钮到标题栏容器（从右到左的顺序）
        titlebarButtonContainer.addView(copyButton, in: .center)
        titlebarButtonContainer.addView(closeButton, in: .center)
        
        // 创建主内容区域的视觉效果视图
        let contentVisualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panel.contentView!.frame.width, height: panel.contentView!.frame.height - 30))
        contentVisualEffect.material = .windowBackground
        contentVisualEffect.blendingMode = .behindWindow
        contentVisualEffect.state = .active
        contentVisualEffect.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(contentVisualEffect)
        
        // 创建主容器视图
        let containerView = NSView(frame: contentVisualEffect.bounds)
        containerView.autoresizingMask = [.width, .height]
        contentVisualEffect.addSubview(containerView)
        
        // 创建 WebView
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        config.userContentController = userContentController
        
        let scriptMessageHandler = ScriptMessageHandler()
        userContentController.add(scriptMessageHandler, name: "copyText")
        
        let webView = WKWebView(frame: NSRect(x: 0, y: 100, width: containerView.frame.width, height: containerView.frame.height - 100), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        containerView.addSubview(webView)
        self.webView = webView
        
        // 加载初始 HTML
        let htmlTemplate = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/python.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/swift.min.js"></script>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/javascript.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    line-height: 1.5;
                    padding: 16px;
                    margin: 0;
                    background: transparent;
                }
                .message {
                    margin-bottom: 24px;
                }
                .message-header {
                    margin-bottom: 8px;
                    font-size: 13px;
                }
                .user-name {
                    color: #0066cc;
                    font-weight: 600;
                }
                .ai-name {
                    color: #28a745;
                    font-weight: 600;
                }
                .timestamp {
                    color: #666;
                    font-size: 12px;
                    margin-left: 8px;
                }
                .message-content {
                    font-size: 14px;
                }
                .code-block-wrapper {
                    position: relative;
                    margin: 8px 0;
                }
                pre {
                    background-color: #282c34;
                    border-radius: 6px;
                    padding: 16px;
                    overflow-x: auto;
                    margin: 0;
                }
                pre code {
                    font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace;
                    font-size: 12px;
                    line-height: 1.4;
                    padding: 0;
                    background: none;
                    color: #abb2bf;
                }
                p code {
                    font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace;
                    font-size: 12px;
                    background-color: #282c34;
                    padding: 2px 4px;
                    border-radius: 3px;
                    color: #abb2bf;
                }
                .copy-button {
                    position: absolute;
                    top: 8px;
                    right: 8px;
                    padding: 4px 8px;
                    background-color: rgba(255, 255, 255, 0.1);
                    border: none;
                    border-radius: 4px;
                    color: #abb2bf;
                    font-size: 12px;
                    cursor: pointer;
                    opacity: 0;
                    transition: opacity 0.2s;
                }
                .code-block-wrapper:hover .copy-button {
                    opacity: 1;
                }
                .copy-button:hover {
                    background-color: rgba(255, 255, 255, 0.2);
                }
                .copy-button.copied {
                    background-color: #28a745;
                    color: white;
                }
            </style>
        </head>
        <body>
            <div id="messages"></div>
            <script>
                marked.setOptions({
                    highlight: function(code, lang) {
                        if (lang && hljs.getLanguage(lang)) {
                            try {
                                return hljs.highlight(code, { language: lang }).value;
                            } catch (err) {
                                console.error('高亮错误:', err);
                            }
                        }
                        return code;
                    },
                    breaks: true,
                    gfm: true,
                    pedantic: false,
                    smartLists: true
                });
                
                function copyCode(button, code) {
                    window.webkit.messageHandlers.copyText.postMessage(code);
                    button.textContent = '已复制';
                    button.classList.add('copied');
                    setTimeout(() => {
                        button.textContent = '复制';
                        button.classList.remove('copied');
                    }, 2000);
                }
                
                function wrapCodeBlock(codeBlock) {
                    const wrapper = document.createElement('div');
                    wrapper.className = 'code-block-wrapper';
                    
                    const parent = codeBlock.parentNode;
                    parent.insertBefore(wrapper, codeBlock);
                    wrapper.appendChild(codeBlock);
                    
                    const copyButton = document.createElement('button');
                    copyButton.className = 'copy-button';
                    copyButton.textContent = '复制';
                    copyButton.onclick = () => copyCode(copyButton, codeBlock.textContent);
                    wrapper.appendChild(copyButton);
                }
                
                function appendMessage(role, content, isUpdate = false, modelName = 'AI') {
                    const messagesDiv = document.getElementById('messages');
                    const messageDiv = document.createElement('div');
                    messageDiv.className = 'message';
                    
                    const header = document.createElement('div');
                    header.className = 'message-header';
                    const name = role === 'user' ? '你' : modelName;
                    const nameClass = role === 'user' ? 'user-name' : 'ai-name';
                    header.innerHTML = `<span class="${nameClass}">${name}</span><span class="timestamp">${new Date().toLocaleTimeString()}</span>`;
                    messageDiv.appendChild(header);
                    
                    const contentDiv = document.createElement('div');
                    contentDiv.className = 'message-content';
                    messageDiv.appendChild(contentDiv);
                    
                    // 使用 marked 解析 Markdown
                    contentDiv.innerHTML = marked.parse(content);
                    
                    // 高亮所有代码块并添加复制按钮
                    contentDiv.querySelectorAll('pre code').forEach((block) => {
                        hljs.highlightElement(block);
                        wrapCodeBlock(block.parentNode);
                    });
                    
                    if (isUpdate) {
                        // 如果是更新，替换最后一条消息
                        const lastMessage = messagesDiv.lastElementChild;
                        if (lastMessage && lastMessage.querySelector('.ai-name')) {
                            messagesDiv.replaceChild(messageDiv, lastMessage);
                        } else {
                            messagesDiv.appendChild(messageDiv);
                        }
                    } else {
                        // 如果是新消息，直接添加
                        messagesDiv.appendChild(messageDiv);
                    }
                    
                    window.scrollTo(0, document.body.scrollHeight);
                }
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(htmlTemplate, baseURL: nil)
        
        // 创建输入框容器（带背景）
        let inputContainer = NSView(frame: NSRect(x: 16, y: 50, width: containerView.frame.width - 32, height: 42))
        inputContainer.wantsLayer = true
        inputContainer.layer?.backgroundColor = NSColor(white: 0.95, alpha: 0.3).cgColor
        inputContainer.layer?.cornerRadius = 8
        inputContainer.autoresizingMask = [.width]
        containerView.addSubview(inputContainer)
        
        // 创建输入框
        let inputField = EditableTextField(frame: NSRect(x: 12, y: 0, width: inputContainer.frame.width - 84, height: 42))
        inputField.placeholderString = "输入消息..."
        inputField.target = self
        inputField.action = #selector(sendMessage)
        inputField.autoresizingMask = [.width, .height]
        inputField.focusRingType = .none
        inputField.wantsLayer = true
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.font = NSFont.systemFont(ofSize: 14)
        inputField.isEditable = true
        inputField.isSelectable = true
        inputContainer.addSubview(inputField)
        self.inputField = inputField
        
        // 创建发送按钮
        let sendButton = NSButton(frame: NSRect(x: inputContainer.frame.width - 70, y: 7, width: 60, height: 28))
        sendButton.title = "发送"
        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(sendMessage)
        sendButton.autoresizingMask = [.minXMargin]
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius = 6
        sendButton.contentTintColor = NSColor.secondaryLabelColor
        inputContainer.addSubview(sendButton)
        
        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func copyText() {
        webView?.evaluateJavaScript("document.body.innerText") { result, error in
            if let text = result as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
    
    @objc func closeWindow() {
        currentTask?.cancel()
        NSApp.terminate(nil)
    }
    
    @objc func sendMessage() {
        guard let text = inputField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        
        messages.append(["role": "user", "content": text])
        inputField?.stringValue = ""
        
        // 立即显示用户消息
        if let webView = self.webView {
            let script = """
                appendMessage('user', `\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`, false, '\(model)');
            """
            webView.evaluateJavaScript(script)
        }
        
        // 使用空提示词调用 API（对话模式）
        callAPI(withPrompt: "", text: text)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView 加载完成")
        // WebView 加载完成后，显示所有消息
        for message in messages {
            print("显示消息：\(message)")
            let script = """
                appendMessage('\(message["role"] ?? "")', `\(message["content"]?.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`") ?? "")`, false, '\(model)');
            """
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("显示消息时出错：\(error)")
                }
            }
        }
    }
    
    func updateLastMessage() {
        print("更新最后一条消息...")
        guard let webView = self.webView,
              let lastMessage = messages.last else {
            print("无法更新消息：webView 或 lastMessage 为空")
            return
        }
        
        let script = """
            appendMessage('\(lastMessage["role"] ?? "")', `\(lastMessage["content"]?.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`") ?? "")`, true, '\(model)');
        """
        print("执行 JavaScript: \(script)")
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("更新消息时出错：\(error)")
            }
        }
    }
    
    func callAPI(withPrompt prompt: String, text: String) {
        // 调用 AI API
        currentTask = Task {
            do {
                print("开始调用 API...")
                let _ = try await callAIAPI(withPrompt: prompt, text: text)
                if !Task.isCancelled {
                    print("API 调用成功")
                }
            } catch {
                if !Task.isCancelled {
                    print("API 调用失败: \(error)")
                    DispatchQueue.main.async { [weak self] in
                        guard let webView = self?.webView else { return }
                        let errorScript = """
                            const errorDiv = document.createElement('div');
                            errorDiv.className = 'message';
                            errorDiv.innerHTML = '<div class="message-header"><span class="ai-name">错误</span></div><div class="message-content" style="color: red;">\(error.localizedDescription)</div>';
                            document.getElementById('messages').appendChild(errorDiv);
                        """
                        webView.evaluateJavaScript(errorScript)
                    }
                }
            }
        }
    }
    
    func callAIAPI(withPrompt prompt: String, text: String) async throws -> String {
        print("准备调用 API: \(apiURL)")
        
        // 检查 API key
        guard !apiKey.isEmpty else {
            print("未找到 API 密钥")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Config.plist 中未设置 API 密钥"])
        }
        
        let url = URL(string: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 组合提示词和文本
        let combinedContent = prompt + text
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": combinedContent]],
            "temperature": temperature,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("发送 API 请求...")
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API 请求失败: HTTP \(httpResponse.statusCode)"])
        }
        
        actor ResponseAggregator {
            private(set) var responseText: String = ""
            private var buffer: String = ""
            private var isFirstChunk = true
            
            func append(_ content: String) -> (currentText: String, shouldUpdate: Bool, isFirst: Bool) {
                buffer += content
                responseText += content
                
                // 每累积一定数量的字符就更新一次显示
                if buffer.count >= 2 || isFirstChunk {
                    let shouldUpdate = true
                    let isFirst = isFirstChunk
                    isFirstChunk = false
                    let currentText = responseText
                    buffer = ""
                    return (currentText, shouldUpdate, isFirst)
                }
                
                return (responseText, false, false)
            }
            
            func getCurrentText() -> String {
                return responseText
            }
        }
        
        let aggregator = ResponseAggregator()
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            
            if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                break
            }
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSON(data: jsonData),
                  let content = json["choices"][0]["delta"]["content"].string else {
                continue
            }
            
            let (currentText, shouldUpdate, isFirst) = await aggregator.append(content)
            
            if shouldUpdate {
                if isFirst {
                    await MainActor.run { [self] in
                        self.messages.append(["role": "assistant", "content": currentText])
                        self.updateLastMessage()
                    }
                } else {
                    await MainActor.run { [self] in
                        self.messages[self.messages.count - 1]["content"] = currentText
                        self.updateLastMessage()
                    }
                }
            }
        }
        
        // 获取最终的响应文本
        let finalText = await aggregator.getCurrentText()
        await MainActor.run { [self] in
            self.messages[self.messages.count - 1]["content"] = finalText
            self.updateLastMessage()
        }
        
        return finalText
    }
} 