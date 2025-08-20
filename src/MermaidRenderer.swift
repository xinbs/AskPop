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
        
        // 设置约束
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        previewWebView.translatesAutoresizingMaskIntoConstraints = false
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
            previewWebView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])
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
        print("🌐 MermaidRenderer: 准备加载WebView内容")
        
        guard let webView = previewWebView else {
            print("❌ MermaidRenderer: previewWebView 在渲染时为 nil")
            return
        }
        
        print("🔍 MermaidRenderer: WebView状态检查...")
        print("   - WebView存在: ✅")
        print("   - 当前线程是主线程: \(Thread.isMainThread ? "✅" : "❌")")
        
        // 先停止现有的加载
        print("🛑 MermaidRenderer: 停止现有加载")
        webView.stopLoading()
        
        let htmlContent = createMermaidHTML(mermaidCode: mermaidCode)
        print("📝 MermaidRenderer: HTML内容长度: \(htmlContent.count)")
        
        // 直接在当前线程加载（应该已经在主线程）
        print("🚀 MermaidRenderer: 即将调用 loadHTMLString")
        
        // 使用异常捕获来检测是否有问题
        autoreleasepool {
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
        
        print("✅ MermaidRenderer: loadHTMLString 调用完成")
        print("📊 MermaidRenderer: WebView isLoading = \(webView.isLoading)")
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
        
        // 采用 svg-pan-zoom 管理交互，避免自研矩阵与包裹逻辑带来的边界与失真问题
        let html = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Mermaid Diagram</title>
  <script src="https://cdn.jsdelivr.net/npm/mermaid@10.6.1/dist/mermaid.min.js"></script>
  <script src="https://unpkg.com/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js"></script>
  <style>
    html, body { 
      height: 100%; 
      width: 100%; 
      margin: 0; 
      padding: 0; 
      background: #ffffff; 
      overflow: visible; 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
    }
    #stage { 
      position: absolute; 
      top: 0; 
      left: 0; 
      right: 0; 
      bottom: 0; 
      width: 100%; 
      height: 100%; 
      overflow: visible;
    }
    #mermaid-diagram { 
      width: 100%; 
      height: 100%; 
      overflow: visible;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    #mermaid-diagram svg { 
      width: 100% !important; 
      height: 100% !important; 
      display: block; 
      overflow: visible;
    }
    .error { 
      color: #d32f2f; 
      background-color: #ffebee; 
      padding: 12px 16px; 
      border-radius: 8px; 
      border: 1px solid #ffcdd2; 
      font-family: SFMono-Regular, Menlo, monospace; 
      white-space: pre-wrap; 
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
    }
  </style>
</head>
<body>
  <div id="stage">
    <div id="mermaid-diagram" class="mermaid">\(htmlEscapedCode)</div>
  </div>
  <script>
    (function(){
      var panZoom;
      
      // 动态viewBox管理器 - 实时计算支持无限拖拽和缩放
      window.dynamicViewBoxManager = {
        handlePan: function(instance, oldPan, newPan) {
          var svgElement = instance.getSvg();
          var currentZoom = instance.getZoom();
          
          try {
            var viewBox = svgElement.getAttribute('viewBox').split(' ');
            var vbX = parseFloat(viewBox[0]);
            var vbY = parseFloat(viewBox[1]);
            var vbW = parseFloat(viewBox[2]);
            var vbH = parseFloat(viewBox[3]);
            
            // 计算容器尺寸
            var containerRect = svgElement.parentElement.getBoundingClientRect();
            var containerW = containerRect.width;
            var containerH = containerRect.height;
            
            // 计算当前视口在SVG坐标系中的位置和尺寸
            var viewportW = containerW / currentZoom;
            var viewportH = containerH / currentZoom;
            var viewportX = vbX + (vbW - viewportW) / 2 - newPan.x / currentZoom;
            var viewportY = vbY + (vbH - viewportH) / 2 - newPan.y / currentZoom;
            
            // 检查是否需要扩展viewBox（当视口接近边界时）
            var margin = Math.min(vbW, vbH) * 0.05; // 5%边距触发扩展
            var expansionFactor = 1.5; // 扩展倍数
            var needsExpansion = false;
            var newVbX = vbX, newVbY = vbY, newVbW = vbW, newVbH = vbH;
            
            // 左边界检查
            if (viewportX < vbX + margin) {
              var expansion = vbW * (expansionFactor - 1) / 2;
              newVbX = vbX - expansion;
              newVbW = vbW + expansion;
              needsExpansion = true;
            }
            // 右边界检查
            if (viewportX + viewportW > vbX + vbW - margin) {
              var expansion = vbW * (expansionFactor - 1) / 2;
              newVbW = vbW + expansion;
              needsExpansion = true;
            }
            // 上边界检查
            if (viewportY < vbY + margin) {
              var expansion = vbH * (expansionFactor - 1) / 2;
              newVbY = vbY - expansion;
              newVbH = vbH + expansion;
              needsExpansion = true;
            }
            // 下边界检查
            if (viewportY + viewportH > vbY + vbH - margin) {
              var expansion = vbH * (expansionFactor - 1) / 2;
              newVbH = vbH + expansion;
              needsExpansion = true;
            }
            
            if (needsExpansion) {
              svgElement.setAttribute('viewBox', newVbX + ' ' + newVbY + ' ' + newVbW + ' ' + newVbH);
              console.log('拖拽时扩展viewBox:', 'x=' + newVbX.toFixed(1), 'y=' + newVbY.toFixed(1), 'w=' + newVbW.toFixed(1), 'h=' + newVbH.toFixed(1));
            }
            
          } catch(e) {
            console.log('拖拽计算错误:', e);
          }
          
          return {x: newPan.x, y: newPan.y};
        },
        
        handleZoom: function(instance, newZoom) {
          // 缩放时确保有足够的viewBox空间
          var svgElement = instance.getSvg();
          var currentPan = instance.getPan();
          
          try {
            var viewBox = svgElement.getAttribute('viewBox').split(' ');
            var vbX = parseFloat(viewBox[0]);
            var vbY = parseFloat(viewBox[1]);
            var vbW = parseFloat(viewBox[2]);
            var vbH = parseFloat(viewBox[3]);
            
            // 计算容器尺寸
            var containerRect = svgElement.parentElement.getBoundingClientRect();
            var containerW = containerRect.width;
            var containerH = containerRect.height;
            
            // 计算新的视口尺寸
            var newViewportW = containerW / newZoom;
            var newViewportH = containerH / newZoom;
            
            // 如果viewBox太小，扩展它
            var minRequiredW = newViewportW * 2; // 给缩放留足空间
            var minRequiredH = newViewportH * 2;
            
            var needsExpansion = false;
            var newVbX = vbX, newVbY = vbY, newVbW = vbW, newVbH = vbH;
            
            if (vbW < minRequiredW) {
              var expansion = minRequiredW - vbW;
              newVbX = vbX - expansion / 2;
              newVbW = minRequiredW;
              needsExpansion = true;
            }
            
            if (vbH < minRequiredH) {
              var expansion = minRequiredH - vbH;
              newVbY = vbY - expansion / 2;
              newVbH = minRequiredH;
              needsExpansion = true;
            }
            
            if (needsExpansion) {
              svgElement.setAttribute('viewBox', newVbX + ' ' + newVbY + ' ' + newVbW + ' ' + newVbH);
              console.log('缩放时扩展viewBox:', 'zoom=' + newZoom.toFixed(2), 'w=' + newVbW.toFixed(1), 'h=' + newVbH.toFixed(1));
            }
            
          } catch(e) {
            console.log('缩放计算错误:', e);
          }
        }
      };
      
      try {
        mermaid.initialize({ startOnLoad: true, securityLevel: 'loose', theme: 'default' });
        mermaid.run().then(function(){
          var svg = document.querySelector('#mermaid-diagram svg');
          if(!svg){ return; }
          
          // 确保SVG填满容器
          svg.style.width = '100%';
          svg.style.height = '100%';
          svg.style.display = 'block';
          svg.setAttribute('width','100%');
          svg.setAttribute('height','100%');
          svg.setAttribute('preserveAspectRatio','xMidYMid meet');
          panZoom = svgPanZoom(svg, {
            zoomEnabled: true,
            panEnabled: true,
            controlIconsEnabled: false,
            fit: true,
            center: true,
            minZoom: 0.1,
            maxZoom: 40,
            zoomScaleSensitivity: 0.2,
            contain: false,
            preventMouseEventsDefault: true,
            beforePan: function(oldPan, newPan){
              // 实时计算并动态调整viewBox以支持无限拖拽
              return window.dynamicViewBoxManager.handlePan(this, oldPan, newPan);
            },
            onZoom: function(newZoom) {
              // 实时计算缩放时的viewBox调整
              window.dynamicViewBoxManager.handleZoom(this, newZoom);
            }
          });
          
          // 等待初始化完成后进行设置
          setTimeout(function() {
            try {
              console.log('Starting post-initialization setup...');
              
              // 获取原始尺寸信息
              var bbox = svg.getBBox();
              var originalViewBox = svg.getAttribute('viewBox');
              console.log('Original bbox:', bbox);
              console.log('Original viewBox:', originalViewBox);
              
              // 如果没有viewBox，基于bbox创建一个
              if (!originalViewBox || originalViewBox === 'null') {
                svg.setAttribute('viewBox', bbox.x + ' ' + bbox.y + ' ' + bbox.width + ' ' + bbox.height);
                console.log('Created initial viewBox from bbox');
              }
              
              // 先正常fit和center
              panZoom.fit();
              panZoom.center();
              
              // 检查是否正常显示
              var currentZoom = panZoom.getZoom();
              var currentPan = panZoom.getPan();
              console.log('After fit/center: zoom=' + currentZoom + ', pan=' + JSON.stringify(currentPan));
              
              // 适当放大以获得更好的显示效果
              panZoom.zoomBy(1.5);
              console.log('Applied 1.5x zoom, final zoom:', panZoom.getZoom());
              
              // 不再扩大viewBox，保持原始尺寸以确保性能和正确显示
              console.log('Setup completed - keeping original viewBox for better performance');
              
            } catch(e) {
              console.log('Setup failed:', e);
            }
          }, 100);
          // 暴露给原生按钮
          window.setZoom = function(scale){ if(panZoom){ panZoom.zoom(scale); } };
          window.resetView = function(){ if(panZoom){ panZoom.resetZoom(); panZoom.center(); panZoom.fit(); } };
        }).catch(function(error){
          var el = document.getElementById('mermaid-diagram');
          el.innerHTML = '<div class=\"error\">渲染错误: ' + (error && error.message ? error.message : '') + '</div>';
        });
      } catch(e) {
        var el = document.getElementById('mermaid-diagram');
        el.innerHTML = '<div class=\"error\">初始化错误: ' + (e && e.message ? e.message : '') + '</div>';
      }
    })();
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
        currentZoomLevel = min(currentZoomLevel * 1.2, 3.0)
        updateZoom()
    }
    
    @objc private func zoomOut() {
        currentZoomLevel = max(currentZoomLevel / 1.2, 0.3)
        updateZoom()
    }
    
    @objc private func zoomReset() {
        currentZoomLevel = 1.0
        let script = "if (typeof resetView === 'function') { resetView(); } else if (typeof setZoom === 'function') { setZoom(1.0); }"
        previewWebView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("重置视图失败: \(error)")
            }
        }
    }
    
    private func updateZoom() {
        // 仅当前端已注入 setZoom 时才调用，避免 JS 未准备好时报错
        let script = "if (typeof setZoom === 'function') { setZoom(\(currentZoomLevel)); }"
        previewWebView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("缩放更新失败: \(error)")
            }
        }
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