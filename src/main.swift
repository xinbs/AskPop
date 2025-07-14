import Cocoa
import KeychainAccess
import SwiftyJSON
import WebKit
import UniformTypeIdentifiers

// 通知名称定义
extension Notification.Name {
    static let historyDidUpdate = Notification.Name("historyDidUpdate")
}

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
        feedback.backgroundColor = NSColor(white: 0.3, alpha: 0.9)  // 深灰色背景
        feedback.drawsBackground = true  // 显示背景
        feedback.textColor = NSColor.white  // 白色文字
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
        
        panel.backgroundColor = NSColor(white: 0.3, alpha: 0.9)  // 面板也使用深灰色背景
        panel.isOpaque = false
        panel.hasShadow = true  // 添加阴影效果
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
    
    // 公开方法供外部调用
    func clearTooltips() {
        hideTooltip()
        feedbackPanel?.close()
        feedbackPanel = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }
    
    func showFeedback(_ text: String) {
        hideTooltip()
        feedbackPanel?.close()
        feedbackPanel = nil
        
        let feedback = NSTextField(frame: .zero)
        feedback.stringValue = text
        feedback.isEditable = false
        feedback.isBordered = false
        feedback.backgroundColor = NSColor(white: 0.3, alpha: 0.9)  // 深灰色背景
        feedback.drawsBackground = true  // 显示背景
        feedback.textColor = NSColor.white  // 白色文字
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
        
        panel.backgroundColor = NSColor(white: 0.3, alpha: 0.9)  // 面板也使用深灰色背景
        panel.isOpaque = false
        panel.hasShadow = true  // 添加阴影效果
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
class NoteWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    // 添加属性
    private var noteTableView: NSTableView?
    private var noteList: [(id: Int, title: String)] = []
    var defaultPathButton: NSButton!
    var newNoteButton: NSButton!
    var selectNoteButton: NSButton!
    var saveButton: NSButton!
    var currentNoteLabel: NSTextField!
    var contentTextView: NSTextView!
    var originalText: String = ""
    var blinkoStatusLabel: NSTextField!
    
    var aiContent: String = "" {
        didSet {
            contentTextView.string = aiContent
        }
    }
    
    // 添加表格视图的数据源方法
    func numberOfRows(in tableView: NSTableView) -> Int {
        return noteList.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < noteList.count else { return nil }
        let note = noteList[row]
        
        // 构建笔记类型标识
        var typeLabels = ""
        if note.id == BlinkoManager.shared.syncNoteId {
            typeLabels += "[同步] "
        }
        if note.id == BlinkoManager.shared.defaultNoteId {
            typeLabels += "[默认] "
        }
        if note.id == BlinkoManager.shared.currentNoteId {
            typeLabels += "[当前] "
        }
        
        // 返回带标识的笔记标题
        return "\(typeLabels)#\(note.id) - \(note.title)"
    }
    
    // 添加表格视图的行高度方法
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 30  // 保持原有高度
    }
    
    // 添加表格视图的行视图方法
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < noteList.count else { return nil }
        
        let cellIdentifier = NSUserInterfaceItemIdentifier("NoteCell")
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView
        
        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = cellIdentifier
            
            let textField = NSTextField()
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = false
            textField.font = NSFont.systemFont(ofSize: 12)
            cell?.textField = textField
            cell?.addSubview(textField)
            
            // 设置文本框约束
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 5),
                textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -5),
                textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
            ])
        }
        
        let note = noteList[row]
        
        // 构建带标识的笔记标题
        let attributedString = NSMutableAttributedString()
        
        // 添加类型标识
        if note.id == BlinkoManager.shared.syncNoteId {
            let syncLabel = NSAttributedString(
                string: "[同步] ",
                attributes: [
                    .foregroundColor: NSColor.systemBlue,
                    .font: NSFont.boldSystemFont(ofSize: 12)
                ]
            )
            attributedString.append(syncLabel)
        }
        
        if note.id == BlinkoManager.shared.defaultNoteId {
            let defaultLabel = NSAttributedString(
                string: "[默认] ",
                attributes: [
                    .foregroundColor: NSColor.systemGreen,
                    .font: NSFont.boldSystemFont(ofSize: 12)
                ]
            )
            attributedString.append(defaultLabel)
        }
        
        if note.id == BlinkoManager.shared.currentNoteId {
            let currentLabel = NSAttributedString(
                string: "[当前] ",
                attributes: [
                    .foregroundColor: NSColor.systemOrange,
                    .font: NSFont.boldSystemFont(ofSize: 12)
                ]
            )
            attributedString.append(currentLabel)
        }
        
        // 添加笔记标题
        let titleString = NSAttributedString(
            string: "#\(note.id) - \(note.title)",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 12)
            ]
        )
        attributedString.append(titleString)
        
        cell?.textField?.attributedStringValue = attributedString
        return cell
    }
    
    convenience init(withText text: String = "") {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), // 将宽度从 600 改为 800
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
        
        // 创建 Blinko 状态标签
        blinkoStatusLabel = NSTextField(frame: NSRect(x: 20, y: window.contentView!.bounds.height - 60, width: window.contentView!.bounds.width - 40, height: 20))
        blinkoStatusLabel.isEditable = false
        blinkoStatusLabel.isBordered = false
        blinkoStatusLabel.backgroundColor = .clear
        blinkoStatusLabel.textColor = .secondaryLabelColor
        blinkoStatusLabel.font = NSFont.systemFont(ofSize: 12)
        blinkoStatusLabel.cell?.truncatesLastVisibleLine = true
        blinkoStatusLabel.cell?.lineBreakMode = .byTruncatingMiddle
        window.contentView?.addSubview(blinkoStatusLabel)
        
        updateBlinkoStatus()
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
    
    func updateBlinkoStatus() {
        var statusText = ""
        
        // 显示同步笔记信息
        if BlinkoManager.shared.syncNoteId > 0 {
            statusText += "同步笔记: #\(BlinkoManager.shared.syncNoteId) - \(BlinkoManager.shared.syncNoteTitle)"
        } else {
            statusText += "未设置同步笔记"
        }
        
        statusText += " | "
        
        // 显示默认笔记信息
        if BlinkoManager.shared.defaultNoteId > 0 {
            statusText += "默认笔记: #\(BlinkoManager.shared.defaultNoteId) - \(BlinkoManager.shared.defaultNoteTitle)"
        } else {
            statusText += "未设置默认笔记"
        }
        
        statusText += " | "
        
        // 显示当前笔记信息
        if BlinkoManager.shared.currentNoteId > 0 {
            statusText += "当前笔记: #\(BlinkoManager.shared.currentNoteId) - \(BlinkoManager.shared.currentNoteTitle)"
        } else {
            statusText += "未设置当前笔记"
        }
        
        blinkoStatusLabel.stringValue = statusText
    }
    
    @objc func selectDefaultPath() {
        // 创建设置窗口
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "笔记设置"
        
        // 创建主容器
        let contentView = NSView(frame: settingsWindow.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        
        // 创建本地笔记设置区域标题和说明
        let localNoteTitle = NSTextField(labelWithString: "本地笔记设置")
        localNoteTitle.frame = NSRect(x: 20, y: contentView.frame.height - 40, width: 200, height: 20)
        localNoteTitle.font = NSFont.boldSystemFont(ofSize: 14)
        contentView.addSubview(localNoteTitle)
        
        let localNoteDesc = NSTextField(labelWithString: "设置本地 Markdown 笔记的默认保存目录")
        localNoteDesc.frame = NSRect(x: 20, y: contentView.frame.height - 65, width: 400, height: 20)
        localNoteDesc.font = NSFont.systemFont(ofSize: 12)
        localNoteDesc.textColor = .secondaryLabelColor
        contentView.addSubview(localNoteDesc)
        
        // 创建路径选择区域
        let pathContainer = NSView(frame: NSRect(x: 20, y: contentView.frame.height - 95, width: contentView.frame.width - 40, height: 20))
        contentView.addSubview(pathContainer)
        
        let pathLabel = NSTextField(labelWithString: "默认保存路径：")
        pathLabel.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        pathLabel.isEditable = false
        pathLabel.isBordered = false
        pathLabel.backgroundColor = .clear
        pathLabel.drawsBackground = false
        pathContainer.addSubview(pathLabel)
        
        let pathField = NSTextField(frame: NSRect(x: 100, y: 0, width: pathContainer.frame.width - 180, height: 20))
        pathField.stringValue = NoteManager.shared.defaultNotePath
        pathField.isEditable = false
        pathField.isBordered = false
        pathField.backgroundColor = .clear
        pathField.drawsBackground = false
        pathField.textColor = .labelColor
        pathField.cell?.truncatesLastVisibleLine = true
        pathField.cell?.lineBreakMode = .byTruncatingMiddle
        pathField.font = NSFont.systemFont(ofSize: 12)
        pathContainer.addSubview(pathField)
        
        let browseButton = HoverableButton(frame: NSRect(x: pathContainer.frame.width - 70, y: 0, width: 70, height: 20))
        browseButton.title = "浏览"
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browsePath(_:))
        pathContainer.addSubview(browseButton)
        
        // 创建 Blinko 设置区域标题和说明
        let blinkoTitle = NSTextField(labelWithString: "Blinko 笔记设置")
        blinkoTitle.frame = NSRect(x: 20, y: contentView.frame.height - 145, width: 200, height: 20)
        blinkoTitle.font = NSFont.boldSystemFont(ofSize: 14)
        contentView.addSubview(blinkoTitle)
        
        let blinkoDesc = NSTextField(labelWithString: "设置同步笔记、默认笔记和当前笔记")
        blinkoDesc.frame = NSRect(x: 20, y: contentView.frame.height - 170, width: 400, height: 20)
        blinkoDesc.font = NSFont.systemFont(ofSize: 12)
        blinkoDesc.textColor = .secondaryLabelColor
        contentView.addSubview(blinkoDesc)
        
        // 创建笔记列表视图容器
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 100, width: 460, height: contentView.frame.height - 290))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        // 创建表格视图
        let tableView = NSTableView(frame: NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NoteColumn"))
        column.title = "笔记列表"
        column.width = scrollView.contentSize.width - 20
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.rowHeight = 30
        scrollView.documentView = tableView

        // 创建底部按钮区域
        let buttonContainer = NSView(frame: NSRect(x: 20, y: 20, width: 460, height: 70))
        
        // 创建笔记设置按钮组
        let noteSettingsContainer = NSView(frame: NSRect(x: 0, y: 40, width: 460, height: 30))
        
        let setSyncButton = HoverableButton(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        setSyncButton.title = "设为同步笔记"
        setSyncButton.bezelStyle = .rounded
        setSyncButton.target = self
        setSyncButton.action = #selector(setSyncNote(_:))
        noteSettingsContainer.addSubview(setSyncButton)
        
        let setDefaultButton = HoverableButton(frame: NSRect(x: 110, y: 0, width: 100, height: 30))
        setDefaultButton.title = "设为默认笔记"
        setDefaultButton.bezelStyle = .rounded
        setDefaultButton.target = self
        setDefaultButton.action = #selector(setDefaultNote(_:))
        noteSettingsContainer.addSubview(setDefaultButton)
        
        let setCurrentButton = HoverableButton(frame: NSRect(x: 220, y: 0, width: 100, height: 30))
        setCurrentButton.title = "设为当前笔记"
        setCurrentButton.bezelStyle = .rounded
        setCurrentButton.target = self
        setCurrentButton.action = #selector(setCurrentNote(_:))
        noteSettingsContainer.addSubview(setCurrentButton)
        
        buttonContainer.addSubview(noteSettingsContainer)
        
        // 创建操作按钮组
        let actionButtonsContainer = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 30))
        
        // 创建刷新按钮
        let refreshButton = HoverableButton(frame: NSRect(x: 0, y: 0, width: 70, height: 30))
        refreshButton.title = "刷新"
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshNoteList(_:))
        actionButtonsContainer.addSubview(refreshButton)

        // 创建取消按钮
        let cancelButton = NSButton(frame: NSRect(x: 310, y: 0, width: 70, height: 30))
        cancelButton.title = "取消"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(closeSettings(_:))
        actionButtonsContainer.addSubview(cancelButton)

        // 创建确定按钮
        let confirmButton = NSButton(frame: NSRect(x: 390, y: 0, width: 70, height: 30))
        confirmButton.title = "确定"
        confirmButton.bezelStyle = .rounded
        confirmButton.target = self
        confirmButton.action = #selector(saveSettings(_:))
        actionButtonsContainer.addSubview(confirmButton)
        
        buttonContainer.addSubview(actionButtonsContainer)
        contentView.addSubview(buttonContainer)

        // 设置表格视图的数据源和代理
        tableView.dataSource = self
        tableView.delegate = self

        // 存储表格视图的引用
        self.noteTableView = tableView

        settingsWindow.contentView = contentView

        // 加载笔记列表
        Task {
            do {
                let notes = try await BlinkoManager.shared.getNoteList()
                await MainActor.run {
                    self.noteList = notes
                    tableView.reloadData()
                    
                    // 选中当前笔记
                    let currentNoteId = BlinkoManager.shared.currentNoteId
                    if currentNoteId > 0 {
                        for (index, note) in notes.enumerated() {
                            if note.id == currentNoteId {
                                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                                break
                            }
                        }
                    }
                }
            } catch {
                print("加载笔记列表失败：\(error)")
            }
        }

        // 显示设置窗口
        if let mainWindow = self.window {
            mainWindow.beginSheet(settingsWindow)
        }
    }
    
    @objc func browsePath(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "请选择本地笔记的默认保存目录"
        panel.prompt = "选择"
        
        // 如果已有默认路径，设置为初始目录
        if !NoteManager.shared.defaultNotePath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: NoteManager.shared.defaultNotePath)
        }
        
        // 获取设置窗口
        if let settingsWindow = sender.window {
            panel.beginSheetModal(for: settingsWindow) { [weak self] response in
                if response == .OK {
                    if let url = panel.url {
                        // 保存选择的路径
                        NoteManager.shared.defaultNotePath = url.path
                        
                        // 更新路径显示
                        if let pathField = settingsWindow.contentView?.subviews.first(where: { ($0 as? NSTextField)?.frame.origin.y == settingsWindow.contentView!.frame.height - 95 }) as? NSTextField {
                            pathField.stringValue = url.path
                        }
                        
                        // 显示成功提示
                        if let button = sender as? HoverableButton {
                            button.showFeedback("已设置默认目录")
                        }
                    }
                }
            }
        }
    }
    
    @objc func refreshNoteList(_ sender: NSButton) {
        // 禁用按钮并显示加载状态
        sender.isEnabled = false
        sender.title = "加载中..."
        
        Task {
            do {
                let notes = try await BlinkoManager.shared.getNoteList()
                await MainActor.run {
                    self.noteList = notes
                    self.noteTableView?.reloadData()
                    
                    // 选中当前笔记
                    let currentNoteId = BlinkoManager.shared.currentNoteId
                    if currentNoteId > 0 {
                        for (index, note) in notes.enumerated() {
                            if note.id == currentNoteId {
                                self.noteTableView?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                                break
                            }
                        }
                    }
                    
                    // 恢复按钮状态
                    sender.isEnabled = true
                    sender.title = "刷新"
                    
                    // 显示成功提示
                    if let button = sender as? HoverableButton {
                        button.showFeedback("刷新成功")
                    }
                }
            } catch {
                await MainActor.run {
                    // 恢复按钮状态
                    sender.isEnabled = true
                    sender.title = "刷新"
                    
                    // 显示错误提示
                    if let button = sender as? HoverableButton {
                        button.showFeedback("刷新失败：\(error.localizedDescription)")
                    }
                    print("刷新笔记列表失败：\(error)")
                }
            }
        }
    }
    
    @objc func closeSettings(_ sender: NSButton) {
        if let settingsWindow = sender.window {
            window?.endSheet(settingsWindow)
        }
    }
    
    @objc func saveSettings(_ sender: NSButton) {
        if let settingsWindow = sender.window {
            // 保存当前选中的笔记作为默认笔记
            if let selectedRow = noteTableView?.selectedRow,
               selectedRow >= 0 && selectedRow < noteList.count {
                let selectedNote = noteList[selectedRow]
                BlinkoManager.shared.defaultNoteId = selectedNote.id
            }
            
            window?.endSheet(settingsWindow)
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
    
    @objc func saveToBlinko() {
        Task {
            do {
                let content = contentTextView.string
                
                // 如果有当前笔记，则更新当前笔记
                if BlinkoManager.shared.currentNoteId > 0 {
                    let _ = try await BlinkoManager.shared.updateNote(
                        id: BlinkoManager.shared.currentNoteId,
                        content: content
                    )
                    await MainActor.run {
                        BlinkoManager.shared.currentNoteTitle = content.components(separatedBy: .newlines).first ?? "无标题"
                        updateBlinkoStatus()
                        if let blinkoButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "saveToBlinko" })?.view as? HoverableButton {
                            blinkoButton.showFeedback("已更新到当前笔记")
                        }
                    }
                }
                // 如果没有当前笔记但有默认笔记，则更新默认笔记
                else if BlinkoManager.shared.defaultNoteId > 0 {
                    let _ = try await BlinkoManager.shared.updateNote(
                        id: BlinkoManager.shared.defaultNoteId,
                        content: content
                    )
                    await MainActor.run {
                        // 将默认笔记设置为当前笔记
                        BlinkoManager.shared.currentNoteId = BlinkoManager.shared.defaultNoteId
                        BlinkoManager.shared.currentNoteTitle = content.components(separatedBy: .newlines).first ?? "无标题"
                        updateBlinkoStatus()
                        if let blinkoButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "saveToBlinko" })?.view as? HoverableButton {
                            blinkoButton.showFeedback("已更新到默认笔记")
                        }
                    }
                }
                // 如果既没有当前笔记也没有默认笔记，则创建新笔记
                else {
                    let note = try await BlinkoManager.shared.createNote(content: content)
                    await MainActor.run {
                        // 将新创建的笔记设置为当前笔记
                        BlinkoManager.shared.currentNoteId = note.id
                        BlinkoManager.shared.currentNoteTitle = note.title
                        updateBlinkoStatus()
                        if let blinkoButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "saveToBlinko" })?.view as? HoverableButton {
                            blinkoButton.showFeedback("已创建新笔记")
                        }
                    }
                }
                
                // 如果有同步笔记，也更新同步笔记
                if BlinkoManager.shared.syncNoteId > 0 && BlinkoManager.shared.syncNoteId != BlinkoManager.shared.currentNoteId {
                    let _ = try await BlinkoManager.shared.updateNote(
                        id: BlinkoManager.shared.syncNoteId,
                        content: content
                    )
                    await MainActor.run {
                        BlinkoManager.shared.syncNoteTitle = content.components(separatedBy: .newlines).first ?? "无标题"
                        updateBlinkoStatus()
                        if let blinkoButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "saveToBlinko" })?.view as? HoverableButton {
                            blinkoButton.showFeedback("已同步到同步笔记")
                        }
                    }
                }
            } catch {
                if let blinkoButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "saveToBlinko" })?.view as? HoverableButton {
                    blinkoButton.showFeedback("保存失败：\(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc func createBlinkoFlash() {
        Task {
            do {
                let content = contentTextView.string
                let _ = try await BlinkoManager.shared.createNote(content: content, type: 0)  // type 0 表示闪念
                await MainActor.run {
                    if let flashButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "createBlinkoFlash" })?.view as? HoverableButton {
                        flashButton.showFeedback("已创建闪念")
                    }
                }
            } catch {
                if let flashButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "createBlinkoFlash" })?.view as? HoverableButton {
                    flashButton.showFeedback("创建失败：\(error.localizedDescription)")
                }
            }
        }
    }

    @objc func resetToDefaultNote(_ sender: NSButton) {
        // 获取默认笔记 ID
        let defaultNoteId = BlinkoManager.shared.defaultNoteId
        if defaultNoteId > 0 {
            // 设置当前笔记为默认笔记
            BlinkoManager.shared.lastNoteId = defaultNoteId
            // 更新 UI
            updateBlinkoStatus()
            
            // 在列表中选中默认笔记
            if let tableView = noteTableView {
                for (index, note) in noteList.enumerated() {
                    if note.id == defaultNoteId {
                        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                        break
                    }
                }
            }
            
            // 显示反馈
            if let button = sender as? HoverableButton {
                button.showFeedback("已重置为默认笔记")
            }
        } else {
            if let button = sender as? HoverableButton {
                button.showFeedback("未设置默认笔记")
            }
        }
    }

    @objc func selectCurrentNote(_ sender: NSButton) {
        guard let tableView = noteTableView,
              let selectedRow = tableView.selectedRowIndexes.first,
              selectedRow < noteList.count else {
            if let button = sender as? HoverableButton {
                button.showFeedback("请先选择笔记")
            }
            return
        }
        
        let selectedNote = noteList[selectedRow]
        BlinkoManager.shared.lastNoteId = selectedNote.id
        BlinkoManager.shared.lastNoteTitle = selectedNote.title
        
        // 更新 UI
        updateBlinkoStatus()
        
        // 显示反馈
        if let button = sender as? HoverableButton {
            button.showFeedback("已选择当前笔记")
        }
    }

    // 图片处理相关的方法
    private func convertLocalImagesToBase64(_ markdown: String) -> String {
        let imagePattern = "!\\[([^\\]]*)\\]\\(([^\\)\"']+)\\)|!\\[([^\\]]*)\\]\\(\"([^\\)]+)\"\\)|!\\[([^\\]]*)\\]\\('([^\\)]+)'\\)"
        var processedMarkdown = markdown
        
        do {
            let regex = try NSRegularExpression(pattern: imagePattern, options: [])
            let nsString = markdown as NSString
            let matches = regex.matches(in: markdown, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                let pathRange = match.range(at: 2).length > 0 ? match.range(at: 2) : 
                               (match.range(at: 4).length > 0 ? match.range(at: 4) : match.range(at: 6))
                let imagePath = nsString.substring(with: pathRange)
                
                // 检查是否已经是 base64 格式
                if imagePath.hasPrefix("data:image/") && imagePath.contains(";base64,") {
                    print("跳过已经是 base64 格式的图片")
                    continue
                }
                
                var imageFullPath: String? = nil
                var possiblePaths: [String] = []
                
                if imagePath.hasPrefix("/") {
                    possiblePaths.append(imagePath)
                } else {
                    let noteDir = (NoteManager.shared.lastSelectedNote as NSString).deletingLastPathComponent
                    possiblePaths.append((noteDir as NSString).appendingPathComponent(imagePath))
                    possiblePaths.append((NoteManager.shared.defaultNotePath as NSString).appendingPathComponent(imagePath))
                    
                    let commonImageDirs = ["assets", "images", "img", "resources", "attachments"]
                    for dir in commonImageDirs {
                        possiblePaths.append((noteDir as NSString).appendingPathComponent("\(dir)/\(imagePath)"))
                        possiblePaths.append((NoteManager.shared.defaultNotePath as NSString).appendingPathComponent("\(dir)/\(imagePath)"))
                    }
                    
                    if imagePath.hasPrefix("../") {
                        let parentPath = (noteDir as NSString).deletingLastPathComponent
                        possiblePaths.append((parentPath as NSString).appendingPathComponent(String(imagePath.dropFirst(3))))
                    }
                }
                
                for path in possiblePaths {
                    if FileManager.default.fileExists(atPath: path) {
                        imageFullPath = path
                        break
                    }
                }
                
                if let fullPath = imageFullPath,
                   let imageData = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) {
                    let pathExtension = (fullPath as NSString).pathExtension.lowercased()
                    let mimeType = getMimeType(for: pathExtension)
                    
                    let fileSizeInMB = Double(imageData.count) / 1_000_000.0
                    if fileSizeInMB > 5.0 {
                        print("警告：图片 '\(imagePath)' 大小为 \(String(format: "%.1f", fileSizeInMB))MB")
                    }
                    
                    let base64String = imageData.base64EncodedString()
                    let base64Image = "![](data:\(mimeType);base64,\(base64String))"
                    
                    let range = match.range
                    processedMarkdown = (processedMarkdown as NSString).replacingCharacters(in: range, with: base64Image)
                    
                    print("已转换图片：\(imagePath) (大小: \(String(format: "%.1f", fileSizeInMB))MB)")
                } else {
                    print("未找到图片或无法读取：\(imagePath)")
                    if !imagePath.hasPrefix("data:image/") {
                        print("尝试过的路径：\n\(possiblePaths.joined(separator: "\n"))")
                    }
                }
            }
        } catch {
            print("处理图片时出错：\(error)")
        }
        
        return processedMarkdown
    }
    
    private func getMimeType(for extension: String) -> String {
        let mimeTypes = [
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "gif": "image/gif",
            "webp": "image/webp",
            "svg": "image/svg+xml",
            "bmp": "image/bmp"
        ]
        return mimeTypes[`extension`.lowercased()] ?? "application/octet-stream"
    }

    // 在 NoteWindowController 类中添加同步方法
    @objc func syncToBlinko() {
        // 检查是否有选择本地笔记
        guard !NoteManager.shared.lastSelectedNote.isEmpty else {
            if let syncButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "syncToBlinko" })?.view as? HoverableButton {
                syncButton.showFeedback("请先选择本地笔记")
            }
            return
        }
        
        // 检查是否有设置同步笔记
        guard BlinkoManager.shared.syncNoteId > 0 else {
            if let syncButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "syncToBlinko" })?.view as? HoverableButton {
                syncButton.showFeedback("请先设置同步笔记")
            }
            return
        }
        
        // 读取本地笔记内容
        let url = URL(fileURLWithPath: NoteManager.shared.lastSelectedNote)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            if let syncButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "syncToBlinko" })?.view as? HoverableButton {
                syncButton.showFeedback("无法读取本地笔记")
            }
            return
        }
        
        // 先转换图片
        print("\n开始同步笔记...")
        print("本地笔记路径：\(NoteManager.shared.lastSelectedNote)")
        print("同步到 Blinko笔记ID：\(BlinkoManager.shared.syncNoteId)")
        
        let processedContent = convertLocalImagesToBase64(content)
        
        // 同步到 Blinko
        Task {
            do {
                print("开始上传到 Blinko...")
                let _ = try await BlinkoManager.shared.updateNote(
                    id: BlinkoManager.shared.syncNoteId,
                    content: processedContent
                )
                await MainActor.run {
                    BlinkoManager.shared.syncNoteTitle = processedContent.components(separatedBy: .newlines).first ?? "无标题"
                    updateBlinkoStatus()
                    if let syncButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "syncToBlinko" })?.view as? HoverableButton {
                        syncButton.showFeedback("同步成功")
                    }
                    print("同步完成！")
                }
            } catch {
                await MainActor.run {
                    if let syncButton = window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "syncToBlinko" })?.view as? HoverableButton {
                        syncButton.showFeedback("同步失败：\(error.localizedDescription)")
                    }
                    print("同步失败：\(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc func setSyncNote(_ sender: NSButton) {
        guard let tableView = noteTableView,
              let selectedRow = tableView.selectedRowIndexes.first,
              selectedRow < noteList.count else {
            if let button = sender as? HoverableButton {
                button.showFeedback("请先选择笔记")
            }
            return
        }
        
        let selectedNote = noteList[selectedRow]
        BlinkoManager.shared.syncNoteId = selectedNote.id
        BlinkoManager.shared.syncNoteTitle = selectedNote.title
        
        // 显示反馈
        if let button = sender as? HoverableButton {
            button.showFeedback("已设置为同步笔记")
        }
    }
    
    @objc func setDefaultNote(_ sender: NSButton) {
        guard let tableView = noteTableView,
              let selectedRow = tableView.selectedRowIndexes.first,
              selectedRow < noteList.count else {
            if let button = sender as? HoverableButton {
                button.showFeedback("请先选择笔记")
            }
            return
        }
        
        let selectedNote = noteList[selectedRow]
        BlinkoManager.shared.defaultNoteId = selectedNote.id
        BlinkoManager.shared.defaultNoteTitle = selectedNote.title
        
        // 显示反馈
        if let button = sender as? HoverableButton {
            button.showFeedback("已设置为默认笔记")
        }
    }
    
    @objc func setCurrentNote(_ sender: NSButton) {
        guard let tableView = noteTableView,
              let selectedRow = tableView.selectedRowIndexes.first,
              selectedRow < noteList.count else {
            if let button = sender as? HoverableButton {
                button.showFeedback("请先选择笔记")
            }
            return
        }
        
        let selectedNote = noteList[selectedRow]
        BlinkoManager.shared.currentNoteId = selectedNote.id
        BlinkoManager.shared.currentNoteTitle = selectedNote.title
        
        // 更新 UI
        updateBlinkoStatus()
        
        // 显示反馈
        if let button = sender as? HoverableButton {
            button.showFeedback("已设置为当前笔记")
        }
    }
}

// 添加工具栏代理
extension NoteWindowController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        
        switch itemIdentifier.rawValue {
        case "defaultPath":
            item.label = "设置"
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
            button.toolTip = "设置默认笔记目录"
            item.view = button
            
        case "newNote":
            item.label = "新建"
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
            button.toolTip = "新建本地笔记"
            item.view = button
            
        case "selectNote":
            item.label = "选择"
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
            button.toolTip = "选择本地笔记"
            item.view = button
            
        case "saveContent":
            item.label = "保存"
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
            button.toolTip = "保存到本地笔记"
            item.view = button
            
        case "rewriteContent":
            item.label = "改写"
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
            button.toolTip = "AI 改写内容"
            item.view = button
            
        case "syncToBlinko":
            item.label = "同步"
            let button = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(syncToBlinko)
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.contentTintColor = NSColor.secondaryLabelColor
            button.hoverHandler = { [weak button] isHovered in
                button?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
            }
            button.toolTip = "同步到 Blinko"
            item.view = button
            
        case "saveToBlinko":
            item.label = "保存"
            let button = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            button.image = NSImage(systemSymbolName: "arrow.up.doc.fill", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(saveToBlinko)
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.contentTintColor = NSColor.secondaryLabelColor
            button.hoverHandler = { [weak button] isHovered in
                button?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
            }
            button.toolTip = "保存到 Blinko"
            item.view = button
            
        case "createBlinkoFlash":
            item.label = "闪念"
            let button = HoverableButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
            button.image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: nil)
            button.target = self
            button.action = #selector(createBlinkoFlash)
            button.isBordered = true
            button.bezelStyle = .texturedRounded
            button.contentTintColor = NSColor.secondaryLabelColor
            button.hoverHandler = { [weak button] isHovered in
                button?.contentTintColor = isHovered ? NSColor.systemBlue : NSColor.secondaryLabelColor
            }
            button.toolTip = "创建 Blinko 闪念"
            item.view = button
            
        default:
            return nil
        }
        
        return item
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            // 本地笔记操作组
            NSToolbarItem.Identifier("defaultPath"),
            NSToolbarItem.Identifier("newNote"),
            NSToolbarItem.Identifier("selectNote"),
            .flexibleSpace,
            
            // 内容操作组
            NSToolbarItem.Identifier("saveContent"),
            NSToolbarItem.Identifier("rewriteContent"),
            .flexibleSpace,
            
            // Blinko 操作组
            NSToolbarItem.Identifier("syncToBlinko"),
            NSToolbarItem.Identifier("saveToBlinko"),
            NSToolbarItem.Identifier("createBlinkoFlash")
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("defaultPath"),
            NSToolbarItem.Identifier("newNote"),
            NSToolbarItem.Identifier("selectNote"),
            NSToolbarItem.Identifier("saveContent"),
            NSToolbarItem.Identifier("rewriteContent"),
            NSToolbarItem.Identifier("syncToBlinko"),
            NSToolbarItem.Identifier("saveToBlinko"),
            NSToolbarItem.Identifier("createBlinkoFlash"),
            .flexibleSpace
        ]
    }
}

// 添加 Blinko 笔记结构体
struct BlinkoNote: Codable {
    var id: Int
    var content: String
    var type: Int  // 0 - 闪念, 1 - 笔记
    var title: String
    
    static func extractTitle(from content: String) -> String {
        return content.components(separatedBy: .newlines).first ?? "无标题"
    }
}

// 添加 Blinko 管理器类
class BlinkoManager {
    static let shared = BlinkoManager()
    private let settingsURL: URL
    private var settings: [String: Any] = [:]
    
    // Blinko API 配置
    private var baseUrl: String
    private var apiToken: String
    
    // 笔记列表缓存
    private var noteListCache: [(id: Int, title: String)] = []
    
    // 三种不同的笔记设置
    var syncNoteId: Int {
        get { settings["syncNoteId"] as? Int ?? 0 }
        set {
            settings["syncNoteId"] = newValue
            saveSettings()
        }
    }
    
    var defaultNoteId: Int {
        get { settings["defaultNoteId"] as? Int ?? 0 }
        set {
            settings["defaultNoteId"] = newValue
            saveSettings()
        }
    }
    
    var currentNoteId: Int {
        get { settings["currentNoteId"] as? Int ?? 0 }
        set {
            settings["currentNoteId"] = newValue
            saveSettings()
        }
    }
    
    var syncNoteTitle: String {
        get { settings["syncNoteTitle"] as? String ?? "" }
        set {
            settings["syncNoteTitle"] = newValue
            saveSettings()
        }
    }
    
    var defaultNoteTitle: String {
        get { settings["defaultNoteTitle"] as? String ?? "" }
        set {
            settings["defaultNoteTitle"] = newValue
            saveSettings()
        }
    }
    
    var currentNoteTitle: String {
        get { settings["currentNoteTitle"] as? String ?? "" }
        set {
            settings["currentNoteTitle"] = newValue
            saveSettings()
        }
    }
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("AskPop")
        settingsURL = appFolder.appendingPathComponent("blinko_settings.json")
        
        // 从 PopClip 环境变量获取配置
        apiToken = ProcessInfo.processInfo.environment["POPCLIP_OPTION_BLINKO_TOKEN"] ?? ""
        baseUrl = ProcessInfo.processInfo.environment["POPCLIP_OPTION_BLINKO_BASE_URL"] ?? ""
        
        // 添加调试日志
        print("【调试】Blinko 初始化:")
        print("【调试】环境变量列表:")
        for (key, value) in ProcessInfo.processInfo.environment {
            if key.contains("BLINKO") || key.contains("blinko") {
                print("【调试】\(key): \(value)")
            }
        }
        print("【调试】Blinko Base URL: \(baseUrl)")
        print("【调试】Blinko Token 是否为空: \(apiToken.isEmpty ? "是" : "否")")
        if !apiToken.isEmpty {
            print("【调试】Blinko Token 前5个字符: \(apiToken.prefix(5))...")
        }
        
        // 创建应用程序文件夹
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        // 加载设置
        if let data = try? Data(contentsOf: settingsURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }
    }
    
    var lastNoteId: Int {
        get { settings["lastNoteId"] as? Int ?? 0 }
        set {
            settings["lastNoteId"] = newValue
            saveSettings()
        }
    }
    
    var lastNoteTitle: String {
        get { settings["lastNoteTitle"] as? String ?? "" }
        set {
            settings["lastNoteTitle"] = newValue
            saveSettings()
        }
    }
    
    private func saveSettings() {
        if let data = try? JSONSerialization.data(withJSONObject: settings) {
            try? data.write(to: settingsURL)
        }
    }
    
    // 构建正确的 API URL，避免路径重复
    private func buildAPIURL(endpoint: String) -> String {
        var apiUrl = baseUrl
        if apiUrl.hasSuffix("/") {
            apiUrl = String(apiUrl.dropLast())
        }
        
        if apiUrl.hasSuffix("/api/v1") {
            return "\(apiUrl)/\(endpoint)"
        } else {
            return "\(apiUrl)/api/v1/\(endpoint)"
        }
    }
    
    // 获取笔记列表
    func getNoteList() async throws -> [(id: Int, title: String)] {
        guard !apiToken.isEmpty else {
            print("【调试】getNoteList：API Token 为空")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未设置 Blinko API Token"])
        }

        let url = URL(string: buildAPIURL(endpoint: "note/list"))!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 调试日志：完整请求头
        print("【调试】请求 URL: \(url.absoluteString)")
        print("【调试】请求方法: \(request.httpMethod ?? "未知")")
        print("【调试】请求头:")
        request.allHTTPHeaderFields?.forEach { key, value in
            if key.lowercased() == "authorization" {
                print("【调试】\(key): Bearer [已隐藏Token]")
            } else {
                print("【调试】\(key): \(value)")
            }
        }
        
        let requestBody: [String: Any] = [
            "page": 1,
            "size": 100,  // 获取前100条笔记
            "orderBy": "desc",
            "type": 1,  // 只获取笔记类型
            "searchText": "",
            "isArchived": false,
            "isRecycle": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 调试日志：请求体
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print("【调试】请求体: \(bodyString)")
        }
        
        print("发送请求到 Blinko API: \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 HTTP 响应"])
        }
        
        print("收到响应状态码: \(httpResponse.statusCode)")
        
        // 调试日志：响应头
        print("【调试】响应头:")
        (httpResponse.allHeaderFields as? [String: Any])?.forEach { key, value in
            print("【调试】\(key): \(value)")
        }
        
        // 调试响应内容
        if let responseString = String(data: data, encoding: .utf8) {
            print("【调试】响应内容: \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // 尝试解析错误响应
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["message"] as? String {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API 错误: \(errorMessage)"])
            }
            throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API 请求失败: HTTP \(httpResponse.statusCode)"])
        }
        
        // 打印接收到的数据以便调试
        if let jsonString = String(data: data, encoding: .utf8) {
            print("收到的 JSON 数据: \(jsonString)")
        }
        
        do {
            // 直接解析为数组
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                noteListCache = jsonArray.compactMap { item in
                    guard let id = item["id"] as? Int,
                          let content = item["content"] as? String else {
                        return nil
                    }
                    
                    let title = BlinkoNote.extractTitle(from: content)
                    return (id, title)
                }
                
                print("成功解析 \(noteListCache.count) 条笔记")
                return noteListCache
            } else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "API 响应格式错误: 不是有效的笔记列表"])
            }
        } catch {
            print("JSON 解析错误: \(error)")
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析笔记列表失败: \(error.localizedDescription)"])
        }
    }
    
    func createNote(content: String, type: Int = 1) async throws -> BlinkoNote {
        guard !apiToken.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未设置 Blinko API Token"])
        }
        
        let url = URL(string: buildAPIURL(endpoint: "note/upsert"))!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let noteData: [String: Any] = [
            "content": content,
            "type": type
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: noteData)
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "创建笔记失败"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let id = json["id"] as? Int else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析响应失败"])
        }
        
        let note = BlinkoNote(id: id, content: content, type: type, title: BlinkoNote.extractTitle(from: content))
        lastNoteId = note.id
        lastNoteTitle = note.title
        return note
    }
    
    func updateNote(id: Int, content: String) async throws -> BlinkoNote {
        guard !apiToken.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未设置 Blinko API Token"])
        }
        
        let url = URL(string: buildAPIURL(endpoint: "note/upsert"))!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let noteData: [String: Any] = [
            "id": id,
            "content": content
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: noteData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "更新笔记失败"])
        }
        
        let note = BlinkoNote(id: id, content: content, type: 1, title: BlinkoNote.extractTitle(from: content))
        lastNoteId = note.id
        lastNoteTitle = note.title
        return note
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {

    static func main() {
        // 检查是否已有实例在运行
        let lockFilePath = NSTemporaryDirectory() + "AskPop.lock"
        let lockFileURL = URL(fileURLWithPath: lockFilePath)
        
        // 检查命令行参数
        let arguments = CommandLine.arguments
        print("Command line arguments: \(arguments)")
        
        // 如果有命令行参数，说明是被PopClip调用的
        if arguments.count > 1 {
            // 尝试发送通知给已存在的实例
            let notificationData: [String: Any] = [
                "prompt": arguments.count > 1 ? arguments[1] : "",
                "text": arguments.count > 2 ? arguments[2] : "",
                "timestamp": Date().timeIntervalSince1970
            ]
            
            // 发送分布式通知
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("AskPopShowWindow"),
                object: nil,
                userInfo: notificationData,
                deliverImmediately: true
            )
            
            // 等待一下让通知发送
            usleep(500000) // 0.5秒
            
            // 如果锁文件存在，说明有实例在运行，直接退出
            if FileManager.default.fileExists(atPath: lockFilePath) {
                print("Found existing instance, sent notification and exiting")
                exit(0)
            }
            
            // 如果没有实例在运行，继续启动
            print("No existing instance found, starting new instance")
        }
        
        // 创建锁文件
        do {
            try "AskPop".write(to: lockFileURL, atomically: true, encoding: .utf8)
            print("Created lock file at: \(lockFilePath)")
        } catch {
            print("Failed to create lock file: \(error)")
        }
        
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
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
    
    var statusItem: NSStatusItem?
    var historyWindowController: HistoryWindowController?
    var currentMode: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Application did finish launching.")
        NSApp.setActivationPolicy(.accessory)
        print("Activation policy set to .accessory")

        // 注册分布式通知监听
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowWindowNotification(_:)),
            name: NSNotification.Name("AskPopShowWindow"),
            object: nil
        )
        print("Registered for distributed notifications")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        print("Status item created.")
        
        if let button = statusItem?.button {
            // 尝试多种方式加载Logo
            var image: NSImage?
            
            // 方法1: 尝试从Bundle加载
            if let bundlePath = Bundle.main.path(forResource: "AskPopLogo", ofType: "png") {
                image = NSImage(byReferencingFile: bundlePath)
                print("Logo loaded from bundle: \(bundlePath)")
            }
            
            // 方法2: 尝试从可执行文件同目录加载
            if image == nil {
                let executablePath = Bundle.main.executablePath ?? ""
                let executableDir = (executablePath as NSString).deletingLastPathComponent
                let logoPath = (executableDir as NSString).appendingPathComponent("AskPopLogo.png")
                image = NSImage(byReferencingFile: logoPath)
                if image != nil {
                    print("Logo loaded from executable directory: \(logoPath)")
                }
            }
            
            // 方法3: 尝试从项目根目录加载（开发时使用）
            if image == nil {
                let currentDir = FileManager.default.currentDirectoryPath
                let logoPath = (currentDir as NSString).appendingPathComponent("AskPopLogo.png")
                image = NSImage(byReferencingFile: logoPath)
                if image != nil {
                    print("Logo loaded from current directory: \(logoPath)")
                }
            }
            
            if let logoImage = image {
                // 设置图标为模板图像，这样macOS会自动调整颜色
                logoImage.isTemplate = true
                
                // 设置正确的图标尺寸 - macOS状态栏图标标准尺寸
                logoImage.size = NSSize(width: 18, height: 18)
                
                // 确保图像支持高分辨率显示
                logoImage.resizingMode = .stretch
                
                // 创建一个新的NSImage来确保正确缩放
                let scaledImage = NSImage(size: NSSize(width: 18, height: 18))
                scaledImage.lockFocus()
                logoImage.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                scaledImage.unlockFocus()
                scaledImage.isTemplate = true
                
                button.image = scaledImage
                print("Status bar icon set successfully with size: \(scaledImage.size)")
            } else {
                button.title = "AskPop"
                print("Failed to load logo image, using title instead")
            }
        }
        
        let menu = NSMenu()
        menu.addItem(withTitle: "问答", action: #selector(showQAWindow), keyEquivalent: "")
        menu.addItem(withTitle: "翻译", action: #selector(showTranslationWindow), keyEquivalent: "")
        menu.addItem(withTitle: "历史记录", action: #selector(showHistoryWindow), keyEquivalent: "")
        menu.addItem(withTitle: "设置", action: #selector(showSettingsWindow), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        statusItem?.menu = menu
        print("Menu created and assigned to status item.")
        
        loadConfig()
        print("Config loaded.")
        
        HistoryManager.shared.loadHistory()
        print("History loaded.")
        
        // 检查命令行参数，如果是通过PopClip启动的，立即显示窗口
        handleCommandLineArguments()
    }

    func loadConfig() {
        // 先从设置文件加载
        let settings = SettingsManager.shared.settings
        self.apiKey = settings.apiKey
        self.apiURL = settings.apiURL
        self.model = settings.modelName
        self.temperature = settings.temperature

        // 然后用PopClip环境变量覆盖（如果存在）
        if let popclipApiKey = ProcessInfo.processInfo.environment["POPCLIP_OPTION_APIKEY"] {
            self.apiKey = popclipApiKey
        }
        if let popclipApiUrl = ProcessInfo.processInfo.environment["POPCLIP_OPTION_API_URL"] {
            self.apiURL = popclipApiUrl
        }
        if let popclipModel = ProcessInfo.processInfo.environment["POPCLIP_OPTION_MODEL"] {
            self.model = popclipModel
        }
        if let tempStr = ProcessInfo.processInfo.environment["POPCLIP_OPTION_TEMPERATURE"],
           let temp = Double(tempStr) {
            self.temperature = temp
        }
        
        if apiKey.isEmpty {
            print("API Key is not set.")
        }
    }
    
    // 获取问答提示词：优先使用PopClip传来的，否则使用设置中的
    func getQAPrompt() -> String {
        // 如果有PopClip传来的提示词，优先使用
        if let popclipPrompt = ProcessInfo.processInfo.environment["POPCLIP_OPTION_QA_PROMPT"] {
            return popclipPrompt
        }
        // 否则使用设置中的提示词
        return SettingsManager.shared.settings.qaPrompt
    }
    
    // 获取翻译提示词：优先使用PopClip传来的，否则使用设置中的
    func getTranslationPrompt() -> String {
        // 如果有PopClip传来的提示词，优先使用
        if let popclipPrompt = ProcessInfo.processInfo.environment["POPCLIP_OPTION_TRANSLATE_PROMPT"] {
            return popclipPrompt
        }
        // 否则使用设置中的提示词
        return SettingsManager.shared.settings.translatePrompt
    }

    @objc func showQAWindow() {
        createWindow(mode: "qa")
    }

    @objc func showTranslationWindow() {
        createWindow(mode: "translation")
    }

    @objc func showHistoryWindow() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController()
        }
        historyWindowController?.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettingsWindow() {
        let settingsWindowController = SettingsWindowController.shared
        // 刷新设置值以显示最新的内容
        settingsWindowController.refreshSettings()
        settingsWindowController.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 清理锁文件
        let lockFilePath = NSTemporaryDirectory() + "AskPop.lock"
        try? FileManager.default.removeItem(atPath: lockFilePath)
        print("Cleaned up lock file")
        
        // 移除分布式通知监听
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    @objc func handleShowWindowNotification(_ notification: Notification) {
        print("Received distributed notification: \(notification)")
        
        guard let userInfo = notification.userInfo,
              let prompt = userInfo["prompt"] as? String,
              let text = userInfo["text"] as? String else {
            print("Invalid notification data")
            return
        }
        
        print("Notification data - prompt: \(prompt), text: \(text)")
        
        // 在主线程上处理UI操作
        DispatchQueue.main.async { [weak self] in
            self?.processPopClipRequest(prompt: prompt, text: text)
        }
    }
    
    func handleCommandLineArguments() {
        let arguments = CommandLine.arguments
        
        // 如果有命令行参数，说明是被PopClip调用的
        if arguments.count > 2 {
            let prompt = arguments[1]
            let text = arguments[2]
            print("Processing command line args - prompt: \(prompt), text: \(text)")
            processPopClipRequest(prompt: prompt, text: text)
        }
    }
    
    func processPopClipRequest(prompt: String, text: String) {
        print("Processing PopClip request with prompt: \(prompt)")
        
        // 解码text（如果是base64编码的）
        var decodedText = text
        if text.hasPrefix("base64:") {
            let base64String = String(text.dropFirst(7)) // 移除 "base64:" 前缀
            if let data = Data(base64Encoded: base64String),
               let decoded = String(data: data, encoding: .utf8) {
                decodedText = decoded
                print("Decoded base64 text: \(decodedText)")
            }
        }
        
        // 根据提示词判断模式
        var mode = "qa"
        if prompt.contains("翻译") || prompt.contains("translate") || prompt.contains("translator") {
            mode = "translation"
        } else if prompt.contains("笔记") || prompt.contains("note") {
            mode = "note"
        }
        
        // 确定最终使用的提示词（优先使用PopClip传来的，但如果是空的或默认的，则使用设置中的）
        var finalPrompt = prompt
        if mode == "qa" && (prompt.isEmpty || prompt == "你是一个有用的AI助手，请用中文回答：") {
            finalPrompt = getQAPrompt()
        } else if mode == "translation" && (prompt.isEmpty || prompt == "你是一位专业的中英互译翻译官，请把中文译成英文，英文译成中文") {
            finalPrompt = getTranslationPrompt()
        }
        
        print("Determined mode: \(mode), final prompt: \(finalPrompt)")
        
        // 如果已有窗口，复用现有窗口；否则创建新窗口
        if let existingWindow = self.window, existingWindow.isVisible {
            print("Reusing existing window")
            // 复用现有窗口，但更新内容
            self.currentMode = mode
            
            // 清除当前对话（可选）
            self.messages = [["role": "system", "content": finalPrompt]]
            self.systemPrompt = finalPrompt
            
            // 更新输入框内容
            if let inputField = self.inputField {
                inputField.stringValue = decodedText
            }
            
            // 清除WebView内容并重新加载空白状态
            if let webView = self.webView {
                let emptyHTML = """
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
                    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
                    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
                    <style>
                        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; padding: 12px; margin: 0; background: transparent; }
                        .conversation-list { display: flex; flex-direction: column; gap: 4px; }
                    </style>
                </head>
                <body>
                    <div id="conversation-list" class="conversation-list"></div>
                    <script>
                        function appendMessage(role, content) { 
                            const conversationList = document.getElementById('conversation-list');
                            const messageDiv = document.createElement('div');
                            messageDiv.innerHTML = content;
                            conversationList.appendChild(messageDiv);
                        }
                    </script>
                </body>
                </html>
                """
                webView.loadHTMLString(emptyHTML, baseURL: nil)
            }
            
            // 激活窗口
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            
            // 自动发送请求
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.sendMessage()
            }
        } else {
            print("Creating new window")
            // 创建新窗口
            createWindow(mode: mode)
            
            // 如果窗口创建成功，自动输入文本并发送请求
            if let window = self.window, let inputField = self.inputField {
                // 设置系统提示词
                self.systemPrompt = finalPrompt
                self.messages = [["role": "system", "content": finalPrompt]]
                
                // 自动输入用户文本
                inputField.stringValue = decodedText
                
                // 激活应用并显示窗口
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                
                // 自动发送请求
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.sendMessage()
                }
            }
        }
    }
    
    func createWindow(mode: String) {
        self.currentMode = mode
        
        print("创建窗口...")
        
        // 创建面板
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
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

        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        panel.representedURL = nil
        panel.representedFilename = ""
        panel.isDocumentEdited = false
        
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true
        
        let titlebarVisualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: panel.contentView!.frame.height - 30, width: panel.contentView!.frame.width, height: 30))
        titlebarVisualEffect.material = .windowBackground
        titlebarVisualEffect.blendingMode = .behindWindow
        titlebarVisualEffect.state = .active
        titlebarVisualEffect.autoresizingMask = [.width, .minYMargin]
        panel.contentView?.addSubview(titlebarVisualEffect)
        
        let titleLabel = NSTextField(frame: NSRect(x: 12, y: 0, width: 200, height: 30))
        
        let titleText: String
        switch mode {
        case "qa":
            titleText = "AI助手 - 问答"
            systemPrompt = getQAPrompt()
        case "translation":
            titleText = "AI助手 - 翻译"
            systemPrompt = getTranslationPrompt()
        default:
            titleText = "AI助手"
            systemPrompt = getQAPrompt()
        }
        titleLabel.stringValue = titleText
        messages = [["role": "system", "content": systemPrompt]]
        
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
        
        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: titlebarVisualEffect.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titlebarVisualEffect.leadingAnchor, constant: 8),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
        ])
        
        let titlebarButtonContainer = NSStackView(frame: NSRect(x: titlebarVisualEffect.frame.width - 127, y: 2, width: 129, height: 26))
        titlebarButtonContainer.orientation = .horizontal
        titlebarButtonContainer.spacing = -2
        titlebarButtonContainer.distribution = .fillEqually
        titlebarButtonContainer.alignment = .centerY
        titlebarButtonContainer.autoresizingMask = [.minXMargin]
        titlebarVisualEffect.addSubview(titlebarButtonContainer)
        self.titlebarButtonContainer = titlebarButtonContainer
        
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
        // 清理所有HoverableButton的tooltip
        if let titlebarButtonContainer = self.titlebarButtonContainer {
            for subview in titlebarButtonContainer.arrangedSubviews {
                if let hoverableButton = subview as? HoverableButton {
                    // 强制隐藏所有tooltip和feedback
                    hoverableButton.clearTooltips()
                }
            }
        }
        
        self.window?.close()
    }
    
    @objc func sendMessage() {
        guard let text = inputField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        
        let messageText: String
        if self.currentMode == "translation" {
            messageText = "翻译: \(text)"
        } else {
            messageText = text
        }
        
        messages.append(["role": "user", "content": messageText])
        inputField?.stringValue = ""
        
        if let webView = self.webView {
            let script = """
                appendMessage('user', `\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`, false);
            """
            webView.evaluateJavaScript(script)
        }
        
        callAPI(withPrompt: "", text: messageText)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView 加载完成")
        for message in messages {
            if message["role"] == "system" { continue }
            
            var displayContent = message["content"] ?? ""
            if message["role"] == "user" && self.currentMode == "translation" {
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
                    await MainActor.run {
                        updateLastMessage()
                    }
                }
            } catch {
                print("API 调用失败：\(error)")
                await MainActor.run {
                    if let webView = self.webView {
                        let errorMessage = "API 调用失败：\(error.localizedDescription)"
                        let script = """
                            appendMessage('error', `\(errorMessage.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`, false);
                        """
                        webView.evaluateJavaScript(script)
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
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "请在设置中填写 API 密钥"])
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

    @objc func handleLocalNoteGroup(_ sender: NSSegmentedControl) {
        guard let noteWindowController = noteWindowController else { return }
        
        switch sender.selectedSegment {
        case 0:
            noteWindowController.createNewNote()
        case 1:
            noteWindowController.selectNote()
        case 2:
            noteWindowController.selectDefaultPath()
        default:
            break
        }
    }

    @objc func handleContentGroup(_ sender: NSSegmentedControl) {
        guard let noteWindowController = noteWindowController else { return }
        
        switch sender.selectedSegment {
        case 0:
            noteWindowController.saveContent()
        case 1:
            noteWindowController.rewriteContent()
        default:
            break
        }
    }

    @objc func handleBlinkoGroup(_ sender: NSSegmentedControl) {
        guard let noteWindowController = noteWindowController else { return }
        
        switch sender.selectedSegment {
        case 0:
            noteWindowController.syncToBlinko()
        case 1:
            noteWindowController.saveToBlinko()
        case 2:
            noteWindowController.createBlinkoFlash()
        default:
            break
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        currentTask?.cancel()
        HistoryManager.shared.addEntry(mode: currentMode, messages: messages)
        clearHistory()
        self.window = nil
    }
}

struct HistoryEntry: Codable {
    let id: UUID
    let timestamp: Date
    let mode: String
    let messages: [[String: String]]
}

class HistoryManager {
    static let shared = HistoryManager()
    private let historyURL: URL
    private(set) var history: [HistoryEntry] = []

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("AskPop")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        historyURL = appFolder.appendingPathComponent("history.json")
    }

    func loadHistory() {
        if let data = try? Data(contentsOf: historyURL),
           let loadedHistory = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = loadedHistory.sorted(by: { $0.timestamp > $1.timestamp })
        }
        // 加载完成后立即清理过期记录
        cleanupOldEntries()
    }

    func saveHistory() {
        let sortedHistory = history.sorted(by: { $0.timestamp > $1.timestamp })
        try? JSONEncoder().encode(sortedHistory).write(to: historyURL)
    }

    func addEntry(mode: String, messages: [[String: String]]) {
        if messages.count <= 1 { return } // Don't save empty conversations
        let entry = HistoryEntry(id: UUID(), timestamp: Date(), mode: mode, messages: messages)
        history.insert(entry, at: 0)
        saveHistory()
        
        // 通知历史窗口更新
        NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
        
        // 通知历史窗口更新
        NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
    }
    
    func deleteEntry(withId id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
        
        // 通知历史窗口更新
        NotificationCenter.default.post(name: .historyDidUpdate, object: nil)
    }
    
    func cleanupOldEntries() {
        let settings = SettingsManager.shared.settings
        guard settings.autoDeleteDays > 0 else { return }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -settings.autoDeleteDays, to: Date()) ?? Date()
        let oldCount = history.count
        
        history.removeAll { entry in
            entry.timestamp < cutoffDate
        }
        
        if history.count != oldCount {
            saveHistory()
            print("清理了 \(oldCount - history.count) 条过期历史记录")
        }
    }
}

class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var tableView: NSTableView!
    private var detailWebView: WKWebView!
    private var splitView: NSSplitView!
    private var searchField: NSSearchField!
    private var filterButton: NSPopUpButton!
    private var history: [HistoryEntry] = []
    private var filteredHistory: [HistoryEntry] = []
    private var selectedEntry: HistoryEntry?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "历史记录"
        window.minSize = NSSize(width: 800, height: 500)
        self.init(window: window)
        setupUI()
        loadHistory()
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // 创建工具栏
        let toolbarView = NSView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolbarView)
        
        // 搜索框
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索对话历史..."
        searchField.target = self
        searchField.action = #selector(searchTextChanged)
        toolbarView.addSubview(searchField)
        
        // 过滤按钮
        filterButton = NSPopUpButton()
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        filterButton.addItems(withTitles: ["全部", "问答", "翻译", "笔记"])
        filterButton.target = self
        filterButton.action = #selector(filterChanged)
        toolbarView.addSubview(filterButton)
        
        // 清除历史按钮
        let clearButton = NSButton(title: "清除历史", target: self, action: #selector(clearHistory))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .rounded
        toolbarView.addSubview(clearButton)
        
        // 分割视图
        splitView = NSSplitView()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        contentView.addSubview(splitView)
        
        // 左侧：历史记录列表
        let leftPanel = NSView()
        leftPanel.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        tableView = NSTableView()
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.rowHeight = 80
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none  // 禁用默认选中高亮
        tableView.allowsEmptySelection = true
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HistoryColumn"))
        column.title = "对话历史"
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        
        // 添加右键菜单
        let menu = NSMenu()
        let deleteItem = NSMenuItem(title: "删除此记录", action: #selector(deleteSelectedItem), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        tableView.menu = menu
        
        scrollView.documentView = tableView
        leftPanel.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: leftPanel.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor)
        ])
        
        // 右侧：对话详情
        let rightPanel = NSView()
        rightPanel.translatesAutoresizingMaskIntoConstraints = false
        
        // 创建详情视图的WebView
        let webConfig = WKWebViewConfiguration()
        detailWebView = WKWebView(frame: .zero, configuration: webConfig)
        detailWebView.translatesAutoresizingMaskIntoConstraints = false
        detailWebView.setValue(false, forKey: "drawsBackground")
        rightPanel.addSubview(detailWebView)
        
        NSLayoutConstraint.activate([
            detailWebView.topAnchor.constraint(equalTo: rightPanel.topAnchor),
            detailWebView.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            detailWebView.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            detailWebView.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor)
        ])
        
        // 添加面板到分割视图
        splitView.addArrangedSubview(leftPanel)
        splitView.addArrangedSubview(rightPanel)
        
        // 设置分割视图比例
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 1)
        
        // 布局约束
        NSLayoutConstraint.activate([
            // 工具栏
            toolbarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            toolbarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            toolbarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            toolbarView.heightAnchor.constraint(equalToConstant: 30),
            
            // 工具栏内容
            searchField.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 200),
            
            filterButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 10),
            filterButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            filterButton.widthAnchor.constraint(equalToConstant: 80),
            
            clearButton.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor),
            clearButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            
            // 分割视图
            splitView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor, constant: 10),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            
            // 左侧面板最小宽度
            leftPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        
        // 设置初始分割比例
        DispatchQueue.main.async {
            self.splitView.setPosition(260, ofDividerAt: 0)
        }
        
        // 加载空白状态
        loadEmptyDetailView()
        
        // 监听历史记录更新通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyDidUpdate),
            name: .historyDidUpdate,
            object: nil
        )
    }
    
    @objc func historyDidUpdate() {
        DispatchQueue.main.async {
            self.loadHistory()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func loadHistory() {
        self.history = HistoryManager.shared.history
        self.filteredHistory = self.history
        tableView.reloadData()
    }
    
    @objc func searchTextChanged() {
        filterHistory()
    }
    
    @objc func filterChanged() {
        filterHistory()
    }
    
    @objc func deleteSelectedItem() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < filteredHistory.count else { return }
        
        let entry = filteredHistory[selectedRow]
        
        let alert = NSAlert()
        alert.messageText = "确认删除此记录"
        alert.informativeText = "此操作将删除选中的对话记录，且无法恢复。"
        alert.addButton(withTitle: "确认")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            HistoryManager.shared.deleteEntry(withId: entry.id)
        }
    }
    
    @objc func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "确认清除历史记录"
        alert.informativeText = "此操作将删除所有对话历史记录，且无法恢复。"
        alert.addButton(withTitle: "确认")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            HistoryManager.shared.clearHistory()
            loadHistory()
            loadEmptyDetailView()
        }
    }
    
    func filterHistory() {
        let searchText = searchField.stringValue.lowercased()
        let selectedFilter = filterButton.indexOfSelectedItem
        
        filteredHistory = history.filter { entry in
            // 过滤模式
            var matchesFilter = true
            switch selectedFilter {
            case 1: matchesFilter = entry.mode == "qa"
            case 2: matchesFilter = entry.mode == "translation"  
            case 3: matchesFilter = entry.mode == "note"
            default: matchesFilter = true
            }
            
            // 搜索文本
            var matchesSearch = true
            if !searchText.isEmpty {
                let allContent = entry.messages.compactMap { $0["content"] }.joined(separator: " ").lowercased()
                matchesSearch = allContent.contains(searchText)
            }
            
            return matchesFilter && matchesSearch
        }
        
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredHistory.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredHistory[row]
        let cellIdentifier = NSUserInterfaceItemIdentifier("HistoryCell")
        
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil)
        if cell == nil {
            cell = createHistoryCell()
            cell?.identifier = cellIdentifier
        }
        
        updateHistoryCell(cell!, with: entry)
        return cell
    }
    
    func createHistoryCell() -> NSView {
        let cell = NSView()
        cell.wantsLayer = true
        cell.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cell.layer?.cornerRadius = 6
        
        // 创建一个容器视图来避免选中高亮影响文字显示
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(containerView)
        
        // 模式标签
        let modeLabel = NSTextField()
        modeLabel.identifier = NSUserInterfaceItemIdentifier("modeLabel")
        modeLabel.isEditable = false
        modeLabel.isBordered = false
        modeLabel.backgroundColor = .clear
        modeLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        modeLabel.textColor = .white
        modeLabel.alignment = .center
        modeLabel.wantsLayer = true
        modeLabel.layer?.cornerRadius = 8
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(modeLabel)
        
        // 时间标签
        let timeLabel = NSTextField()
        timeLabel.identifier = NSUserInterfaceItemIdentifier("timeLabel")
        timeLabel.isEditable = false
        timeLabel.isBordered = false
        timeLabel.backgroundColor = .clear
        timeLabel.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(timeLabel)
        
        // 预览标签
        let previewLabel = NSTextField()
        previewLabel.identifier = NSUserInterfaceItemIdentifier("previewLabel")
        previewLabel.isEditable = false
        previewLabel.isBordered = false
        previewLabel.backgroundColor = .clear
        previewLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        previewLabel.textColor = .labelColor
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.maximumNumberOfLines = 2
        previewLabel.cell?.wraps = true
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(previewLabel)
        
        NSLayoutConstraint.activate([
            // 容器视图约束 - 填满整个cell
            containerView.topAnchor.constraint(equalTo: cell.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
            
            // 模式标签 - 左上角小徽章
            modeLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 6),
            modeLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            modeLabel.widthAnchor.constraint(equalToConstant: 32),
            modeLabel.heightAnchor.constraint(equalToConstant: 16),
            
            // 时间标签 - 右上角
            timeLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 6),
            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: modeLabel.trailingAnchor, constant: 4),
            
            // 预览文本 - 下方两行
            previewLabel.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 4),
            previewLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            previewLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -6)
        ])
        
        return cell
    }
    
    func updateHistoryCell(_ cell: NSView, with entry: HistoryEntry) {
        // 找到容器视图
        guard let containerView = cell.subviews.first,
              let modeLabel = containerView.subviews.first(where: { $0.identifier?.rawValue == "modeLabel" }) as? NSTextField,
              let timeLabel = containerView.subviews.first(where: { $0.identifier?.rawValue == "timeLabel" }) as? NSTextField,
              let previewLabel = containerView.subviews.first(where: { $0.identifier?.rawValue == "previewLabel" }) as? NSTextField else {
            return
        }
        
        // 设置模式标签
        switch entry.mode {
        case "qa":
            modeLabel.stringValue = "问答"
            modeLabel.layer?.backgroundColor = NSColor.systemBlue.cgColor
        case "translation":
            modeLabel.stringValue = "翻译"
            modeLabel.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case "note":
            modeLabel.stringValue = "笔记"
            modeLabel.layer?.backgroundColor = NSColor.systemOrange.cgColor
        default:
            modeLabel.stringValue = "其他"
            modeLabel.layer?.backgroundColor = NSColor.systemGray.cgColor
        }
        
        // 设置时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        timeLabel.stringValue = dateFormatter.string(from: entry.timestamp)
        
        // 设置预览文本
        let userMessage = entry.messages.first(where: { $0["role"] == "user" })?["content"] ?? ""
        let preview = userMessage.count > 100 ? String(userMessage.prefix(100)) + "..." : userMessage
        previewLabel.stringValue = preview.isEmpty ? "空对话" : preview
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 50  // 设置固定行高为50像素
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        
        // 更新所有cell的选中状态显示
        for i in 0..<tableView.numberOfRows {
            if let cell = tableView.view(atColumn: 0, row: i, makeIfNecessary: false) {
                updateCellSelection(cell, isSelected: i == selectedRow)
            }
        }
        
        if selectedRow >= 0 && selectedRow < filteredHistory.count {
            selectedEntry = filteredHistory[selectedRow]
            loadDetailView(for: selectedEntry!)
        } else {
            selectedEntry = nil
            loadEmptyDetailView()
        }
    }
    
    func updateCellSelection(_ cell: NSView, isSelected: Bool) {
        // 更新cell的选中状态外观
        if isSelected {
            cell.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.1).cgColor
        } else {
            cell.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
    
    func loadDetailView(for entry: HistoryEntry) {
        let html = generateDetailHTML(for: entry)
        detailWebView.loadHTMLString(html, baseURL: nil)
    }
    
    func loadEmptyDetailView() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    margin: 0;
                    padding: 40px;
                    text-align: center;
                    color: #888;
                    background: transparent;
                }
                .empty-state {
                    margin-top: 100px;
                }
                .empty-icon {
                    font-size: 64px;
                    margin-bottom: 20px;
                }
                h2 {
                    color: #666;
                    font-weight: 300;
                }
            </style>
        </head>
        <body>
            <div class="empty-state">
                <div class="empty-icon">💬</div>
                <h2>选择一个对话查看详细内容</h2>
                <p>点击左侧的历史记录以查看完整对话</p>
            </div>
        </body>
        </html>
        """
        detailWebView.loadHTMLString(html, baseURL: nil)
    }
    
    func generateDetailHTML(for entry: HistoryEntry) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .medium
        let dateString = dateFormatter.string(from: entry.timestamp)
        
        let modeString = entry.mode == "qa" ? "问答" : (entry.mode == "translation" ? "翻译" : "笔记")
        let modeColor = entry.mode == "qa" ? "#007AFF" : (entry.mode == "translation" ? "#34C759" : "#FF9500")
        
        var messagesHTML = ""
        for message in entry.messages {
            guard let role = message["role"], let content = message["content"] else { continue }
            
            if role == "system" { continue } // 跳过系统消息
            
            let isUser = role == "user"
            let roleText = isUser ? "用户" : "AI助手"
            let roleColor = isUser ? "#007AFF" : "#34C759"
            let alignClass = isUser ? "user-message" : "ai-message"
            
            // 处理内容中的换行和特殊字符
            let escapedContent = content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            
            messagesHTML += """
            <div class="message \(alignClass)">
                <div class="message-header">
                    <span class="role" style="color: \(roleColor);">\(roleText)</span>
                </div>
                <div class="message-content">\(escapedContent)</div>
            </div>
            """
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    line-height: 1.6;
                    margin: 0;
                    padding: 20px;
                    background: transparent;
                    color: #333;
                }
                .header {
                    border-bottom: 1px solid #eee;
                    padding-bottom: 15px;
                    margin-bottom: 20px;
                }
                .mode-badge {
                    display: inline-block;
                    background: \(modeColor);
                    color: white;
                    padding: 4px 12px;
                    border-radius: 12px;
                    font-size: 12px;
                    font-weight: 500;
                    margin-bottom: 10px;
                }
                .date {
                    color: #666;
                    font-size: 14px;
                }
                .messages {
                    max-width: 100%;
                }
                .message {
                    margin-bottom: 20px;
                    padding: 15px;
                    border-radius: 12px;
                    max-width: 80%;
                }
                .user-message {
                    background: #E3F2FD;
                    margin-left: auto;
                    text-align: right;
                }
                .ai-message {
                    background: #F1F8E9;
                    margin-right: auto;
                }
                .message-header {
                    font-size: 12px;
                    font-weight: 600;
                    margin-bottom: 8px;
                }
                .message-content {
                    font-size: 14px;
                    word-wrap: break-word;
                }
                .role {
                    font-weight: 600;
                }
            </style>
        </head>
        <body>
            <div class="header">
                <div class="mode-badge">\(modeString)</div>
                <div class="date">\(dateString)</div>
            </div>
            <div class="messages">
                \(messagesHTML)
            </div>
        </body>
        </html>
        """
    }
}

struct AppSettings: Codable {
    var apiKey: String
    var apiURL: String
    var autoDeleteDays: Int = 0 // 自动删除天数，0表示不自动删除
    var modelName: String = "gpt-3.5-turbo"
    var temperature: Double = 0.7
    var qaPrompt: String = "你是一个有用的AI助手，请用中文回答："
    var translatePrompt: String = "你是一位专业的中英互译翻译官，请把中文译成英文，英文译成中文"
}

class SettingsManager {
    static let shared = SettingsManager()
    private let settingsURL: URL
    var settings: AppSettings

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("AskPop")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        settingsURL = appFolder.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: settingsURL),
           let loadedSettings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = loadedSettings
        } else {
            settings = AppSettings(
                apiKey: "", 
                apiURL: "https://aihubmix.com/v1/chat/completions",
                autoDeleteDays: 0,
                modelName: "gpt-3.5-turbo",
                temperature: 0.7,
                qaPrompt: "你是一个有用的AI助手，请用中文回答：",
                translatePrompt: "你是一位专业的中英互译翻译官，请把中文译成英文，英文译成中文"
            )
        }
    }

    func saveSettings() throws {
        let data = try JSONEncoder().encode(settings)
        try data.write(to: settingsURL)
    }
    
    @discardableResult
    func saveSettingsWithResult() -> Bool {
        do {
            try saveSettings()
            return true
        } catch {
            print("保存设置失败: \(error)")
            return false
        }
    }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private var apiKeyField: EditableTextField!
    private var apiURLField: EditableTextField!
    private var autoDeletePopUp: NSPopUpButton!
    private var modelField: EditableTextField!
    private var temperatureField: EditableTextField!
    private var qaPromptField: EditableTextField!
    private var translatePromptField: EditableTextField!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 550),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "AskPop 设置"
        window.minSize = NSSize(width: 600, height: 550)
        
        // 设置现代化的窗口外观
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor.windowBackgroundColor
        
        super.init(window: window)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupUI() {
        let contentView = NSView(frame: window!.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        
        // 添加背景视觉效果
        let backgroundView = NSVisualEffectView(frame: contentView.bounds)
        backgroundView.material = .windowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.autoresizingMask = [.width, .height]
        contentView.addSubview(backgroundView)

        // 每次都重新获取最新的设置值
        let settings = SettingsManager.shared.settings
        
        // 创建滚动视图来支持更多内容
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 80, width: contentView.frame.width, height: contentView.frame.height - 80))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        contentView.addSubview(scrollView)
        
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: max(600, scrollView.contentSize.width), height: 700))
        documentView.autoresizingMask = [.width]
        scrollView.documentView = documentView
        
        let margin: CGFloat = 30
        let labelWidth: CGFloat = 140
        let fieldWidth: CGFloat = 400
        let rowHeight: CGFloat = 90
        let sectionGap: CGFloat = 40
        var currentY: CGFloat = documentView.frame.height - 30
        
        // 标题
        let titleLabel = NSTextField(labelWithString: "AskPop 配置设置")
        titleLabel.frame = NSRect(x: margin, y: currentY, width: 300, height: 28)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 22)
        titleLabel.textColor = .labelColor
        documentView.addSubview(titleLabel)
        currentY -= 40
        
        // API 配置分组
        let apiGroupLabel = NSTextField(labelWithString: "API 配置")
        apiGroupLabel.frame = NSRect(x: margin, y: currentY, width: 200, height: 20)
        apiGroupLabel.font = NSFont.boldSystemFont(ofSize: 16)
        apiGroupLabel.textColor = .secondaryLabelColor
        documentView.addSubview(apiGroupLabel)
        currentY -= 30
        
        // API Key
        let apiKeyLabel = NSTextField(labelWithString: "API Key:")
        apiKeyLabel.frame = NSRect(x: margin, y: currentY, width: labelWidth, height: 20)
        apiKeyLabel.font = NSFont.systemFont(ofSize: 14)
        documentView.addSubview(apiKeyLabel)
        
        let apiKeyDesc = NSTextField(labelWithString: "OpenAI 或其他兼容服务的 API 密钥")
        apiKeyDesc.frame = NSRect(x: margin, y: currentY - 18, width: 350, height: 16)
        apiKeyDesc.font = NSFont.systemFont(ofSize: 11)
        apiKeyDesc.textColor = .tertiaryLabelColor
        documentView.addSubview(apiKeyDesc)

        apiKeyField = EditableTextField(frame: NSRect(x: margin + labelWidth + 10, y: currentY - 35, width: fieldWidth, height: 44))
        apiKeyField.stringValue = settings.apiKey
        apiKeyField.placeholderString = "请输入您的 API Key"
        apiKeyField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        apiKeyField.bezelStyle = .roundedBezel
        apiKeyField.autoresizingMask = [.width]
        apiKeyField.alignment = .left
        documentView.addSubview(apiKeyField)
        currentY -= rowHeight

        // API URL
        let apiURLLabel = NSTextField(labelWithString: "API URL:")
        apiURLLabel.frame = NSRect(x: margin, y: currentY, width: labelWidth, height: 20)
        apiURLLabel.font = NSFont.systemFont(ofSize: 14)
        documentView.addSubview(apiURLLabel)
        
        let apiURLDesc = NSTextField(labelWithString: "API 服务的完整地址")
        apiURLDesc.frame = NSRect(x: margin, y: currentY - 18, width: 350, height: 16)
        apiURLDesc.font = NSFont.systemFont(ofSize: 11)
        apiURLDesc.textColor = .tertiaryLabelColor
        documentView.addSubview(apiURLDesc)

        apiURLField = EditableTextField(frame: NSRect(x: margin + labelWidth + 10, y: currentY - 35, width: fieldWidth, height: 44))
        apiURLField.stringValue = settings.apiURL
        apiURLField.placeholderString = "https://api.openai.com/v1/chat/completions"
        apiURLField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        apiURLField.bezelStyle = .roundedBezel
        apiURLField.autoresizingMask = [.width]
        apiURLField.alignment = .left
        documentView.addSubview(apiURLField)
        currentY -= sectionGap

        // 模型配置分组
        let modelGroupLabel = NSTextField(labelWithString: "模型配置")
        modelGroupLabel.frame = NSRect(x: margin, y: currentY, width: 200, height: 20)
        modelGroupLabel.font = NSFont.boldSystemFont(ofSize: 16)
        modelGroupLabel.textColor = .secondaryLabelColor
        documentView.addSubview(modelGroupLabel)
        currentY -= 30

        // Model
        let modelLabel = NSTextField(labelWithString: "AI 模型:")
        modelLabel.frame = NSRect(x: margin, y: currentY, width: labelWidth, height: 20)
        modelLabel.font = NSFont.systemFont(ofSize: 14)
        documentView.addSubview(modelLabel)
        
        let modelDesc = NSTextField(labelWithString: "使用的 AI 模型名称")
        modelDesc.frame = NSRect(x: margin, y: currentY - 18, width: 350, height: 16)
        modelDesc.font = NSFont.systemFont(ofSize: 11)
        modelDesc.textColor = .tertiaryLabelColor
        documentView.addSubview(modelDesc)

        modelField = EditableTextField(frame: NSRect(x: margin + labelWidth + 10, y: currentY - 35, width: fieldWidth, height: 44))
        modelField.stringValue = settings.modelName
        modelField.placeholderString = "gpt-3.5-turbo, gpt-4, deepseek-chat"
        modelField.font = NSFont.systemFont(ofSize: 14)
        modelField.bezelStyle = .roundedBezel
        modelField.autoresizingMask = [.width]
        modelField.alignment = .left
        documentView.addSubview(modelField)
        currentY -= rowHeight

        // Temperature
        let temperatureLabel = NSTextField(labelWithString: "创造性温度:")
        temperatureLabel.frame = NSRect(x: margin, y: currentY, width: labelWidth, height: 20)
        temperatureLabel.font = NSFont.systemFont(ofSize: 14)
        documentView.addSubview(temperatureLabel)
        
        let temperatureDesc = NSTextField(labelWithString: "控制回答的随机性，0.0-2.0，越高越有创意")
        temperatureDesc.frame = NSRect(x: margin, y: currentY - 18, width: 350, height: 16)
        temperatureDesc.font = NSFont.systemFont(ofSize: 11)
        temperatureDesc.textColor = .tertiaryLabelColor
        documentView.addSubview(temperatureDesc)

        temperatureField = EditableTextField(frame: NSRect(x: margin + labelWidth + 10, y: currentY - 35, width: 150, height: 44))
        temperatureField.stringValue = String(settings.temperature)
        temperatureField.placeholderString = "0.7"
        temperatureField.font = NSFont.systemFont(ofSize: 14)
        temperatureField.bezelStyle = .roundedBezel
        temperatureField.alignment = .center
        documentView.addSubview(temperatureField)
        currentY -= sectionGap

        // 提示词配置分组
        let promptGroupLabel = NSTextField(labelWithString: "提示词配置")
        promptGroupLabel.frame = NSRect(x: margin, y: currentY, width: 200, height: 20)
        promptGroupLabel.font = NSFont.boldSystemFont(ofSize: 16)
        promptGroupLabel.textColor = .secondaryLabelColor
        documentView.addSubview(promptGroupLabel)
        currentY -= 30

        // Q&A Prompt
        let qaPromptLabel = NSTextField(labelWithString: "问答提示词:")
        qaPromptLabel.frame = NSRect(x: margin, y: currentY, width: labelWidth, height: 20)
        qaPromptLabel.font = NSFont.systemFont(ofSize: 14)
        documentView.addSubview(qaPromptLabel)
        
        let qaPromptDesc = NSTextField(labelWithString: "问答模式的系统提示词")
        qaPromptDesc.frame = NSRect(x: margin, y: currentY - 18, width: 350, height: 16)
        qaPromptDesc.font = NSFont.systemFont(ofSize: 11)
        qaPromptDesc.textColor = .tertiaryLabelColor
        documentView.addSubview(qaPromptDesc)

        qaPromptField = EditableTextField(frame: NSRect(x: margin + labelWidth + 10, y: currentY - 35, width: fieldWidth, height: 44))
        qaPromptField.stringValue = settings.qaPrompt
        qaPromptField.placeholderString = "你是一个有用的AI助手，请用中文回答："
        qaPromptField.font = NSFont.systemFont(ofSize: 14)
        qaPromptField.bezelStyle = .roundedBezel
        qaPromptField.autoresizingMask = [.width]
        qaPromptField.alignment = .left
        documentView.addSubview(qaPromptField)
        currentY -= rowHeight

        // Translation Prompt
        let translatePromptLabel = NSTextField(labelWithString: "翻译提示词:")
        translatePromptLabel.frame = NSRect(x: margin, y: currentY, width: labelWidth, height: 20)
        translatePromptLabel.font = NSFont.systemFont(ofSize: 14)
        documentView.addSubview(translatePromptLabel)
        
        let translatePromptDesc = NSTextField(labelWithString: "翻译模式的系统提示词")
        translatePromptDesc.frame = NSRect(x: margin, y: currentY - 18, width: 350, height: 16)
        translatePromptDesc.font = NSFont.systemFont(ofSize: 11)
        translatePromptDesc.textColor = .tertiaryLabelColor
        documentView.addSubview(translatePromptDesc)

        translatePromptField = EditableTextField(frame: NSRect(x: margin + labelWidth + 10, y: currentY - 35, width: fieldWidth, height: 44))
        translatePromptField.stringValue = settings.translatePrompt
        translatePromptField.placeholderString = "你是一位专业的中英互译翻译官"
        translatePromptField.font = NSFont.systemFont(ofSize: 14)
        translatePromptField.bezelStyle = .roundedBezel
        translatePromptField.autoresizingMask = [.width]
        translatePromptField.alignment = .left
        documentView.addSubview(translatePromptField)
        currentY -= sectionGap

        // 历史记录配置分组
        let historyGroupLabel = NSTextField(labelWithString: "历史记录管理")
        historyGroupLabel.frame = NSRect(x: margin, y: currentY, width: 200, height: 20)
        historyGroupLabel.font = NSFont.boldSystemFont(ofSize: 16)
        historyGroupLabel.textColor = .secondaryLabelColor
        documentView.addSubview(historyGroupLabel)
        currentY -= 30

        // Auto Delete
        let autoDeleteLabel = NSTextField(labelWithString: "自动删除:")
        autoDeleteLabel.frame = NSRect(x: margin, y: currentY, width: labelWidth, height: 20)
        autoDeleteLabel.font = NSFont.systemFont(ofSize: 14)
        documentView.addSubview(autoDeleteLabel)
        
        let autoDeleteDesc = NSTextField(labelWithString: "自动删除过期的历史记录")
        autoDeleteDesc.frame = NSRect(x: margin, y: currentY - 18, width: 350, height: 16)
        autoDeleteDesc.font = NSFont.systemFont(ofSize: 11)
        autoDeleteDesc.textColor = .tertiaryLabelColor
        documentView.addSubview(autoDeleteDesc)

        autoDeletePopUp = NSPopUpButton(frame: NSRect(x: margin + labelWidth + 10, y: currentY - 3, width: 200, height: 26))
        autoDeletePopUp.addItems(withTitles: [
            "不自动删除",
            "7天后删除",
            "15天后删除", 
            "30天后删除",
            "3个月后删除",
            "6个月后删除"
        ])
        autoDeletePopUp.bezelStyle = .rounded
        autoDeletePopUp.font = NSFont.systemFont(ofSize: 13)
        
        // 设置当前选择
        let currentDays = settings.autoDeleteDays
        switch currentDays {
        case 0: autoDeletePopUp.selectItem(at: 0)
        case 7: autoDeletePopUp.selectItem(at: 1)
        case 15: autoDeletePopUp.selectItem(at: 2)
        case 30: autoDeletePopUp.selectItem(at: 3)
        case 90: autoDeletePopUp.selectItem(at: 4)
        case 180: autoDeletePopUp.selectItem(at: 5)
        default: autoDeletePopUp.selectItem(at: 0)
        }
        
        documentView.addSubview(autoDeletePopUp)

        // 底部按钮区域
        let buttonContainer = NSView(frame: NSRect(x: 0, y: 0, width: contentView.frame.width, height: 80))
        buttonContainer.autoresizingMask = [.width]
        contentView.addSubview(buttonContainer)
        
        // 分隔线
        let separator = NSBox(frame: NSRect(x: 0, y: 79, width: buttonContainer.frame.width, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width]
        buttonContainer.addSubview(separator)

        // Save Button
        let saveButton = HoverableButton()
        saveButton.title = "保存设置"
        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        saveButton.frame = NSRect(x: buttonContainer.frame.width - 140, y: 25, width: 120, height: 32)
        saveButton.autoresizingMask = [.minXMargin]
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"  // 支持回车键保存
        saveButton.toolTip = "保存所有设置并应用更改"
        saveButton.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        buttonContainer.addSubview(saveButton)
        
        // Reset Button
        let resetButton = HoverableButton()
        resetButton.title = "重置为默认"
        resetButton.target = self
        resetButton.action = #selector(resetToDefault)
        resetButton.frame = NSRect(x: buttonContainer.frame.width - 280, y: 25, width: 120, height: 32)
        resetButton.autoresizingMask = [.minXMargin]
        resetButton.bezelStyle = .rounded
        resetButton.toolTip = "重置所有设置为默认值"
        resetButton.font = NSFont.systemFont(ofSize: 14)
        buttonContainer.addSubview(resetButton)

        window!.contentView = contentView
    }
    
    func refreshSettings() {
        // 重新获取最新的设置值并更新界面
        let settings = SettingsManager.shared.settings
        
        apiKeyField.stringValue = settings.apiKey
        apiURLField.stringValue = settings.apiURL
        modelField.stringValue = settings.modelName
        temperatureField.stringValue = String(settings.temperature)
        qaPromptField.stringValue = settings.qaPrompt
        translatePromptField.stringValue = settings.translatePrompt
        
        // 确保输入框的对齐和自适应属性
        apiKeyField.autoresizingMask = [.width]
        apiKeyField.alignment = .left
        apiURLField.autoresizingMask = [.width]
        apiURLField.alignment = .left
        modelField.autoresizingMask = [.width]
        modelField.alignment = .left
        temperatureField.alignment = .center
        qaPromptField.autoresizingMask = [.width]
        qaPromptField.alignment = .left
        translatePromptField.autoresizingMask = [.width]
        translatePromptField.alignment = .left
        
        // 更新自动删除下拉框
        let currentDays = settings.autoDeleteDays
        switch currentDays {
        case 0: autoDeletePopUp.selectItem(at: 0)
        case 7: autoDeletePopUp.selectItem(at: 1)
        case 15: autoDeletePopUp.selectItem(at: 2)
        case 30: autoDeletePopUp.selectItem(at: 3)
        case 90: autoDeletePopUp.selectItem(at: 4)
        case 180: autoDeletePopUp.selectItem(at: 5)
        default: autoDeletePopUp.selectItem(at: 0)
        }
    }

    @objc func resetToDefault() {
        let alert = NSAlert()
        alert.messageText = "重置设置"
        alert.informativeText = "确定要重置所有设置为默认值吗？这个操作不能撤销。"
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            // 重置为默认设置
            let defaultSettings = AppSettings(
                apiKey: "",
                apiURL: "https://aihubmix.com/v1/chat/completions",
                autoDeleteDays: 0,
                modelName: "gpt-3.5-turbo",
                temperature: 0.7,
                qaPrompt: "你是一个有用的AI助手，请用中文回答：",
                translatePrompt: "你是一位专业的中英互译翻译官，请把中文译成英文，英文译成中文"
            )
            
            SettingsManager.shared.settings = defaultSettings
            
            // 保存默认设置
            if SettingsManager.shared.saveSettingsWithResult() {
                // 刷新界面显示
                refreshSettings()
                
                // 显示成功提示
                if let resetButton = window?.contentView?.subviews.first(where: { $0 is NSView })?.subviews.first(where: { $0 is HoverableButton && ($0 as! HoverableButton).title == "重置为默认" }) as? HoverableButton {
                    resetButton.showFeedback("已重置!")
                }
                
                // 重新加载配置
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.loadConfig()
                }
            }
        }
    }

    @objc func saveSettings() {
        // 验证输入
        let temperatureValue = Double(temperatureField.stringValue) ?? 0.7
        if temperatureValue < 0.0 || temperatureValue > 2.0 {
            let alert = NSAlert()
            alert.messageText = "输入错误"
            alert.informativeText = "温度值必须在 0.0 到 2.0 之间"
            alert.addButton(withTitle: "确定")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        // 验证 API URL
        if !apiURLField.stringValue.isEmpty && !apiURLField.stringValue.hasPrefix("http") {
            let alert = NSAlert()
            alert.messageText = "输入错误"
            alert.informativeText = "API URL 必须以 http:// 或 https:// 开头"
            alert.addButton(withTitle: "确定")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        // 保存设置
        SettingsManager.shared.settings.apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsManager.shared.settings.apiURL = apiURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsManager.shared.settings.modelName = modelField.stringValue.isEmpty ? "gpt-3.5-turbo" : modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsManager.shared.settings.temperature = max(0.0, min(2.0, temperatureValue))
        SettingsManager.shared.settings.qaPrompt = qaPromptField.stringValue.isEmpty ? "你是一个有用的AI助手，请用中文回答：" : qaPromptField.stringValue
        SettingsManager.shared.settings.translatePrompt = translatePromptField.stringValue.isEmpty ? "你是一位专业的中英互译翻译官，请把中文译成英文，英文译成中文" : translatePromptField.stringValue
        
        // 保存自动删除设置
        let selectedIndex = autoDeletePopUp.indexOfSelectedItem
        switch selectedIndex {
        case 0: SettingsManager.shared.settings.autoDeleteDays = 0   // 不自动删除
        case 1: SettingsManager.shared.settings.autoDeleteDays = 7   // 7天
        case 2: SettingsManager.shared.settings.autoDeleteDays = 15  // 15天
        case 3: SettingsManager.shared.settings.autoDeleteDays = 30  // 30天
        case 4: SettingsManager.shared.settings.autoDeleteDays = 90  // 3个月
        case 5: SettingsManager.shared.settings.autoDeleteDays = 180 // 6个月
        default: SettingsManager.shared.settings.autoDeleteDays = 0
        }
        
        // 尝试保存设置
        let saveSuccess = SettingsManager.shared.saveSettingsWithResult()
        
        if saveSuccess {
            // 显示保存成功反馈
            if let saveButton = window?.contentView?.subviews.first(where: { $0 is HoverableButton }) as? HoverableButton {
                saveButton.showFeedback("保存成功!")
            }
            
            // 重新加载所有配置
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.loadConfig()
            }
            
            // 在单例模式下，不自动关闭窗口，让用户手动关闭
            print("设置已保存成功")
            
        } else {
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = "无法保存设置，请检查文件权限或磁盘空间"
            alert.addButton(withTitle: "确定")
            alert.alertStyle = .critical
            alert.runModal()
        }
    }
}

    