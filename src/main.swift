import Cocoa
import KeychainAccess
import SwiftyJSON
import WebKit
import UniformTypeIdentifiers

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

// 添加 HoverableButton 类作为全局类
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
        
        let size = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)])
        let padding: CGFloat = 16
        let width = size.width + padding
        let height: CGFloat = 22
        
        let buttonFrame = self.window?.convertToScreen(self.convert(self.bounds, to: nil)) ?? .zero
        
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
        
        tooltipPanel = panel
    }
    
    private func hideTooltip() {
        tooltipPanel?.close()
        tooltipPanel = nil
    }
    
    func showFeedback(_ text: String) {
        hideTooltip()
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
        
        let size = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)])
        let padding: CGFloat = 16
        let width = size.width + padding
        let height: CGFloat = 22
        
        feedback.frame = NSRect(x: 0, y: 0, width: width, height: height)
        
        let buttonFrame = self.window?.convertToScreen(self.convert(self.bounds, to: nil)) ?? .zero
        
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
        
        feedbackPanel = panel
        
        NSObject.cancelPreviousPerformRequests(withTarget: self)
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

class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "copyText", let text = message.body as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

// 添加笔记设置结构体
struct NoteSettings: Codable {
    var defaultNotePath: String
    var lastSelectedNote: String
    
    static let defaultSettings = NoteSettings(defaultNotePath: "", lastSelectedNote: "")
}

// 添加笔记管理器类
class NoteManager {
    static let shared = NoteManager()
    private let settingsURL: URL
    private var settings: NoteSettings
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("AskPop")
        
        // 创建应用程序文件夹
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        settingsURL = appFolder.appendingPathComponent("note_settings.json")
        
        if let data = try? Data(contentsOf: settingsURL),
           let loadedSettings = try? JSONDecoder().decode(NoteSettings.self, from: data) {
            settings = loadedSettings
        } else {
            settings = .defaultSettings
        }
    }
    
    func saveSettings() {
        try? JSONEncoder().encode(settings).write(to: settingsURL)
    }
    
    var defaultNotePath: String {
        get { settings.defaultNotePath }
        set {
            settings.defaultNotePath = newValue
            saveSettings()
        }
    }
    
    var lastSelectedNote: String {
        get { settings.lastSelectedNote }
        set {
            settings.lastSelectedNote = newValue
            saveSettings()
        }
    }
}

// 添加笔记窗口控制器类
class NoteWindowController: NSWindowController {
    var defaultPathButton: NSButton!
    var newNoteButton: NSButton!
    var selectNoteButton: NSButton!
    var saveButton: NSButton!
    var currentNoteLabel: NSTextField!
    var contentTextView: NSTextView!
    var originalText: String = ""  // 存储原始文本
    
    var aiContent: String = "" {
        didSet {
            contentTextView.string = aiContent
        }
    }
    
    convenience init(withText text: String = "") {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // 设置窗口在主屏幕中心位置
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.title = "笔记模式"
        self.init(window: window)
        
        // 设置关闭按钮事件
        window.standardWindowButton(.closeButton)?.target = NSApplication.shared.delegate
        window.standardWindowButton(.closeButton)?.action = #selector(AppDelegate.closeWindow)
        
        originalText = text  // 保存原始文本
        setupUI()
        
        // 显示原始文本
        contentTextView.string = text
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        // 创建工具栏
        let toolbar = NSToolbar(identifier: "NoteToolbar")
        toolbar.displayMode = .iconAndLabel
        toolbar.delegate = self
        window.toolbar = toolbar
        
        // 创建内容视图
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        
        // 创建当前笔记标签容器
        let labelContainer = NSView(frame: NSRect(x: 20, y: window.contentView!.bounds.height - 40, width: window.contentView!.bounds.width - 40, height: 20))
        labelContainer.autoresizingMask = [.width, .minYMargin]
        
        // 创建前缀标签
        let prefixLabel = NSTextField(frame: NSRect(x: 0, y: 0, width: 70, height: 20))
        prefixLabel.stringValue = "当前笔记："
        prefixLabel.isEditable = false
        prefixLabel.isBordered = false
        prefixLabel.backgroundColor = .clear
        prefixLabel.textColor = .secondaryLabelColor
        prefixLabel.font = NSFont.systemFont(ofSize: 12)
        labelContainer.addSubview(prefixLabel)
        
        // 创建当前笔记路径标签
        currentNoteLabel = NSTextField(frame: NSRect(x: 70, y: 0, width: labelContainer.frame.width - 70, height: 20))
        currentNoteLabel.isEditable = false
        currentNoteLabel.isBordered = false
        currentNoteLabel.backgroundColor = .clear
        currentNoteLabel.cell?.truncatesLastVisibleLine = true
        currentNoteLabel.cell?.lineBreakMode = .byTruncatingMiddle  // 在中间使用省略号
        currentNoteLabel.font = NSFont.systemFont(ofSize: 12)
        
        // 添加鼠标跟踪区域，用于显示完整路径
        let trackingArea = NSTrackingArea(
            rect: currentNoteLabel.bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: currentNoteLabel,
            userInfo: nil
        )
        currentNoteLabel.addTrackingArea(trackingArea)
        
        // 添加鼠标事件处理
        currentNoteLabel.wantsLayer = true
        currentNoteLabel.layer?.cornerRadius = 4
        
        // 子类化 NSTextField 来处理鼠标事件
        class HoverableLabel: NSTextField {
            override func mouseEntered(with event: NSEvent) {
                super.mouseEntered(with: event)
                self.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.1).cgColor
            }
            
            override func mouseExited(with event: NSEvent) {
                super.mouseExited(with: event)
                self.layer?.backgroundColor = .clear
            }
        }
        
        // 使用新的可悬停标签
        let hoverableLabel = HoverableLabel(frame: currentNoteLabel.frame)
        hoverableLabel.isEditable = false
        hoverableLabel.isBordered = false
        hoverableLabel.backgroundColor = .clear
        hoverableLabel.cell?.truncatesLastVisibleLine = true
        hoverableLabel.cell?.lineBreakMode = .byTruncatingMiddle
        hoverableLabel.font = NSFont.systemFont(ofSize: 12)
        currentNoteLabel = hoverableLabel
        
        labelContainer.addSubview(currentNoteLabel)
        contentView.addSubview(labelContainer)
        
        // 创建内容文本视图
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: window.contentView!.bounds.width - 40, height: window.contentView!.bounds.height - 80))
        scrollView.autoresizingMask = [.width, .height]
        
        contentTextView = NSTextView(frame: scrollView.bounds)
        contentTextView.autoresizingMask = [.width, .height]
        contentTextView.isEditable = true
        contentTextView.font = NSFont.systemFont(ofSize: 14)
        
        scrollView.documentView = contentTextView
        scrollView.hasVerticalScroller = true
        
        contentView.addSubview(scrollView)
        
        window.contentView = contentView
        
        // 更新当前笔记标签
        updateCurrentNoteLabel()
    }
    
    func updateCurrentNoteLabel() {
        let path = NoteManager.shared.lastSelectedNote
        if path.isEmpty {
            currentNoteLabel.stringValue = "未选择笔记"
            currentNoteLabel.toolTip = nil
        } else {
            // 获取相对于用户主目录的路径
            var relativePath = path
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            if path.hasPrefix(homeDir) {
                relativePath = path.replacingOccurrences(of: homeDir, with: "~")
            }
            
            // 设置显示文本和工具提示
            currentNoteLabel.stringValue = relativePath
            currentNoteLabel.toolTip = path  // 显示完整路径作为工具提示
        }
    }
    
    @objc func selectDefaultPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        panel.beginSheetModal(for: window!) { response in
            if response == .OK {
                if let url = panel.url {
                    NoteManager.shared.defaultNotePath = url.path
                }
            }
        }
    }
    
    @objc func createNewNote() {
        let panel = NSSavePanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType(filenameExtension: "md")!]
        } else {
            panel.allowedFileTypes = ["md"]
        }
        panel.nameFieldStringValue = "新笔记.md"
        
        if !NoteManager.shared.defaultNotePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: NoteManager.shared.defaultNotePath)
        }
        
        panel.beginSheetModal(for: window!) { response in
            if response == .OK {
                if let url = panel.url {
                    try? "# 新笔记\n\n".write(to: url, atomically: true, encoding: .utf8)
                    NoteManager.shared.lastSelectedNote = url.path
                    self.updateCurrentNoteLabel()
                }
            }
        }
    }
    
    @objc func selectNote() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType(filenameExtension: "md")!]
        } else {
            panel.allowedFileTypes = ["md"]
        }
        panel.allowsMultipleSelection = false
        
        if !NoteManager.shared.defaultNotePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: NoteManager.shared.defaultNotePath)
        }
        
        panel.beginSheetModal(for: window!) { response in
            if response == .OK {
                if let url = panel.url {
                    NoteManager.shared.lastSelectedNote = url.path
                    self.updateCurrentNoteLabel()
                }
            }
        }
    }
    
    @objc func saveContent() {
        guard !NoteManager.shared.lastSelectedNote.isEmpty else {
            if let saveButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "saveContent" })?.view as? HoverableButton {
                saveButton.showFeedback("请先选择笔记")
            }
            return
        }
        
        let url = URL(fileURLWithPath: NoteManager.shared.lastSelectedNote)
        var existingContent = ""
        
        // 读取现有内容
        do {
            existingContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("无法读取现有内容：\(error)")
        }
        
        // 在文件末尾添加新内容
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        
        // 获取内容的第一行作为标题
        let contentLines = contentTextView.string.components(separatedBy: .newlines)
        let firstLine = contentLines.first ?? "新笔记"
        
        // 构建新内容，保持原始标题的 Markdown 格式，只在后面添加时间戳
        let contentWithoutTitle = contentLines.count > 1 ? 
            contentLines[1...].joined(separator: "\n") : ""
        
        let newContent = """
        \(existingContent)
        
        \(firstLine) - \(timestamp)
        
        \(contentWithoutTitle)
        
        ---
        
        """
        
        do {
            try newContent.write(to: url, atomically: true, encoding: .utf8)
            if let saveButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "saveContent" })?.view as? HoverableButton {
                saveButton.showFeedback("保存成功")
            }
        } catch {
            if let saveButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "saveContent" })?.view as? HoverableButton {
                saveButton.showFeedback("保存失败")
            }
            print("保存失败：\(error.localizedDescription)")
        }
    }
    
    @objc func rewriteContent() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        
        // 获取当前文本内容
        let currentText = contentTextView.string
        guard !currentText.isEmpty else {
            if let rewriteButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "rewriteContent" })?.view as? HoverableButton {
                rewriteButton.showFeedback("请先输入内容")
            }
            return
        }
        
        // 调用 AI API 进行改写
        appDelegate.messages = [["role": "system", "content": appDelegate.systemPrompt]]
        appDelegate.messages.append(["role": "user", "content": currentText])
        
        // 清空内容，准备显示 AI 改写的结果
        contentTextView.string = ""
        
        // 调用 API
        appDelegate.callAPI(withPrompt: "", text: currentText)
        
        if let rewriteButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "rewriteContent" })?.view as? HoverableButton {
            rewriteButton.showFeedback("正在改写...")
        }
    }
}

// 添加工具栏代理
extension NoteWindowController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        
        switch itemIdentifier.rawValue {
        case "defaultPath":
            item.label = "set"
            let button = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(selectDefaultPath)
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.contentTintColor = NSColor.secondaryLabelColor
            button.hoverHandler = { [weak button] isHovered in
                button?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
            }
            item.view = button
            
        case "newNote":
            item.label = "new"
            let button = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            button.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(createNewNote)
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.contentTintColor = NSColor.secondaryLabelColor
            button.hoverHandler = { [weak button] isHovered in
                button?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
            }
            item.view = button
            
        case "selectNote":
            item.label = "select"
            let button = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            button.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(selectNote)
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.contentTintColor = NSColor.secondaryLabelColor
            button.hoverHandler = { [weak button] isHovered in
                button?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
            }
            item.view = button
            
        case "saveContent":
            item.label = "save"
            let button = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            button.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(saveContent)
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.contentTintColor = NSColor.secondaryLabelColor
            button.hoverHandler = { [weak button] isHovered in
                button?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
            }
            item.view = button
            
        case "rewriteContent":
            item.label = "rewrite"
            let button = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            button.image = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(rewriteContent)
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.contentTintColor = NSColor.secondaryLabelColor
            button.hoverHandler = { [weak button] isHovered in
                button?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
            }
            item.view = button
            
        default:
            return nil
        }
        
        return item
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("defaultPath"),
            NSToolbarItem.Identifier("newNote"),
            NSToolbarItem.Identifier("selectNote"),
            NSToolbarItem.Identifier("saveContent"),
            NSToolbarItem.Identifier("rewriteContent"),
            .flexibleSpace
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
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
    
    // 添加笔记窗口控制器的引用
    var noteWindowController: NoteWindowController?
    
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
        
        // 确保应用程序在前台运行
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // 从命令行参数获取提示词和文本
        let prompt = CommandLine.arguments[1]
        let encodedText = CommandLine.arguments[2]
        let text: String
        if encodedText.hasPrefix("base64:") {
            let base64String = String(encodedText.dropFirst(7))
            if let data = Data(base64Encoded: base64String),
               let decodedText = String(data: data, encoding: .utf8) {
                text = decodedText
                print("成功解码 base64 文本")
            } else {
                print("错误：无法解码 base64 文本")
                exit(1)
            }
        } else {
            text = encodedText
        }
        
        systemPrompt = prompt  // 保存系统提示词
        print("接收到的提示词: \(prompt)")
        print("接收到的文本: \(text)")
        
        if !text.isEmpty {
            // 检查是否是笔记模式
            if let actionId = ProcessInfo.processInfo.environment["POPCLIP_ACTION_IDENTIFIER"],
               actionId == "note_action" {
                // 笔记模式：直接显示原文，不调用 AI
                noteWindowController = NoteWindowController(withText: text)
                noteWindowController?.showWindow(nil)
            } else {
                // 普通模式
                messages = [["role": "system", "content": prompt]]
                // 检查是否是翻译模式
                let isTranslateMode = ProcessInfo.processInfo.environment["POPCLIP_ACTION_IDENTIFIER"] == "translate_action"
                let messageText = isTranslateMode ? "翻译: \(text)" : text
                messages.append(["role": "user", "content": messageText])
                createWindow()
                // 在 WebView 中显示原始文本（不带前缀）
                webView?.evaluateJavaScript("""
                    appendMessage('user', `\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`, false);
                """)
                callAPI(withPrompt: "", text: messageText)
            }
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
        
        // 设置窗口在主屏幕中心位置
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = panel.frame
            let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        //panel.title = "AI助手"
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.level = .floating  // 默认设置为浮动层级
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]  // 设置窗口行为
        panel.hidesOnDeactivate = false  // 失去焦点时不隐藏
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        // 移除左上角的代表性图标
        panel.representedURL = nil
        panel.representedFilename = ""
        panel.isDocumentEdited = false
        
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
                    display: inline-block;  /* 让消息框宽度自适应内容 */
                    max-width: 100%;  /* 最大宽度为容器宽度 */
                    word-wrap: break-word;  /* 允许长单词换行 */
                    white-space: pre-wrap;  /* 保留换行和空格，同时允许自动换行 */
                }
                .message-header {
                    margin-bottom: 4px;
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
                    word-wrap: break-word;
                    white-space: normal;  /* 使用正常的换行 */
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
                    white-space: normal;  /* 使用正常的换行 */
                }
                
                /* AI 消息样式 */
                .message[data-role="assistant"] {
                    background-color: rgba(40, 167, 69, 0.1);
                    align-self: flex-start;
                    width: calc(100% - 12px);  /* 减去右侧空间 */
                    white-space: normal;  /* 使用正常的换行 */
                }
                
                /* 统一消息样式 */
                .message {
                    margin-left: 0;  /* 确保左对齐 */
                    margin-right: auto;  /* 允许右边有空间 */
                    padding: 8px 12px;  /* 消息内部的内边距 */
                    word-wrap: break-word;  /* 允许长单词换行 */
                }
                
                .message-content {
                    font-size: 14px;
                    white-space: normal;  /* 使用正常的换行 */
                    word-wrap: break-word;  /* 允许长单词换行 */
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
        
        // 确保窗口显示在最前面
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        
        // 添加标准关闭按钮的事件处理
        panel.standardWindowButton(.closeButton)?.isHidden = false  // 显示关闭按钮
        panel.standardWindowButton(.closeButton)?.target = self
        panel.standardWindowButton(.closeButton)?.action = #selector(closeWindow)

        // 如果是第一次创建窗口，设置为浮动层级
        if let pinButton = titlebarButtonContainer.arrangedSubviews.first as? HoverableButton {
            pinButton.contentTintColor = NSColor.systemBlue
        }
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
        
        // 检查是否是翻译模式
        let isTranslateMode = ProcessInfo.processInfo.environment["POPCLIP_ACTION_IDENTIFIER"] == "translate_action"
        let messageText = isTranslateMode ? "翻译: \(text)" : text
        
        messages.append(["role": "user", "content": messageText])
        inputField?.stringValue = ""
        
        // 立即显示用户消息，但显示原始文本
        if let webView = self.webView {
            let script = """
                appendMessage('user', `\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`, false);
            """
            webView.evaluateJavaScript(script)
        }
        
        // 使用空提示词调用 API（对话模式）
        callAPI(withPrompt: "", text: messageText)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView 加载完成")
        // WebView 加载完成后，只显示用户消息和 AI 回复
        for message in messages {
            // 跳过系统提示词
            if message["role"] == "system" { continue }
            
            // 获取显示文本（如果是翻译模式下的用户消息，移除前缀）
            var displayContent = message["content"] ?? ""
            if message["role"] == "user" && ProcessInfo.processInfo.environment["POPCLIP_ACTION_IDENTIFIER"] == "translate_action" {
                // 只在翻译模式下移除"翻译: "前缀
                displayContent = displayContent.replacingOccurrences(of: "翻译: ", with: "")
            }
            
            print("显示消息：\(message)")
            let script = """
                appendMessage('\(message["role"] ?? "")', `\(displayContent.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`, false, '\(model)');
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
                    
                    // 检查是否是笔记模式
                    let isNoteMode = ProcessInfo.processInfo.environment["POPCLIP_ACTION_IDENTIFIER"] == "note_action"
                    
                    await MainActor.run {
                        if isNoteMode {
                            // 在笔记窗口显示错误
                            if let noteWindow = NSApp.windows
                                .compactMap({ $0.windowController as? NoteWindowController })
                                .first {
                                noteWindow.aiContent = "错误：\(error.localizedDescription)"
                            }
                        } else {
                            // 在聊天窗口显示错误
                            guard let webView = self.webView else { return }
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
            "messages": messages,
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
        
        // 检查是否是笔记模式
        let isNoteMode = ProcessInfo.processInfo.environment["POPCLIP_ACTION_IDENTIFIER"] == "note_action"
        
        // 如果是笔记模式，获取笔记窗口控制器
        let noteWindowController = isNoteMode ? await MainActor.run {
            NSApp.windows
                .compactMap { $0.windowController as? NoteWindowController }
                .first
        } : nil
        
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
                await MainActor.run { [self] in
                    if isNoteMode {
                        // 笔记模式：更新笔记窗口
                        noteWindowController?.aiContent = currentText
                    } else {
                        // 普通模式：更新聊天窗口
                        if isFirst {
                            self.messages.append(["role": "assistant", "content": currentText])
                        } else {
                            self.messages[self.messages.count - 1]["content"] = currentText
                        }
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

// 修改窗口代理方法
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        currentTask?.cancel()  // 取消当前任务
        clearHistory()
        DispatchQueue.main.async {
            NSApp.terminate(nil)  // 确保在主线程中终止应用
        }
    }
} 