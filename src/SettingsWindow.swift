import Cocoa

struct AppSettings: Codable {
    var apiKey: String
    var apiURL: String
    var autoDeleteDays: Int = 0 // 自动删除天数，0表示不自动删除
    var modelName: String = "gpt-3.5-turbo"
    var temperature: Double = 0.7
    var enableTemperature: Bool = true // temperature开关
    var allowPopClipOverride: Bool = false // 是否允许PopClip覆盖设置
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
                enableTemperature: true,
                allowPopClipOverride: false,
                qaPrompt: "你是一个有用的AI助手，请用中文回答：",
                translatePrompt: "你是一位专业的中英互译翻译官，请把中文译成英文，英文译成中文"
            )
            // 保存默认设置到文件
            try? saveSettings()
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
    private var temperatureSwitch: NSSwitch!
    private var testConnectionButton: HoverableButton!
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

        temperatureField = EditableTextField(frame: NSRect(x: margin + labelWidth + 10, y: currentY - 35, width: 120, height: 44))
        temperatureField.stringValue = String(settings.temperature)
        temperatureField.placeholderString = "0.7"
        temperatureField.font = NSFont.systemFont(ofSize: 14)
        temperatureField.bezelStyle = .roundedBezel
        temperatureField.alignment = .center
        documentView.addSubview(temperatureField)
        
        // Temperature 开关
        temperatureSwitch = NSSwitch(frame: NSRect(x: margin + labelWidth + 140, y: currentY - 30, width: 60, height: 20))
        temperatureSwitch.state = settings.enableTemperature ? .on : .off
        temperatureSwitch.target = self
        temperatureSwitch.action = #selector(temperatureSwitchChanged(_:))
        documentView.addSubview(temperatureSwitch)
        
        let switchLabel = NSTextField(labelWithString: "启用")
        switchLabel.frame = NSRect(x: margin + labelWidth + 210, y: currentY - 28, width: 40, height: 16)
        switchLabel.font = NSFont.systemFont(ofSize: 12)
        switchLabel.textColor = .secondaryLabelColor
        documentView.addSubview(switchLabel)
        
        // 测试连接按钮
        testConnectionButton = HoverableButton()
        testConnectionButton.title = "测试连接模型"
        testConnectionButton.target = self
        testConnectionButton.action = #selector(testConnection)
        testConnectionButton.frame = NSRect(x: margin + labelWidth + 260, y: currentY - 35, width: 120, height: 32)
        testConnectionButton.bezelStyle = .rounded
        testConnectionButton.font = NSFont.systemFont(ofSize: 13)
        testConnectionButton.toolTip = "测试当前配置的模型是否能正常工作"
        documentView.addSubview(testConnectionButton)
        
        // 根据开关状态设置temperature字段的启用状态
        temperatureField.isEnabled = settings.enableTemperature
        
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
        temperatureSwitch.state = settings.enableTemperature ? .on : .off
        temperatureField.isEnabled = settings.enableTemperature
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

    @objc func temperatureSwitchChanged(_ sender: NSSwitch) {
        temperatureField.isEnabled = sender.state == .on
    }
    
    @objc func testConnection() {
        testConnectionButton.isEnabled = false
        testConnectionButton.title = "测试中..."
        
        Task {
            do {
                let result = await performConnectionTest()
                DispatchQueue.main.async {
                    self.testConnectionButton.isEnabled = true
                    self.testConnectionButton.title = "测试连接模型"
                    
                    let alert = NSAlert()
                    if result.success {
                        alert.messageText = "连接测试成功"
                        alert.informativeText = "模型: \(result.model)\n温度支持: \(result.temperatureSupported ? "是" : "否")\n响应时间: \(result.responseTime)ms"
                        alert.alertStyle = .informational
                    } else {
                        alert.messageText = "连接测试失败"
                        alert.informativeText = result.error ?? "未知错误"
                        alert.alertStyle = .warning
                    }
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            }
        }
    }
    
    private func performConnectionTest() async -> (success: Bool, model: String, temperatureSupported: Bool, responseTime: Int, error: String?) {
        let startTime = Date()
        
        do {
            let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let apiURL = apiURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = modelField.stringValue.isEmpty ? "gpt-3.5-turbo" : modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !apiKey.isEmpty else {
                return (false, model, false, 0, "API Key 不能为空")
            }
            
            guard !apiURL.isEmpty else {
                return (false, model, false, 0, "API URL 不能为空")
            }
            
            guard let url = URL(string: apiURL) else {
                return (false, model, false, 0, "API URL 格式无效")
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30
            
            // 先测试不带temperature的请求
            let requestBodyWithoutTemp: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "user", "content": "Hello, this is a connection test."]
                ],
                "max_completion_tokens": 10,
                "stream": false
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBodyWithoutTemp)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse
            
            if httpResponse.statusCode == 200 {
                // 获取当前UI中的温度设置
                let currentTemperature = Double(temperatureField.stringValue) ?? 0.7
                let isTemperatureEnabled = temperatureSwitch.state == .on
                
                // 测试带temperature的请求（仅在温度开关开启时）
                var requestBodyWithTemp: [String: Any] = [
                    "model": model,
                    "messages": [
                        ["role": "user", "content": "Hello, this is a temperature test."]
                    ],
                    "max_completion_tokens": 10,
                    "stream": false
                ]
                
                // 只有在温度开关开启时才添加temperature参数
                if isTemperatureEnabled {
                    requestBodyWithTemp["temperature"] = currentTemperature
                }
                
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBodyWithTemp)
                let (_, tempResponse) = try await URLSession.shared.data(for: request)
                let tempHttpResponse = tempResponse as! HTTPURLResponse
                
                let temperatureSupported = tempHttpResponse.statusCode == 200
                let responseTime = Int(Date().timeIntervalSince(startTime) * 1000)
                
                return (true, model, temperatureSupported, responseTime, nil)
            } else {
                let errorData = String(data: data, encoding: .utf8) ?? "未知错误"
                return (false, model, false, 0, "HTTP \(httpResponse.statusCode): \(errorData)")
            }
            
        } catch {
            let responseTime = Int(Date().timeIntervalSince(startTime) * 1000)
            return (false, modelField.stringValue, false, responseTime, error.localizedDescription)
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
                enableTemperature: true,
                qaPrompt: "你是一个有用的AI助手，请用中文回答：",
                translatePrompt: "你是一位专业的中英互译翻译官，请把中文译成英文，英文译成中文"
            )
            
            SettingsManager.shared.settings = defaultSettings
            
            // 保存默认设置
            if SettingsManager.shared.saveSettingsWithResult() {
                // 刷新界面显示
                refreshSettings()
                
                // 显示成功提示
                if let resetButton = window?.contentView?.subviews.first?.subviews.first(where: { $0 is HoverableButton && ($0 as! HoverableButton).title == "重置为默认" }) as? HoverableButton {
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
        SettingsManager.shared.settings.enableTemperature = temperatureSwitch.state == .on
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
            
            print("设置已保存成功")
        } else {
            // 显示保存失败提示
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = "无法保存设置，请检查文件权限或磁盘空间"
            alert.addButton(withTitle: "确定")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}