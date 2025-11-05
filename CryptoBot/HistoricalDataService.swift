import Foundation

/// Service for fetching historical cryptocurrency data from free APIs and managing local database
class HistoricalDataService {
    static let shared = HistoricalDataService()
    
    private let dbManager = HistoricalDatabaseManager.shared
    private let maxDaysPerRequest = 365 // CoinGecko API limit for free tier (1 year)
    private let maxHistoricalDays = 365 // Maximum historical data to fetch
    
    private init() {}
    
    /// Perform full historical data pull for all symbols on app startup
    func performFullDataPull(symbols: [String]) async {
        print("🚀 [HistoricalDataService] Starting full historical data pull for \(symbols.count) symbols")
        
        let startTime = Date()
        
        for symbol in symbols {
            do {
                print("📈 [HistoricalDataService] Processing \(symbol)...")
                
                // Check if we have any data for this symbol
                let latestTimestamp = await dbManager.getLatestTimestamp(for: symbol)
                
                if let latestTimestamp = latestTimestamp {
                    print("📈 [HistoricalDataService] \(symbol) has data up to \(latestTimestamp)")
                    // Update with recent data (last 30 days to catch any gaps)
                    try await fetchAndStoreRecentData(symbol: symbol, days: 30)
                } else {
                    print("📈 [HistoricalDataService] \(symbol) has no data, fetching full history")
                    // Full historical pull (max 90 days per request)
                    try await fetchAndStoreFullHistory(symbol: symbol)
                }
                
                // Longer delay to avoid rate limiting (CoinGecko free tier: 10-50 calls/minute)
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
            } catch {
                print("❌ [HistoricalDataService] Failed to process \(symbol): \(error)")
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        print("✅ [HistoricalDataService] Full data pull completed in \(String(format: "%.2f", duration)) seconds")
        
        // Print database statistics
        let stats = await dbManager.getDatabaseStats()
        print("📊 [HistoricalDataService] Database stats: \(stats.totalRecords) records, \(stats.symbols) symbols")
        if let oldest = stats.oldestDate, let newest = stats.newestDate {
            print("📊 [HistoricalDataService] Date range: \(oldest) to \(newest)")
        }
    }
    
    /// Fetch historical data for display (from local database first, then API if needed)
    func fetchHistoricalData(symbol: String, days: Int = 1) async throws -> [PriceDataPoint] {
        print("📈 [HistoricalDataService] Fetching historical data for \(symbol) (\(days) days)")
        
        // Try to get data from local database first
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        
        let localData = await dbManager.getPriceData(symbol: symbol, from: startDate, to: endDate)
        
        if !localData.isEmpty {
            print("📈 [HistoricalDataService] Found \(localData.count) local data points for \(symbol)")
            return localData
        }
        
        // If no local data, fetch from API
        print("📈 [HistoricalDataService] No local data found, fetching from API for \(symbol)")
        
        // For 1-day requests, fetch 2 days to get hourly data, then filter
        let fetchDays = max(days, 2)
        let apiData = try await fetchFromCoinGecko(symbol: symbol, days: fetchDays)
        
        // Filter to only the data we need
        let filteredData = apiData.filter { $0.timestamp >= startDate }
        
        // Store the fetched data
        await dbManager.storePriceData(symbol: symbol, dataPoints: filteredData)
        
        return filteredData
    }
    
    /// Fetch and store recent data (for incremental updates)
    private func fetchAndStoreRecentData(symbol: String, days: Int) async throws {
        // For recent data, fetch 2 days to get hourly data, then filter to what we need
        let fetchDays = max(days, 2) // CoinGecko requires at least 2 days for hourly data
        let dataPoints = try await fetchFromCoinGecko(symbol: symbol, days: fetchDays)
        
        // Filter to only the most recent data we need
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let filteredPoints = dataPoints.filter { $0.timestamp >= cutoffDate }
        
        await dbManager.storePriceData(symbol: symbol, dataPoints: filteredPoints)
        print("📈 [HistoricalDataService] Stored \(filteredPoints.count) recent data points for \(symbol) (filtered from \(dataPoints.count))")
    }
    
    /// Fetch and store full historical data
    private func fetchAndStoreFullHistory(symbol: String) async throws {
        print("📈 [HistoricalDataService] Fetching MAXIMUM historical data for \(symbol) (365 days)")
        
        // Fetch maximum allowed data (365 days is CoinGecko free tier limit)
        let dataPoints = try await fetchFromCoinGecko(symbol: symbol, days: maxHistoricalDays)
        await dbManager.storePriceData(symbol: symbol, dataPoints: dataPoints)
        print("📈 [HistoricalDataService] Stored \(dataPoints.count) historical data points for \(symbol)")
        
        // Store metadata about the data range
        if let firstPoint = dataPoints.first, let lastPoint = dataPoints.last {
            let dateRange = "\(firstPoint.timestamp) to \(lastPoint.timestamp)"
            print("📈 [HistoricalDataService] Data range for \(symbol): \(dateRange)")
        }
    }
    
    
    /// Fetch data from CoinGecko API with retry logic
    private func fetchFromCoinGecko(symbol: String, days: Int) async throws -> [PriceDataPoint] {
        let coinId = convertSymbolToCoinGeckoId(symbol)
        
        let urlString = "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart"
        guard let url = URL(string: urlString) else {
            throw HistoricalDataError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "days", value: "\(days)")
            // Note: Don't specify interval parameter - CoinGecko automatically provides hourly for 2-90 days
        ]
        
        guard let finalURL = components.url else {
            throw HistoricalDataError.invalidURL
        }
        
        print("📈 [HistoricalDataService] Requesting: \(finalURL)")
        
        // Retry logic for rate limiting
        var retryCount = 0
        let maxRetries = 3
        
        while retryCount < maxRetries {
            let (data, response) = try await URLSession.shared.data(from: finalURL)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HistoricalDataError.invalidResponse
            }
            
            print("📈 [HistoricalDataService] Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let coinGeckoResponse = try JSONDecoder().decode(CoinGeckoResponse.self, from: data)
                
                let pricePoints = coinGeckoResponse.prices.compactMap { priceData -> PriceDataPoint? in
                    guard priceData.count >= 2 else { return nil }
                    let timestamp = Date(timeIntervalSince1970: priceData[0] / 1000) // Convert from milliseconds
                    let price = priceData[1]
                    return PriceDataPoint(timestamp: timestamp, price: price)
                }
                
                print("📈 [HistoricalDataService] Parsed \(pricePoints.count) price points for \(symbol)")
                return pricePoints
            } else if httpResponse.statusCode == 429 {
                retryCount += 1
                if retryCount < maxRetries {
                    let waitTime = min(10 * retryCount, 30) // Exponential backoff, max 30 seconds
                    print("📈 [HistoricalDataService] Rate limit hit, waiting \(waitTime) seconds (attempt \(retryCount)/\(maxRetries))...")
                    try await Task.sleep(nanoseconds: UInt64(waitTime) * 1_000_000_000)
                    continue
                } else {
                    throw HistoricalDataError.rateLimited
                }
            } else {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📈 [HistoricalDataService] Error response: \(responseString)")
                }
                throw HistoricalDataError.apiError(httpResponse.statusCode)
            }
        }
        
        throw HistoricalDataError.rateLimited
    }
    
    /// Convert trading symbol to CoinGecko coin ID
    private func convertSymbolToCoinGeckoId(_ symbol: String) -> String {
        let symbolMap: [String: String] = [
            "BTC-USD": "bitcoin",
            "ETH-USD": "ethereum",
            "SUI-USD": "sui",
            "WLFI-USD": "walletfi",
            "MOODENG-USD": "moodeng",
            "PNUT-USD": "peanut-the-squirrel",
            "MEW-USD": "cat-in-a-dogs-world"
        ]
        
        return symbolMap[symbol] ?? symbol.lowercased().replacingOccurrences(of: "-usd", with: "")
    }
    
    /// Get database statistics for debugging
    func getDatabaseStats() async -> (totalRecords: Int, symbols: Int, oldestDate: Date?, newestDate: Date?) {
        return await dbManager.getDatabaseStats()
    }
    
    /// Build comprehensive historical database over time
    /// This method will be called periodically to extend historical data
    func extendHistoricalData(symbols: [String]) async {
        print("🔄 [HistoricalDataService] Extending historical data for \(symbols.count) symbols")
        
        for symbol in symbols {
            do {
                // Check what data we already have
                let existingData = await dbManager.getPriceData(symbol: symbol)
                let oldestDate = existingData.first?.timestamp
                
                if let oldestDate = oldestDate {
                    // Calculate how many days back we can go from our oldest data
                    let daysSinceOldest = Calendar.current.dateComponents([.day], from: oldestDate, to: Date()).day ?? 0
                    
                    if daysSinceOldest > 365 {
                        print("📈 [HistoricalDataService] \(symbol) has data going back \(daysSinceOldest) days, extending...")
                        
                        // Fetch another 365 days of data
                        let newData = try await fetchFromCoinGecko(symbol: symbol, days: 365)
                        
                        // Filter out data we already have (avoid duplicates)
                        let existingTimestamps = Set(existingData.map { Int64($0.timestamp.timeIntervalSince1970) })
                        let uniqueNewData = newData.filter { point in
                            let timestamp = Int64(point.timestamp.timeIntervalSince1970)
                            return !existingTimestamps.contains(timestamp)
                        }
                        
                        if !uniqueNewData.isEmpty {
                            await dbManager.storePriceData(symbol: symbol, dataPoints: uniqueNewData)
                            print("📈 [HistoricalDataService] Extended \(symbol) with \(uniqueNewData.count) new data points")
                        }
                    } else {
                        print("📈 [HistoricalDataService] \(symbol) already has comprehensive data (\(daysSinceOldest) days)")
                    }
                }
                
                // Rate limiting delay
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
            } catch {
                print("❌ [HistoricalDataService] Failed to extend data for \(symbol): \(error)")
            }
        }
        
        print("✅ [HistoricalDataService] Historical data extension completed")
    }
}

enum HistoricalDataError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int)
    case rateLimited
    case noData
    case brokerNotInitialized
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .apiError(let code):
            return "API error with status code: \(code)"
        case .rateLimited:
            return "Rate limit exceeded, please try again later"
        case .noData:
            return "No data available"
        case .brokerNotInitialized:
            return "Broker not initialized"
        }
    }
}

struct CoinGeckoResponse: Decodable {
    let prices: [[Double]]
    let marketCaps: [[Double]]
    let totalVolumes: [[Double]]
    
    enum CodingKeys: String, CodingKey {
        case prices
        case marketCaps = "market_caps"
        case totalVolumes = "total_volumes"
    }
}
