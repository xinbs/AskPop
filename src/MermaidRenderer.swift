//
//  MermaidRenderer.swift
//  AskPop
//
//  Created by Assistant on 2024
//  Mermaid 图表渲染器相关功能
//

import Cocoa
import WebKit

// 简易弱桥接，便于在不引入循环引用的情况下从 WebKit 接收日志
private class WeakBridge: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Custom Text View for Mermaid Input
class MermaidInputTextView: NSTextView {
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

// MARK: - Mermaid Renderer Window Controller
class MermaidRendererWindowController: NSWindowController, NSSplitViewDelegate {
    private var inputTextView: NSTextView!
    private var previewWebView: WKWebView!
    private var renderButton: NSButton!
    private var fixWithAIButton: NSButton!
    private var copyImageButton: NSButton!
    private var saveImageButton: NSButton!
    private var zoomInButton: NSButton!
    private var zoomOutButton: NSButton!
    private var zoomResetButton: NSButton!
    private var scrollView: NSScrollView!
    private var currentMermaidCode: String?
    private var currentZoomLevel: CGFloat = 1.0
    
    // 拖拽缩放状态
    private var dragOverlayView: NSView!
    private var isDragging = false
    private var lastMouseLocation = NSPoint.zero
    private var currentTranslation = NSPoint.zero
    private var currentScale: CGFloat = 1.0
    
    // AI修正相关属性
    private var isFixingWithAI: Bool = false
    private var progressIndicator: NSProgressIndicator?
    private var progressWindow: NSWindow?
    private var isProgressVisible: Bool = false
    private var currentAITask: URLSessionDataTask?
    
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
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mermaid 图表渲染器"
        window.center()
        self.window = window
        setupUI()
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        // UI 已经在 setupWindow 中设置过了
    }
    
    deinit {
        print("🗑️ MermaidRenderer: 正在清理资源")
        
        // 取消正在进行的网络请求
        currentAITask?.cancel()
        currentAITask = nil
        
        // 清理WebView委托，避免悬空指针
        if let webView = previewWebView {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }
        
        // 清理进度指示器
        hideProgressIndicator()
        
        print("✅ MermaidRenderer: 资源清理完成")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        
        // 确保文本视图可以接收焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.window?.makeFirstResponder(self.inputTextView)
            self.loadExampleMermaidCode()
        }
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        
        let contentView = NSView()
        window.contentView = contentView
        
        // 创建主要的分割视图
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        contentView.addSubview(splitView)
        
        // 左侧输入区域
        let leftContainer = NSView()
        splitView.addArrangedSubview(leftContainer)
        
        // 右侧预览区域
        let rightContainer = NSView()
        splitView.addArrangedSubview(rightContainer)
        
        // 设置分割视图约束
        splitView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        // 设置左侧输入区域
        setupInputArea(leftContainer)
        
        // 设置右侧预览区域
        setupPreviewArea(rightContainer)
        
        // 设置分割视图的初始比例
        splitView.setPosition(400, ofDividerAt: 0)
    }
    
    private func setupInputArea(_ container: NSView) {
        // 标题标签
        let titleLabel = NSTextField(labelWithString: "Mermaid 代码:")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        container.addSubview(titleLabel)
        
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
        inputTextView = MermaidInputTextView()
        inputTextView.isRichText = false
        inputTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
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
        
        // 设置默认文本内容
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
        
        container.addSubview(scrollView)
        
        // 按钮工具栏
        let buttonContainer = NSView()
        container.addSubview(buttonContainer)
        
        // 渲染按钮
        renderButton = NSButton(title: "渲染图表", target: self, action: #selector(renderMermaid))
        renderButton.bezelStyle = .rounded
        buttonContainer.addSubview(renderButton)
        
        // AI修正按钮
        fixWithAIButton = NSButton(title: "AI修正", target: self, action: #selector(fixMermaidWithAI))
        fixWithAIButton.bezelStyle = .rounded
        buttonContainer.addSubview(fixWithAIButton)
        
        // 设置约束
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        renderButton.translatesAutoresizingMaskIntoConstraints = false
        fixWithAIButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // 标题
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            
            // 文本输入区域
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: -10),
            
            // 按钮容器
            buttonContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            buttonContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            buttonContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            buttonContainer.heightAnchor.constraint(equalToConstant: 40),
            
            // 按钮
            renderButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            renderButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            renderButton.widthAnchor.constraint(equalToConstant: 100),
            
            fixWithAIButton.leadingAnchor.constraint(equalTo: renderButton.trailingAnchor, constant: 10),
            fixWithAIButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            fixWithAIButton.widthAnchor.constraint(equalToConstant: 80)
        ])
    }
    
    private func setupPreviewArea(_ container: NSView) {
        // 标题和工具栏
        let titleLabel = NSTextField(labelWithString: "图表预览:")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        container.addSubview(titleLabel)
        
        // 工具栏
        let toolbar = NSView()
        container.addSubview(toolbar)
        
        // 缩放按钮
        zoomInButton = NSButton(title: "放大", target: self, action: #selector(zoomIn))
        zoomInButton.bezelStyle = .rounded
        toolbar.addSubview(zoomInButton)
        
        zoomOutButton = NSButton(title: "缩小", target: self, action: #selector(zoomOut))
        zoomOutButton.bezelStyle = .rounded
        toolbar.addSubview(zoomOutButton)
        
        zoomResetButton = NSButton(title: "重置", target: self, action: #selector(zoomReset))
        zoomResetButton.bezelStyle = .rounded
        toolbar.addSubview(zoomResetButton)
        
        // 导出按钮
        copyImageButton = NSButton(title: "复制图片", target: self, action: #selector(copyImage))
        copyImageButton.bezelStyle = .rounded
        toolbar.addSubview(copyImageButton)
        
        saveImageButton = NSButton(title: "保存图片", target: self, action: #selector(saveImage))
        saveImageButton.bezelStyle = .rounded
        toolbar.addSubview(saveImageButton)
        
        // WebView 配置
        let webViewConfig = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        // 调试通道：前端通过 window.webkit.messageHandlers.debug.postMessage({...}) 打日志
        userContentController.add(WeakBridge(self), name: "debug")
        webViewConfig.userContentController = userContentController
        
        // 创建 WebView
        previewWebView = WKWebView(frame: .zero, configuration: webViewConfig)
        previewWebView.navigationDelegate = self
        container.addSubview(previewWebView)
        
        // 创建拖拽叠加层
        dragOverlayView = NSView(frame: .zero)
        dragOverlayView.wantsLayer = true
        dragOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(dragOverlayView)
        
        // 添加拖拽手势识别
        setupDragGestures()
        
        // 设置约束
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        previewWebView.translatesAutoresizingMaskIntoConstraints = false
        dragOverlayView.translatesAutoresizingMaskIntoConstraints = false
        zoomInButton.translatesAutoresizingMaskIntoConstraints = false
        zoomOutButton.translatesAutoresizingMaskIntoConstraints = false
        zoomResetButton.translatesAutoresizingMaskIntoConstraints = false
        copyImageButton.translatesAutoresizingMaskIntoConstraints = false
        saveImageButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // 标题
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            
            // 工具栏
            toolbar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            toolbar.heightAnchor.constraint(equalToConstant: 40),
            
            // 工具栏按钮
            zoomInButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            zoomInButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomInButton.widthAnchor.constraint(equalToConstant: 60),
            
            zoomOutButton.leadingAnchor.constraint(equalTo: zoomInButton.trailingAnchor, constant: 5),
            zoomOutButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomOutButton.widthAnchor.constraint(equalToConstant: 60),
            
            zoomResetButton.leadingAnchor.constraint(equalTo: zoomOutButton.trailingAnchor, constant: 5),
            zoomResetButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            zoomResetButton.widthAnchor.constraint(equalToConstant: 60),
            
            copyImageButton.trailingAnchor.constraint(equalTo: saveImageButton.leadingAnchor, constant: -5),
            copyImageButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            copyImageButton.widthAnchor.constraint(equalToConstant: 80),
            
            saveImageButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            saveImageButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            saveImageButton.widthAnchor.constraint(equalToConstant: 80),
            
            // WebView
            previewWebView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            previewWebView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            previewWebView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            previewWebView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            
            // 拖拽叠加层 - 完全覆盖WebView
            dragOverlayView.topAnchor.constraint(equalTo: previewWebView.topAnchor),
            dragOverlayView.leadingAnchor.constraint(equalTo: previewWebView.leadingAnchor),
            dragOverlayView.trailingAnchor.constraint(equalTo: previewWebView.trailingAnchor),
            dragOverlayView.bottomAnchor.constraint(equalTo: previewWebView.bottomAnchor)
        ])
    }
    
    // MARK: - 拖拽缩放功能
    private func setupDragGestures() {
        // 设置鼠标跟踪
        let trackingArea = NSTrackingArea(
            rect: dragOverlayView.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        dragOverlayView.addTrackingArea(trackingArea)
        
        // 设置手势识别器
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        dragOverlayView.addGestureRecognizer(panGesture)
        
        print("✅ MermaidRenderer: 拖拽手势设置完成")
    }
    
    @objc private func handlePanGesture(_ gesture: NSPanGestureRecognizer) {
        let location = gesture.location(in: dragOverlayView)
        
        switch gesture.state {
        case .began:
            isDragging = true
            lastMouseLocation = location
            print("🖱️ 开始拖拽")
            
        case .changed:
            if isDragging {
                let deltaX = location.x - lastMouseLocation.x
                let deltaY = location.y - lastMouseLocation.y
                
                currentTranslation.x += deltaX
                currentTranslation.y -= deltaY // WebView坐标系Y轴相反
                
                lastMouseLocation = location
                applyTransform()
                
                print("🔄 拖拽中: (\(currentTranslation.x), \(currentTranslation.y))")
            }
            
        case .ended, .cancelled:
            isDragging = false
            print("✋ 拖拽结束")
            
        default:
            break
        }
    }
    
    // 处理滚轮缩放
    override func scrollWheel(with event: NSEvent) {
        let scaleFactor: CGFloat = event.deltaY > 0 ? 0.9 : 1.1
        let newScale = currentScale * scaleFactor
        currentScale = max(0.1, min(5.0, newScale))
        
        applyTransform()
        print("🔍 缩放到: \(currentScale)")
    }
    
    // 应用CSS变换
    private func applyTransform() {
        guard let webView = previewWebView else { return }
        
        let jsCode = """
        if (window.applyTransform) {
            window.applyTransform(\(currentTranslation.x), \(currentTranslation.y), \(currentScale));
        }
        """
        
        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                print("❌ CSS Transform错误: \(error)")
            }
        }
    }
    
    private func loadExampleMermaidCode() {
        let exampleCode = """
graph TD
    A[开始] --> B{是否有数据?}
    B -->|是| C[处理数据]
    B -->|否| D[获取数据]
    C --> E[显示结果]
    D --> C
    E --> F[结束]
"""
        inputTextView.string = exampleCode
    }
    
    // MARK: - 渲染功能
    @objc private func renderMermaid() {
        print("🖱️ 点击了‘渲染图表’按钮")
        renderMermaidSafely()
    }
    
    private func renderMermaidSafely() {
        print("🔄 MermaidRenderer: 开始安全渲染")
        
        // 检查关键UI组件是否存在
        guard let textView = inputTextView else {
            print("❌ MermaidRenderer: inputTextView 为 nil，无法渲染")
            return
        }
        
        guard previewWebView != nil else {
            print("❌ MermaidRenderer: previewWebView 为 nil，无法渲染")
            return
        }
        
        let mermaidCode = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mermaidCode.isEmpty else {
            print("⚠️ MermaidRenderer: 检测到空的 mermaid 代码")
            showStatusMessage("请输入Mermaid代码", color: .systemRed)
            return
        }
        
        print("✅ MermaidRenderer: 开始渲染，代码长度: \(mermaidCode.count)")
        currentMermaidCode = mermaidCode
        renderMermaidInWebView(mermaidCode)
    }
    
    private func renderMermaidInWebView(_ mermaidCode: String) {
        print("🔄 MermaidRenderer: 开始渲染Mermaid图表")
        
        guard let webView = previewWebView else {
            print("❌ MermaidRenderer: WebView不存在")
            return
        }
        
        print("🛑 MermaidRenderer: 停止现有加载")
        webView.stopLoading()
        
        let htmlContent = createMermaidHTML(mermaidCode: mermaidCode)
        print("📝 MermaidRenderer: HTML内容长度: \(htmlContent.count)")
        
        webView.loadHTMLString(htmlContent, baseURL: nil)
        print("✅ MermaidRenderer: 开始加载HTML内容")
    }
    
    private func createMermaidHTML(mermaidCode: String) -> String {
        // 对输入进行安全检查
        let safeCode = mermaidCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeCode.isEmpty else {
            print("⚠️ MermaidRenderer: Mermaid代码为空")
            return createEmptyHTML()
        }
        
        // 对 HTML 中的特殊字符进行转义，但保持 Mermaid 代码的原始格式
        let htmlEscapedCode = safeCode.replacingOccurrences(of: "&", with: "&amp;")
                                       .replacingOccurrences(of: "<", with: "&lt;")
                                       .replacingOccurrences(of: ">", with: "&gt;")
        
        // 恢复原来的Mermaid.js客户端渲染，但保留Swift拖拽缩放控制
        let html = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <style>
        body {
            margin: 0;
      padding: 0; 
      background: white; 
      font-family: Arial, sans-serif; 
      overflow: hidden;
    }
    #mermaid-diagram { 
      width: 100vw; 
      height: 100vh; 
            display: flex;
            align-items: center;
      justify-content: center;
      position: relative;
      overflow: visible;
        }
    #mermaid-diagram svg { 
      max-width: none; 
      max-height: none; 
      display: block;
            transform-origin: center center;
        }
    </style>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10.6.1/dist/mermaid.min.js"></script>
</head>
<body>
  <div id="mermaid-diagram">
    \(htmlEscapedCode)
    </div>
    
    <script>
    window.webkit.messageHandlers.debug.postMessage('🎬 Mermaid.js开始初始化');
    
            // 配置Mermaid - 参考SVG默认样式的优雅主题
        mermaid.initialize({
          startOnLoad: false,
          theme: 'base',
            securityLevel: 'loose',
          fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
          themeVariables: {
            // 主要颜色：清爽蓝色系
            primaryColor: '#f3f9ff',
            primaryTextColor: '#2c3e50',
            primaryBorderColor: '#2196f3',
            
            // 决策节点：温暖橙黄色系
            secondaryColor: '#fff8e1',
            secondaryTextColor: '#2c3e50',
            secondaryBorderColor: '#ff9800',
            
            // 开始结束节点：清新绿色系
            tertiaryColor: '#e8f5e8',
            tertiaryTextColor: '#2c3e50',
            tertiaryBorderColor: '#4caf50',
            
            // 线条和箭头
            lineColor: '#5d6d7e',
            arrowheadColor: '#34495e',
            
            // 背景和其他
            background: '#ffffff',
            mainBkg: '#f3f9ff',
            secondBkg: '#fff8e1',
            tertiaryBkg: '#e8f5e8',
            
            // 特殊元素：数据库等
            cScale0: '#e0e0e0',  // 圆柱数据库颜色
            cScale1: '#e0e0e0',
            cScale2: '#e0e0e0',
            
            // 文字样式 - 保持简洁避免影响布局
            textColor: '#2c3e50'
          }
        });
    
    // 等待DOM准备就绪后渲染
    function renderMermaid() {
      const element = document.getElementById('mermaid-diagram');
      if (!element) {
        window.webkit.messageHandlers.debug.postMessage('❌ 找不到mermaid-diagram元素');
        return;
      }
      
      window.webkit.messageHandlers.debug.postMessage('🔄 开始渲染Mermaid图表');
      
      mermaid.init(undefined, element).then(() => {
        window.webkit.messageHandlers.debug.postMessage('✅ Mermaid渲染完成');
        
        // 查找生成的SVG并设置ID和修复样式
        const svg = element.querySelector('svg');
        if (svg) {
          svg.id = 'mermaid-svg';
          svg.style.transformOrigin = 'center center';
          
          // 智能美化SVG样式：基于元素类型和上下文选择合适颜色
          window.webkit.messageHandlers.debug.postMessage('🎨 开始处理SVG样式');
          
          svg.querySelectorAll('*').forEach(el => {
            // 分析元素类型和上下文
            const isStartEnd = el.closest('.start') || el.closest('.end') || 
                              (el.textContent && (el.textContent.includes('开始') || el.textContent.includes('结束')));
            const isDecision = el.closest('.decision') || el.tagName === 'polygon' ||
                              (el.textContent && (el.textContent.includes('?') || el.textContent.includes('是否')));
            const isProcess = el.closest('.process') || el.tagName === 'rect';
            const isArrow = el.classList.contains('arrowhead') || el.getAttribute('marker-end') || 
                           (el.tagName === 'path' && el.getAttribute('d') && el.getAttribute('d').includes('M'));
            const isText = el.tagName === 'text' || el.tagName === 'tspan';
            // 更准确的数据库识别：圆柱形通常是多个路径组合
            const parentG = el.closest('g');
            const isDatabase = (el.tagName === 'path' && el.getAttribute('d') && 
                              (el.getAttribute('d').includes('ellipse') || 
                               (el.getAttribute('d').includes('A') && el.getAttribute('d').includes('Z')))) ||
                              el.closest('g[class*="cluster"]') || 
                              (parentG && parentG.querySelector('ellipse'));
            
            // 修复所有黑色问题，包括已有的黑色填充
            const currentFill = el.getAttribute('fill');
            const currentStroke = el.getAttribute('stroke');
            
            // 处理黑色填充或没有填充的可见元素
            if (currentFill === 'black' || currentFill === '#000000' || currentFill === '#000' || 
                (!currentFill && (el.tagName === 'rect' || el.tagName === 'circle' || el.tagName === 'ellipse' || 
                                 el.tagName === 'polygon' || (el.tagName === 'path' && !isArrow)))) {
              window.webkit.messageHandlers.debug.postMessage('🖖️ 处理元素: ' + el.tagName + ' fill=' + (currentFill || 'none'));
              
              if (isText) {
                // 文字：设置深色
                el.setAttribute('fill', '#2c3e50');
              } else if (el.tagName === 'path' && !isArrow) {
                // 数据库圆柱等复杂形状：设置为浅灰色
                window.webkit.messageHandlers.debug.postMessage('🗄️ 处理Path元素: d=' + (el.getAttribute('d') || '').substring(0, 50));
                el.setAttribute('fill', '#e0e0e0');
                el.style.fill = '#e0e0e0'; // 强制设置style属性
                if (!currentStroke) {
                  el.setAttribute('stroke', '#757575');
                  el.setAttribute('stroke-width', '2px');
                }
              } else if (el.tagName === 'rect') {
                // 矩形节点：蓝色
                el.setAttribute('fill', '#f3f9ff');
                if (!currentStroke) {
                  el.setAttribute('stroke', '#2196f3');
                  el.setAttribute('stroke-width', '2px');
                }
              } else if (el.tagName === 'polygon') {
                // 决策节点：黄色
                el.setAttribute('fill', '#fff8e1');
                if (!currentStroke) {
                  el.setAttribute('stroke', '#ff9800');
                  el.setAttribute('stroke-width', '2px');
                }
              } else if (el.tagName === 'circle' || el.tagName === 'ellipse') {
                // 圆形节点：绿色
                el.setAttribute('fill', '#e8f5e8');
                if (!currentStroke) {
                  el.setAttribute('stroke', '#4caf50');
                  el.setAttribute('stroke-width', '2px');
                }
              } else {
                // 其他：浅灰色
                el.setAttribute('fill', '#f5f5f5');
                if (!currentStroke) {
                  el.setAttribute('stroke', '#616161');
                  el.setAttribute('stroke-width', '1.5px');
                }
              }
            }
            
            // 处理黑色描边
            if (currentStroke === 'black' || currentStroke === '#000000' || currentStroke === '#000') {
              window.webkit.messageHandlers.debug.postMessage('🖖️ 处理黑色描边: ' + el.tagName);
              el.setAttribute('stroke', '#616161');
            }
            
            // 优化线条和箭头样式
            if (el.tagName === 'path' || el.tagName === 'line' || el.tagName === 'polyline') {
              if (!el.hasAttribute('stroke') || el.getAttribute('stroke') === 'black' || el.getAttribute('stroke') === '#000000') {
                el.setAttribute('stroke', '#5d6d7e'); // 优雅的蓝灰色
                el.setAttribute('stroke-width', '1.8px');
                el.setAttribute('stroke-linecap', 'round');
                el.setAttribute('stroke-linejoin', 'round');
              }
              
              // 特殊处理箭头
              if (isArrow || el.getAttribute('marker-end')) {
                el.setAttribute('stroke', '#34495e');
                el.setAttribute('stroke-width', '2px');
                el.style.filter = 'drop-shadow(0 1px 2px rgba(0,0,0,0.1))';
              }
            }
            
            // 箭头标记优化
            if (el.tagName === 'marker' || el.closest('marker')) {
              el.setAttribute('fill', '#34495e');
            }
            
            // 为主要形状添加微妙阴影
            if ((el.tagName === 'rect' || el.tagName === 'circle' || el.tagName === 'ellipse' || el.tagName === 'polygon') && 
                !isArrow && el.getAttribute('fill') && el.getAttribute('fill') !== 'none') {
              el.style.filter = 'drop-shadow(0 1px 3px rgba(0,0,0,0.08))';
            }
          });
          
          // 处理文字元素 - 确保文字不被边框挡住
          const allTextElements = svg.querySelectorAll('text, tspan, foreignObject');
          window.webkit.messageHandlers.debug.postMessage('📝 找到 ' + allTextElements.length + ' 个文字元素');
          
          allTextElements.forEach((textEl, index) => {
            window.webkit.messageHandlers.debug.postMessage('📝 处理文字[' + index + ']: ' + textEl.tagName + ' 内容=' + (textEl.textContent || '').substring(0, 20));
            
            // 确保文字有正确的颜色
            if (!textEl.getAttribute('fill') || textEl.getAttribute('fill') === 'black' || textEl.getAttribute('fill') === '#000000') {
              textEl.setAttribute('fill', '#2c3e50');
              textEl.style.fill = '#2c3e50'; // 强制设置style
            }
            
            // 确保文字在最上层，不添加背景
            if (textEl.tagName === 'text' || textEl.tagName === 'foreignObject') {
              textEl.style.zIndex = '1000';
              textEl.style.pointerEvents = 'none';
              
              if (textEl.tagName === 'text') {
                textEl.style.dominantBaseline = 'central';
                textEl.style.textAnchor = 'middle';
              }
              
              window.webkit.messageHandlers.debug.postMessage('📝 文字处理完成，无背景: ' + (textEl.textContent || '').substring(0, 10));
            }
          });
          
          // 专门处理所有图形的文字框大小不够的问题
          const allGroups = svg.querySelectorAll('g');
          allGroups.forEach(group => {
            const textEl = group.querySelector('foreignObject');
            const rectEl = group.querySelector('rect');
            const polygonEl = group.querySelector('polygon');
            const circleEl = group.querySelector('circle');
            const ellipseEl = group.querySelector('ellipse');
            const pathEl = group.querySelector('path');
            
            if (textEl && textEl.textContent) {
              const textContent = textEl.textContent.trim();
              if (textContent.length > 0) {
                const textLength = textContent.length;
                const currentWidth = parseFloat(textEl.getAttribute('width') || '0');
                const currentHeight = parseFloat(textEl.getAttribute('height') || '0');
                const minWidth = textLength * 12 + 20; // 每字符12px + 边距
                const minHeight = Math.max(24, currentHeight); // 确保足够高度
                
                let shapeType = '';
                if (polygonEl) shapeType = '多边形';
                else if (rectEl) shapeType = '矩形';
                else if (circleEl || ellipseEl) shapeType = '圆形';
                else if (pathEl) shapeType = '路径';
                else shapeType = '未知';
                
                window.webkit.messageHandlers.debug.postMessage('📏 ' + shapeType + '文字框: "' + textContent + '" 当前=' + currentWidth + 'x' + currentHeight + ' 需要=' + minWidth + 'x' + minHeight);
                
                let needsUpdate = false;
                
                // 检查宽度
                if (minWidth > currentWidth) {
                  textEl.setAttribute('width', minWidth.toString());
                  
                  // 调整x位置保持文字居中
                  const currentX = parseFloat(textEl.getAttribute('x') || '0');
                  const newX = currentX - (minWidth - currentWidth) / 2;
                  textEl.setAttribute('x', newX.toString());
                  
                  needsUpdate = true;
                }
                
                // 检查高度
                if (minHeight > currentHeight) {
                  textEl.setAttribute('height', minHeight.toString());
                  
                  // 调整y位置保持文字居中
                  const currentY = parseFloat(textEl.getAttribute('y') || '0');
                  const newY = currentY - (minHeight - currentHeight) / 2;
                  textEl.setAttribute('y', newY.toString());
                  
                  needsUpdate = true;
                }
                
                if (needsUpdate) {
                  // 确保文字居中显示
                  const divEl = textEl.querySelector('div');
                  if (divEl) {
                    divEl.style.textAlign = 'center';
                    divEl.style.lineHeight = minHeight + 'px';
                    divEl.style.height = minHeight + 'px';
                    divEl.style.display = 'flex';
                    divEl.style.alignItems = 'center';
                    divEl.style.justifyContent = 'center';
                    divEl.style.overflow = 'visible';
                  }
                  
                  window.webkit.messageHandlers.debug.postMessage('📏 ' + shapeType + '文字框已调整: ' + currentWidth + 'x' + currentHeight + ' -> ' + minWidth + 'x' + minHeight);
                }
              }
            }
          });
          
          // 专门处理圆柱形数据库（可能是特殊组合）
          const allElements = svg.querySelectorAll('*');
          let databaseElements = [];
          
          allElements.forEach(el => {
            // 查找可能的数据库元素
            const computedFill = window.getComputedStyle(el).fill;
            const computedStroke = window.getComputedStyle(el).stroke;
            
            if ((computedFill === 'rgb(0, 0, 0)' || computedFill === 'black') && 
                (el.tagName === 'path' || el.tagName === 'ellipse' || el.tagName === 'rect')) {
              databaseElements.push(el);
              window.webkit.messageHandlers.debug.postMessage('🗄️ 处理黑色圆柱: ' + el.tagName + ' fill=' + computedFill);
              
              // 多种方式强制覆盖圆柱颜色
              el.setAttribute('fill', '#e0e0e0');
              el.style.fill = '#e0e0e0';
              el.style.setProperty('fill', '#e0e0e0', 'important');
              
              el.setAttribute('stroke', '#757575');
              el.style.stroke = '#757575';
              el.style.setProperty('stroke', '#757575', 'important');
              
              el.setAttribute('stroke-width', '2px');
              el.style.strokeWidth = '2px';
              el.style.setProperty('stroke-width', '2px', 'important');
              
              window.webkit.messageHandlers.debug.postMessage('🗄️ 圆柱颜色已强制设置为浅灰色');
            }
          });
          
          // 统计处理结果
          const textElements = svg.querySelectorAll('text, tspan, foreignObject');
          const blackFillElements = svg.querySelectorAll('[fill="black"], [fill="#000000"], [fill="#000"]');
          const blackStrokeElements = svg.querySelectorAll('[stroke="black"], [stroke="#000000"], [stroke="#000"]');
          const allPaths = svg.querySelectorAll('path');
          
          window.webkit.messageHandlers.debug.postMessage('✅ SVG处理统计:');
          window.webkit.messageHandlers.debug.postMessage('  - ' + textElements.length + '个文字元素');
          window.webkit.messageHandlers.debug.postMessage('  - ' + blackFillElements.length + '个黑色填充元素');
          window.webkit.messageHandlers.debug.postMessage('  - ' + blackStrokeElements.length + '个黑色描边元素');
          window.webkit.messageHandlers.debug.postMessage('  - ' + allPaths.length + '个路径元素');
          window.webkit.messageHandlers.debug.postMessage('  - ' + databaseElements.length + '个数据库元素(计算样式黑色)');
        }
      }).catch(error => {
        window.webkit.messageHandlers.debug.postMessage('❌ Mermaid渲染失败: ' + error);
      });
    }
    
    // Swift控制的变换函数
    window.applyTransform = function(translateX, translateY, scale) {
      const svg = document.getElementById('mermaid-svg');
      if (svg) {
        svg.style.transform = 'translate(' + translateX + 'px, ' + translateY + 'px) scale(' + scale + ')';
        window.webkit.messageHandlers.debug.postMessage('🔄 应用变换: translate(' + translateX + ', ' + translateY + ') scale(' + scale + ')');
      }
    };
    
    // 等待DOM加载完成后渲染
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', renderMermaid);
    } else {
      renderMermaid();
        }
    </script>
</body>
</html>
"""
        
        print("📄 MermaidRenderer: HTML内容生成完成")
        return html
    }
    
    private func createEmptyHTML() -> String {
        return """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Empty Mermaid Diagram</title>
    <style>
        body {
            margin: 0;
            padding: 20px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background-color: #ffffff;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            color: #666;
        }
    </style>
</head>
<body>
    <div>请输入Mermaid代码</div>
</body>
</html>
"""
    }
    
    // MARK: - AI修正功能
    @objc private func fixMermaidWithAI() {
        print("🔧 MermaidRenderer: 开始AI修正流程")
        
        let mermaidCode = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📝 MermaidRenderer: 当前代码长度: \(mermaidCode.count)")
        
        guard !mermaidCode.isEmpty else {
            showStatusMessage("请先输入Mermaid代码", color: .systemRed, icon: "⚠️")
            return
        }
        
        if isFixingWithAI {
            return
        }
        
        // 取消之前的任务（如果有）
        currentAITask?.cancel()
        currentAITask = nil
        
        isFixingWithAI = true
        fixWithAIButton.title = "修正中..."
        fixWithAIButton.isEnabled = false
        
        // 显示进度指示器
        showProgressIndicator(message: "AI正在分析和修正代码...")
        
        let prompt = """
    请检查并修正以下Mermaid代码中的语法错误。如果代码正确，请直接返回原代码。如果有错误，请修正并返回正确的代码。只返回Mermaid代码，不要添加任何解释或markdown格式。
    
    Mermaid代码:
    \(mermaidCode)
    """
        
        // 调用AI API修正代码
        callAIForMermaidFix(prompt: prompt) { [weak self] result in
            print("🔄 MermaidRenderer: AI修正完成，准备处理结果")
            
            // 在后台线程处理完成，需要回到主线程更新UI
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else {
                    print("⚠️ MermaidRenderer: self已被释放")
                    return
                }
                
                // 首先隐藏进度指示器和重置状态
                strongSelf.isFixingWithAI = false
                strongSelf.fixWithAIButton.title = "AI修正"
                strongSelf.fixWithAIButton.isEnabled = true
                strongSelf.hideProgressIndicator()
                strongSelf.currentAITask = nil
                
                print("📝 MermaidRenderer: 处理AI修正结果")
                
                // 处理结果
                switch result {
                case .success(let fixedCode):
                    print("✅ MermaidRenderer: 修正成功")
                    print("📝 MermaidRenderer: AI返回的修正代码: \(fixedCode)")
                    
                    // 安全地更新文本视图
                    if let textView = strongSelf.inputTextView {
                        textView.string = fixedCode
                    strongSelf.showStatusMessage("AI修正完成", color: .systemGreen, icon: "✅")
                        print("🎯 MermaidRenderer: 文本已更新，请手动点击渲染按钮")
                    }
                    
                case .failure(let error):
                    print("❌ MermaidRenderer: 修正失败 - \(error.localizedDescription)")
                    strongSelf.showStatusMessage("AI修正失败: \(error.localizedDescription)", color: .systemRed, icon: "❌")
                }
                
                print("🏁 MermaidRenderer: AI修正处理完成")
            }
        }
    }
    
    private func callAIForMermaidFix(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        // 获取应用委托来访问AI配置
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            print("❌ MermaidRenderer: 无法获取 AppDelegate")
            DispatchQueue.main.async {
            completion(.failure(NSError(domain: "MermaidRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取应用配置"])))
            }
            return
        }
        
        print("✅ MermaidRenderer: 成功获取 AppDelegate")
        print("🔑 API Key: \(appDelegate.apiKey.isEmpty ? "空" : "已设置")")
        print("🌐 API URL: \(appDelegate.apiURL)")
        print("🤖 Model: \(appDelegate.model)")
        print("🌡️ Temperature: \(appDelegate.temperature)")
        
        // 检查API配置
        guard !appDelegate.apiKey.isEmpty else {
            print("❌ MermaidRenderer: API密钥为空")
            DispatchQueue.main.async {
            completion(.failure(NSError(domain: "MermaidRenderer", code: -2, userInfo: [NSLocalizedDescriptionKey: "API密钥未配置，请在设置中配置"])))
            }
            return
        }
        
        guard !appDelegate.apiURL.isEmpty else {
            print("❌ MermaidRenderer: API地址为空")
            DispatchQueue.main.async {
            completion(.failure(NSError(domain: "MermaidRenderer", code: -3, userInfo: [NSLocalizedDescriptionKey: "API地址未配置，请在设置中配置"])))
            }
            return
        }
        
        // 构建消息数组
        let messages = [
            ["role": "user", "content": prompt]
        ]
        
        // 构建请求体
        var requestBody: [String: Any] = [
            "model": appDelegate.model,
            "messages": messages,
            "stream": false
        ]
        
        // 只有在温度开关开启时才添加temperature参数
        if appDelegate.enableTemperature {
            requestBody["temperature"] = appDelegate.temperature
        }
        
        // 创建请求
        guard let url = URL(string: appDelegate.apiURL) else {
            DispatchQueue.main.async {
            completion(.failure(NSError(domain: "MermaidRenderer", code: -4, userInfo: [NSLocalizedDescriptionKey: "API地址格式无效"])))
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(appDelegate.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60.0 // 设置60秒超时，防止无限期等待
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DispatchQueue.main.async {
            completion(.failure(NSError(domain: "MermaidRenderer", code: -5, userInfo: [NSLocalizedDescriptionKey: "请求数据序列化失败: \(error.localizedDescription)"])))
            }
            return
        }
        
        print("🚀 MermaidRenderer: 开始发送网络请求")
        
        // 发送请求
        currentAITask = URLSession.shared.dataTask(with: request) { data, response, error in
            // 处理网络响应的本地函数，避免在闭包中持有self
            func handleResponse() {
                print("📡 MermaidRenderer: 收到网络响应")
                
                // 检查任务是否被取消
                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    print("🚫 MermaidRenderer: 网络请求已被取消")
                return
            }
            
            // 网络错误处理
            if let error = error {
                print("❌ MermaidRenderer: 网络请求错误 - \(error.localizedDescription)")
                let nsError = error as NSError
                var errorMessage = "网络请求失败"
                
                if nsError.code == NSURLErrorTimedOut {
                    errorMessage = "请求超时，请检查网络连接"
                } else if nsError.code == NSURLErrorNotConnectedToInternet {
                    errorMessage = "网络连接不可用"
                } else if nsError.code == NSURLErrorCannotFindHost {
                    errorMessage = "无法连接到服务器，请检查API地址"
                } else {
                    errorMessage = "网络错误: \(error.localizedDescription)"
                }
                
                    DispatchQueue.main.async {
                completion(.failure(NSError(domain: "MermaidRenderer", code: -6, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                    }
                return
            }
            
            // HTTP状态码检查
            if let httpResponse = response as? HTTPURLResponse {
                print("📊 MermaidRenderer: HTTP状态码 - \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    var errorMessage = "服务器错误"
                    switch httpResponse.statusCode {
                    case 401:
                        errorMessage = "API密钥无效或已过期"
                    case 403:
                        errorMessage = "访问被拒绝，请检查API权限"
                    case 429:
                        errorMessage = "请求过于频繁，请稍后再试"
                    case 500...599:
                        errorMessage = "服务器内部错误，请稍后再试"
                    default:
                        errorMessage = "HTTP错误: \(httpResponse.statusCode)"
                    }
                    
                    print("❌ MermaidRenderer: HTTP错误 - \(errorMessage)")
                        DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MermaidRenderer", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                        }
                    return
                }
            }
            
            guard let data = data else {
                print("❌ MermaidRenderer: 服务器返回空数据")
                    DispatchQueue.main.async {
                completion(.failure(NSError(domain: "MermaidRenderer", code: -7, userInfo: [NSLocalizedDescriptionKey: "服务器未返回数据"])))
                    }
                return
            }
            
            print("📦 MermaidRenderer: 收到数据，大小: \(data.count) 字节")
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("❌ MermaidRenderer: 无法解析为JSON对象")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("📄 MermaidRenderer: 原始响应: \(responseString.prefix(200))...")
                    }
                        DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MermaidRenderer", code: -8, userInfo: [NSLocalizedDescriptionKey: "响应数据格式错误"])))
                        }
                    return
                }
                
                print("✅ MermaidRenderer: JSON解析成功")
                print("📋 MermaidRenderer: JSON键: \(Array(json.keys))")
                
                // 检查API错误
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ MermaidRenderer: API返回错误 - \(message)")
                        DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MermaidRenderer", code: -9, userInfo: [NSLocalizedDescriptionKey: "API错误: \(message)"])))
                        }
                    return
                }
                
                // 处理不同的API响应格式
                var content: String?
                
                // OpenAI格式
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let messageContent = message["content"] as? String {
                    print("🤖 MermaidRenderer: 使用OpenAI格式解析")
                    content = messageContent
                }
                // Claude格式
                else if let claudeContent = json["content"] as? [[String: Any]],
                        let firstContent = claudeContent.first,
                        let text = firstContent["text"] as? String {
                    print("🤖 MermaidRenderer: 使用Claude格式解析")
                    content = text
                }
                // 通用格式
                else if let directContent = json["content"] as? String {
                    print("🤖 MermaidRenderer: 使用通用格式解析")
                    content = directContent
                }
                
                if let content = content, !content.isEmpty {
                    print("✅ MermaidRenderer: AI修正成功，内容长度: \(content.count)")
                    let fixedCode = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        DispatchQueue.main.async {
                    completion(.success(fixedCode))
                        }
                } else {
                    print("❌ MermaidRenderer: AI返回的内容为空或格式不正确")
                        DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "MermaidRenderer", code: -10, userInfo: [NSLocalizedDescriptionKey: "AI响应格式不正确或内容为空"])))
                        }
                }
            } catch {
                print("❌ MermaidRenderer: JSON解析异常 - \(error.localizedDescription)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📄 MermaidRenderer: 原始响应: \(responseString.prefix(200))...")
                }
                    DispatchQueue.main.async {
                completion(.failure(NSError(domain: "MermaidRenderer", code: -12, userInfo: [NSLocalizedDescriptionKey: "解析响应数据失败: \(error.localizedDescription)"])))
                    }
                }
            }
            
            // 调用处理函数
            handleResponse()
        }
        
        currentAITask?.resume()
         print("🚀 MermaidRenderer: 网络任务已启动")
    }
    
    // MARK: - 缩放控制
    @objc private func zoomIn() {
        currentScale = min(currentScale * 1.2, 5.0)
        applyTransform()
        print("🔍 按钮放大到: \(currentScale)")
    }
    
    @objc private func zoomOut() {
        currentScale = max(currentScale / 1.2, 0.1)
        applyTransform()
        print("🔍 按钮缩小到: \(currentScale)")
    }
    
    @objc private func zoomReset() {
        currentScale = 1.0
        currentTranslation = NSPoint.zero
        applyTransform()
        print("🔄 重置视图")
    }
    

    
    // MARK: - 图片导出功能
    @objc private func copyImage() {
        captureWebViewAsImage { [weak self] image in
            DispatchQueue.main.async {
                if let image = image {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                    self?.showStatusMessage("图片已复制到剪贴板", color: .systemGreen)
                } else {
                    self?.showStatusMessage("图片复制失败", color: .systemRed)
                }
            }
        }
    }
    
    @objc private func saveImage() {
        captureWebViewAsImage { [weak self] image in
            DispatchQueue.main.async {
                guard let image = image else {
                    self?.showStatusMessage("图片生成失败", color: .systemRed)
                    return
                }
                
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.png]
                savePanel.nameFieldStringValue = "mermaid-diagram.png"
                
                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        if let tiffData = image.tiffRepresentation,
                           let bitmapRep = NSBitmapImageRep(data: tiffData),
                           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                            do {
                                try pngData.write(to: url)
                                self?.showStatusMessage("图片保存成功", color: .systemGreen)
                            } catch {
                                self?.showStatusMessage("图片保存失败: \(error.localizedDescription)", color: .systemRed)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func captureWebViewAsImage(completion: @escaping (NSImage?) -> Void) {
        let config = WKSnapshotConfiguration()
        previewWebView.takeSnapshot(with: config) { image, error in
            if let error = error {
                print("截图失败: \(error)")
                completion(nil)
            } else {
                completion(image)
            }
        }
    }
    
    // MARK: - 状态消息
    private func showStatusMessage(_ message: String, color: NSColor, icon: String? = nil) {
        let displayMessage = (icon != nil) ? "\(icon!) \(message)" : message
        print("📢 状态消息: \(displayMessage)")
        // 完全移除UI状态显示，只保留控制台输出以避免崩溃
    }
    
    // MARK: - WKScriptMessageHandler (已禁用以避免循环引用)
    // func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    //     // 暂时禁用以避免循环引用导致的崩溃
    // }
}

// MARK: - WKNavigationDelegate
extension MermaidRendererWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ MermaidRenderer: WebView页面加载完成")
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ MermaidRenderer: WebView页面加载失败 - \(error.localizedDescription)")
        // 暂时移除UI状态显示避免崩溃
        // showStatusMessage("页面加载失败: \(error.localizedDescription)", color: .systemRed, icon: "❌")
    }
}

// MARK: - NSSplitViewDelegate
extension MermaidRendererWindowController {
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        return false // 防止子视图被完全折叠
    }
    
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return 200 // 左侧最小宽度200像素
    }
    
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return splitView.frame.width - 200 // 右侧最小宽度200像素
    }
    
    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        // 自定义调整大小行为，保持比例
        guard splitView.subviews.count == 2 else {
            splitView.adjustSubviews()
            return
        }
        
        let leftView = splitView.subviews[0]
        let rightView = splitView.subviews[1]
        let dividerThickness = splitView.dividerThickness
        
        let totalWidth = splitView.frame.width
        let leftWidth = max(200, min(totalWidth - 200 - dividerThickness, leftView.frame.width))
        let rightWidth = totalWidth - leftWidth - dividerThickness
        
        leftView.frame = NSRect(x: 0, y: 0, width: leftWidth, height: splitView.frame.height)
        rightView.frame = NSRect(x: leftWidth + dividerThickness, y: 0, width: rightWidth, height: splitView.frame.height)
    }
}

// MARK: - WebView Debug Bridge
extension MermaidRendererWindowController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "debug" {
            print("[WebView] debug: \(message.body)")
        }
    }
}

extension MermaidRendererWindowController {
    // MARK: - 进度指示器
    private func showProgressIndicator(message: String) {
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        if self.isProgressVisible { return }
    
    // 创建进度窗口
        self.progressWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 250, height: 100),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    
        guard let progressWindow = self.progressWindow else { return }
    
        progressWindow.isReleasedWhenClosed = false
    progressWindow.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95)
    progressWindow.level = .floating
    progressWindow.isOpaque = false
    progressWindow.hasShadow = true
        progressWindow.collectionBehavior = [.transient]
    progressWindow.contentView?.wantsLayer = true
    progressWindow.contentView?.layer?.cornerRadius = 8
    
    let containerView = NSView(frame: progressWindow.contentRect(forFrameRect: progressWindow.frame))
    
    // 创建进度指示器
        self.progressIndicator = NSProgressIndicator(frame: NSRect(x: 75, y: 50, width: 100, height: 20))
        self.progressIndicator!.style = .spinning
        self.progressIndicator!.startAnimation(nil)
        containerView.addSubview(self.progressIndicator!)
    
    // 创建消息标签
    let label = NSTextField(labelWithString: message)
    label.textColor = .labelColor
    label.font = NSFont.systemFont(ofSize: 12)
    label.alignment = .center
    label.frame = NSRect(x: 10, y: 20, width: 230, height: 20)
    containerView.addSubview(label)
    
    progressWindow.contentView = containerView
    
    // 居中显示
        if let mainWindow = self.window {
        let mainFrame = mainWindow.frame
        let progressFrame = progressWindow.frame
        let x = mainFrame.midX - progressFrame.width / 2
        let y = mainFrame.midY - progressFrame.height / 2
        progressWindow.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
        progressWindow.orderFrontRegardless()
        self.isProgressVisible = true
    }
    }
    
    private func hideProgressIndicator() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.isProgressVisible { return }
            self.progressIndicator?.stopAnimation(nil)
            self.progressIndicator = nil
            self.progressWindow?.orderOut(nil)
            self.progressWindow = nil
            self.isProgressVisible = false
        }
    }
}