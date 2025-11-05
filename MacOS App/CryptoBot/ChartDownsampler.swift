import Foundation

/// Enum representing bucket intervals for downsampling price data.
public enum ChartBucketInterval: TimeInterval {
    case minute5 = 300
    case minute15 = 900
    case hour1 = 3600
    case hour4 = 14400
    case day1 = 86400
}

public extension ChartBucketInterval {
    static func from(seconds: TimeInterval) -> ChartBucketInterval {
        // Map to nearest bucket size not exceeding seconds when possible, otherwise pick smallest
        if seconds <= ChartBucketInterval.minute5.rawValue { return .minute5 }
        if seconds <= ChartBucketInterval.minute15.rawValue { return .minute15 }
        if seconds <= ChartBucketInterval.hour1.rawValue { return .hour1 }
        if seconds <= ChartBucketInterval.hour4.rawValue { return .hour4 }
        return .day1
    }
}

public struct ChartBucket: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let avg: Double
    public let min: Double
    public let max: Double
}

/// Helper for bucketing and downsampling arrays of `PriceDataPoint`.
public struct ChartDownsampler {
    /// Downsamples the given array of `PriceDataPoint` into buckets of the specified interval.
    /// Each bucket aggregates points by averaging their prices.
    /// - Parameters:
    ///   - points: The array of `PriceDataPoint` to downsample.
    ///   - interval: The bucket interval to use for aggregation.
    /// - Returns: A downsampled array of `PriceDataPoint` with bucketed average prices.
    public static func downsample(_ points: [PriceDataPoint], interval: ChartBucketInterval) -> [PriceDataPoint] {
        guard points.count > 2 else { return points }
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        var result: [PriceDataPoint] = []
        var bucketStart: Date? = nil
        var bucketSum: Double = 0
        var bucketCount: Int = 0
        for p in sorted {
            let currentBucket = floorToInterval(p.timestamp, interval: interval)
            if bucketStart == nil {
                bucketStart = currentBucket
            } else if currentBucket != bucketStart {
                if bucketCount > 0, let start = bucketStart {
                    let avg = bucketSum / Double(bucketCount)
                    result.append(PriceDataPoint(timestamp: start, price: avg))
                }
                bucketStart = currentBucket
                bucketSum = 0
                bucketCount = 0
            }
            bucketSum += p.price
            bucketCount += 1
        }
        if bucketCount > 0, let start = bucketStart {
            let avg = bucketSum / Double(bucketCount)
            result.append(PriceDataPoint(timestamp: start, price: avg))
        }
        return result
    }

    public static func downsample(_ points: [PriceDataPoint], intervalSeconds: TimeInterval) -> [PriceDataPoint] {
        let interval = ChartBucketInterval.from(seconds: intervalSeconds)
        return downsample(points, interval: interval)
    }

    public static func bucketize(_ points: [PriceDataPoint], interval: ChartBucketInterval) -> [ChartBucket] {
        guard points.count > 2 else {
            return points.map { ChartBucket(timestamp: $0.timestamp, avg: $0.price, min: $0.price, max: $0.price) }
        }
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        var result: [ChartBucket] = []
        var bucketStart: Date? = nil
        var sum: Double = 0
        var count: Int = 0
        var minV: Double = .infinity
        var maxV: Double = -.infinity
        for p in sorted {
            if bucketStart == nil { bucketStart = floorToInterval(p.timestamp, interval: interval) }
            let currentBucket = floorToInterval(p.timestamp, interval: interval)
            if currentBucket != bucketStart {
                if let start = bucketStart, count > 0 {
                    let avg = sum / Double(count)
                    result.append(ChartBucket(timestamp: start, avg: avg, min: minV, max: maxV))
                }
                bucketStart = currentBucket
                sum = 0
                count = 0
                minV = .infinity
                maxV = -.infinity
            }
            sum += p.price
            count += 1
            minV = min(minV, p.price)
            maxV = max(maxV, p.price)
        }
        if let start = bucketStart, count > 0 {
            let avg = sum / Double(count)
            result.append(ChartBucket(timestamp: start, avg: avg, min: minV, max: maxV))
        }
        return result
    }

    public static func bucketize(_ points: [PriceDataPoint], intervalSeconds: TimeInterval) -> [ChartBucket] {
        let interval = ChartBucketInterval.from(seconds: intervalSeconds)
        return bucketize(points, interval: interval)
    }

    /// Suggests an appropriate bucket interval based on the total time span and desired number of points.
    /// - Parameters:
    ///   - spanSeconds: Total time span in seconds.
    ///   - targetPointCount: Desired number of points after downsampling (default is 120).
    /// - Returns: A `ChartBucketInterval` suitable for downsampling to approximately the target point count.
    public static func suggestedInterval(for spanSeconds: TimeInterval, targetPointCount: Int = 120) -> ChartBucketInterval {
        let approx = spanSeconds / Double(max(1, targetPointCount))
        if approx <= ChartBucketInterval.minute5.rawValue { return .minute5 }
        if approx <= ChartBucketInterval.minute15.rawValue { return .minute15 }
        if approx <= ChartBucketInterval.hour1.rawValue { return .hour1 }
        if approx <= ChartBucketInterval.hour4.rawValue { return .hour4 }
        return .day1
    }

    /// Floors the given date to the nearest lower multiple of the specified interval.
    /// - Parameters:
    ///   - date: The date to floor.
    ///   - interval: The bucket interval to floor to.
    /// - Returns: The floored date.
    private static func floorToInterval(_ date: Date, interval: ChartBucketInterval) -> Date {
        let t = date.timeIntervalSince1970
        let floored = floor(t / interval.rawValue) * interval.rawValue
        return Date(timeIntervalSince1970: floored)
    }
}

/// Minimal fallback definition of `PriceDataPoint` for standalone usage.
/// When imported in projects that define `PriceDataPoint`, this extension ensures compatibility.
/// Represents a single price data point with a timestamp and price.
public struct PriceDataPoint: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let price: Double
    public init(timestamp: Date, price: Double) {
        self.timestamp = timestamp
        self.price = price
    }
}
