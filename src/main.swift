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
    var clearButton: NSButton?
    var titlebarButtonContainer: NSStackView?
    var messages: [[String: String]] = []
    var systemPrompt: String = ""  // 存储系统提示词
    var currentResponse: String = ""
    
    // 配置参数
    var apiURL: String = "https://aihubmix.com/v1/chat/completions"
    var model: String = "gemini-2.0-flash-exp-search"
    var temperature: Double = 0.7
    var apiKey: String = ""
    
    // API 请求任务
    var currentTask: Task<Void, Never>?
    
    // 添加 NSTrackingArea 代理
    class HoverableButton: NSButton {
        var hoverHandler: ((Bool) -> Void)?
        var tooltipHandler: ((Bool) -> Void)?
        private var tooltipPanel: NSPanel?
        private var feedbackPanel: NSPanel?
        private var hoverTimer: Timer?
        
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach { removeTrackingArea($0) }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
        }
        
        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            hoverHandler?(true)
            hoverTimer?.invalidate()
            
            if feedbackPanel == nil {
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    if let tooltip = self?.toolTip {
                        self?.showTooltip(tooltip)
                    }
                }
            }
        }
        
        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            hoverHandler?(false)
            hoverTimer?.invalidate()
            hoverTimer = nil
            hideTooltip()
        }
        
        private func showTooltip(_ text: String) {
            let feedback = NSTextField(frame: .zero)
            feedback.stringValue = text
            feedback.isEditable = false
            feedback.isBordered = false
            feedback.backgroundColor = NSColor.clear
            feedback.drawsBackground = false
            feedback.textColor = NSColor.secondaryLabelColor
            feedback.alignment = .center
            feedback.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            
            // 根据文字内容调整宽度
            let size = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)])
            let padding: CGFloat = 16
            let width = size.width + padding
            let height: CGFloat = 22
            
            // 获取按钮在屏幕中的位置
            let buttonFrame = self.window?.convertToScreen(self.convert(self.bounds, to: nil)) ?? .zero
            
            // 调整位置，使其在按钮正下方居中
            let panelFrame = NSRect(
                x: buttonFrame.origin.x + (buttonFrame.width - width) / 2,
                y: buttonFrame.origin.y - height - 4,
                width: width,
                height: height
            )
            
            let panel = NSPanel(
                contentRect: panelFrame,
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isMovable = false
            
            feedback.frame = NSRect(x: 0, y: 0, width: width, height: height)
            panel.contentView?.addSubview(feedback)
            
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.orderFront(nil)
            
            // 保存面板引用以便后续关闭
            tooltipPanel = panel
        }
        
        private func hideTooltip() {
            tooltipPanel?.close()
            tooltipPanel = nil
        }
        
        func showFeedback(_ text: String) {
            // 隐藏悬停提示
            hideTooltip()
            
            // 关闭现有的反馈面板
            feedbackPanel?.close()
            feedbackPanel = nil
            
            let feedback = NSTextField(frame: .zero)
            feedback.stringValue = text
            feedback.isEditable = false
            feedback.isBordered = false
            feedback.backgroundColor = .clear
            feedback.drawsBackground = false
            feedback.textColor = NSColor.secondaryLabelColor
            feedback.alignment = .center
            feedback.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            
            // 根据文字内容调整宽度
            let size = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)])
            let padding: CGFloat = 16
            let width = size.width + padding
            let height: CGFloat = 22
            
            // 设置反馈框的大小
            feedback.frame = NSRect(x: 0, y: 0, width: width, height: height)
            
            // 获取按钮在屏幕中的位置
            let buttonFrame = self.window?.convertToScreen(self.convert(self.bounds, to: nil)) ?? .zero
            
            // 调整位置，使其在按钮正下方居中
            let panelFrame = NSRect(
                x: buttonFrame.origin.x + (buttonFrame.width - width) / 2,
                y: buttonFrame.origin.y - height - 4,
                width: width,
                height: height
            )
            
            // 创建临时窗口显示反馈
            let panel = NSPanel(
                contentRect: panelFrame,
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            // 设置面板样式
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isMovable = false
            
            // 使用自动布局确保文本框在面板中完全居中
            feedback.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView?.addSubview(feedback)
            
            if let contentView = panel.contentView {
                NSLayoutConstraint.activate([
                    feedback.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                    feedback.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                    feedback.widthAnchor.constraint(equalToConstant: width),
                    feedback.heightAnchor.constraint(equalToConstant: height)
                ])
            }
            
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.orderFront(nil)
            
            // 保存反馈面板引用
            feedbackPanel = panel
            
            // 取消之前的延迟关闭任务
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            
            // 1.5秒后关闭
            perform(#selector(hideFeedback), with: nil, afterDelay: 1.5)
        }
        
        @objc private func hideFeedback() {
            feedbackPanel?.close()
            feedbackPanel = nil
        }
        
        deinit {
            hoverTimer?.invalidate()
            hideTooltip()
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            feedbackPanel?.close()
        }
    }
    
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
        systemPrompt = prompt  // 保存系统提示词
        print("接收到的提示词: \(prompt)")
        print("接收到的文本: \(text)")
        
        if !text.isEmpty {
            // 初始化消息列表，添加系统提示词
            messages = [["role": "system", "content": prompt]]
            messages.append(["role": "user", "content": text])
            createWindow()
            // 直接使用文本调用 API
            callAPI(withPrompt: "", text: text)
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
        panel.level = .normal  // 设置初始层级为普通窗口
        panel.collectionBehavior = []  // 使用空集合作为默认行为
        panel.hidesOnDeactivate = true  // 默认情况下失去焦点时隐藏
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
        let titlebarButtonContainer = NSStackView(frame: NSRect(x: titlebarVisualEffect.frame.width - 127, y: 2, width: 129, height: 26))
        titlebarButtonContainer.orientation = .horizontal
        titlebarButtonContainer.spacing = -2
        titlebarButtonContainer.distribution = .fillEqually
        titlebarButtonContainer.alignment = .centerY
        titlebarButtonContainer.autoresizingMask = [.minXMargin]
        titlebarVisualEffect.addSubview(titlebarButtonContainer)
        self.titlebarButtonContainer = titlebarButtonContainer
        
        // 创建置顶按钮
        let pinButton = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        let pinImage = NSImage(systemSymbolName: "pin", accessibilityDescription: "置顶")
        pinButton.image = pinImage
        pinButton.imagePosition = .imageOnly
        pinButton.contentTintColor = NSColor.secondaryLabelColor
        pinButton.hoverHandler = { [weak pinButton] isHovered in
            if let window = self.window {
                if window.level == .floating {
                    pinButton?.contentTintColor = isHovered ? NSColor.systemBlue.withAlphaComponent(0.8) : NSColor.systemBlue
                } else {
                    pinButton?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
                }
            }
        }
        pinButton.toolTip = "置顶窗口"
        titlebarButtonContainer.addArrangedSubview(pinButton)
        
        // 创建清除按钮
        let clearButton = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        clearButton.bezelStyle = .inline
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearButtonClicked)
        let clearImage = NSImage(systemSymbolName: "trash", accessibilityDescription: "清除")
        clearButton.image = clearImage
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = NSColor.secondaryLabelColor
        clearButton.hoverHandler = { [weak clearButton] isHovered in
            clearButton?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
        }
        clearButton.toolTip = "清除对话"
        titlebarButtonContainer.addArrangedSubview(clearButton)
        self.clearButton = clearButton
        
        // 创建复制按钮
        let copyButton = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyText)
        let copyImage = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")
        copyButton.image = copyImage
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = NSColor.secondaryLabelColor
        copyButton.hoverHandler = { [weak copyButton] isHovered in
            copyButton?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
        }
        copyButton.toolTip = "复制对话"
        titlebarButtonContainer.addArrangedSubview(copyButton)
        
        // 创建关闭按钮
        let closeButton = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 26))
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        let closeImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.image = closeImage
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.hoverHandler = { [weak closeButton] isHovered in
            closeButton?.contentTintColor = isHovered ? NSColor.systemRed : NSColor.secondaryLabelColor
        }
        closeButton.toolTip = "关闭窗口"
        titlebarButtonContainer.addArrangedSubview(closeButton)
        
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
                    padding: 12px 24px 12px 12px;  /* 右侧增加更多内边距 */
                    margin: 0;
                    background: transparent;
                }
                .message {
                    margin-bottom: 12px;
                }
                .message-header {
                    margin-bottom: 4px;
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
                    border-radius: 6px;
                    background-color: #282c34;
                    display: block;  /* 确保容器正确显示 */
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
                    top: 4px;
                    right: 4px;
                    padding: 4px 8px;
                    background-color: rgba(255, 255, 255, 0.15);
                    border: none;
                    border-radius: 4px;
                    color: #abb2bf;
                    font-size: 12px;
                    cursor: pointer;
                    opacity: 0.8;  /* 默认显示，但稍微透明 */
                    transition: opacity 0.2s;
                    z-index: 100;
                }
                .message pre:hover .copy-button,
                .code-block-wrapper:hover .copy-button,
                .copy-button:hover {
                    opacity: 1;
                }
                .copy-button:hover {
                    background-color: rgba(255, 255, 255, 0.2);
                }
                .copy-button.copied {
                    background-color: #28a745;
                    color: white;
                    opacity: 1;
                }
                .conversation-list {
                    display: flex;
                    flex-direction: column;
                    gap: 4px;
                }
                
                .message {
                    padding: 8px 12px;  /* 消息内部的内边距 */
                    border-radius: 8px;
                    margin-bottom: 4px;
                }
                
                .message-header {
                    font-size: 12px;
                    color: var(--header-color);
                    margin-bottom: 4px;
                }
                
                /* 用户消息样式 */
                .message[data-role="user"] {
                    background-color: rgba(0, 102, 204, 0.1);
                    align-self: flex-start;
                    width: calc(100% - 12px);  /* 减去右侧空间 */
                }
                
                /* AI 消息样式 */
                .message[data-role="assistant"] {
                    background-color: rgba(40, 167, 69, 0.1);
                    align-self: flex-start;
                    width: calc(100% - 12px);  /* 减去右侧空间 */
                }
                
                /* 统一消息样式 */
                .message {
                    margin-left: 0;  /* 确保左对齐 */
                    margin-right: auto;  /* 允许右边有空间 */
                    padding: 8px 12px;  /* 消息内部的内边距 */
                }
                
                /* 确保代码块背景不受消息背景影响 */
                .message pre {
                    background-color: #282c34 !important;
                    margin: 8px 0;
                    position: relative;
                    border-radius: 6px;
                    padding: 12px;
                    width: calc(100% - 24px);
                    overflow-x: auto;
                    overflow-y: hidden;
                }
                
                /* 隐藏 WebKit 滚动条 */
                .message pre::-webkit-scrollbar {
                    display: none;
                }
                
                /* 鼠标悬停时显示滚动条 */
                .message pre:hover {
                    overflow-x: auto;
                    scrollbar-width: thin;
                    -ms-overflow-style: auto;
                }
                
                .message pre:hover::-webkit-scrollbar {
                    display: block;
                    height: 6px;
                }
                
                .message pre::-webkit-scrollbar-track {
                    background: transparent;
                }
                
                .message pre::-webkit-scrollbar-thumb {
                    background: rgba(255, 255, 255, 0.2);
                    border-radius: 3px;
                }
                
                .message pre::-webkit-scrollbar-thumb:hover {
                    background: rgba(255, 255, 255, 0.3);
                }
                
                /* 调整复制按钮样式 */
                .copy-button {
                    position: absolute;
                    top: 4px;
                    right: 4px;
                    padding: 4px 8px;
                    background-color: rgba(255, 255, 255, 0.15);
                    border: none;
                    border-radius: 4px;
                    color: #abb2bf;
                    font-size: 12px;
                    cursor: pointer;
                    opacity: 0.8;  /* 默认显示，但稍微透明 */
                    transition: opacity 0.2s;
                    z-index: 100;
                }
                
                /* 调整复制按钮悬停状态 */
                .code-block-wrapper:hover .copy-button,
                .copy-button:hover {
                    opacity: 1;
                    background-color: rgba(255, 255, 255, 0.25);
                }
                
                .copy-button.copied {
                    background-color: #28a745;
                    color: white;
                    opacity: 1;
                }
            </style>
        </head>
        <body>
            <div id="messages" class="conversation-list"></div>
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
                
                function appendMessage(role, content, replace = false, model = '') {
                    const messagesDiv = document.getElementById('messages');
                    if (replace) {
                        const lastMessage = messagesDiv.lastElementChild;
                        if (lastMessage) {
                            lastMessage.querySelector('.message-content').innerHTML = marked.parse(content);
                            // 为替换的内容也添加代码块复制按钮
                            lastMessage.querySelectorAll('pre code').forEach(block => {
                                const preElement = block.parentElement;
                                if (preElement && !preElement.parentElement.classList.contains('code-block-wrapper')) {
                                    wrapCodeBlock(preElement);
                                }
                            });
                            return;
                        }
                    }
                    
                    const messageDiv = document.createElement('div');
                    messageDiv.className = 'message';
                    messageDiv.setAttribute('data-role', role);
                    
                    const headerDiv = document.createElement('div');
                    headerDiv.className = 'message-header';
                    
                    const nameSpan = document.createElement('span');
                    nameSpan.className = role === 'user' ? 'user-name' : 'ai-name';
                    nameSpan.textContent = role === 'user' ? '你' : (model || 'AI助手');
                    
                    const timeSpan = document.createElement('span');
                    timeSpan.className = 'timestamp';
                    timeSpan.textContent = new Date().toLocaleTimeString();
                    
                    headerDiv.appendChild(nameSpan);
                    headerDiv.appendChild(timeSpan);
                    
                    const contentDiv = document.createElement('div');
                    contentDiv.className = 'message-content';
                    contentDiv.innerHTML = marked.parse(content);
                    
                    messageDiv.appendChild(headerDiv);
                    messageDiv.appendChild(contentDiv);
                    messagesDiv.appendChild(messageDiv);
                    
                    // 添加代码块复制按钮
                    messageDiv.querySelectorAll('pre code').forEach(block => {
                        const preElement = block.parentElement;
                        if (preElement && !preElement.parentElement.classList.contains('code-block-wrapper')) {
                            wrapCodeBlock(preElement);
                        }
                    });
                    
                    // 滚动到底部
                    messagesDiv.scrollTop = messagesDiv.scrollHeight;
                }
                
                function wrapCodeBlock(codeBlock) {
                    // 如果已经被包装过，就不再重复包装
                    if (codeBlock.parentElement.classList.contains('code-block-wrapper')) {
                        return;
                    }
                    
                    const wrapper = document.createElement('div');
                    wrapper.className = 'code-block-wrapper';
                    
                    // 获取代码块的父元素
                    const parent = codeBlock.parentElement;
                    
                    // 在代码块外面包一层 wrapper
                    parent.insertBefore(wrapper, codeBlock);
                    wrapper.appendChild(codeBlock);
                    
                    // 创建并添加复制按钮
                    const copyButton = document.createElement('button');
                    copyButton.className = 'copy-button';
                    copyButton.textContent = '复制';
                    copyButton.onclick = () => copyCode(copyButton, codeBlock.textContent);
                    wrapper.appendChild(copyButton);
                    
                    // 确保代码高亮
                    hljs.highlightElement(codeBlock.querySelector('code') || codeBlock);
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
        
        // 创建发送按钮（使用图标）
        let sendButton = HoverableButton(frame: NSRect(x: inputContainer.frame.width - 42, y: 8, width: 26, height: 26))
        sendButton.bezelStyle = .inline
        sendButton.isBordered = false
        sendButton.target = self
        sendButton.action = #selector(sendMessage)
        sendButton.autoresizingMask = [.minXMargin]
        
        // 设置发送图标
        if let sendImage = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "发送") {
            sendButton.image = sendImage
            sendButton.imagePosition = .imageOnly
        }
        
        // 添加悬停效果
        sendButton.toolTip = "发送消息"
        sendButton.contentTintColor = NSColor.secondaryLabelColor
        sendButton.hoverHandler = { [weak sendButton] isHovered in
            sendButton?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
        }
        
        inputContainer.addSubview(sendButton)
        
        // 设置窗口关闭回调
        panel.delegate = self
        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func copyText() {
        webView?.evaluateJavaScript("document.body.innerText") { result, error in
            if let text = result as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                if let copyButton = self.titlebarButtonContainer?.arrangedSubviews[2] as? HoverableButton {
                    copyButton.showFeedback("已复制对话")
                }
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
                appendMessage('user', `\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`, false);
            """
            webView.evaluateJavaScript(script)
        }
        
        // 使用空提示词调用 API（对话模式）
        callAPI(withPrompt: "", text: text)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView 加载完成")
        // WebView 加载完成后，只显示用户消息和 AI 回复
        for message in messages {
            // 跳过系统提示词
            if message["role"] == "system" { continue }
            print("显示消息：\(message)")
            let script = """
                appendMessage('\(message["role"] ?? "")', `\(message["content"]?.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`") ?? "")`, false, '\(model)');
            """
            webView.evaluateJavaScript(script)
        }
    }
    
    func updateLastMessage() {
        print("更新最后一条消息...")
        guard let webView = self.webView,
              let lastMessage = messages.last else {
            print("无法更新消息：webView 或 lastMessage 为空")
            return
        }
        
        // 只有当最后一条消息是 AI 回复时才替换
        let script = """
            if (document.querySelector('.message:last-child')?.getAttribute('data-role') === 'assistant') {
                appendMessage('\(lastMessage["role"] ?? "")', `\(lastMessage["content"]?.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`") ?? "")`, true, '\(model)');
            } else {
                appendMessage('\(lastMessage["role"] ?? "")', `\(lastMessage["content"]?.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`") ?? "")`, false, '\(model)');
            }
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
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,  // 使用完整的消息历史
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
        
        return finalText
    }
    
    // 添加清除历史记录的方法
    func clearHistory() {
        // 清除历史记录但保留系统提示词
        messages = [["role": "system", "content": systemPrompt]]
    }
    
    // 清除按钮点击事件
    @objc func clearButtonClicked() {
        messages = [["role": "system", "content": systemPrompt]]
        webView?.evaluateJavaScript("document.getElementById('messages').innerHTML = '';")
        if let clearButton = titlebarButtonContainer?.arrangedSubviews[1] as? HoverableButton {
            clearButton.showFeedback("已清除对话")
        }
    }
    
    // 添加置顶切换方法
    @objc func togglePin() {
        guard let window = self.window else { return }
        if window.level == .normal {
            // 设置为浮动面板层级，确保在大多数窗口之上
            window.level = .floating
            // 设置窗口行为，使其始终保持在最前
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.hidesOnDeactivate = false
            if let pinButton = titlebarButtonContainer?.arrangedSubviews.first as? HoverableButton {
                pinButton.contentTintColor = NSColor.systemBlue  // 设置初始高亮颜色
                pinButton.showFeedback("已置顶")
                // 更新按钮状态
                pinButton.updateTrackingAreas()
            }
        } else {
            window.level = .normal
            // 恢复默认窗口行为
            window.collectionBehavior = []
            window.hidesOnDeactivate = true
            if let pinButton = titlebarButtonContainer?.arrangedSubviews.first as? HoverableButton {
                pinButton.contentTintColor = NSColor.secondaryLabelColor
                pinButton.showFeedback("已取消置顶")
                // 更新按钮状态
                pinButton.updateTrackingAreas()
            }
        }
    }
}

// 添加窗口代理方法
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        clearHistory()
        NSApp.terminate(nil)
    }
} 