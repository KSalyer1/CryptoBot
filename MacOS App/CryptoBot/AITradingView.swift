import SwiftUI
import Combine

struct AITradingView: View {
    @Environment(ApplicationState.self) private var appState
    @AppStorage("openai_api_key") private var storedAPIKey: String = ""

    // AI Strategy Engine
    @State private var aiStrategy: ShortSellingAIStrategy?
    @State private var apiKey: String = ""
    @State private var isAnalyzing = false

    // Crypto Selection
    @State private var selectedSymbol: String = "BTC-USD"
    @State private var availableCryptos: [String] = []
    @State private var showSymbolPicker = false

    // AI Analysis Results
    @State private var currentAnalysis: ShortSellingAnalysis?
    @State private var analysisError: String?

    // Portfolio Information
    @State private var buyingPower: Double = 0.0
    @State private var portfolioValue: Double = 0.0
    
    // Order execution feedback
    @State private var showOrderSuccess = false
    @State private var showOrderError = false
    @State private var orderMessage = ""
    @State private var showOrderConfirmation = false
    @State private var pendingOrder: ShortSellingAnalysis?
    
    // Data quality
    @State private var dataQuality: String = "Checking..."
    @State private var hasSufficientData = false
    
    // Analysis history
    @State private var analysisHistory: [(date: Date, symbol: String, recommendation: String, confidence: Double)] = []
    @State private var showHistory = false
    
    // AI Auto-trading
    @State private var isAutoTradingEnabled = false
    @State private var autoTradingInterval: TimeInterval = 300 // 5 minutes
    @State private var autoTradingTimer: Timer?
    @State private var selectedStrategy: TradingStrategy = .conservative
    @State private var minConfidenceThreshold: Double = 70.0
    @State private var showStrategyPicker = false
    
    // Trading Mode
    @State private var tradingMode: TradingMode = .shortSelling
    @State private var showTradingModePicker = false
    
    enum TradingMode: String, CaseIterable, Identifiable {
        case buyOnly = "Buy Only"
        case shortSelling = "Short Selling"
        case both = "Buy & Short"
        
        var id: String { rawValue }
        
        var description: String {
            switch self {
            case .buyOnly:
                return "Only execute buy orders when opportunities arise"
            case .shortSelling:
                return "Only execute short sell orders for bearish signals"
            case .both:
                return "Execute both buy and short sell orders based on market conditions"
            }
        }
        
        var icon: String {
            switch self {
            case .buyOnly: return "arrow.up.circle.fill"
            case .shortSelling: return "arrow.down.circle.fill"
            case .both: return "arrow.up.arrow.down.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .buyOnly: return .green
            case .shortSelling: return .red
            case .both: return .blue
            }
        }
    }
    
    enum TradingStrategy: String, CaseIterable, Identifiable {
        case conservative = "Conservative"
        case moderate = "Moderate"
        case aggressive = "Aggressive"
        case custom = "Custom"
        
        var id: String { rawValue }
        
        var description: String {
            switch self {
            case .conservative:
                return "Low risk, high confidence required (80%+), smaller positions"
            case .moderate:
                return "Balanced risk/reward, 70%+ confidence, standard positions"
            case .aggressive:
                return "Higher risk, 60%+ confidence, larger positions"
            case .custom:
                return "Configure your own parameters"
            }
        }
        
        var confidenceThreshold: Double {
            switch self {
            case .conservative: return 80
            case .moderate: return 70
            case .aggressive: return 60
            case .custom: return 70
            }
        }
        
        var positionSizeMultiplier: Double {
            switch self {
            case .conservative: return 0.5
            case .moderate: return 1.0
            case .aggressive: return 1.5
            case .custom: return 1.0
            }
        }
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Quick Stats Dashboard
                    if !analysisHistory.isEmpty {
                        quickStatsDashboard
                    }

                    // Configuration Section
                    configurationSection
                    
                    // Crypto Selection & Portfolio Status
                    HStack(spacing: 20) {
                        cryptoSelectionSection
                        portfolioStatusSection
                    }
                    
                    // Trading Mode Selection
                    if aiStrategy != nil {
                        tradingModeSection
                    }
                    
                    // AI Auto-Trading Control
                    if aiStrategy != nil {
                        autonomousTradingSection
                    } else {
                        missingAIStrategyNotice
                    }
                    
                    // Strategy Selection
                    if aiStrategy != nil {
                        strategySelectionSection
                    }
                    
                    // Risk Analysis Section
                    if aiStrategy != nil {
                        riskAnalysisSection
                    }

                    // AI Analysis Results
                    if isAnalyzing {
                        analysisLoadingSection
                    } else if let analysis = currentAnalysis {
                        analysisResultsSection(analysis)
                    } else if analysisError != nil {
                        errorSection
                    } else {
                        emptyStateSection
                    }

                    // Action Buttons
                    if currentAnalysis != nil {
                        actionButtonsSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("AI Trading")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .sheet(isPresented: $showTradingModePicker) {
            tradingModePickerSheet
        }
        .sheet(isPresented: $showStrategyPicker) {
            strategyPickerSheet
        }
        .sheet(isPresented: $showSymbolPicker) {
            cryptoPickerSheet
        }
        .sheet(isPresented: $showHistory) {
            analysisHistorySheet
        }
        .task {
            // Load stored API key
            if !storedAPIKey.isEmpty {
                print("📱 [AITradingView] Loading stored API key: \(storedAPIKey.prefix(10))...")
                apiKey = storedAPIKey
                aiStrategy = ShortSellingAIStrategy(apiKey: storedAPIKey)
                print("✅ [AITradingView] AI Strategy initialized successfully")
            } else {
                print("⚠️ [AITradingView] No stored API key found")
            }
            
            await loadAvailableCryptos()
            await loadPortfolioInfo()
            await checkDataQuality()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await loadPortfolioInfo()
            }
        }
        .onChange(of: selectedSymbol) { _, _ in
            // Clear previous analysis when symbol changes
            currentAnalysis = nil
            analysisError = nil
            
            // Check data quality for new symbol
            Task {
                await checkDataQuality()
            }
        }
        .alert("Order Placed Successfully", isPresented: $showOrderSuccess) {
            Button("OK") { }
        } message: {
            Text(orderMessage)
        }
        .alert("Order Failed", isPresented: $showOrderError) {
            Button("OK") { }
        } message: {
            Text(orderMessage)
        }
        .alert("Confirm Short Sell Order", isPresented: $showOrderConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingOrder = nil
            }
            Button("Confirm", role: .destructive) {
                if let order = pendingOrder {
                    executeShortSellConfirmed(analysis: order)
                }
            }
        } message: {
            if let order = pendingOrder {
                Text("Sell \(String(format: "%.4f", order.quantity)) \(selectedSymbol) at limit price $\(String(format: "%.2f", order.currentPrice * 0.995))\n\nEstimated value: $\(String(format: "%.2f", order.quantity * order.currentPrice * 0.995))")
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            stopAutoTrading()
        }
    }

    private var tradingModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("🎯 Trading Mode")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { 
                    print("🔄 [Trading Mode Button] Tapped - showing picker")
                    showTradingModePicker = true 
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: tradingMode.icon)
                            .foregroundColor(tradingMode.color)
                        Text(tradingMode.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tradingMode.color.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Mode description
            Text(tradingMode.description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
    
    private var tradingModePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(TradingMode.allCases) { mode in
                    Button(action: {
                        print("🔄 [Trading Mode Picker] Selected: \(mode.rawValue)")
                        tradingMode = mode
                        showTradingModePicker = false
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: mode.icon)
                                    .foregroundColor(mode.color)
                                    .font(.title2)
                                
                                Text(mode.rawValue)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if mode == tradingMode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(mode.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Trading Mode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        print("🔄 [Trading Mode Picker] Cancelled")
                        showTradingModePicker = false
                    }
                }
            }
            .onAppear {
                print("🔄 [Trading Mode Picker Sheet] onAppear - current mode: \(tradingMode.rawValue)")
            }
            .frame(minWidth: 400, idealWidth: 500, maxWidth: 600, minHeight: 300, idealHeight: 400, maxHeight: 500)
        }
    }
    
    private var autonomousTradingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("🤖 Autonomous Trading")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(isAutoTradingEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isAutoTradingEnabled ? "RUNNING" : "STOPPED")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isAutoTradingEnabled ? .green : .gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isAutoTradingEnabled ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                )
            }
            
            // Big Play/Stop Button
            Button(action: {
                isAutoTradingEnabled.toggle()
                if isAutoTradingEnabled {
                    startAutoTrading()
                } else {
                    stopAutoTrading()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: isAutoTradingEnabled ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isAutoTradingEnabled ? "Stop Autonomous Trading" : "Start Autonomous Trading")
                            .font(.headline)
                        Text(isAutoTradingEnabled ? "AI is actively trading" : "Start AI-powered automated trading")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    
                    Spacer()
                }
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: isAutoTradingEnabled ? [Color.red, Color.red.opacity(0.8)] : [Color.green, Color.green.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: isAutoTradingEnabled ? Color.red.opacity(0.5) : Color.green.opacity(0.5), radius: 8)
                )
            }
            .buttonStyle(.plain)
            
            // Interval selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Analysis Interval")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                HStack(spacing: 12) {
                    ForEach([("1m", 60.0), ("5m", 300.0), ("15m", 900.0), ("30m", 1800.0)], id: \.0) { label, interval in
                        Button(action: {
                            autoTradingInterval = interval
                            if isAutoTradingEnabled {
                                stopAutoTrading()
                                startAutoTrading()
                            }
                        }) {
                            Text(label)
                                .font(.caption)
                                .fontWeight(autoTradingInterval == interval ? .semibold : .regular)
                                .foregroundColor(autoTradingInterval == interval ? .white : .white.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(autoTradingInterval == interval ? Color.blue : Color.white.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
            )
            
            // Warning message
            if isAutoTradingEnabled {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Autonomous Trading Active")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text("AI is executing trades automatically. Monitor your portfolio regularly.")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.15))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
    
    private var missingAIStrategyNotice: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Strategy Not Configured")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Enter your OpenAI API key above to enable AI trading features, strategy selection, and auto-trading controls.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                )
        )
    }
    
    private var autoTradingControlSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("🤖 Auto-Trading Control")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(isAutoTradingEnabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isAutoTradingEnabled ? "ACTIVE" : "INACTIVE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isAutoTradingEnabled ? .green : .gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isAutoTradingEnabled ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                )
            }
            
            VStack(spacing: 16) {
                // Main toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Auto-Trading")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Text("AI will automatically analyze and execute trades")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    Toggle("", isOn: $isAutoTradingEnabled)
                        .labelsHidden()
                        .onChange(of: isAutoTradingEnabled) { _, newValue in
                            if newValue {
                                startAutoTrading()
                            } else {
                                stopAutoTrading()
                            }
                        }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                )
                
                // Interval selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Analysis Interval")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 12) {
                        ForEach([("1m", 60.0), ("5m", 300.0), ("15m", 900.0), ("30m", 1800.0)], id: \.0) { label, interval in
                            Button(action: {
                                autoTradingInterval = interval
                                if isAutoTradingEnabled {
                                    stopAutoTrading()
                                    startAutoTrading()
                                }
                            }) {
                                Text(label)
                                    .font(.caption)
                                    .fontWeight(autoTradingInterval == interval ? .semibold : .regular)
                                    .foregroundColor(autoTradingInterval == interval ? .white : .white.opacity(0.7))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(autoTradingInterval == interval ? Color.blue : Color.white.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                )
                
                // Warning message
                if isAutoTradingEnabled {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-Trading Active")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            Text("AI will execute trades automatically based on your selected strategy. Monitor regularly.")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.15))
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
    
    private var strategySelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📋 Trading Strategy")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { 
                    print("🔄 [Strategy Button] Tapped - showing picker")
                    showStrategyPicker = true 
                }) {
                    HStack(spacing: 6) {
                        Text(selectedStrategy.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Strategy description
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedStrategy.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Strategy parameters
                VStack(spacing: 12) {
                    HStack {
                        Text("Confidence Threshold")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        if selectedStrategy == .custom {
                            HStack(spacing: 8) {
                                Slider(value: $minConfidenceThreshold, in: 50...90, step: 5)
                                    .frame(width: 100)
                                Text("\(Int(minConfidenceThreshold))%")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        } else {
                            Text("\(Int(selectedStrategy.confidenceThreshold))%")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                    
                    HStack {
                        Text("Position Size Multiplier")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(String(format: "%.1f", selectedStrategy.positionSizeMultiplier))x")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Text("Estimated Position Size")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("$\(String(format: "%.2f", buyingPower * 0.05 * selectedStrategy.positionSizeMultiplier))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
    
    private var strategyPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(TradingStrategy.allCases) { strategy in
                    Button(action: {
                        print("🔄 [Strategy Picker] Selected: \(strategy.rawValue)")
                        selectedStrategy = strategy
                        if strategy != .custom {
                            minConfidenceThreshold = strategy.confidenceThreshold
                        }
                        showStrategyPicker = false
                    }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(strategy.rawValue)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                if strategy == selectedStrategy {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(strategy.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Strategy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        print("🔄 [Strategy Picker] Cancelled")
                        showStrategyPicker = false
                    }
                }
            }
            .onAppear {
                print("🔄 [Strategy Picker Sheet] onAppear - current strategy: \(selectedStrategy.rawValue)")
            }
        }
    }
    
    private var quickStatsDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📊 Analysis Overview")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showHistory.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                }
                .buttonStyle(.bordered)
            }
            
            let totalAnalyses = analysisHistory.count
            let sellSignals = analysisHistory.filter { $0.recommendation == "SELL" }.count
            let buySignals = analysisHistory.filter { $0.recommendation == "BUY" }.count
            let avgConfidence = analysisHistory.isEmpty ? 0 : analysisHistory.map { $0.confidence }.reduce(0, +) / Double(totalAnalyses)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(title: "Total Analyses", value: "\(totalAnalyses)", icon: "brain", color: .blue)
                statCard(title: "Sell Signals", value: "\(sellSignals)", icon: "arrow.down.circle.fill", color: .red)
                statCard(title: "Buy Signals", value: "\(buySignals)", icon: "arrow.up.circle.fill", color: .green)
                statCard(title: "Avg Confidence", value: String(format: "%.0f%%", avgConfidence), icon: "gauge.medium", color: .purple)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
    
    private var analysisHistorySheet: some View {
        NavigationStack {
            List {
                ForEach(analysisHistory.reversed().indices, id: \.self) { idx in
                    let item = analysisHistory.reversed()[idx]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.symbol)
                                .font(.headline)
                            Spacer()
                            Text(item.recommendation)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(recommendationColor(item.recommendation))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(recommendationColor(item.recommendation).opacity(0.2))
                                )
                        }
                        
                        HStack {
                            Text(item.date, style: .date)
                            Text(item.date, style: .time)
                            Spacer()
                            Text("\(Int(item.confidence))% confidence")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Analysis History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showHistory = false
                    }
                }
            }
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
        )
    }
    
    private var riskAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("⚠️ Risk Management")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                // Max position size
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Maximum Position Size")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Text("5% of buying power per trade")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    Text("$\(String(format: "%.2f", buyingPower * 0.05))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                )
                
                // Risk metrics grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    riskMetricCard(
                        title: "Available Capital",
                        value: "$\(String(format: "%.2f", buyingPower))",
                        icon: "dollarsign.circle.fill",
                        color: .green
                    )
                    
                    riskMetricCard(
                        title: "Portfolio Value",
                        value: "$\(String(format: "%.2f", portfolioValue))",
                        icon: "chart.pie.fill",
                        color: .blue
                    )
                    
                    let riskPct = portfolioValue > 0 ? (buyingPower * 0.05 / portfolioValue) * 100 : 0
                    riskMetricCard(
                        title: "Risk per Trade",
                        value: String(format: "%.2f%%", riskPct),
                        icon: "exclamationmark.shield.fill",
                        color: .orange
                    )
                    
                    let maxTrades = buyingPower > 0 ? Int(buyingPower / (buyingPower * 0.05)) : 0
                    riskMetricCard(
                        title: "Max Positions",
                        value: "\(min(maxTrades, 20))",
                        icon: "square.grid.3x3.fill",
                        color: .purple
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
    
    private func riskMetricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
        )
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.blue)
                            .font(.system(size: 24))
                        
                        Text("AI Trading Engine")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    Text("Advanced trading strategies powered by OpenAI GPT-4")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(aiStrategy != nil ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(aiStrategy != nil ? "AI Ready" : "Configure")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(aiStrategy != nil ? .green : .red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((aiStrategy != nil ? Color.green : Color.red).opacity(0.1))
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 16))
                
                Text("OpenAI Configuration")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                modernTextField(title: "API Key", text: $apiKey, placeholder: "sk-...", isSecure: true)
                
                if !apiKey.isEmpty {
                    Button(aiStrategy != nil ? "✓ Configured" : "Initialize") {
                        // Save API key and initialize
                        print("💾 [AITradingView] Saving API key and initializing strategy")
                        storedAPIKey = apiKey
                        aiStrategy = ShortSellingAIStrategy(apiKey: apiKey)
                        print("✅ [AITradingView] Strategy initialized: \(aiStrategy != nil)")
                    }
                    .buttonStyle(ModernButtonStyle(style: .primary))
                    .disabled(aiStrategy != nil)
                }
                
                // Debug info
                if aiStrategy == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("AI Strategy not initialized")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.orange.opacity(0.1))
                    )
                }
                
                Text("Enter your OpenAI API key to enable AI-powered trading analysis")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private var cryptoSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📊 Target Cryptocurrency")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
        HStack {
                    Text("Selected:")
                        .font(.subheadline)
                        .foregroundColor(Color.white.opacity(0.7))

            Spacer()

                    Text(selectedSymbol)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                Button("Change Cryptocurrency") {
                    print("🔄 [Button] Change Cryptocurrency tapped")
                    print("🔄 [Button] availableCryptos count: \(availableCryptos.count)")
                    print("🔄 [Button] availableCryptos: \(availableCryptos)")
                    showSymbolPicker = true
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                if !availableCryptos.isEmpty {
                    Text("\(availableCryptos.count) cryptocurrencies available")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.6))
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    private var portfolioStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💼 Portfolio Status")
                .font(.headline)
                .foregroundColor(.white)

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Buying Power")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.7))
                        Text("$\(String(format: "%.2f", buyingPower))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Portfolio Value")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.7))
                        Text("$\(String(format: "%.2f", portfolioValue))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }

                // Risk allocation indicator
                HStack {
                    Text("Max Short Position:")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.6))
                    Spacer()
                    Text("$\(String(format: "%.2f", buyingPower * 0.05))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    private var cryptoPickerSheet: some View {
        NavigationStack {
            VStack {
                if availableCryptos.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Loading cryptocurrencies...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(availableCryptos, id: \.self) { symbol in
                            Button(action: {
                                print("🔄 [Crypto Picker] User tapped: \(symbol)")
                                handleCryptoSelection(symbol)
                            }) {
                                HStack {
                                    Text(symbol)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if symbol == selectedSymbol {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.title3)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Select Cryptocurrency")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        print("🔄 [Crypto Picker] User cancelled")
                        showSymbolPicker = false
                    }
                }
            }
            .onAppear {
                print("🔄 [Crypto Picker Sheet] onAppear - availableCryptos count: \(availableCryptos.count)")
                print("🔄 [Crypto Picker Sheet] onAppear - availableCryptos: \(availableCryptos)")
                
                // Reload if empty
                if availableCryptos.isEmpty {
                    Task {
                        await loadAvailableCryptos()
                    }
                }
            }
        }
    }
    
    private func handleCryptoSelection(_ symbol: String) {
        print("📍 [Crypto Picker] handleCryptoSelection called for: \(symbol)")
        print("📍 [Crypto Picker] Current selectedSymbol: \(selectedSymbol)")
        
        selectedSymbol = symbol
        
        print("📍 [Crypto Picker] Updated selectedSymbol to: \(selectedSymbol)")
        print("🔄 [Crypto Picker] Dismissing sheet...")
        
        showSymbolPicker = false
        
        print("✅ [Crypto Picker] Selection complete: \(symbol)")
    }

    private var emptyStateSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(Color.white.opacity(0.3))

            Text("Ready for AI Analysis")
                .font(.headline)
                .foregroundColor(.white)

            Text("Select a cryptocurrency and configure your OpenAI API key to begin AI-powered trading analysis")
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            
            // Data quality status
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: hasSufficientData ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasSufficientData ? .green : .orange)
                    Text("Historical Data:")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text(dataQuality)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(hasSufficientData ? .green : .orange)
                }
                
                if let quote = appState.quotes[selectedSymbol] {
                    Text("Current Price: $\(String(format: "%.2f", quote.price))")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.7))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
            )

            if aiStrategy != nil {
                Button(action: {
                    analyzeSelectedCrypto()
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyze \(selectedSymbol)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasSufficientData)
            } else {
                Text("Configure OpenAI API key above to begin")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    private var analysisLoadingSection: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)

            Text("🤖 Analyzing \(selectedSymbol)...")
                .font(.headline)
                .foregroundColor(.white)

            Text("Calculating technical indicators and consulting AI...")
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)

            // Loading steps with realistic timing
        VStack(alignment: .leading, spacing: 8) {
                loadingStep("Retrieving historical data", completed: true)
                loadingStep("Calculating technical indicators", completed: true)
                loadingStep("Analyzing market trends", completed: isAnalyzing)
                loadingStep("Consulting OpenAI AI", completed: false)
                loadingStep("Generating recommendation", completed: false)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.2))
            )
            
            // Show data quality info
            if let quote = appState.quotes[selectedSymbol] {
                VStack(spacing: 8) {
                    Text("Current Price: $\(String(format: "%.2f", quote.price))")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    Text("Buying Power: $\(String(format: "%.2f", buyingPower))")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.7))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    private func loadingStep(_ text: String, completed: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(completed ? .green : Color.white.opacity(0.5))
                .font(.subheadline)

            Text(text)
                .font(.subheadline)
                .foregroundColor(completed ? .white : Color.white.opacity(0.7))
        }
    }

    private func analysisResultsSection(_ analysis: ShortSellingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Main recommendation card
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("📈 AI Analysis Results")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Text(analysis.recommendation)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(recommendationColor(analysis.recommendation))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(recommendationColor(analysis.recommendation).opacity(0.2))
                        )
                }

                // Confidence meter
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                        Text("Confidence Level")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.8))

                        Spacer()

                        Text("\(Int(analysis.confidence))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }

                    ProgressView(value: analysis.confidence, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: confidenceColor(analysis.confidence)))
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(4)
                }

                // Reasoning
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Reasoning")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)

                    Text(analysis.reasoning)
                        .font(.subheadline)
                        .foregroundColor(Color.white.opacity(0.8))
                        .lineLimit(6)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )

            // Technical indicators grid
            technicalIndicatorsSection(analysis)
            
            // Price movement visualization
            priceMovementSection(analysis)

            // Suggested action
            if !analysis.suggestedAction.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("💡 Suggested Action")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(analysis.suggestedAction)
                        .font(.subheadline)
                        .foregroundColor(Color.white.opacity(0.8))
                        .lineLimit(4)

                    if analysis.recommendation == "SELL" {
            HStack {
                            Text("Quantity:")
                                .font(.subheadline)
                                .foregroundColor(Color.white.opacity(0.7))
                            Spacer()
                            Text("\(String(format: "%.4f", analysis.quantity)) \(selectedSymbol)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                )
            }
        }
    }

    private func technicalIndicatorsSection(_ analysis: ShortSellingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📊 Technical Indicators")
                .font(.headline)
                .foregroundColor(.white)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                indicatorCard("Current Price", "$\(String(format: "%.2f", analysis.currentPrice))", .white)
                indicatorCard("Data Points", "\(analysis.historicalData.count)", .blue)
                
                if let minPrice = analysis.historicalData.map(\.price).min(),
                   let maxPrice = analysis.historicalData.map(\.price).max() {
                    indicatorCard("Price Range", "$\(String(format: "%.2f", minPrice)) - $\(String(format: "%.2f", maxPrice))", .green)
                }
                
                indicatorCard("Volatility", "\(String(format: "%.2f", calculateVolatility(analysis.historicalData)))%", .orange)
                
                // Add more technical indicators
                let priceChange = calculatePriceChange(analysis.historicalData)
                indicatorCard("24h Change", "\(String(format: "%.2f", priceChange))%", priceChange >= 0 ? .green : .red)
                
                let trend = analyzeTrend(analysis.historicalData)
                indicatorCard("Trend", trend.capitalized, trendColor(trend))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    private func indicatorCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(Color.white.opacity(0.7))
                .textCase(.uppercase)
                .fontWeight(.medium)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.2))
        )
    }

    private func calculateVolatility(_ data: [PriceDataPoint]) -> Double {
        guard data.count > 1 else { return 0 }
        let prices = data.map(\.price)
        var returns: [Double] = []
        for i in 1..<prices.count {
            returns.append((prices[i] - prices[i-1]) / prices[i-1])
        }
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count)
        return sqrt(variance) * 100
    }
    
    private func calculatePriceChange(_ data: [PriceDataPoint]) -> Double {
        guard data.count >= 2 else { return 0 }
        let prices = data.map(\.price)
        let firstPrice = prices.first!
        let lastPrice = prices.last!
        return ((lastPrice - firstPrice) / firstPrice) * 100
    }
    
    private func analyzeTrend(_ data: [PriceDataPoint]) -> String {
        guard data.count >= 20 else { return "insufficient_data" }
        let prices = data.map(\.price)
        let recentPrices = Array(prices.suffix(20))
        let olderPrices = Array(prices.suffix(40).prefix(20))
        
        let recentAvg = recentPrices.reduce(0, +) / Double(recentPrices.count)
        let olderAvg = olderPrices.reduce(0, +) / Double(olderPrices.count)
        
        if recentAvg > olderAvg * 1.02 {
            return "uptrend"
        } else if recentAvg < olderAvg * 0.98 {
            return "downtrend"
        } else {
            return "sideways"
        }
    }
    
    private func trendColor(_ trend: String) -> Color {
        switch trend.lowercased() {
        case "uptrend":
            return .green
        case "downtrend":
            return .red
        case "sideways":
            return .yellow
        default:
            return .gray
        }
    }

    private func recommendationColor(_ recommendation: String) -> Color {
        switch recommendation.uppercased() {
        case "SELL":
            return .red
        case "BUY":
            return .green
        default:
            return .orange
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 80 {
            return .green
        } else if confidence >= 60 {
            return .yellow
        } else {
            return .red
        }
    }

    private var errorSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)

            Text("Analysis Error")
                .font(.headline)
                .foregroundColor(.white)

            Text(analysisError ?? "Unknown error occurred")
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button("Try Again") {
                analyzeSelectedCrypto()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            Button("🔄 Re-analyze") {
                analyzeSelectedCrypto()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)

            if let analysis = currentAnalysis, analysis.recommendation == "SELL" {
                Button("📉 Execute Short Sell") {
                    // Show confirmation dialog
                    pendingOrder = analysis
                    showOrderConfirmation = true
            }
            .buttonStyle(.borderedProminent)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
            } else {
                Button("✅ Analysis Complete") {
                    // Could add more actions here
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(true)
            }
        }
    }

    private func priceMovementSection(_ analysis: ShortSellingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📈 Price Analysis")
                .font(.headline)
                .foregroundColor(.white)
            
            let prices = analysis.historicalData.map { $0.price }
            let timestamps = analysis.historicalData.map { $0.timestamp }
            
            if !prices.isEmpty {
                let minPrice = prices.min() ?? 0
                let maxPrice = prices.max() ?? 0
                let currentPrice = analysis.currentPrice
                let priceRange = maxPrice - minPrice
                
                VStack(spacing: 16) {
                    // Price range visualization
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Price Range")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text("$\(String(format: "%.2f", minPrice)) - $\(String(format: "%.2f", maxPrice))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background bar
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 12)
                                
                                // Current price indicator
                                let position = priceRange > 0 ? (currentPrice - minPrice) / priceRange : 0.5
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 16, height: 16)
                                    .offset(x: CGFloat(position) * (geometry.size.width - 16))
                                    .shadow(color: Color.blue.opacity(0.5), radius: 4)
                            }
                        }
                        .frame(height: 16)
                        
                        HStack {
                            Text("Low")
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                            Text("Current: $\(String(format: "%.2f", currentPrice))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                            Spacer()
                            Text("High")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.3))
                    )
                    
                    // Key levels
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Support Level")
                                .font(.caption)
                                .foregroundColor(.green.opacity(0.8))
                            Text("$\(String(format: "%.2f", minPrice * 1.01))")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.green.opacity(0.1))
                        )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resistance Level")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.8))
                            Text("$\(String(format: "%.2f", maxPrice * 0.99))")
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.1))
                        )
                    }
                    
                    // Time period info
                    if let firstTime = timestamps.first, let lastTime = timestamps.last {
                        let hoursCovered = Calendar.current.dateComponents([.hour], from: firstTime, to: lastTime).hour ?? 0
                        
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.white.opacity(0.6))
                            Text("Analysis Period: \(hoursCovered) hours (\(analysis.historicalData.count) data points)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
    
    private func startAutoTrading() {
        print("🤖 Starting AI Auto-Trading")
        
        // Run initial analysis
        analyzeSelectedCrypto()
        
        // Set up timer for recurring analysis
        autoTradingTimer = Timer.scheduledTimer(withTimeInterval: autoTradingInterval, repeats: true) { _ in
            Task {
                await self.performAutoTradingCycle()
            }
        }
    }
    
    private func stopAutoTrading() {
        print("🛑 Stopping AI Auto-Trading")
        autoTradingTimer?.invalidate()
        autoTradingTimer = nil
    }
    
    private func performAutoTradingCycle() async {
        guard let strategy = aiStrategy,
              let quote = appState.quotes[selectedSymbol],
              buyingPower > 0 else {
            return
        }
        
        print("🔄 Auto-Trading Cycle: Analyzing \(selectedSymbol)")
        
        do {
            let analysis = try await strategy.analyzeForShortSelling(
                symbol: selectedSymbol,
                currentPrice: quote.price,
                buyingPower: buyingPower,
                portfolioValue: portfolioValue
            )
            
            await MainActor.run {
                // Add to history
                analysisHistory.append((
                    date: Date(),
                    symbol: selectedSymbol,
                    recommendation: analysis.recommendation,
                    confidence: analysis.confidence
                ))
            }
            
            // Check if we should execute based on strategy
            let threshold = selectedStrategy == .custom ? minConfidenceThreshold : selectedStrategy.confidenceThreshold
            
            if analysis.recommendation == "SELL" && analysis.confidence >= threshold {
                print("✅ Auto-Trading: Executing SELL order (confidence: \(analysis.confidence)%)")
                
                // Adjust quantity based on strategy
                let adjustedQuantity = analysis.quantity * selectedStrategy.positionSizeMultiplier
                
                // Execute the order
                let limitPrice = analysis.currentPrice * 0.995
                
                do {
                    let _ = try await appState.executionManager.placeLimit(
                        symbol: selectedSymbol,
                        side: .sell,
                        quantity: adjustedQuantity,
                        limitPrice: limitPrice
                    )
                    
                    await MainActor.run {
                        orderMessage = "Auto-Trade: Sold \(String(format: "%.4f", adjustedQuantity)) \(selectedSymbol) at $\(String(format: "%.2f", limitPrice))"
                        showOrderSuccess = true
                    }
                } catch {
                    print("❌ Auto-Trading order failed: \(error)")
                }
            } else {
                print("ℹ️ Auto-Trading: No action taken (rec: \(analysis.recommendation), confidence: \(analysis.confidence)%)")
            }
            
        } catch {
            print("❌ Auto-Trading analysis failed: \(error)")
        }
    }
    
    private func loadAvailableCryptos() async {
        print("📊 Loading available cryptos...")
        
        // Get available cryptos from the app state quotes
        await MainActor.run {
            let symbols = Set(appState.quotes.keys)
            availableCryptos = Array(symbols).sorted()
            print("📊 Found \(availableCryptos.count) cryptos from quotes")
        }

        // If no quotes yet, try to get from markets or use fallback
        if availableCryptos.isEmpty {
            print("📊 No quotes available, using fallback list")
            await MainActor.run {
                availableCryptos = ["BTC-USD", "ETH-USD", "SOL-USD", "ADA-USD", "DOT-USD", "AVAX-USD", "DOGE-USD", "SHIB-USD", "LINK-USD", "UNI-USD"]
            }
        }
        
        print("📊 Available cryptos loaded: \(availableCryptos)")
    }

    private func loadPortfolioInfo() async {
        // Get real portfolio data from the app state
        await MainActor.run {
            // Get buying power from Robinhood account
            if let account = appState.account {
                buyingPower = Double(account.buying_power) ?? 0.0
                portfolioValue = appState.portfolioValue
            } else {
                // Fallback values if account not loaded
                buyingPower = 0.0
                portfolioValue = 0.0
            }
        }
    }
    
    private func checkDataQuality() async {
        let data = await HistoricalDatabaseManager.shared.getPriceData(symbol: selectedSymbol)
        
        await MainActor.run {
            if data.isEmpty {
                dataQuality = "No data available"
                hasSufficientData = false
                return
            }
            
            let hoursCovered = Calendar.current.dateComponents([.hour], 
                from: data.first!.timestamp, 
                to: data.last!.timestamp).hour ?? 0
            
            if hoursCovered < 24 {
                dataQuality = "\(data.count) points (\(hoursCovered)h) - Need 24h+"
                hasSufficientData = false
            } else {
                dataQuality = "\(data.count) points over \(hoursCovered) hours ✓"
                hasSufficientData = true
            }
        }
    }

    private func analyzeSelectedCrypto() {
        guard let strategy = aiStrategy else {
            analysisError = "Please configure OpenAI API key first"
            return
        }

        guard let quote = appState.quotes[selectedSymbol] else {
            analysisError = "No price data available for \(selectedSymbol)"
            return
        }

        guard buyingPower > 0 else {
            analysisError = "No buying power available. Please check your account connection."
            return
        }

        isAnalyzing = true
        currentAnalysis = nil
        analysisError = nil

        Task {
            do {
                // Get comprehensive historical data
                let historicalData = await HistoricalDatabaseManager.shared.getPriceData(symbol: selectedSymbol)

                guard !historicalData.isEmpty else {
                    await MainActor.run {
                        analysisError = "Insufficient historical data for \(selectedSymbol). Need at least 7 days of data."
                        isAnalyzing = false
                    }
                    return
                }

                let analysis = try await strategy.analyzeForShortSelling(
                    symbol: selectedSymbol,
                    currentPrice: quote.price,
                    buyingPower: buyingPower,
                    portfolioValue: portfolioValue
                )

                await MainActor.run {
                    currentAnalysis = analysis
                    isAnalyzing = false
                    
                    // Add to analysis history
                    analysisHistory.append((
                        date: Date(),
                        symbol: selectedSymbol,
                        recommendation: analysis.recommendation,
                        confidence: analysis.confidence
                    ))
                }
            } catch {
                await MainActor.run {
                    analysisError = "Analysis failed: \(error.localizedDescription)"
                    isAnalyzing = false
                }
            }
        }
    }

    private func executeShortSellConfirmed(analysis: ShortSellingAnalysis) {
        // Validate order parameters
        guard analysis.quantity > 0 else {
            analysisError = "Invalid quantity for short sell order"
            return
        }
        
        guard analysis.quantity * analysis.currentPrice <= buyingPower * 0.05 else {
            analysisError = "Order size exceeds 5% risk limit"
            return
        }

        Task {
            do {
                // Place a limit order slightly below current price for better execution
                let limitPrice = analysis.currentPrice * 0.995 // 0.5% below current price
                
                let _ = try await appState.executionManager.placeLimit(
                    symbol: selectedSymbol,
                    side: .sell,
                    quantity: analysis.quantity,
                    limitPrice: limitPrice
                )

                await MainActor.run {
                    // Show success message
                    orderMessage = "Short sell order for \(String(format: "%.4f", analysis.quantity)) \(selectedSymbol) at $\(String(format: "%.2f", limitPrice)) placed successfully!"
                    showOrderSuccess = true
                    
                    // Clear analysis and pending order
                    currentAnalysis = nil
                    pendingOrder = nil
                    
                    // Refresh portfolio info
                    Task {
                        await loadPortfolioInfo()
                    }
                }
            } catch {
                await MainActor.run {
                    orderMessage = "Failed to place short sell order: \(error.localizedDescription)"
                    showOrderError = true
                    pendingOrder = nil
                }
            }
        }
    }
    
    // MARK: - Modern UI Components
    
    private func modernTextField(title: String, text: Binding<String>, placeholder: String = "", isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Group {
                if isSecure {
                    SecureField(placeholder.isEmpty ? title : placeholder, text: text)
                } else {
                    TextField(placeholder.isEmpty ? title : placeholder, text: text)
                }
            }
            .font(.system(size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .disableAutocorrection(true)
#if os(iOS) || os(visionOS)
            .autocapitalization(.none)
#endif
        }
    }
}

#Preview {
    NavigationStack {
        AITradingView()
    }
    .environment(ApplicationState())
}