import Foundation

/// Service for fetching historical cryptocurrency data from Robinhood API
class RobinhoodHistoricalDataService {
    static let shared = RobinhoodHistoricalDataService()
    
    private let dbManager = HistoricalDatabaseManager.shared
    private var broker: RobinhoodCryptoClient?
    
    // Robinhood rate limiting: 100 req/min, 300 burst
    private let maxRequestsPerMinute = 100
    private let burstCapacity = 300
    private let refillInterval: TimeInterval = 1.0 // 1 second
    private let refillAmount = 1
    
    // Token bucket for rate limiting
    private var currentTokens: Int = 300
    private var lastRefillTime: Date = Date()
    
    private init() {
        // Broker will be injected via initialize method
    }
    
    /// Initialize with broker instance
    func initialize(with broker: RobinhoodCryptoClient) {
        self.broker = broker
        print("🔧 [RobinhoodHistoricalDataService] Initialized with broker")
    }
    
    /// Perform full historical data pull for all Robinhood crypto symbols
    func performFullDataPull(symbols: [String]) async {
        print("🚀 [RobinhoodHistoricalDataService] Starting full historical data pull for \(symbols.count) symbols")
        
        let startTime = Date()
        
        for symbol in symbols {
            do {
                print("📈 [RobinhoodHistoricalDataService] Processing \(symbol)...")
                
                // Check if we have any data for this symbol
                let latestTimestamp = await dbManager.getLatestTimestamp(for: symbol)
                
                if let latestTimestamp = latestTimestamp {
                    print("📈 [RobinhoodHistoricalDataService] \(symbol) has data up to \(latestTimestamp)")
                    // Update with recent data
                    try await fetchAndStoreRecentData(symbol: symbol)
                } else {
                    print("📈 [RobinhoodHistoricalDataService] \(symbol) has no data, fetching full history")
                    // Full historical pull
                    try await fetchAndStoreFullHistory(symbol: symbol)
                }
                
                // Rate limiting delay
                await waitForRateLimit()
                
            } catch {
                print("❌ [RobinhoodHistoricalDataService] Failed to process \(symbol): \(error)")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        print("✅ [RobinhoodHistoricalDataService] Full data pull completed in \(String(format: "%.2f", duration)) seconds")
        
        // Print database statistics
        let stats = await dbManager.getDatabaseStats()
        print("📊 [RobinhoodHistoricalDataService] Database stats: \(stats.totalRecords) records, \(stats.symbols) symbols")
        if let oldest = stats.oldestDate, let newest = stats.newestDate {
            print("📊 [RobinhoodHistoricalDataService] Date range: \(oldest) to \(newest)")
        }
    }
    
    /// Fetch historical data for display (from local database first, then API if needed)
    func fetchHistoricalData(symbol: String, days: Int = 1) async throws -> [PriceDataPoint] {
        print("📈 [RobinhoodHistoricalDataService] Fetching historical data for \(symbol) (\(days) days)")
        
        // Try to get data from local database first
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        
        let localData = await dbManager.getPriceData(symbol: symbol, from: startDate, to: endDate)
        
        if !localData.isEmpty {
            print("📈 [RobinhoodHistoricalDataService] Found \(localData.count) local data points for \(symbol)")
            return localData
        }
        
        // If no local data, fetch from Robinhood API
        print("📈 [RobinhoodHistoricalDataService] No local data found, fetching from Robinhood API for \(symbol)")
        let apiData = try await fetchFromRobinhood(symbol: symbol, days: days)
        
        // Store the fetched data
        await dbManager.storePriceData(symbol: symbol, dataPoints: apiData)
        
        return apiData
    }
    
    /// Fetch and store recent data (for incremental updates)
    private func fetchAndStoreRecentData(symbol: String) async throws {
        // Fetch recent data (last 7 days)
        let dataPoints = try await fetchFromRobinhood(symbol: symbol, days: 7)
        await dbManager.storePriceData(symbol: symbol, dataPoints: dataPoints)
        print("📈 [RobinhoodHistoricalDataService] Stored \(dataPoints.count) recent data points for \(symbol)")
    }
    
    /// Fetch and store full historical data
    private func fetchAndStoreFullHistory(symbol: String) async throws {
        print("📈 [RobinhoodHistoricalDataService] Fetching MAXIMUM historical data for \(symbol)")
        
        // Try different time spans to get maximum data
        let spans = ["year", "5year"] // Start with year, then try 5year if available
        var allDataPoints: [PriceDataPoint] = []
        
        for span in spans {
            do {
                let dataPoints = try await fetchFromRobinhood(symbol: symbol, span: span)
                allDataPoints.append(contentsOf: dataPoints)
                print("📈 [RobinhoodHistoricalDataService] Fetched \(dataPoints.count) data points for \(symbol) with span \(span)")
                
                // If we got data, break (don't try smaller spans)
                if !dataPoints.isEmpty {
                    break
                }
            } catch {
                print("📈 [RobinhoodHistoricalDataService] Failed to fetch \(span) data for \(symbol): \(error)")
                continue
            }
        }
        
        if !allDataPoints.isEmpty {
            await dbManager.storePriceData(symbol: symbol, dataPoints: allDataPoints)
            print("📈 [RobinhoodHistoricalDataService] Stored \(allDataPoints.count) historical data points for \(symbol)")
            
            // Store metadata about the data range
            if let firstPoint = allDataPoints.first, let lastPoint = allDataPoints.last {
                let dateRange = "\(firstPoint.timestamp) to \(lastPoint.timestamp)"
                print("📈 [RobinhoodHistoricalDataService] Data range for \(symbol): \(dateRange)")
            }
        }
    }
    
    /// Fetch data from Robinhood API
    private func fetchFromRobinhood(symbol: String, days: Int? = nil, span: String = "year") async throws -> [PriceDataPoint] {
        guard let broker = broker else {
            throw HistoricalDataError.brokerNotInitialized
        }
        
        // Wait for rate limit
        await waitForRateLimit()
        
        // Build the API request
        var components = URLComponents(url: broker.config.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/crypto/marketdata/historicals/"
        
        var queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        
        if let days = days {
            // Convert days to appropriate span
            if days <= 1 {
                queryItems.append(URLQueryItem(name: "interval", value: "5minute"))
                queryItems.append(URLQueryItem(name: "span", value: "day"))
            } else if days <= 7 {
                queryItems.append(URLQueryItem(name: "interval", value: "hour"))
                queryItems.append(URLQueryItem(name: "span", value: "week"))
            } else if days <= 30 {
                queryItems.append(URLQueryItem(name: "interval", value: "day"))
                queryItems.append(URLQueryItem(name: "span", value: "month"))
            } else {
                queryItems.append(URLQueryItem(name: "interval", value: "day"))
                queryItems.append(URLQueryItem(name: "span", value: "year"))
            }
        } else {
            queryItems.append(URLQueryItem(name: "interval", value: "day"))
            queryItems.append(URLQueryItem(name: "span", value: span))
        }
        
        components.queryItems = queryItems
        let pathWithQuery = components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        
        print("📈 [RobinhoodHistoricalDataService] Requesting: \(pathWithQuery)")
        
        // Make the signed request
        let data = try await broker.signedRequest(method: "GET", path: pathWithQuery, jsonBodyString: nil)
        
        // Parse the response
        let response = try JSONDecoder().decode(RobinhoodHistoricalResponse.self, from: data)
        
        let pricePoints = response.data_points?.compactMap { point -> PriceDataPoint? in
            guard let timestamp = ISO8601DateFormatter().date(from: point.begins_at),
                  let price = Double(point.close_price) else { return nil }
            return PriceDataPoint(timestamp: timestamp, price: price)
        } ?? []
        
        print("📈 [RobinhoodHistoricalDataService] Parsed \(pricePoints.count) price points for \(symbol)")
        return pricePoints
    }
    
    /// Wait for rate limit using token bucket algorithm
    private func waitForRateLimit() async {
        let now = Date()
        let timeSinceLastRefill = now.timeIntervalSince(lastRefillTime)
        
        // Refill tokens based on time elapsed
        if timeSinceLastRefill >= refillInterval {
            let refillCycles = Int(timeSinceLastRefill / refillInterval)
            currentTokens = min(burstCapacity, currentTokens + (refillCycles * refillAmount))
            lastRefillTime = now
        }
        
        // If no tokens available, wait
        if currentTokens <= 0 {
            let waitTime = refillInterval
            print("⏳ [RobinhoodHistoricalDataService] Rate limit reached, waiting \(waitTime) seconds...")
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            
            // Refill after waiting
            currentTokens = min(burstCapacity, currentTokens + refillAmount)
            lastRefillTime = Date()
        }
        
        // Consume a token
        currentTokens -= 1
        print("🪙 [RobinhoodHistoricalDataService] Tokens remaining: \(currentTokens)/\(burstCapacity)")
    }
    
    /// Get database statistics for debugging
    func getDatabaseStats() async -> (totalRecords: Int, symbols: Int, oldestDate: Date?, newestDate: Date?) {
        return await dbManager.getDatabaseStats()
    }
}

// MARK: - Robinhood API Response Models

struct RobinhoodHistoricalResponse: Decodable {
    let data_points: [HistoricalDataPoint]?
}

struct HistoricalDataPoint: Decodable {
    let begins_at: String
    let open_price: String
    let close_price: String
    let high_price: String
    let low_price: String
    let volume: String
}
