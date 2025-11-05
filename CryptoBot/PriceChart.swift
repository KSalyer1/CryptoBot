import SwiftUI
import Charts

/// A chart view that displays price data points over time.
///
/// The chart sorts the provided data points by their timestamp in ascending order.
/// It automatically pads the y-axis domain to avoid flat lines when all prices are identical.
/// The chart can optionally show grid lines on both axes.
///
/// - Parameters:
///   - dataPoints: An array of `PriceDataPoint` representing time and price.
///   - height: The height of the chart view.
///   - showGrid: A Boolean value indicating whether to display grid lines.
struct PriceChart: View {
    let dataPoints: [PriceDataPoint]
    let height: CGFloat
    let showGrid: Bool
    // Optional: external domain control and interactivity toggle
    let xDomain: ClosedRange<Date>?
    let interactive: Bool
    // Optional bucketed series (avg/min/max). If provided, it takes precedence for rendering.
    let buckets: [ChartBucket]?
    // Optional: hide Y-axis labels for mini charts
    let hideYAxisLabels: Bool
    
    init(
        dataPoints: [PriceDataPoint],
        height: CGFloat = 60,
        showGrid: Bool = false,
        xDomain: ClosedRange<Date>? = nil,
        interactive: Bool = false,
        buckets: [ChartBucket]? = nil,
        hideYAxisLabels: Bool = false
    ) {
        self.dataPoints = dataPoints
        self.height = height
        self.showGrid = showGrid
        self.xDomain = xDomain
        self.interactive = interactive
        self.buckets = buckets
        self.hideYAxisLabels = hideYAxisLabels
    }
    
    private var sortedPoints: [PriceDataPoint] {
        dataPoints.sorted { $0.timestamp < $1.timestamp }
    }
    
    private var sortedBuckets: [ChartBucket] {
        (buckets ?? []).sorted { $0.timestamp < $1.timestamp }
    }
    
    private var yDomain: ClosedRange<Double> {
        if let b = buckets, !b.isEmpty {
            let mins = b.map { $0.min }
            let maxs = b.map { $0.max }
            guard let min = mins.min(), let max = maxs.max() else { return 0...1 }
            if min == max {
                let center = min
                let range = Swift.max(center * 0.01, 0.01)
                return (center - range)...(center + range)
            } else {
                let padding = (max - min) * 0.1
                return (min - padding)...(max + padding)
            }
        } else {
            let prices = sortedPoints.map(\.price)
            guard let min = prices.min(), let max = prices.max(), !prices.isEmpty else {
                return 0...1
            }
            if min == max {
                let center = min
                let range = Swift.max(center * 0.01, 0.01)
                return (center - range)...(center + range)
            } else {
                let padding = (max - min) * 0.1
                return (min - padding)...(max + padding)
            }
        }
    }
    
    // Formatters
    private let priceFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        return nf
    }()
    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()
    
    // Interaction state
    @State private var selectedDate: Date? = nil
    private var nearestPoint: (date: Date, price: Double)? {
        guard let d = selectedDate else { return nil }
        if !sortedBuckets.isEmpty {
            if let nearest = sortedBuckets.min(by: { abs($0.timestamp.timeIntervalSince(d)) < abs($1.timestamp.timeIntervalSince(d)) }) {
                return (nearest.timestamp, nearest.avg)
            }
            return nil
        } else {
            if let nearest = sortedPoints.min(by: { abs($0.timestamp.timeIntervalSince(d)) < abs($1.timestamp.timeIntervalSince(d)) }) {
                return (nearest.timestamp, nearest.price)
            }
            return nil
        }
    }
    
    private var accessibilityDescription: String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        let lower = (xDomain?.lowerBound) ?? (sortedBuckets.first?.timestamp ?? sortedPoints.first?.timestamp ?? Date())
        let upper = (xDomain?.upperBound) ?? (sortedBuckets.last?.timestamp ?? sortedPoints.last?.timestamp ?? Date())
        let startText = df.string(from: lower)
        let endText = df.string(from: upper)
        if let np = nearestPoint {
            let priceText = priceFormatter.string(from: NSNumber(value: np.price)) ?? String(format: "$%.2f", np.price)
            let timeText = timeFormatter.string(from: np.date)
            return "Range: \(startText) to \(endText). Selected: \(priceText) at \(timeText)."
        } else {
            return "Range: \(startText) to \(endText)."
        }
    }
    
    private var chartView: some View {
        if !sortedBuckets.isEmpty {
            AnyView(bucketChart)
        } else {
            AnyView(lineChart)
        }
    }
    
    private var bucketChart: some View {
        Chart(sortedBuckets) { b in
            AreaMark(
                x: .value("Time", b.timestamp),
                yStart: .value("Low", b.min),
                yEnd: .value("High", b.max)
            )
            .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)], startPoint: .top, endPoint: .bottom))

            LineMark(
                x: .value("Time", b.timestamp),
                y: .value("Avg", b.avg)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if showGrid { AxisGridLine().foregroundStyle(.white.opacity(0.1)) }
                AxisTick().foregroundStyle(.white.opacity(0.4))
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if showGrid { AxisGridLine().foregroundStyle(.white.opacity(0.1)) }
                AxisTick().foregroundStyle(.white.opacity(0.4))
                if !hideYAxisLabels {
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(priceFormatter.string(from: NSNumber(value: d)) ?? String(format: "$%.2f", d))
                        }
                    }
                }
            }
        }
        .chartXScale(domain: (xDomain ?? ((sortedPoints.first?.timestamp ?? Date())...(sortedPoints.last?.timestamp ?? Date()))))
        .chartYScale(domain: yDomain)
        .accessibilityLabel("Price chart")
        .accessibilityValue(accessibilityDescription)
    }
    
    private var lineChart: some View {
        Chart(sortedPoints) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Price", point.price)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if showGrid { AxisGridLine().foregroundStyle(.white.opacity(0.1)) }
                AxisTick().foregroundStyle(.white.opacity(0.4))
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if showGrid { AxisGridLine().foregroundStyle(.white.opacity(0.1)) }
                AxisTick().foregroundStyle(.white.opacity(0.4))
                if !hideYAxisLabels {
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(priceFormatter.string(from: NSNumber(value: d)) ?? String(format: "$%.2f", d))
                        }
                    }
                }
            }
        }
        .chartXScale(domain: (xDomain ?? ((sortedPoints.first?.timestamp ?? Date())...(sortedPoints.last?.timestamp ?? Date()))))
        .chartYScale(domain: yDomain)
        .accessibilityLabel("Price chart")
        .accessibilityValue(accessibilityDescription)
    }
    
    var body: some View {
        if sortedPoints.isEmpty {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: height)
                .overlay(
                    Text("No data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
        } else {
            // Debug logging for chart data
            let _ = print("📊 [PriceChart] Rendering chart with \(sortedPoints.count) points, Y-domain: \(yDomain)")
            
            chartView
                .frame(height: height)
        }
    }
}


#Preview {
    let sampleData = [
        PriceDataPoint(timestamp: Date().addingTimeInterval(-3600), price: 100),
        PriceDataPoint(timestamp: Date().addingTimeInterval(-1800), price: 105),
        PriceDataPoint(timestamp: Date().addingTimeInterval(-900), price: 102),
        PriceDataPoint(timestamp: Date(), price: 108)
    ]
    
    VStack {
        PriceChart(dataPoints: sampleData, height: 60)
        PriceChart(
            dataPoints: sampleData,
            height: 120,
            showGrid: true,
            xDomain: (sampleData.first!.timestamp...sampleData.last!.timestamp),
            interactive: true
        )
    }
    .padding()
}
