import SwiftUI
import Foundation

private enum ChartRange: String, CaseIterable, Identifiable {
    case min10 = "10M"
    case hour1 = "1H"
    case hour6 = "6H"
    case hour12 = "12H"
    case day1 = "1D"
    case day3 = "3D"
    case week1 = "7D"
    case month1 = "1M"
    case month3 = "3M"
    case month6 = "6M"
    case year1 = "1Y"
    case year2 = "2Y"
    case year5 = "5Y"
    case all = "All"

    var id: String { rawValue }

    var duration: TimeInterval? {
        switch self {
        case .min10: return 60 * 10
        case .hour1: return 60 * 60
        case .hour6: return 60 * 60 * 6
        case .hour12: return 60 * 60 * 12
        case .day1: return 60 * 60 * 24
        case .day3: return 60 * 60 * 24 * 3
        case .week1: return 60 * 60 * 24 * 7
        case .month1: return 60 * 60 * 24 * 30
        case .month3: return 60 * 60 * 24 * 30 * 3
        case .month6: return 60 * 60 * 24 * 30 * 6
        case .year1: return 60 * 60 * 24 * 365
        case .year2: return 60 * 60 * 24 * 365 * 2
        case .year5: return 60 * 60 * 24 * 365 * 5
        case .all: return nil
        }
    }

    var preferredInterval: TimeInterval {
        switch self {
        case .min10: return 60 * 5
        case .hour1: return 60 * 5
        case .hour6: return 60 * 15
        case .hour12: return 60 * 15
        case .day1: return 60 * 60
        case .day3: return 60 * 60
        case .week1: return 60 * 60 * 4
        case .month1: return 60 * 60 * 24
        case .month3: return 60 * 60 * 24
        case .month6: return 60 * 60 * 24
        case .year1: return 60 * 60 * 24
        case .year2: return 60 * 60 * 24
        case .year5: return 60 * 60 * 24
        case .all: return 60 * 60 * 24
        }
    }
}

struct MarketsView: View {
    @Environment(ApplicationState.self) private var app
    @State private var vm = MarketsViewModel()
    @State private var selectedSymbol: String? = nil
    @State private var subscriptionID: UUID?
    @State private var historicalData: [String: [PriceDataPoint]] = [:]
    @State private var downsampleCache: [String: [String: [PriceDataPoint]]] = [:] // symbol -> rangeRaw -> points
    @State private var bucketCache: [String: [String: [ChartBucket]]] = [:] // symbol -> rangeRaw -> buckets
    @State private var isHistoricalDataLoaded = false
    @State private var selectedChartRange: ChartRange = .day1

    // Track symbols/ranges currently fetching recent data to avoid infinite loops
    @State private var isFetchingRecentData: Set<String> = []

    private let maxCacheRangesPerSymbol = 8
    
    // Smart price formatting based on value
    private func formatPrice(_ price: Double) -> String {
        if price >= 100 {
            return String(format: "%.2f", price)
        } else if price >= 10 {
            return String(format: "%.3f", price)
        } else if price >= 1 {
            return String(format: "%.4f", price)
        } else if price >= 0.1 {
            return String(format: "%.5f", price)
        } else if price >= 0.01 {
            return String(format: "%.6f", price)
        } else {
            return String(format: "%.8f", price)
        }
    }
    
    // Smart percentage formatting
    private func formatPercentage(_ percentage: Double) -> String {
        if abs(percentage) >= 100 {
            return String(format: "%+.1f%%", percentage)
        } else if abs(percentage) >= 10 {
            return String(format: "%+.2f%%", percentage)
        } else {
            return String(format: "%+.3f%%", percentage)
        }
    }

    private func setCache(for symbol: String, rangeKey: String, points: [PriceDataPoint], buckets: [ChartBucket]) {
        DispatchQueue.main.async {
            var symPoints = self.downsampleCache[symbol] ?? [:]
            var symBuckets = self.bucketCache[symbol] ?? [:]
            // Trim if needed
            if symPoints.keys.count >= self.maxCacheRangesPerSymbol {
                if let oldestKey = symPoints.keys.first { 
                    symPoints.removeValue(forKey: oldestKey)
                    symBuckets.removeValue(forKey: oldestKey) 
                }
            }
            symPoints[rangeKey] = points
            symBuckets[rangeKey] = buckets
            self.downsampleCache[symbol] = symPoints
            self.bucketCache[symbol] = symBuckets
        }
    }

    private var isDetailOpen: Bool { selectedSymbol != nil }

    private var backgroundGradient: LinearGradient {
        let colors: [Color] = [
            Color(red: 0.1, green: 0.1, blue: 0.15),
            Color(red: 0.05, green: 0.05, blue: 0.1)
        ]
        return LinearGradient(gradient: Gradient(colors: colors), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                mainContent
            }
            .task {
                print("🚀 [MarketsView] .task modifier executing")
                await vm.load(app: app, heldAssets: app.heldAssets)

                // Ensure we load historical data for ALL symbols, not just filtered ones
                let allSymbols = Set(vm.myMarkets + vm.otherMarkets)
                print("📊 [MarketsView] Loading data for \(allSymbols.count) total symbols")

                if let id = subscriptionID {
                    app.quotePoller.updateSubscription(id, symbols: allSymbols)
                } else {
                    subscriptionID = app.quotePoller.subscribe(allSymbols)
                }
                if !app.quotePoller.isRunning {
                    app.quotePoller.start(state: app)
                }

                // Load historical data for charts for ALL symbols
                print("🚀 [MarketsView] About to call loadHistoricalData for \(allSymbols.count) symbols")

                // Load historical data synchronously first, then await the result
                let historicalTask = Task {
                    await loadHistoricalData(for: Array(allSymbols))
                }

                // Wait for historical data to load before continuing
                await historicalTask.value

                print("✅ [MarketsView] Historical data loading completed")
            }
            .alert("Error", isPresented: Binding(get: { vm.errorMessage != nil }, set: { _ in vm.errorMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: { Text(vm.errorMessage ?? "") }
        }
        .onDisappear {
            if let id = subscriptionID {
                app.quotePoller.unsubscribe(id)
                subscriptionID = nil
                if app.quotePoller.trackedSymbols.isEmpty {
                    app.quotePoller.stop()
                }
            }
        }
    }
    
    private var mainContent: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                mainMarketsView
                    .frame(width: isDetailOpen ? max(450, geometry.size.width * 0.6) : geometry.size.width)

                if let selectedSymbol = selectedSymbol {
                    detailPanelView(for: selectedSymbol)
                        .frame(width: min(480, geometry.size.width * 0.4))
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isDetailOpen)
        .padding(isDetailOpen ? 20 : 0)
    }
    
    private var mainMarketsView: some View {
        VStack(spacing: 0) {
            marketsHeader
            searchBar
            listSections
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private var marketsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Markets")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Text("\(vm.searchText.isEmpty ? (vm.myMarkets.count + vm.otherMarkets.count) : (vm.filtered(vm.myMarkets).count + vm.filtered(vm.otherMarkets).count)) cryptocurrencies")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Market status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.green.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
    
    private func detailPanelView(for selectedSymbol: String) -> some View {
        HStack(spacing: 0) {
            // Divider line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.1), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
            
            ScrollView {
                VStack(spacing: 24) {
                    detailHeader(for: selectedSymbol)
                    chartSection(for: selectedSymbol)
                    marketStatisticsSection(for: selectedSymbol)
                    holdingsSection(for: selectedSymbol)
                    tradeSection(for: selectedSymbol)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.12))
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
    }
    
    private func detailHeader(for selectedSymbol: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Asset icon
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.8), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(selectedSymbol.prefix(selectedSymbol.count - 4)).prefix(2))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedSymbol)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(String(selectedSymbol.prefix(selectedSymbol.count - 4)))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                if let quote = app.quotes[selectedSymbol] {
                    priceDisplay(for: selectedSymbol, quote: quote)
                } else {
                    Text("--")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            Spacer()
            
            Button(action: { 
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.selectedSymbol = nil 
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
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
    
    private func priceDisplay(for selectedSymbol: String, quote: Quote) -> some View {
        HStack(spacing: 16) {
            Text("$\(formatPrice(quote.price))")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            // Show 24h change if we have data
            let allData = historicalData[selectedSymbol] ?? []
            if !allData.isEmpty {
                let cutoff24h = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
                let last24hData = allData.filter { $0.timestamp >= cutoff24h }
                let price24hAgo = last24hData.first?.price ?? quote.price
                let change24h = quote.price - price24hAgo
                let pct24h = price24hAgo != 0 ? (change24h / price24hAgo) * 100 : 0
                
                HStack(spacing: 8) {
                    Image(systemName: change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(change24h >= 0 ? .green : .red)
                    
                    Text(formatPercentage(pct24h))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(change24h >= 0 ? .green : .red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((change24h >= 0 ? Color.green : Color.red).opacity(0.15))
                )
            }
        }
    }
    
    private func chartSection(for selectedSymbol: String) -> some View {
        let chartData = getChartData(for: selectedSymbol)
        let buckets = getChartBuckets(for: selectedSymbol)
        let hasData = isHistoricalDataLoaded && !chartData.isEmpty

        return VStack(alignment: .leading, spacing: 16) {
            chartHeaderView()

            timeRangePickerView()

            chartContentView(chartData: chartData, buckets: buckets, hasData: hasData)
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
        .onChange(of: app.quotes[selectedSymbol]?.price) { _, _ in
            let rangeKey = selectedChartRange.rawValue
            downsampleCache[selectedSymbol]?[rangeKey] = nil
            bucketCache[selectedSymbol]?[rangeKey] = nil
        }
    }

    private func chartHeaderView() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(.blue)
                .font(.system(size: 16))

            Text("Price Chart")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func timeRangePickerView() -> some View {
        Picker("Range", selection: $selectedChartRange) {
            ForEach(ChartRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
        .onChange(of: selectedChartRange) { oldRange, newRange in
            handleChartRangeChange(oldRange: oldRange, newRange: newRange)
        }
    }

    private func handleChartRangeChange(oldRange: ChartRange, newRange: ChartRange) {
        print("📊 [MarketsView] Chart range changed from \(oldRange.rawValue) to \(newRange.rawValue)")

        // Clear all cached data to force fresh calculation
        downsampleCache.removeAll()
        bucketCache.removeAll()
    }

    private func chartContentView(chartData: [PriceDataPoint], buckets: [ChartBucket], hasData: Bool) -> some View {
        Group {
            if !isHistoricalDataLoaded {
                loadingIndicatorView()
            } else if hasData {
                chartWithDataView(chartData: chartData, buckets: buckets)
            } else {
                noDataView()
            }
        }
    }

    private func loadingIndicatorView() -> some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .foregroundColor(.blue)
            Text("Loading chart data...")
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func chartWithDataView(chartData: [PriceDataPoint], buckets: [ChartBucket]) -> some View {
        VStack(spacing: 16) {
            chartStatsRow(for: chartData)

            PriceChart(
                dataPoints: chartData,
                height: 200,
                showGrid: true,
                xDomain: chartDomain(from: chartData),
                interactive: true,
                buckets: buckets
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
            )
            .animation(.easeInOut(duration: 0.25), value: chartData.count)
            .animation(.easeInOut(duration: 0.25), value: selectedChartRange)

            if !buckets.isEmpty {
                performanceIndicatorView()
            }
        }
    }

    private func noDataView() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                .frame(height: 200)

            VStack(spacing: 12) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.4))

                Text("No data for selected range")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func performanceIndicatorView() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
            Text("Downsampled for performance")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.top, 4)
    }

    private func chartDomain(from chartData: [PriceDataPoint]) -> ClosedRange<Date> {
        guard let first = chartData.first?.timestamp,
              let last = chartData.last?.timestamp else {
            return Date()...Date()
        }
        return first...last
    }
    
    private func getChartData(for selectedSymbol: String) -> [PriceDataPoint] {
        let allData = historicalData[selectedSymbol] ?? []
        let now = Date()
        let cutoff: Date = {
            if let dur = selectedChartRange.duration {
                return now.addingTimeInterval(-dur)
            } else {
                return allData.first?.timestamp ?? now.addingTimeInterval(-60*60*24*365*10)
            }
        }()
        
        let rangeKey = selectedChartRange.rawValue
        let symbolKey = selectedSymbol

        print("📊 [MarketsView] getChartData for \(symbolKey) range \(rangeKey) - Total data points: \(allData.count)")

        // Cached values
        let cachedPoints = downsampleCache[symbolKey]?[rangeKey]

        if let cp = cachedPoints, !cp.isEmpty {
            print("📊 [MarketsView] Using cached data for \(symbolKey) range \(rangeKey) - \(cp.count) points")
            return cp
        } else {
            print("📊 [MarketsView] Computing new data for \(symbolKey) range \(rangeKey)")
            // Compute using preferred interval
            let intervalSeconds = selectedChartRange.preferredInterval
            let filteredData: [PriceDataPoint] = allData.filter { $0.timestamp >= cutoff }
            
            // For any chart range, if filteredData is empty and a fetch for this symbol/range isn't already in progress,
            // asynchronously fetch recent data from the database for an appropriate time window.
            //
            // This now applies to all chart time ranges, not just the shortest filters.
            if filteredData.isEmpty && selectedChartRange.duration != nil {
                let fetchKey = "\(symbolKey)-\(rangeKey)"
                if !isFetchingRecentData.contains(fetchKey) {
                    isFetchingRecentData.insert(fetchKey)
                    Task {
                        print("🚀 [MarketsView] Fetching recent historical data for symbol \(symbolKey), range \(rangeKey)")
                        let dbManager = HistoricalDatabaseManager.shared
                        let now = Date()
                        // Determine fetch duration based on selectedChartRange duration
                        // Fetch at least double the selected range duration up to some reasonable max (e.g., 30 days)
                        let requestedDuration = selectedChartRange.duration!
                        let fetchDurationSeconds = min(max(requestedDuration * 2, 60*60*24), 60*60*24*30) // At least 1 day, at most 30 days
                        let fetchStartDate = now.addingTimeInterval(-fetchDurationSeconds)
                        let newData = await dbManager.getPriceData(symbol: symbolKey, from: fetchStartDate, to: now)
                        if !newData.isEmpty {
                            await MainActor.run {
                                // Update historicalData with fresh data
                                historicalData[symbolKey] = newData
                                print("✅ [MarketsView] Loaded recent data for \(symbolKey): \(newData.count) points")
                                // Remove from fetching set
                                isFetchingRecentData.remove(fetchKey)
                                // Invalidate caches so data is reprocessed
                                downsampleCache[symbolKey]?[rangeKey] = nil
                                bucketCache[symbolKey]?[rangeKey] = nil
                            }
                        } else {
                            await MainActor.run {
                                print("⚠️ [MarketsView] No recent data found for \(symbolKey) in database")
                                isFetchingRecentData.remove(fetchKey)
                            }
                        }
                    }
                }
                
                // Also try extended data range fallback if available
                let extendedCutoff = now.addingTimeInterval(-(selectedChartRange.duration! * 2))
                let extendedData = allData.filter { $0.timestamp >= extendedCutoff }
                if !extendedData.isEmpty {
                    print("📊 [MarketsView] Using extended data range for \(selectedSymbol) - \(selectedChartRange.rawValue)")
                    let chartData = ChartDownsampler.downsample(extendedData, intervalSeconds: intervalSeconds)
                    let buckets = ChartDownsampler.bucketize(extendedData, intervalSeconds: intervalSeconds)
                    setCache(for: symbolKey, rangeKey: rangeKey, points: chartData, buckets: buckets)
                    return chartData
                }
            }
            
            let chartData = ChartDownsampler.downsample(filteredData, intervalSeconds: intervalSeconds)
            print("📊 [MarketsView] Generated \(chartData.count) chart points for \(symbolKey) range \(rangeKey)")
            
            // Store in cache
            withAnimation {
                let buckets = ChartDownsampler.bucketize(filteredData, intervalSeconds: intervalSeconds)
                setCache(for: symbolKey, rangeKey: rangeKey, points: chartData, buckets: buckets)
            }
            return chartData
        }
    }
    
    private func getChartBuckets(for selectedSymbol: String) -> [ChartBucket] {
        let allData = historicalData[selectedSymbol] ?? []
        let now = Date()
        let cutoff: Date = {
            if let dur = selectedChartRange.duration {
                return now.addingTimeInterval(-dur)
            } else {
                return allData.first?.timestamp ?? now.addingTimeInterval(-60*60*24*365*10)
            }
        }()
        
        let rangeKey = selectedChartRange.rawValue
        let symbolKey = selectedSymbol

        // Cached values
        let cachedBuckets = bucketCache[symbolKey]?[rangeKey]

        if let cb = cachedBuckets, !cb.isEmpty {
            return cb
        } else {
            // Compute using preferred interval
            let intervalSeconds = selectedChartRange.preferredInterval
            let filteredData: [PriceDataPoint] = allData.filter { $0.timestamp >= cutoff }
            
            // For very short time ranges (like 10M), ensure we have enough data points
            // If we don't have enough data for the selected range, try to get more recent data
            if filteredData.isEmpty && selectedChartRange.duration != nil {
                let extendedCutoff = now.addingTimeInterval(-(selectedChartRange.duration! * 2))
                let extendedData = allData.filter { $0.timestamp >= extendedCutoff }
                if !extendedData.isEmpty {
                    return ChartDownsampler.bucketize(extendedData, intervalSeconds: intervalSeconds)
                }
            }
            
            let buckets = ChartDownsampler.bucketize(filteredData, intervalSeconds: intervalSeconds)
            return buckets
        }
    }
    
    private func chartStatsRow(for chartData: [PriceDataPoint]) -> some View {
        let first = chartData.first!.price
        let last = chartData.last!.price
        let change = last - first
        let pct = first != 0 ? (change / first) * 100 : 0
        let high = chartData.map { $0.price }.max() ?? last
        let low = chartData.map { $0.price }.min() ?? last
        let color: Color = change >= 0 ? .green : .red

        return HStack(spacing: 20) {
            statBadge(title: "Change", value: String(format: "%@%.6f", change >= 0 ? "+" : "", change), color: color)
            statBadge(title: "Percent", value: formatPercentage(pct), color: color)
            statBadge(title: "High", value: "$\(formatPrice(high))", color: .white)
            statBadge(title: "Low", value: "$\(formatPrice(low))", color: .white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
        )
    }
    
    private func marketStatisticsSection(for selectedSymbol: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16))
                
                Text("Market Statistics")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            let allData = historicalData[selectedSymbol] ?? []
            let hasData = !allData.isEmpty
            
            if hasData {
                marketStatsContent(for: selectedSymbol, allData: allData)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text("No market data available")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
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
    
    private func marketStatsContent(for selectedSymbol: String, allData: [PriceDataPoint]) -> some View {
        let prices = allData.map { $0.price }
        let currentPrice = app.quotes[selectedSymbol]?.price ?? prices.last ?? 0
        
        // Calculate 24h metrics
        let cutoff24h = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let last24hData = allData.filter { $0.timestamp >= cutoff24h }
        let price24hAgo = last24hData.first?.price ?? currentPrice
        let change24h = currentPrice - price24hAgo
        let pct24h = price24hAgo != 0 ? (change24h / price24hAgo) * 100 : 0
        
        // Calculate volatility
        let avgPrice = prices.reduce(0, +) / Double(prices.count)
        let variance = prices.map { pow($0 - avgPrice, 2) }.reduce(0, +) / Double(prices.count)
        let volatility = sqrt(variance)
        let volatilityPct = avgPrice != 0 ? (volatility / avgPrice) * 100 : 0
        
        return VStack(spacing: 12) {
            // 24h Change
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("24h Change")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 8) {
                        Text("$\(String(format: "%.2f", change24h))")
                            .font(.headline)
                            .foregroundColor(change24h >= 0 ? .green : .red)
                        Text("(\(String(format: "%+.2f%%", pct24h)))")
                            .font(.subheadline)
                            .foregroundColor(change24h >= 0 ? .green.opacity(0.8) : .red.opacity(0.8))
                    }
                }
                Spacer()
                Image(systemName: change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.title3)
                    .foregroundColor(change24h >= 0 ? .green : .red)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
            )
            
            // Market metrics grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "24h High", value: "$\(String(format: "%.2f", last24hData.map { $0.price }.max() ?? currentPrice))", icon: "arrow.up.circle.fill", color: .green)
                metricCard(title: "24h Low", value: "$\(String(format: "%.2f", last24hData.map { $0.price }.min() ?? currentPrice))", icon: "arrow.down.circle.fill", color: .red)
                metricCard(title: "Volatility", value: String(format: "%.2f%%", volatilityPct), icon: "waveform.path.ecg", color: .orange)
                metricCard(title: "Avg Price", value: "$\(String(format: "%.2f", avgPrice))", icon: "chart.line.uptrend.xyaxis", color: .blue)
            }
        }
    }
    
    private func holdingsSection(for selectedSymbol: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                
                Text("Your Holdings")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            let assetCode = String(selectedSymbol.prefix(selectedSymbol.count - 4))
            if let holding = app.holdings.first(where: { $0.asset_code == assetCode }) {
                holdingsContent(for: selectedSymbol, assetCode: assetCode, holding: holding)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.4))
                    
                    VStack(spacing: 8) {
                        Text("No Holdings")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("You don't own any \(assetCode)")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
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
    
    private func holdingsContent(for selectedSymbol: String, assetCode: String, holding: HoldingItem) -> some View {
        let qty = Double(holding.quantity) ?? 0
        if let quote = app.quotes[selectedSymbol] {
            let currentValue = qty * quote.price
            
            return AnyView(VStack(spacing: 12) {
                // Position size
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Position Size")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(String(format: "%.8f", qty)) \(assetCode)")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                )
                
                // Current value
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Value")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text("$\(String(format: "%.2f", currentValue))")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    
                    // Portfolio %
                    if app.portfolioValue > 0 {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Portfolio %")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Text(String(format: "%.1f%%", (currentValue / app.portfolioValue) * 100))
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.3))
                )
            })
        } else {
            return AnyView(Text("\(String(format: "%.8f", qty)) \(assetCode)")
                .font(.headline)
                .foregroundColor(.white)
                .padding())
        }
    }
    
    private func tradeSection(for selectedSymbol: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(.blue)
                    .font(.system(size: 16))
                
                Text("Trade")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            TradeTicketInline(symbol: selectedSymbol)
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

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 16, weight: .medium))
            
            TextField("Search cryptocurrencies...", text: $vm.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .accentColor(.blue)
            
            if !vm.searchText.isEmpty {
                Button(action: { vm.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            vm.searchText.isEmpty ? 
                            Color.white.opacity(0.1) : 
                            Color.blue.opacity(0.3), 
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .onChange(of: vm.searchText) { _, newValue in
            // Debug logging
            if !newValue.isEmpty {
                let filteredMyMarkets = vm.filtered(vm.myMarkets)
                let filteredOtherMarkets = vm.filtered(vm.otherMarkets)
                print("🔍 [MarketsView] Search: '\(newValue)' - My: \(filteredMyMarkets.count)/\(vm.myMarkets.count), Other: \(filteredOtherMarkets.count)/\(vm.otherMarkets.count)")
            }
            
            // Clear cache when search changes to ensure fresh data loading
            if newValue.isEmpty {
                downsampleCache.removeAll()
                bucketCache.removeAll()
            } else {
                // Load data for newly visible symbols
                let filteredSymbols = vm.filtered(vm.myMarkets + vm.otherMarkets)
                let symbolsNeedingData = filteredSymbols.filter { historicalData[$0]?.isEmpty ?? true }
                
                if !symbolsNeedingData.isEmpty {
                    Task {
                        await loadHistoricalData(for: symbolsNeedingData)
                    }
                }
            }
        }
    }

    private var listSections: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // My Markets Section
                let filteredMyMarkets = vm.filtered(vm.myMarkets)
                let filteredOtherMarkets = vm.filtered(vm.otherMarkets)
                
                // Debug logging - moved to onChange to avoid view update issues
                
                if !filteredMyMarkets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 14))
                            
                            Text("My Markets")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("\(filteredMyMarkets.count)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.1))
                                )
                        }
                        .padding(.horizontal, 24)

                        LazyVStack(spacing: 8) {
                            ForEach(filteredMyMarkets, id: \.self) { sym in
                                marketRow(sym)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                // All Markets Section
                if !filteredOtherMarkets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))
                            
                            Text("All Markets")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("\(filteredOtherMarkets.count)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.1))
                                )
                        }
                        .padding(.horizontal, 24)

                        LazyVStack(spacing: 8) {
                            ForEach(filteredOtherMarkets, id: \.self) { sym in
                                marketRow(sym)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }

                // Empty state
                if filteredMyMarkets.isEmpty && filteredOtherMarkets.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.3))
                        
                        VStack(spacing: 8) {
                            Text("No markets found")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("Try adjusting your search terms")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 60)
                }
                
                // Bottom padding
                Color.clear.frame(height: 20)
            }
        }
        .background(Color.clear)
    }


    private func marketRow(_ sym: String) -> some View {
        let q = app.quotes[sym]
        let chartData = historicalData[sym] ?? []
        let assetCode = String(sym.prefix(sym.count - 4))
        
        return HStack(spacing: 16) {
            // Left side - Symbol info
            HStack(spacing: 12) {
                // Asset icon placeholder
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.8), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(assetCode.prefix(2)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(assetCode)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(sym)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Right side - Price and chart
            HStack(spacing: 12) {
                // Current price
                if let quote = q {
                    Text("$\(formatPrice(quote.price))")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                } else {
                    Text("--")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                // Mini chart
                if isHistoricalDataLoaded && !chartData.isEmpty {
                    PriceChart(dataPoints: chartData, height: 40, showGrid: false, hideYAxisLabels: true)
                        .frame(width: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 80, height: 40)
                        .overlay(
                            Text(isHistoricalDataLoaded ? "No data" : "Loading...")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        )
                }
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
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedSymbol = sym
                if let sym = selectedSymbol {
                    downsampleCache[sym] = [:]
                    bucketCache[sym] = [:]
                }
            }
        }
    }

    private func statBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16))
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private func loadHistoricalData(for symbols: [String]) async {
        print("🚀 [MarketsView] loadHistoricalData() CALLED for \(symbols.count) symbols")

        let dbManager = HistoricalDatabaseManager.shared
        let calendar = Calendar.current

        // Get data from last 7 days to ensure we have enough data for all chart ranges
        let now = Date()
        let startOfLastWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        print("📈 [MarketsView] Loading historical data for \(symbols.count) symbols from \(startOfLastWeek) to \(now)")

        var loadedSymbols = 0
        for symbol in symbols { // Load data for all symbols
            print("📈 [MarketsView] Loading historical data for \(symbol) from local database")
            
            // Try to get data from the last week first
            var pricePoints = await dbManager.getPriceData(symbol: symbol, from: startOfLastWeek, to: now)
            
            // If no data in the last week, try to get any available data
            if pricePoints.isEmpty {
                print("📈 [MarketsView] No data in last week for \(symbol), trying to get any available data")
                pricePoints = await dbManager.getPriceData(symbol: symbol)
            }
            
            print("📈 [MarketsView] Found \(pricePoints.count) local price points for \(symbol)")

            await MainActor.run {
                historicalData[symbol] = pricePoints
                print("💾 [MarketsView] Stored \(pricePoints.count) points for \(symbol) in historicalData dictionary")
                print("💾 [MarketsView] historicalData now has \(historicalData.count) symbols")

                if !pricePoints.isEmpty {
                    loadedSymbols += 1
                    print("✅ [MarketsView] Successfully loaded \(pricePoints.count) points for \(symbol)")
                } else {
                    print("⚠️ [MarketsView] No data found for \(symbol) in database")
                }
            }
        }

        print("📈 [MarketsView] Completed loading historical data. \(loadedSymbols)/\(symbols.count) symbols have data. Total symbols in historicalData: \(historicalData.count)")

        // Set the loaded flag only if we actually loaded some data
        if loadedSymbols > 0 {
            await MainActor.run {
                isHistoricalDataLoaded = true
                print("✅ [MarketsView] Historical data loaded successfully - setting flag to true")
            }
        } else {
            print("⚠️ [MarketsView] No historical data was loaded - keeping flag as false")
        }
    }
}

private struct TradeTicketInline: View {
    @Environment(ApplicationState.self) private var app
    @State private var side: Side = .buy
    @State private var quantity: String = "0.001"
    @State private var execError: String? = nil
    @State private var orderType: String = "market"
    @State private var limitPrice: String = ""
    @State private var stopPrice: String = ""
    @State private var timeInForce: String = "gtc"
    @State private var estimatedPriceText: String = ""
    @State private var showOrderSuccess: Bool = false
    @State private var orderSuccessMessage: String = ""
    let symbol: String

    // Compute the user's current holding quantity for the selected symbol
    private var heldQuantity: Double {
        // holdings are in asset_code (e.g., BTC) and quantity as String
        // Convert symbol like "BTC-USD" to asset code "BTC"
        let assetCode = symbol.components(separatedBy: "-").first ?? symbol
        if let holding = app.holdings.first(where: { $0.asset_code == assetCode }) {
            return Double(holding.quantity) ?? 0
        }
        return 0
    }

    // Convenience to format a double without trailing zeros where possible
    private func formatQty(_ value: Double) -> String {
        if value == 0 { return "0" }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.minimumIntegerDigits = 1
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current Holdings Summary
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Holdings")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    let qty = heldQuantity
                    if qty > 0 {
                        let qtyText = formatQty(qty)
                        if let quote = app.quotes[symbol] {
                            let value = qty * quote.price
                            Text("\(qtyText) \(symbol)  •  $\(String(format: "%.2f", value))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(qtyText) \(symbol)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No position")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Sell All") {
                    // Set up a full-position sell
                    let qty = heldQuantity
                    guard qty > 0 else { return }
                    side = .sell
                    quantity = formatQty(qty)
                    // Default to market sell for speed; user can change type if desired
                    orderType = "market"
                    // Trigger place order
                    Task { await placeOrder() }
                }
                .buttonStyle(.bordered)
                .disabled(heldQuantity <= 0)
            }

            Picker("Side", selection: $side) {
                Text("Buy").tag(Side.buy)
                Text("Sell").tag(Side.sell)
            }
            .pickerStyle(.segmented)
            Picker("Type", selection: $orderType) {
                Text("Market").tag("market")
                Text("Limit").tag("limit")
                Text("Stop-Loss").tag("stop_loss")
                Text("Stop-Limit").tag("stop_limit")
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Qty")
                TextField("0.0", text: $quantity)
                    .textFieldStyle(.roundedBorder)
            }
            if orderType == "limit" || orderType == "stop_limit" {
                HStack {
                    Text("Limit Price")
                    TextField("0.00", text: $limitPrice)
                        .textFieldStyle(.roundedBorder)
                }
            }
            if orderType == "stop_loss" || orderType == "stop_limit" {
                HStack {
                    Text("Stop Price")
                    TextField("0.00", text: $stopPrice)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Text("Time in Force")
                TextField("gtc", text: $timeInForce)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Estimate Price") {
                    Task {
                        do {
                            let sideStr = side == .buy ? "ask" : "bid"
                            let qtyStr = quantity.isEmpty ? "0" : quantity
                            let data = try await app.broker.getEstimatedPrice(symbol: symbol, side: sideStr, quantity: qtyStr)
                            estimatedPriceText = String(data: data, encoding: .utf8) ?? "(no data)"
                        } catch {
                            estimatedPriceText = "Error: \(error.localizedDescription)"
                        }
                    }
                }
                Spacer()
                Text(estimatedPriceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button("Place Order") {
                Task { await placeOrder() }
            }
            .buttonStyle(.borderedProminent)
            .alert("Order Error", isPresented: Binding(get: { execError != nil }, set: { _ in execError = nil })) {
                Button("OK", role: .cancel) {}
            } message: { Text(execError ?? "") }
            .alert("Order Placed", isPresented: $showOrderSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(orderSuccessMessage)
            }
        }
    }

    @MainActor
    private func showExecError(_ message: String) {
        execError = message
    }

    private func validateInputs() throws {
        let qty = Double(quantity) ?? 0
        if qty <= 0 { throw NSError(domain: "TradeTicketInline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Quantity must be greater than 0"]) }
        if orderType == "limit" || orderType == "stop_limit" {
            let lp = Double(limitPrice) ?? 0
            if lp <= 0 { throw NSError(domain: "TradeTicketInline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Limit price must be greater than 0"]) }
        }
        if orderType == "stop_loss" || orderType == "stop_limit" {
            let sp = Double(stopPrice) ?? 0
            if sp <= 0 { throw NSError(domain: "TradeTicketInline", code: 3, userInfo: [NSLocalizedDescriptionKey: "Stop price must be greater than 0"]) }
        }
    }

    private func placeOrder() async {
        do {
            try validateInputs()
            let qty = Double(quantity) ?? 0
            let sideText = (side == .buy) ? "Buy" : "Sell"

            switch orderType {
            case "market":
                _ = try await app.executionManager.placeMarket(symbol: symbol, side: side, quantity: qty)
            case "limit":
                let lp = Double(limitPrice) ?? 0
                _ = try await app.executionManager.placeLimit(symbol: symbol, side: side, quantity: qty, limitPrice: lp, tif: timeInForce)
            case "stop_loss":
                let sp = Double(stopPrice) ?? 0
                _ = try await app.executionManager.placeStopLoss(symbol: symbol, side: side, quantity: qty, stopPrice: sp, tif: timeInForce)
            case "stop_limit":
                let sp = Double(stopPrice) ?? 0
                let lp = Double(limitPrice) ?? 0
                _ = try await app.executionManager.placeStopLimit(symbol: symbol, side: side, quantity: qty, stopPrice: sp, limitPrice: lp, tif: timeInForce)
            default:
                break
            }

            // If we reached here, submission returned without throwing. Treat as success immediately.
            await MainActor.run {
                let priceContext: String
                if let q = app.quotes[symbol] {
                    priceContext = String(format: "@$%.2f", q.price)
                } else {
                    priceContext = ""
                }
                orderSuccessMessage = "\(sideText) \(formatQty(qty)) \(symbol) \(priceContext) submitted successfully."
                showOrderSuccess = true
            }

            // Soft-refresh portfolio/holdings in the background. Do not surface failures as order failure.
            Task.detached {
                // Give the broker a moment to settle
                try? await Task.sleep(nanoseconds: 500_000_000)
                DispatchQueue.main.async {
                    app.updatePortfolioDerivedValues()
                }
            }
        } catch {
            let errorDesc = error.localizedDescription
            let nsError = error as NSError
            
            // Check for specific Robinhood errors
            var message = errorDesc
            
            if errorDesc.contains("halt") {
                message = "⚠️ Trading Halted\n\nRobinhood has temporarily halted trading for this cryptocurrency. This can happen due to:\n• Extreme market volatility\n• System maintenance\n• Regulatory requirements\n\nPlease try again later or check Robinhood's status page."
            } else if errorDesc.contains("insufficient") && errorDesc.lowercased().contains("fund") {
                message = "💰 Insufficient Funds\n\nYou don't have enough buying power for this order. Please check your portfolio balance."
            } else if errorDesc.contains("Rate limited") {
                message = "⏱️ Rate Limit Exceeded\n\nYou've made too many requests. Please wait a moment before trying again."
            } else {
                // Check for likely-transient network/data issues
                let likelyTransient = (nsError.domain == NSURLErrorDomain)
                    || errorDesc.lowercased().contains("timeout")
                    || errorDesc.lowercased().contains("network error")
                    || errorDesc.lowercased().contains("could not be parsed")
                    || errorDesc.lowercased().contains("data could not be read")
                
                if likelyTransient {
                    message = "🔄 Temporary Network Issue\n\nThere was a temporary connectivity issue. Your order may have been accepted.\n\nPlease check your portfolio or orders to confirm.\n\nDetails: \(errorDesc)"
                }
            }
            
            await MainActor.run {
                execError = message
            }
        }
    }
}

#Preview {
    let state = ApplicationState()
    return MarketsView().environment(state)
}

