//
//  MarkdownRenderer.swift
//  AskPop
//
//  Created by Assistant on 2024
//  Markdown 渲染器相关功能
//

import Cocoa
import WebKit

// MARK: - Custom Text View for Markdown Input
class MarkdownInputTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 处理复制粘贴快捷键
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "c":
                copy(nil)
                return true
            case "v":
                paste(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            case "z":
                if event.modifierFlags.contains(.shift) {
                    undoManager?.redo()
                } else {
                    undoManager?.undo()
                }
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Markdown Renderer Window Controller
class MarkdownRendererWindowController: NSWindowController, WKScriptMessageHandler {
    private var inputTextView: NSTextView!
    private var previewWebView: WKWebView!
    private var renderButton: NSButton!
    private var saveButton: NSButton!
    private var copyButton: NSButton!
    private var pdfButton: NSButton!
    private var scrollView: NSScrollView!
    private var currentMarkdownText: String?
    
    // 添加属性来存储完成回调
    private var longImageCompletionHandler: ((Bool) -> Void)?
    
    override init(window: NSWindow?) {
        super.init(window: window)
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupWindow()
    }
    
    private func setupWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown 渲染器"
        window.center()
        self.window = window
        setupUI()
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        // UI 已经在 setupWindow 中设置过了
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        
        // 确保文本视图可以接收焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.window?.makeFirstResponder(self.inputTextView)
        }
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        // 确保窗口可以接收事件
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        
        let contentView = window.contentView!
        
        // 创建分割视图
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)
        
        // 左侧：输入区域
        let leftContainer = NSView()
        leftContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let inputLabel = NSTextField(labelWithString: "输入 Markdown 文本：")
        inputLabel.translatesAutoresizingMaskIntoConstraints = false
        inputLabel.font = NSFont.boldSystemFont(ofSize: 14)
        leftContainer.addSubview(inputLabel)
        
        // 创建滚动视图 - 先创建滚动视图
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true // 启用水平滚动以防长行
        scrollView.autohidesScrollers = false  // 禁用自动隐藏
        scrollView.borderType = .bezelBorder
        scrollView.scrollerStyle = .legacy    // 使用传统滚动条样式
        scrollView.scrollerKnobStyle = .default
        
        // 创建文本视图
        inputTextView = MarkdownInputTextView()
        inputTextView.isRichText = false
        inputTextView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        inputTextView.isEditable = true
        inputTextView.isSelectable = true
        inputTextView.allowsUndo = true
        inputTextView.isAutomaticQuoteSubstitutionEnabled = false
        inputTextView.isAutomaticDashSubstitutionEnabled = false
        inputTextView.isAutomaticTextReplacementEnabled = false
        inputTextView.isContinuousSpellCheckingEnabled = false
        inputTextView.backgroundColor = NSColor.textBackgroundColor
        inputTextView.insertionPointColor = NSColor.labelColor
        inputTextView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.selectedTextColor
        ]
        
        // 设置文本容器属性
        inputTextView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.textContainer?.heightTracksTextView = false
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.autoresizingMask = [.width]
        
        // 设置默认文本内容以便测试滚动
        inputTextView.string = ""
        
        // 将文本视图设置为滚动视图的文档视图
        scrollView.documentView = inputTextView
        
        // 强制显示滚动条
        DispatchQueue.main.async {
            self.scrollView.hasVerticalScroller = true
            self.scrollView.hasHorizontalScroller = true
            self.scrollView.autohidesScrollers = false
            self.scrollView.verticalScroller?.isHidden = false
            self.scrollView.horizontalScroller?.isHidden = false
        }
        
        leftContainer.addSubview(scrollView)
        
        // 按钮区域
        let buttonStack = NSStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        
        renderButton = NSButton(title: "渲染", target: self, action: #selector(renderMarkdown))
        renderButton.bezelStyle = .rounded
        renderButton.keyEquivalent = "\r"

        saveButton = NSButton(title: "保存长图", target: self, action: #selector(saveLongImage))
        saveButton.bezelStyle = .rounded
        saveButton.isEnabled = false

        copyButton = NSButton(title: "复制长图", target: self, action: #selector(copyLongImage))
        copyButton.bezelStyle = .rounded
        copyButton.isEnabled = false
        
        // 添加HTML保存按钮
        let pdfButton = NSButton(title: "保存HTML", target: self, action: #selector(savePDF))
        pdfButton.bezelStyle = .rounded
        pdfButton.isEnabled = false
        self.pdfButton = pdfButton
        
        buttonStack.addArrangedSubview(renderButton)
        buttonStack.addArrangedSubview(saveButton)
        buttonStack.addArrangedSubview(copyButton)
        buttonStack.addArrangedSubview(pdfButton)
        leftContainer.addSubview(buttonStack)
        
        // 右侧：预览区域
        let rightContainer = NSView()
        rightContainer.translatesAutoresizingMaskIntoConstraints = false
        
        let previewLabel = NSTextField(labelWithString: "渲染预览：")
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(previewLabel)
        
        previewWebView = WKWebView()
        previewWebView.translatesAutoresizingMaskIntoConstraints = false
        previewWebView.wantsLayer = true
        previewWebView.layer?.backgroundColor = NSColor.white.cgColor
        previewWebView.layer?.cornerRadius = 4
        previewWebView.layer?.borderWidth = 1
        previewWebView.layer?.borderColor = NSColor.lightGray.cgColor
        rightContainer.addSubview(previewWebView)
        
        // 设置约束
        splitView.addArrangedSubview(leftContainer)
        splitView.addArrangedSubview(rightContainer)
        
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)
        
        NSLayoutConstraint.activate([
            // 分割视图约束
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            
            // 左侧约束
            inputLabel.topAnchor.constraint(equalTo: leftContainer.topAnchor),
            inputLabel.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor),
            inputLabel.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor),
            
            scrollView.topAnchor.constraint(equalTo: inputLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -8),
            
            buttonStack.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: leftContainer.bottomAnchor),
            
            // 右侧约束
            previewLabel.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            previewLabel.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
            
            previewWebView.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 8),
            previewWebView.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            previewWebView.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
            previewWebView.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor)
        ])
        
        // 设置分割视图比例
        splitView.setPosition(400, ofDividerAt: 0)
    }
    
    // MARK: - Markdown 渲染相关方法
    
    @objc private func renderMarkdown() {
        let markdownText = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🎬 渲染按钮被点击")
        print("📝 文本内容长度：\(markdownText.count) 字符")
        
        // 保存当前Markdown文本
        self.currentMarkdownText = markdownText
        
        // 禁用渲染按钮防止重复点击
        renderButton.isEnabled = false
        renderButton.title = "渲染中..."
        
        // 直接在 WebView 中渲染 Markdown
        renderMarkdownInWebView(markdownText) { [weak self] success in
            DispatchQueue.main.async {
                self?.renderButton.isEnabled = true
                self?.renderButton.title = "渲染"
                
                if success {
                    print("✅ 渲染成功")
                    self?.saveButton.isEnabled = true
                    self?.copyButton.isEnabled = true
                    self?.pdfButton.isEnabled = true
                    self?.showStatusMessage("渲染成功！", color: .systemGreen)
                } else {
                    print("❌ 渲染失败")
                    self?.saveButton.isEnabled = false
                    self?.copyButton.isEnabled = false
                    self?.pdfButton.isEnabled = false
                    self?.showStatusMessage("渲染失败", color: .systemRed)
                }
            }
        }
    }
    
    // 新的渲染方法：直接在 WebView 中显示
    private func renderMarkdownInWebView(_ markdownText: String, completion: @escaping (Bool) -> Void) {
        print("🌐 开始在 WebView 中渲染 Markdown")
        
        // 转义Markdown文本
        let escapedMarkdown = markdownText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        
        // 创建HTML内容（参考问答功能的HTML结构）
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    line-height: 1.6;
                    padding: 20px;
                    margin: 0;
                    background: white;
                    color: #333;
                    max-width: none;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 10px; }
                h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 8px; }
                h3 { font-size: 1.25em; }
                h4 { font-size: 1em; }
                h5 { font-size: 0.875em; }
                h6 { font-size: 0.85em; color: #6a737d; }
                
                p { margin-bottom: 16px; }
                
                ul, ol {
                    margin-bottom: 16px;
                    padding-left: 30px;
                }
                li { margin-bottom: 4px; }
                
                blockquote {
                    margin: 16px 0;
                    padding: 0 16px;
                    border-left: 4px solid #dfe2e5;
                    color: #6a737d;
                }
                
                code {
                    background-color: rgba(27,31,35,0.05);
                    border-radius: 3px;
                    font-size: 85%;
                    margin: 0;
                    padding: 0.2em 0.4em;
                }
                
                pre {
                    background-color: #f6f8fa;
                    border-radius: 6px;
                    font-size: 85%;
                    line-height: 1.45;
                    overflow: auto;
                    padding: 16px;
                    margin-bottom: 16px;
                }
                
                pre code {
                    background-color: transparent;
                    border: 0;
                    display: inline;
                    line-height: inherit;
                    margin: 0;
                    max-width: auto;
                    overflow: visible;
                    padding: 0;
                    white-space: pre;
                    word-break: normal;
                }
                
                table {
                    border-collapse: collapse;
                    margin-bottom: 16px;
                    width: 100%;
                }
                
                table th, table td {
                    border: 1px solid #dfe2e5;
                    padding: 6px 13px;
                }
                
                table th {
                    background-color: #f6f8fa;
                    font-weight: 600;
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 6px;
                }
                
                hr {
                    height: 0.25em;
                    padding: 0;
                    margin: 24px 0;
                    background-color: #e1e4e8;
                    border: 0;
                }
                
                a {
                    color: #0366d6;
                    text-decoration: none;
                }
                
                a:hover {
                    text-decoration: underline;
                }
                
                strong { font-weight: 600; }
                em { font-style: italic; }
                
                .markdown-body {
                    box-sizing: border-box;
                    min-width: 200px;
                    max-width: 100%;
                    margin: 0 auto;
                }
            </style>
        </head>
        <body>
            <div class="markdown-body" id="content">
                <p>正在渲染...</p>
            </div>
            <script>
                // 等待 marked 和 highlight.js 库加载
                function waitForLibraries() {
                    return new Promise((resolve, reject) => {
                        let attempts = 0;
                        const maxAttempts = 50;
                        
                        function check() {
                            attempts++;
                            if (typeof marked !== 'undefined' && typeof hljs !== 'undefined') {
                                console.log('✅ 库已加载');
                                resolve();
                            } else if (attempts >= maxAttempts) {
                                console.error('❌ 库加载超时');
                                reject(new Error('库加载超时'));
                            } else {
                                setTimeout(check, 100);
                            }
                        }
                        check();
                    });
                }
                
                async function renderMarkdown() {
                    try {
                        await waitForLibraries();
                        
                        const markdown = `\(escapedMarkdown)`;
                        console.log('📝 开始渲染，文本长度:', markdown.length);
                        
                        if (!markdown.trim()) {
                            document.getElementById('content').innerHTML = '<p>请输入 Markdown 内容</p>';
                            return;
                        }
                        
                        // 配置 marked
                        marked.setOptions({
                            breaks: true,
                            gfm: true,
                            pedantic: false,
                            smartLists: true,
                            smartypants: false,
                            highlight: function(code, lang) {
                                if (lang && hljs.getLanguage(lang)) {
                                    try {
                                        return hljs.highlight(code, { language: lang }).value;
                                    } catch (err) {}
                                }
                                return hljs.highlightAuto(code).value;
                            }
                        });
                        
                        // 渲染 Markdown
                        const html = marked.parse(markdown);
                        document.getElementById('content').innerHTML = html;
                        
                        console.log('✅ 渲染完成');
                        
                        // 通知原生代码渲染成功
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderComplete) {
                            window.webkit.messageHandlers.renderComplete.postMessage('success');
                        }
                        
                    } catch (error) {
                        console.error('❌ 渲染错误:', error);
                        document.getElementById('content').innerHTML = 
                            '<div style="color: red; padding: 20px; border: 1px solid #ff6b6b; border-radius: 4px; background-color: #ffe0e0;">' +
                            '<h3>渲染失败</h3>' +
                            '<p>错误信息：' + error.message + '</p>' +
                            '<p>请检查 Markdown 格式或网络连接</p>' +
                            '</div>';
                            
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderComplete) {
                            window.webkit.messageHandlers.renderComplete.postMessage('error');
                        }
                    }
                }
                
                // 开始渲染
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', renderMarkdown);
                } else {
                    renderMarkdown();
                }
                
                // 超时处理
                setTimeout(() => {
                    if (document.getElementById('content').innerHTML.includes('正在渲染...')) {
                        document.getElementById('content').innerHTML = 
                            '<div style="color: orange; padding: 20px; border: 1px solid #ffa500; border-radius: 4px; background-color: #fff8e1;">' +
                            '<h3>渲染超时</h3>' +
                            '<p>可能的原因：</p>' +
                            '<ul><li>网络连接问题</li><li>JavaScript 库加载失败</li><li>内容过于复杂</li></ul>' +
                            '</div>';
                        
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderComplete) {
                            window.webkit.messageHandlers.renderComplete.postMessage('timeout');
                        }
                    }
                }, 10000);
            </script>
        </body>
        </html>
        """
        
        // 加载HTML到WebView
        previewWebView.loadHTMLString(htmlContent, baseURL: nil)
        
        // 简单的超时处理
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            completion(true) // 假设成功，实际应该通过消息处理器确认
        }
    }
    
    // MARK: - 状态消息显示
    
    private func showStatusMessage(_ message: String, color: NSColor) {
        // 实现状态消息显示逻辑
        print("📢 状态消息: \(message)")
        
        // 创建临时状态窗口
        DispatchQueue.main.async {
            self.createAndShowStatusWindow(message: message, color: color)
        }
    }
    
    private func createAndShowStatusWindow(message: String, color: NSColor) {
        // 创建状态窗口
        let statusWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        statusWindow.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95)
        statusWindow.level = .floating
        statusWindow.isOpaque = false
        statusWindow.hasShadow = true
        statusWindow.center()
        
        // 创建内容视图
        let contentView = NSView(frame: statusWindow.contentRect(forFrameRect: statusWindow.frame))
        
        // 添加圆角
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        // 创建消息标签
        let messageLabel = NSTextField(frame: NSRect(x: 20, y: 20, width: 260, height: 40))
        messageLabel.stringValue = message
        messageLabel.isEditable = false
        messageLabel.isBordered = false
        messageLabel.backgroundColor = .clear
        messageLabel.textColor = color
        messageLabel.alignment = .center
        messageLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        messageLabel.cell?.wraps = true
        messageLabel.cell?.truncatesLastVisibleLine = false
        
        contentView.addSubview(messageLabel)
        statusWindow.contentView = contentView
        
        // 显示窗口
        statusWindow.makeKeyAndOrderFront(nil)
        statusWindow.orderFrontRegardless()
        
        // 2秒后自动关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            statusWindow.close()
        }
    }
    
    // MARK: - 长图生成功能
    
    // 从WebView生成长图 - 使用原渲染方案
    private func generateLongImageFromWebView(completion: @escaping (NSImage?) -> Void) {
        let markdownText = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdownText.isEmpty else {
            print("❌ Markdown文本为空")
            generateBackupLongImage(completion: completion)
            return
        }
        
        let startTime = Date()
        print("🚀 [开始] 生成长图，时间：\(startTime)")
        
        DispatchQueue.main.async {
            let config = WKWebViewConfiguration()
            // 移除已弃用的javaScriptEnabled设置，现代WebView默认启用JavaScript
            
            // 添加消息处理器来接收JavaScript的renderComplete消息
            let userContentController = WKUserContentController()
            userContentController.add(self, name: "renderComplete")
            config.userContentController = userContentController
            
            let targetWidth: CGFloat = 800
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: targetWidth, height: 1000), configuration: config)
            
            // 创建离屏容器
            let containerView = NSView(frame: NSRect(x: -3000, y: -3000, width: targetWidth, height: 1000))
            containerView.addSubview(webView)
            
            if let window = self.window {
                window.contentView?.addSubview(containerView)
            }
            
            // 设置15秒超时
            let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { _ in
                print("⏰ [超时] 长图生成超时，使用备用方案")
                containerView.removeFromSuperview()
                self.generateBackupLongImage(completion: completion)
            }
            
            // 存储WebView引用和完成回调，用于消息处理
            var isCompleted = false
            let handleCompletion = { (image: NSImage?) in
                guard !isCompleted else { return }
                isCompleted = true
                timeoutTimer.invalidate()
                containerView.removeFromSuperview()
                
                let totalTime = Date().timeIntervalSince(startTime)
                if let image = image {
                    print("✅ [最终成功] 长图生成成功，总耗时：\(String(format: "%.2f", totalTime))秒")
                    completion(image)
                } else {
                    print("⚠️ 长图生成失败，使用备用方案")
                    self.generateBackupLongImage(completion: completion)
                }
            }
            
            // 创建导航代理
            let navigationDelegate = LongImageNavigationDelegate {
                print("🎯 长图WebView加载完成")
                
                // 等待JavaScript渲染完成，如果没有收到renderComplete消息，则使用延迟截图
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    guard !isCompleted else { return }
                    print("⏰ 未收到JavaScript完成消息，开始延迟截图")
                    self.performLongImageSnapshot(webView: webView, targetWidth: targetWidth, completion: handleCompletion)
                }
            }
            
            webView.navigationDelegate = navigationDelegate
            
            // 使用与原渲染方案完全相同的HTML内容和JavaScript逻辑
            let htmlContent = self.createRenderingHTML(markdownText: markdownText)
            
            print("🌐 [步骤1] 开始加载HTML到长图WebView")
            webView.loadHTMLString(htmlContent, baseURL: nil)
            
            // 存储回调供消息处理器使用
            self.longImageCompletionHandler = { success in
                if success {
                    print("✅ 收到JavaScript渲染完成消息")
                    self.performLongImageSnapshot(webView: webView, targetWidth: targetWidth, completion: handleCompletion)
                } else {
                    print("❌ JavaScript渲染失败")
                    handleCompletion(nil)
                }
            }
        }
    }

    // 辅助方法：执行截图
    private func performLongImageSnapshot(webView: WKWebView, targetWidth: CGFloat, completion: @escaping (NSImage?) -> Void) {
        // 计算内容高度
        webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 400)") { result, error in
            var contentHeight: CGFloat = 1000
            
            if let error = error {
                print("⚠️ JavaScript执行错误：\(error.localizedDescription)")
            }
            
            if let height = result as? NSNumber {
                contentHeight = max(400, CGFloat(height.doubleValue) + 80)
                print("📏 计算得到内容高度：\(contentHeight)")
            }
            
            // 调整WebView尺寸
            webView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: contentHeight)
            if let containerView = webView.superview {
                containerView.frame = NSRect(x: -3000, y: -3000, width: targetWidth, height: contentHeight)
            }
            
            // 等待布局更新后截图
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("📸 开始截图...")
                
                webView.takeSnapshot(with: nil) { image, error in
                    if let error = error {
                        print("❌ 截图失败：\(error.localizedDescription)")
                        completion(nil)
                    } else if let image = image {
                        print("✅ 截图成功，尺寸：\(image.size)")
                        completion(image)
                    } else {
                        print("⚠️ 截图返回nil")
                        completion(nil)
                    }
                }
            }
        }
    }
    
    // 新增：创建与原渲染方案相同的HTML内容
    private func createRenderingHTML(markdownText: String) -> String {
        let escapedMarkdown = markdownText
            .replacingOccurrences(of: "\\", with: "\\\\\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        
        // 返回与 renderMarkdownToImage 完全相同的HTML内容
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    background: white;
                    padding: 30px;
                    margin: 0;
                    max-width: 740px;
                    word-wrap: break-word;
                    font-size: 16px;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
                h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
                h3 { font-size: 1.25em; }
                h4 { font-size: 1em; }
                h5 { font-size: 0.875em; }
                h6 { font-size: 0.85em; color: #6a737d; }
                p { margin-bottom: 16px; }
                blockquote {
                    padding: 0 1em;
                    color: #6a737d;
                    border-left: 0.25em solid #dfe2e5;
                    margin: 0 0 16px 0;
                }
                code {
                    padding: 0.2em 0.4em;
                    margin: 0;
                    font-size: 85%;
                    background-color: rgba(27,31,35,0.05);
                    border-radius: 3px;
                    font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
                }
                pre {
                    padding: 16px;
                    overflow: auto;
                    font-size: 85%;
                    line-height: 1.45;
                    background-color: #f6f8fa;
                    border-radius: 6px;
                    margin-bottom: 16px;
                    border: 1px solid #d0d7de;
                }
                pre code {
                    padding: 0;
                    background-color: transparent;
                    border-radius: 0;
                }
                ul, ol {
                    padding-left: 2em;
                    margin-bottom: 16px;
                }
                li {
                    margin-bottom: 4px;
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin-bottom: 16px;
                    border: 1px solid #d0d7de;
                }
                th, td {
                    padding: 6px 13px;
                    border: 1px solid #d0d7de;
                }
                th {
                    background-color: #f6f8fa;
                    font-weight: 600;
                }
                img {
                    max-width: 100%;
                    height: auto;
                }
                hr {
                    height: 0.25em;
                    padding: 0;
                    margin: 24px 0;
                    background-color: #d0d7de;
                    border: 0;
                }
                strong {
                    font-weight: 600;
                }
                em {
                    font-style: italic;
                }
            </style>
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        </head>
        <body>
            <div id="content">正在加载...</div>
            <script>
                let renderingTimeout;
                
                // 等待 marked 库加载完成的函数
                function waitForMarked() {
                    return new Promise((resolve, reject) => {
                        let attempts = 0;
                        const maxAttempts = 50; // 5秒超时
                        
                        function checkMarked() {
                            attempts++;
                            if (typeof marked !== 'undefined') {
                                console.log('✅ Marked 库已加载');
                                resolve();
                            } else if (attempts >= maxAttempts) {
                                console.error('❌ Marked 库加载超时');
                                reject(new Error('Marked 库加载超时'));
                            } else {
                                setTimeout(checkMarked, 100);
                            }
                        }
                        checkMarked();
                    });
                }
                
                // 渲染 Markdown 的函数
                async function renderMarkdown() {
                    try {
                        console.log('🚀 开始渲染过程');
                        
                        // 等待 marked 库加载
                        await waitForMarked();
                        
                        const markdown = `\(escapedMarkdown)`;
                        console.log('📝 Markdown 文本长度:', markdown.length);
                        console.log('📝 Markdown 内容预览:', markdown.substring(0, 100) + '...');
                        
                        if (!markdown.trim()) {
                            document.getElementById('content').innerHTML = '<p>内容为空，请输入 Markdown 文本</p>';
                            return;
                        }
                        
                        // 配置 marked 选项
                        marked.setOptions({
                            breaks: true,
                            gfm: true,
                            pedantic: false,
                            smartLists: true,
                            smartypants: false
                        });
                        
                        // 解析 Markdown
                        const html = marked.parse(markdown);
                        console.log('🎯 HTML 生成成功，长度:', html.length);
                        
                        // 渲染到页面
                        document.getElementById('content').innerHTML = html;
                        console.log('✅ 渲染完成');
                        
                        // 通知原生代码渲染成功
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderComplete) {
                            window.webkit.messageHandlers.renderComplete.postMessage('success');
                        }
                        
                    } catch (error) {
                        console.error('❌ 渲染错误:', error);
                        document.getElementById('content').innerHTML = 
                            '<p style="color: red;">渲染错误: ' + error.message + '</p>' +
                            '<p>请检查 Markdown 格式或网络连接</p>';
                            
                        // 通知原生代码渲染失败
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.renderComplete) {
                            window.webkit.messageHandlers.renderComplete.postMessage('error: ' + error.message);
                        }
                    }
                }
                
                // 页面加载完成后开始渲染
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', renderMarkdown);
                } else {
                    renderMarkdown();
                }
                
                // 设置超时处理
                renderingTimeout = setTimeout(() => {
                    console.warn('⏰ 渲染超时');
                    if (document.getElementById('content').innerHTML === '正在加载...') {
                        document.getElementById('content').innerHTML = 
                            '<p style="color: orange;">渲染超时，可能的原因:</p>' +
                            '<ul>' +
                            '<li>网络连接问题</li>' +
                            '<li>JavaScript 库加载失败</li>' +
                            '<li>Markdown 格式复杂</li>' +
                            '</ul>';
                    }
                }, 8000); // 8秒超时
            </script>
        </body>
        </html>
        """
    }
    
    // 备用长图生成方案
    private func generateBackupLongImage(completion: @escaping (NSImage?) -> Void) {
        print("🎨 使用备用方案生成长图...")
        
        // 获取Markdown文本
        let markdownText = inputTextView.string
        
        // 使用智能宽度和高度计算
        let optimalWidth = calculateOptimalWidth(for: markdownText)
        let heightSize = calculateOptimalImageSize(for: markdownText)
        let calculatedSize = NSSize(width: optimalWidth, height: heightSize.height)
        print("📐 计算得出最优尺寸：\(calculatedSize)")
        
        // 创建备用图片（纯文本渲染）
        let image = createBackupImage(markdownText: markdownText, size: calculatedSize)
        completion(image)
    }
    
    // 智能计算最佳宽度
    private func calculateOptimalWidth(for markdownText: String) -> CGFloat {
        print("📐 开始计算最佳宽度...")
        
        let lines = markdownText.components(separatedBy: .newlines)
        var maxLineLength: CGFloat = 0
        let baseFont = NSFont.systemFont(ofSize: 14)
        
        // 分析每行文本，找到最长的行
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            
            // 根据Markdown语法确定字体
            var font: NSFont = baseFont
            var displayText = trimmedLine
            
            if trimmedLine.hasPrefix("# ") {
                font = NSFont.boldSystemFont(ofSize: 20)
                displayText = String(trimmedLine.dropFirst(2))
            } else if trimmedLine.hasPrefix("## ") {
                font = NSFont.boldSystemFont(ofSize: 18)
                displayText = String(trimmedLine.dropFirst(3))
            } else if trimmedLine.hasPrefix("### ") {
                font = NSFont.boldSystemFont(ofSize: 16)
                displayText = String(trimmedLine.dropFirst(4))
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                font = NSFont.systemFont(ofSize: 14)
                displayText = "• " + String(trimmedLine.dropFirst(2))
            }
            
            // 计算这行文本的实际宽度
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attributedString = NSAttributedString(string: displayText, attributes: attributes)
            let textWidth = attributedString.size().width
            
            maxLineLength = max(maxLineLength, textWidth)
        }
        
        // 设置合理的宽度范围和边距
        let padding: CGFloat = 60 // 左右边距总计
        let minWidth: CGFloat = 600  // 最小宽度
        let maxWidth: CGFloat = 1200 // 最大宽度
        
        // 计算建议宽度：基于最长行 + 边距
        let suggestedWidth = maxLineLength + padding
        
        // 调整策略：
        // 1. 如果文本行很短，使用最小宽度
        // 2. 如果文本行很长，限制在最大宽度内
        // 3. 中等长度则根据实际内容调整
        let finalWidth: CGFloat
        
        if maxLineLength < 400 {
            // 短文本：使用较小宽度，但不小于最小值
            finalWidth = max(minWidth, suggestedWidth)
        } else if maxLineLength > 1000 {
            // 长文本：使用最大宽度，避免过宽
            finalWidth = maxWidth
        } else {
            // 中等长度：根据内容适度调整
            let contentBasedWidth = suggestedWidth * 1.1 // 增加10%的呼吸空间
            finalWidth = min(max(minWidth, contentBasedWidth), maxWidth)
        }
        
        print("📊 文本分析结果：")
        print("  - 最长行宽度：\(maxLineLength)")
        print("  - 建议宽度：\(suggestedWidth)")
        print("  - 最终宽度：\(finalWidth)")
        
        return finalWidth
    }
    
    // 计算最佳图片尺寸
    private func calculateOptimalImageSize(for markdownText: String) -> NSSize {
        let lines = markdownText.components(separatedBy: .newlines)
        let lineCount = lines.count
        
        // 基础高度计算
        let baseLineHeight: CGFloat = 25
        let estimatedHeight = CGFloat(lineCount) * baseLineHeight + 100 // 加100px的边距
        
        // 限制高度范围
        let minHeight: CGFloat = 400
        let maxHeight: CGFloat = 3000
        
        let finalHeight = max(minHeight, min(maxHeight, estimatedHeight))
        
        return NSSize(width: 800, height: finalHeight)
    }
    
    // 创建备用图片
    private func createBackupImage(markdownText: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        // 绘制白色背景
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        
        // 绘制文本
        let font = NSFont.systemFont(ofSize: 14)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let rect = NSRect(x: 20, y: 20, width: size.width - 40, height: size.height - 40)
        markdownText.draw(in: rect, withAttributes: attributes)
        
        image.unlockFocus()
        return image
    }
    
    // MARK: - 实现WKScriptMessageHandler协议
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "renderComplete" {
            print("✅ 收到JavaScript渲染完成消息：\(message.body)")
            
            DispatchQueue.main.async {
                if let handler = self.longImageCompletionHandler {
                    let success = (message.body as? String) == "success"
                    handler(success)
                    self.longImageCompletionHandler = nil
                }
            }
        }
    }
    
    // MARK: - 按钮操作方法
    
    @objc private func savePDF() {
        let savePanel = NSSavePanel()
        if #available(macOS 11.0, *) {
            savePanel.allowedContentTypes = [.html]
        } else {
            savePanel.allowedFileTypes = ["html"]
        }
        savePanel.nameFieldStringValue = "markdown_rendered.html"
        
        savePanel.begin { [weak self] result in
            if result == .OK, let url = savePanel.url, let webView = self?.previewWebView {
                // 使用WebView的HTML导出功能
                webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
                    DispatchQueue.main.async {
                        if let htmlString = result as? String {
                            // 创建包含完整HTML的内容
                            let completeHTML = """
                            <!DOCTYPE html>
                            <html>
                            <head>
                                <meta charset="UTF-8">
                                <style>
                                    body { 
                                        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                                        line-height: 1.6;
                                        color: #333;
                                        max-width: 800px;
                                        margin: 0 auto;
                                        padding: 20px;
                                    }
                                    @media print { 
                                        body { 
                                            margin: 0; 
                                            padding: 20px; 
                                        } 
                                    }
                                </style>
                            </head>
                            <body>
                            \(htmlString)
                            </body>
                            </html>
                            """
                            
                            do {
                                try completeHTML.write(to: url, atomically: true, encoding: .utf8)
                                self?.showStatusMessage("HTML 保存成功！", color: .systemGreen)
                                print("✅ HTML保存成功: \(url.path)")
                            } catch {
                                self?.showStatusMessage("保存失败：\(error.localizedDescription)", color: .systemRed)
                                print("❌ HTML保存失败: \(error.localizedDescription)")
                            }
                        } else {
                            self?.showStatusMessage("保存失败：无法获取内容", color: .systemRed)
                            print("❌ 获取WebView内容失败: \(error?.localizedDescription ?? "未知错误")")
                        }
                    }
                }
            }
        }
    }
    
    @objc private func saveLongImage() {
        print("💾 开始保存长图...")
        
        generateLongImageFromWebView { [weak self] image in
            DispatchQueue.main.async {
                if let image = image {
                    let savePanel = NSSavePanel()
                    if #available(macOS 11.0, *) {
                        savePanel.allowedContentTypes = [.png]
                    } else {
                        savePanel.allowedFileTypes = ["png"]
                    }
                    savePanel.nameFieldStringValue = "markdown_long_image.png"
                    
                    savePanel.begin { result in
                        if result == .OK, let url = savePanel.url {
                            if let imageData = image.tiffRepresentation,
                               let bitmapImage = NSBitmapImageRep(data: imageData),
                               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                                do {
                                    try pngData.write(to: url)
                                    self?.showStatusMessage("长图保存成功！", color: .systemGreen)
                                    print("✅ 长图保存成功: \(url.path)")
                                } catch {
                                    self?.showStatusMessage("保存失败", color: .systemRed)
                                    print("❌ 长图保存失败: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                } else {
                    self?.showStatusMessage("长图生成失败", color: .systemRed)
                    print("❌ 长图生成失败")
                }
            }
        }
    }
    
    @objc private func copyLongImage() {
        print("📋 开始复制长图...")
        
        generateLongImageFromWebView { [weak self] image in
            DispatchQueue.main.async {
                if let image = image {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    
                    // 只复制图片对象（推荐方式，兼容性最好）
                    if pasteboard.writeObjects([image]) {
                        self?.showStatusMessage("长图已复制到剪贴板！", color: .systemGreen)
                        print("✅ 长图复制成功")
                    } else {
                        self?.showStatusMessage("复制失败", color: .systemRed)
                        print("❌ 长图复制失败")
                    }
                } else {
                    self?.showStatusMessage("长图生成失败", color: .systemRed)
                    print("❌ 长图生成失败")
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func createPDFFromHTML(_ htmlString: String) -> Data? {
        // 创建包含完整HTML的PDF内容
        let pdfHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 800px;
                    margin: 0 auto;
                    padding: 20px;
                }
                @media print { 
                    body { 
                        margin: 0; 
                        padding: 20px; 
                    } 
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                pre {
                    background-color: #f6f8fa;
                    border-radius: 6px;
                    padding: 16px;
                    overflow-x: auto;
                }
                code {
                    background-color: rgba(27,31,35,0.05);
                    border-radius: 3px;
                    padding: 0.2em 0.4em;
                }
                blockquote {
                    border-left: 4px solid #dfe2e5;
                    margin: 16px 0;
                    padding: 0 16px;
                    color: #6a737d;
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin-bottom: 16px;
                }
                th, td {
                    border: 1px solid #dfe2e5;
                    padding: 6px 13px;
                    text-align: left;
                }
                th {
                    background-color: #f6f8fa;
                    font-weight: 600;
                }
            </style>
        </head>
        <body>
        \(htmlString)
        </body>
        </html>
        """
        
        // 使用 WebView 生成 PDF
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(pdfHTML, baseURL: nil)
        
        // 注意：这是同步实现，实际应该异步处理
        // 这里返回HTML数据作为PDF的替代方案
        return pdfHTML.data(using: .utf8)
    }
    
    // MARK: - 图片处理相关的辅助方法
    
    // 将本地图片转换为 Base64 编码（用于笔记同步等功能）
    private func convertLocalImagesToBase64(_ markdown: String) -> String {
        let imagePattern = "!\\[([^\\]]*)\\]\\(([^\\)\"']+)\\)|!\\[([^\\]]*)\\]\\(\"([^\\)]+)\"\\)|!\\[([^\\]]*)\\]\\('([^\\)]+)'\\)"
        var processedMarkdown = markdown
        
        do {
            let regex = try NSRegularExpression(pattern: imagePattern, options: [])
            let nsString = markdown as NSString
            let matches = regex.matches(in: markdown, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches.reversed() {
                let pathRange = match.range(at: 2).length > 0 ? match.range(at: 2) : 
                                match.range(at: 4).length > 0 ? match.range(at: 4) : match.range(at: 6)
                
                if pathRange.location != NSNotFound {
                    let imagePath = nsString.substring(with: pathRange)
                    
                    // 跳过已经是 base64 的图片
                    if imagePath.hasPrefix("data:") {
                        continue
                    }
                    
                    // 处理相对路径
                    var imageFullPath: String?
                    if imagePath.hasPrefix("/") {
                        imageFullPath = imagePath
                    } else {
                        // 相对于笔记文件的路径
                        let noteDir = (NoteManager.shared.lastSelectedNote as NSString).deletingLastPathComponent
                        imageFullPath = (noteDir as NSString).appendingPathComponent(imagePath)
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
                        print("无法读取图片：\(imagePath)")
                    }
                }
            }
        } catch {
            print("处理图片时出错：\(error)")
        }
        
        return processedMarkdown
    }
    
    // 获取文件的 MIME 类型
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
    
    // 裁剪图片空白区域的辅助函数
    private func trimWhitespace(from image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // 创建位图上下文来分析像素
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            return image
        }
        
        let pixels = data.bindMemory(to: UInt32.self, capacity: width * height)
        
        // 找到实际内容的边界（非白色像素）
        var bottomBound = 0
        
        // 从下往上扫描，找到最后一行有内容的位置
        for y in stride(from: height - 1, through: 0, by: -1) {
            var hasContent = false
            for x in 0..<width {
                let pixel = pixels[y * width + x]
                let r = (pixel >> 24) & 0xFF
                let g = (pixel >> 16) & 0xFF
                let b = (pixel >> 8) & 0xFF
                
                // 如果不是纯白色或接近白色，认为是内容
                if r < 250 || g < 250 || b < 250 {
                    hasContent = true
                    break
                }
            }
            
            if hasContent {
                bottomBound = y + 20 // 保留一些底部边距
                break
            }
        }
        
        // 如果没有找到内容边界，返回原图
        if bottomBound <= 0 {
            return image
        }
        
        // 创建裁剪后的图片
        let trimmedHeight = min(bottomBound + 1, height)
        let trimmedRect = CGRect(x: 0, y: height - trimmedHeight, width: width, height: trimmedHeight)
        
        if let trimmedCGImage = cgImage.cropping(to: trimmedRect) {
            let trimmedImage = NSImage(cgImage: trimmedCGImage, size: NSSize(width: width, height: trimmedHeight))
            return trimmedImage
        }
        
        return image
    }
}

// MARK: - 长图专用的WebView导航代理类

private class LongImageNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onLoadFinished: () -> Void
    
    init(onLoadFinished: @escaping () -> Void) {
        self.onLoadFinished = onLoadFinished
        super.init()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🎯 长图WebView didFinish navigation")
        onLoadFinished()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ 长图WebView navigation failed: \(error.localizedDescription)")
        // 即使失败也尝试截图
        onLoadFinished()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ 长图WebView provisional navigation failed: \(error.localizedDescription)")
    }
}
