import Foundation

// MARK: - OpenAI API Client

final class OpenAIClient {
    private let apiKey: String
    private let urlSession: URLSession

    init(apiKey: String, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let max_tokens: Int?
        let temperature: Double?
    }

    struct ChatResponse: Codable {
        let choices: [Choice]

        struct Choice: Codable {
            let message: ChatMessage
        }
    }

    func sendChatRequest(model: String = "gpt-4", messages: [ChatMessage], maxTokens: Int? = 1000, temperature: Double? = 0.7) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let chatRequest = ChatRequest(
            model: model,
            messages: messages,
            max_tokens: maxTokens,
            temperature: temperature
        )

        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAIClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from OpenAI API"])
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }
}

// MARK: - Short Selling AI Strategy

struct ShortSellingAnalysis {
    let symbol: String
    let currentPrice: Double
    let historicalData: [PriceDataPoint]
    let recommendation: String
    let confidence: Double
    let reasoning: String
    let suggestedAction: String
    let quantity: Double
}

final class ShortSellingAIStrategy {
    private let openAIClient: OpenAIClient
    private let historicalDB: HistoricalDatabaseManager

    init(apiKey: String) {
        self.openAIClient = OpenAIClient(apiKey: apiKey)
        self.historicalDB = HistoricalDatabaseManager.shared
    }

    func analyzeForShortSelling(symbol: String, currentPrice: Double, buyingPower: Double, portfolioValue: Double) async throws -> ShortSellingAnalysis {
        // Get historical data for the symbol
        let historicalData = await historicalDB.getPriceData(symbol: symbol)

        guard !historicalData.isEmpty else {
            throw NSError(domain: "ShortSellingAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "No historical data available for \(symbol)"])
        }

        // Calculate technical indicators
        let indicators = calculateTechnicalIndicators(historicalData: historicalData)
        let context = buildAnalysisContext(symbol: symbol, currentPrice: currentPrice, indicators: indicators, buyingPower: buyingPower, portfolioValue: portfolioValue)

        // Create AI prompt for short selling analysis
        let prompt = createShortSellingPrompt(context: context)

        let messages = [
            OpenAIClient.ChatMessage(role: "system", content: "You are an expert cryptocurrency trader specializing in short selling strategies. Analyze the provided data and recommend whether to short sell this cryptocurrency. Consider technical indicators, market trends, and risk management."),
            OpenAIClient.ChatMessage(role: "user", content: prompt)
        ]

        let response = try await openAIClient.sendChatRequest(messages: messages, maxTokens: 1500, temperature: 0.3)

        return parseAIResponse(response: response, symbol: symbol, currentPrice: currentPrice, buyingPower: buyingPower, historicalData: historicalData)
    }

    private func calculateTechnicalIndicators(historicalData: [PriceDataPoint]) -> TechnicalIndicators {
        let prices = historicalData.map { $0.price }

        // Simple Moving Averages
        let sma20 = calculateSMA(prices: prices, period: 20)
        let sma50 = calculateSMA(prices: prices, period: 50)

        // RSI (Relative Strength Index)
        let rsi = calculateRSI(prices: prices, period: 14)

        // MACD
        let macd = calculateMACD(prices: prices)

        // Price volatility
        let volatility = calculateVolatility(prices: prices)

        // Trend analysis
        let trend = analyzeTrend(prices: prices)

        return TechnicalIndicators(
            sma20: sma20,
            sma50: sma50,
            rsi: rsi,
            macd: macd,
            volatility: volatility,
            trend: trend,
            currentPrice: prices.last ?? 0,
            priceChange24h: calculatePriceChange24h(prices: prices),
            volume: 0 // Would need volume data for this
        )
    }

    private func calculateSMA(prices: [Double], period: Int) -> Double {
        guard prices.count >= period else { return prices.last ?? 0 }
        let recentPrices = Array(prices.suffix(period))
        return recentPrices.reduce(0, +) / Double(period)
    }

    private func calculateRSI(prices: [Double], period: Int) -> Double {
        guard prices.count > period + 1 else { return 50 }

        var gains: [Double] = []
        var losses: [Double] = []

        for i in 1..<prices.count {
            let change = prices[i] - prices[i-1]
            if change > 0 {
                gains.append(change)
                losses.append(0)
            } else {
                gains.append(0)
                losses.append(abs(change))
            }
        }

        let avgGain = gains.suffix(period).reduce(0, +) / Double(period)
        let avgLoss = losses.suffix(period).reduce(0, +) / Double(period)

        if avgLoss == 0 { return 100 }

        let rs = avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }

    private func calculateMACD(prices: [Double]) -> (macd: Double, signal: Double, histogram: Double) {
        let ema12 = calculateEMA(prices: prices, period: 12)
        let ema26 = calculateEMA(prices: prices, period: 26)
        let macdLine = ema12 - ema26

        let signalLine = calculateEMA(values: (0..<prices.count).map { _ in macdLine }, period: 9)
        let histogram = macdLine - signalLine

        return (macd: macdLine, signal: signalLine, histogram: histogram)
    }

    private func calculateEMA(prices: [Double], period: Int) -> Double {
        guard !prices.isEmpty else { return 0 }

        let multiplier = 2.0 / (Double(period) + 1.0)
        var ema = prices[0]

        for i in 1..<prices.count {
            ema = (prices[i] * multiplier) + (ema * (1 - multiplier))
        }

        return ema
    }

    private func calculateEMA(values: [Double], period: Int) -> Double {
        guard !values.isEmpty else { return 0 }

        let multiplier = 2.0 / (Double(period) + 1.0)
        var ema = values[0]

        for i in 1..<values.count {
            ema = (values[i] * multiplier) + (ema * (1 - multiplier))
        }

        return ema
    }

    private func calculateVolatility(prices: [Double]) -> Double {
        guard prices.count > 1 else { return 0 }

        var returns: [Double] = []
        for i in 1..<prices.count {
            returns.append((prices[i] - prices[i-1]) / prices[i-1])
        }

        let mean = returns.reduce(0, +) / Double(returns.count)

        var variance: Double = 0
        for returnValue in returns {
            variance += pow(returnValue - mean, 2)
        }
        variance /= Double(returns.count)

        return sqrt(variance)
    }

    private func analyzeTrend(prices: [Double]) -> String {
        guard prices.count >= 20 else { return "insufficient_data" }

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

    private func calculatePriceChange24h(prices: [Double]) -> Double {
        guard prices.count >= 2 else { return 0 }
        return (prices.last! - prices.first!) / prices.first!
    }

    private func buildAnalysisContext(symbol: String, currentPrice: Double, indicators: TechnicalIndicators, buyingPower: Double, portfolioValue: Double) -> String {
        return """
        CRYPTOCURRENCY: \(symbol)
        CURRENT PRICE: $\(String(format: "%.2f", currentPrice))

        TECHNICAL INDICATORS:
        - 20-day SMA: $\(String(format: "%.2f", indicators.sma20))
        - 50-day SMA: $\(String(format: "%.2f", indicators.sma50))
        - RSI (14): \(String(format: "%.1f", indicators.rsi))
        - MACD: \(String(format: "%.4f", indicators.macd.macd))
        - Trend: \(indicators.trend)
        - Volatility: \(String(format: "%.4f", indicators.volatility))
        - 24h Change: \(String(format: "%.2f", indicators.priceChange24h * 100))%

        PORTFOLIO CONTEXT:
        - Buying Power: $\(String(format: "%.2f", buyingPower))
        - Portfolio Value: $\(String(format: "%.2f", portfolioValue))

        SHORT SELLING ANALYSIS REQUEST:
        Based on this cryptocurrency's historical price data and current market conditions, should we initiate a short position?
        Consider: trend direction, overbought/oversold conditions, volatility, and risk management.

        Provide your recommendation in this format:
        RECOMMENDATION: [BUY|SSELL|HOLD]
        CONFIDENCE: [0-100%]
        REASONING: [Brief explanation]
        SUGGESTED_ACTION: [Description of trade]
        QUANTITY: [Number of shares to short, considering buying power]
        """
    }

    private func createShortSellingPrompt(context: String) -> String {
        return """
        You are analyzing cryptocurrency \(context)

        As a short selling specialist, evaluate if this is a good candidate for short selling:

        1. **Trend Analysis**: Is the price in an uptrend that might reverse?
        2. **Overbought Conditions**: RSI above 70 suggests overbought
        3. **Technical Patterns**: Look for bearish patterns or divergences
        4. **Volatility**: Higher volatility increases short selling opportunities but also risk
        5. **Risk Management**: Ensure position size doesn't exceed 5% of portfolio

        **Important**: Only recommend short selling if there's strong evidence of a price decline. Be conservative with confidence levels.

        Provide your analysis in the specified format.
        """
    }

    private func parseAIResponse(response: String, symbol: String, currentPrice: Double, buyingPower: Double, historicalData: [PriceDataPoint]) -> ShortSellingAnalysis {
        // Parse the AI response to extract recommendation, confidence, reasoning, etc.
        let lines = response.components(separatedBy: .newlines)

        var recommendation = "HOLD"
        var confidence = 50.0
        var reasoning = "Unable to parse AI response"
        var suggestedAction = "No action recommended"
        var quantity = 0.0

        for line in lines {
            if line.contains("RECOMMENDATION:") {
                recommendation = line.components(separatedBy: "RECOMMENDATION:")[1].trimmingCharacters(in: .whitespaces)
            } else if line.contains("CONFIDENCE:") {
                let confidenceStr = line.components(separatedBy: "CONFIDENCE:")[1].trimmingCharacters(in: .whitespaces)
                confidence = Double(confidenceStr.replacingOccurrences(of: "%", with: "")) ?? 50.0
            } else if line.contains("REASONING:") {
                reasoning = line.components(separatedBy: "REASONING:")[1].trimmingCharacters(in: .whitespaces)
            } else if line.contains("SUGGESTED_ACTION:") {
                suggestedAction = line.components(separatedBy: "SUGGESTED_ACTION:")[1].trimmingCharacters(in: .whitespaces)
            } else if line.contains("QUANTITY:") {
                let quantityStr = line.components(separatedBy: "QUANTITY:")[1].trimmingCharacters(in: .whitespaces)
                quantity = Double(quantityStr) ?? 0.0
            }
        }

        // Calculate safe quantity based on buying power (assuming 5% max allocation for short positions)
        if recommendation == "SELL" && quantity == 0.0 {
            let maxPositionValue = buyingPower * 0.05 // 5% of buying power for short positions
            quantity = maxPositionValue / currentPrice
        }

        return ShortSellingAnalysis(
            symbol: symbol,
            currentPrice: currentPrice,
            historicalData: historicalData,
            recommendation: recommendation,
            confidence: confidence,
            reasoning: reasoning,
            suggestedAction: suggestedAction,
            quantity: quantity
        )
    }
}

struct TechnicalIndicators {
    let sma20: Double
    let sma50: Double
    let rsi: Double
    let macd: (macd: Double, signal: Double, histogram: Double)
    let volatility: Double
    let trend: String
    let currentPrice: Double
    let priceChange24h: Double
    let volume: Double
}
