import Foundation
import CryptoKit

// MARK: - Robinhood Crypto Client

final class RobinhoodCryptoClient: BrokerClient {
    struct Config {
        let baseURL: URL // e.g., https://trading.robinhood.com
        let apiKey: String // x-api-key
        let base64PrivateKeySeed: String // base64-encoded Ed25519 private key seed
        let base64PublicKey: String // base64-encoded Ed25519 public key
    }

    let config: Config
    private let urlSession: URLSession

    init(config: Config, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    // MARK: BrokerClient

    func fetchInstruments() async throws -> [Instrument] {
        print("📋 [RobinhoodCryptoClient] fetchInstruments() called")
        // Use trading pairs endpoint and map to Instrument
        let pairs = try await getTradingPairs(symbols: nil)
        print("📋 [RobinhoodCryptoClient] Got \(pairs.results.count) trading pairs")
        // Pairs response is not fully specified; map conservatively
        // Expecting objects with at least a symbol and display name; fallback to symbol
        let instruments: [Instrument] = pairs.results.compactMap { item in
            let symbol = item.symbol ?? item["symbol"] as? String
            let name = item.displayName ?? item["display_name"] as? String
            if let s = symbol {
                return Instrument(id: s, displayName: name ?? s)
            }
            return nil
        }
        let finalInstruments = instruments.isEmpty ? defaultInstruments : instruments
        print("📋 [RobinhoodCryptoClient] Returning \(finalInstruments.count) instruments")
        return finalInstruments
    }

    func placeOrder(_ request: OrderRequest) async throws -> OrderResponse {
        // Build Robinhood order body for market orders (current UI uses market)
        let clientOrderID = UUID().uuidString
        let body: [String: Any] = [
            "client_order_id": clientOrderID,
            "side": request.side == .buy ? "buy" : "sell",
            "type": request.type, // expect "market"
            "symbol": request.instrumentID,
            "market_order_config": [
                "asset_quantity": String(request.quantity)
            ]
        ]
        let path = "/api/v1/crypto/trading/orders/"
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let jsonString = String(data: data, encoding: .utf8) ?? "{}"
        let responseData = try await signedRequest(method: "POST", path: path, jsonBodyString: jsonString)
        // Decode minimal fields we need
        struct RHOrderResponse: Decodable { let id: String; let state: String; let average_price: Double?; let filled_asset_quantity: Double? }
        let decoded = try JSONDecoder().decode(RHOrderResponse.self, from: responseData)
        return OrderResponse(id: decoded.id, status: decoded.state, filledQuantity: decoded.filled_asset_quantity, avgFillPrice: decoded.average_price)
    }

    // MARK: - Public helpers (not in BrokerClient)

    struct PagedResults: Decodable { let results: [TradingPairItem] }
    struct TradingPairItem: Decodable {
        let symbol: String?
        let displayName: String?
        private enum CodingKeys: String, CodingKey { case symbol; case displayName = "display_name" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            symbol = try? c.decode(String.self, forKey: .symbol)
            displayName = try? c.decode(String.self, forKey: .displayName)
        }
        subscript(key: String) -> Any? { return nil }
    }

    struct BestBidAskResponse: Decodable { let results: [BestBidAskItem] }
    struct BestBidAskItem: Decodable { 
        let symbol: String?
        let bid_inclusive_of_sell_spread: String?
        let ask_inclusive_of_buy_spread: String?
        let timestamp: String?
    }

    struct AccountResponse: Decodable {
        let account_number: String
        let status: String
        let buying_power: String
        let buying_power_currency: String
    }

    struct HoldingsResponse: Decodable {
        struct Item: Decodable {
            let asset_code: String
            let total_quantity: String
        }
        let results: [Item]
    }

    struct EstimatedPriceResponse: Decodable {
        struct Item: Decodable { }
        let results: [Item]
    }
    

    func getBestBidAsk(symbols: [String]) async throws -> [Quote] {
        print("💰 [RobinhoodCryptoClient] getBestBidAsk() called for symbols: \(symbols)")
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/crypto/marketdata/best_bid_ask/"
        components.queryItems = symbols.map { URLQueryItem(name: "symbol", value: $0) }
        let pathWithQuery = components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        print("💰 [RobinhoodCryptoClient] Best bid/ask path: \(pathWithQuery)")
        let data = try await signedRequest(method: "GET", path: pathWithQuery, jsonBodyString: nil)
        let decoded = try JSONDecoder().decode(BestBidAskResponse.self, from: data)
        print("💰 [RobinhoodCryptoClient] Decoded \(decoded.results.count) bid/ask results")
        let dateFormatter = ISO8601DateFormatter()
        let quotes: [Quote] = decoded.results.compactMap { item in
            guard let sym = item.symbol else { return nil }
            let bid = item.bid_inclusive_of_sell_spread.flatMap(Double.init)
            let ask = item.ask_inclusive_of_buy_spread.flatMap(Double.init)
            let price: Double
            if let b = bid, let a = ask { price = (a + b) / 2.0 }
            else if let a = ask { price = a }
            else if let b = bid { price = b }
            else { return nil }
            let time = item.timestamp.flatMap { dateFormatter.date(from: $0) } ?? Date()
            return Quote(id: sym, price: price, bid: bid, ask: ask, time: time)
        }
        print("💰 [RobinhoodCryptoClient] Returning \(quotes.count) quotes")
        return quotes
    }

    struct TradingPairsResponse: Decodable { let results: [TradingPairItem]; let next: String?; let previous: String? }

    func getTradingPairs(symbols: [String]?) async throws -> TradingPairsResponse {
        print("🔗 [RobinhoodCryptoClient] getTradingPairs() called for symbols: \(symbols ?? [])")
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/crypto/trading/trading_pairs/"
        if let symbols, !symbols.isEmpty {
            components.queryItems = symbols.map { URLQueryItem(name: "symbol", value: $0) }
        }
        let pathWithQuery = components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        print("🔗 [RobinhoodCryptoClient] Trading pairs path: \(pathWithQuery)")
        let data = try await signedRequest(method: "GET", path: pathWithQuery, jsonBodyString: nil)
        let decoded = try JSONDecoder().decode(TradingPairsResponse.self, from: data)
        print("🔗 [RobinhoodCryptoClient] Decoded \(decoded.results.count) trading pairs")
        return decoded
    }

    func getAccount() async throws -> AccountResponse {
        print("👤 [RobinhoodCryptoClient] getAccount() called")
        let path = "/api/v1/crypto/trading/accounts/"
        let data = try await signedRequest(method: "GET", path: path, jsonBodyString: nil)
        let account = try JSONDecoder().decode(AccountResponse.self, from: data)
        print("👤 [RobinhoodCryptoClient] Account retrieved: \(account.account_number)")
        return account
    }

    func getHoldings(assetCodes: [String]? = nil) async throws -> HoldingsResponse {
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/crypto/trading/holdings/"
        if let assetCodes, !assetCodes.isEmpty {
            components.queryItems = assetCodes.map { URLQueryItem(name: "asset_code", value: $0) }
        }
        let pathWithQuery = components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        let data = try await signedRequest(method: "GET", path: pathWithQuery, jsonBodyString: nil)
        return try JSONDecoder().decode(HoldingsResponse.self, from: data)
    }

    func getEstimatedPrice(symbol: String, side: String, quantity: String) async throws -> Data {
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/crypto/marketdata/estimated_price/"
        components.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "side", value: side),
            URLQueryItem(name: "quantity", value: quantity)
        ]
        let pathWithQuery = components.path + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        return try await signedRequest(method: "GET", path: pathWithQuery, jsonBodyString: nil)
    }
    

    func placeAdvancedOrder(symbol: String, side: String, type: String, market: [String: String]?, limit: [String: Any]?, stopLoss: [String: Any]?, stopLimit: [String: Any]?) async throws -> OrderResponse {
        var body: [String: Any] = [
            "client_order_id": UUID().uuidString,
            "side": side,
            "type": type,
            "symbol": symbol
        ]
        if let market { body["market_order_config"] = market }
        if let limit { body["limit_order_config"] = limit }
        if let stopLoss { body["stop_loss_order_config"] = stopLoss }
        if let stopLimit { body["stop_limit_order_config"] = stopLimit }
        let path = "/api/v1/crypto/trading/orders/"
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let jsonString = String(data: data, encoding: .utf8) ?? "{}"
        let respData = try await signedRequest(method: "POST", path: path, jsonBodyString: jsonString)
        struct RHOrderResponse: Decodable { let id: String; let state: String; let average_price: Double?; let filled_asset_quantity: Double? }
        let decoded = try JSONDecoder().decode(RHOrderResponse.self, from: respData)
        return OrderResponse(id: decoded.id, status: decoded.state, filledQuantity: decoded.filled_asset_quantity, avgFillPrice: decoded.average_price)
    }

    // MARK: - Signing + Networking

    func signedRequest(method: String, path: String, jsonBodyString: String?) async throws -> Data {
        print("🔗 [RobinhoodCryptoClient] Starting signed request")
        print("   Method: \(method)")
        print("   Path: \(path)")
        print("   Base URL: \(config.baseURL)")
        print("   API Key: \(config.apiKey.prefix(20))...")
        print("   Private Key: \(config.base64PrivateKeySeed.prefix(20))...")
        print("   Public Key: \(config.base64PublicKey.prefix(20))...")
        
        // Build URL
        guard let url = URL(string: path, relativeTo: config.baseURL) else { 
            print("❌ [RobinhoodCryptoClient] Failed to build URL from path: \(path)")
            throw BrokerError.invalidRequest("Bad path: \(path)") 
        }
        print("   Full URL: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        // Body
        if let bodyString = jsonBodyString, method == "POST" {
            request.httpBody = bodyString.data(using: .utf8)
            print("   Request Body: \(bodyString)")
        } else {
            print("   Request Body: (none)")
        }

        // Timestamp in seconds
        let timestamp = Int(Date().timeIntervalSince1970)
        print("   Timestamp: \(timestamp)")
        
        // Per docs, message = apiKey + timestamp + path + method + body (omit body if none)
        let message = config.apiKey + String(timestamp) + path + method + (jsonBodyString ?? "")
        print("   Message to sign: \(message)")

        // Sign using Ed25519 with private key seed (base64)
        guard let seedData = Data(base64Encoded: config.base64PrivateKeySeed) else {
            print("❌ [RobinhoodCryptoClient] Invalid base64 private key seed")
            throw BrokerError.invalidRequest("Invalid base64 private key seed")
        }
        print("   Private key seed data length: \(seedData.count) bytes")
        
        // CryptoKit requires full private key; derive from seed using Curve25519.Signing.PrivateKey? CryptoKit doesn't directly expose Ed25519 seed init.
        // We'll build key using libsodium-compatible 32-byte seed if provided; otherwise, fallback to generating and throw.
        let privateKey: Curve25519.Signing.PrivateKey
        if seedData.count == 32 {
            // Initialize with seed by deterministic derivation
            print("   Using 32-byte seed for private key")
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seedData)
        } else if seedData.count == 64 {
            // If a 64-byte secret key is supplied, use first 32 bytes as seed
            print("   Using first 32 bytes of 64-byte seed for private key")
            let seed = seedData.prefix(32)
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        } else {
            print("❌ [RobinhoodCryptoClient] Private key must be 32 or 64 bytes when base64-decoded, got \(seedData.count)")
            throw BrokerError.invalidRequest("Private key must be 32 or 64 bytes when base64-decoded")
        }

        let signature = try privateKey.signature(for: Data(message.utf8))
        let signatureBase64 = signature.base64EncodedString()
        print("   Generated signature: \(signatureBase64.prefix(20))...")

        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(String(timestamp), forHTTPHeaderField: "x-timestamp")
        request.setValue(signatureBase64, forHTTPHeaderField: "x-signature")
        
        print("   Request headers:")
        print("     x-api-key: \(config.apiKey)")
        print("     x-timestamp: \(timestamp)")
        print("     x-signature: \(signatureBase64.prefix(20))...")
        print("     Content-Type: application/json; charset=utf-8")

        print("🚀 [RobinhoodCryptoClient] Making network request...")
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            if let http = response as? HTTPURLResponse {
                print("📡 [RobinhoodCryptoClient] Response received:")
                print("   Status Code: \(http.statusCode)")
                print("   Response Headers: \(http.allHeaderFields)")
                print("   Response Data Length: \(data.count) bytes")
                
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Response Body: \(responseString)")
                }
                
                if !(200...299).contains(http.statusCode) {
                    // Try to surface server error payload
                    let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    print("❌ [RobinhoodCryptoClient] HTTP Error \(http.statusCode): \(message)")
                    
                    // Parse Robinhood error format: {"type":"client_error","errors":[{"detail":"...","attr":null}]}
                    var userFriendlyMessage = message
                    if let jsonData = message.data(using: .utf8),
                       let errorObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let errors = errorObj["errors"] as? [[String: Any]],
                       let firstError = errors.first,
                       let detail = firstError["detail"] as? String {
                        userFriendlyMessage = detail
                        print("📝 [RobinhoodCryptoClient] Parsed error detail: \(detail)")
                    }
                    
                    if http.statusCode == 401 { 
                        print("❌ [RobinhoodCryptoClient] Unauthorized - check API key and signature")
                        throw BrokerError.unauthorized 
                    }
                    if http.statusCode == 429 { 
                        print("❌ [RobinhoodCryptoClient] Rate limited")
                        throw BrokerError.network("Rate limited: \(userFriendlyMessage)") 
                    }
                    throw BrokerError.network(userFriendlyMessage)
                }
            } else {
                print("❌ [RobinhoodCryptoClient] Invalid response type")
            }
            
            print("✅ [RobinhoodCryptoClient] Request completed successfully")
            return data
        } catch let error as URLError {
            print("🌐 [RobinhoodCryptoClient] Network Error:")
            print("   Code: \(error.code.rawValue)")
            print("   Description: \(error.localizedDescription)")
            print("   User Info: \(error.userInfo)")
            
            switch error.code {
            case .cannotFindHost:
                print("❌ [RobinhoodCryptoClient] Cannot find host - check base URL: \(config.baseURL)")
            case .cannotConnectToHost:
                print("❌ [RobinhoodCryptoClient] Cannot connect to host - check network connectivity")
            case .timedOut:
                print("❌ [RobinhoodCryptoClient] Request timed out")
            case .notConnectedToInternet:
                print("❌ [RobinhoodCryptoClient] Not connected to internet")
            default:
                print("❌ [RobinhoodCryptoClient] Other network error: \(error)")
            }
            throw BrokerError.network(error.localizedDescription)
        } catch {
            print("❌ [RobinhoodCryptoClient] Unexpected error: \(error)")
            throw BrokerError.network("Unexpected error: \(error.localizedDescription)")
        }
    }

    private var defaultInstruments: [Instrument] {
        [
            Instrument(id: "BTC-USD", displayName: "Bitcoin"),
            Instrument(id: "ETH-USD", displayName: "Ethereum"),
            Instrument(id: "SOL-USD", displayName: "Solana"),
        ]
    }
}

// MARK: - Simulator Quote Stream (unchanged)

final class SimulatorQuoteStream: QuoteStream {
    private var continuation: AsyncStream<Quote>.Continuation?
    private var timer: Timer?
    private var symbols: [String] = []
    private var lastPrices: [String: Double] = [:]

    var quotes: AsyncStream<Quote> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func connect(symbols: [String]) async throws {
        self.symbols = symbols
        for s in symbols { lastPrices[s] = seed(for: s) }
        startTicking()
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
        continuation?.finish()
        continuation = nil
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            for s in symbols {
                let new = nextPrice(for: s)
                let q = Quote(id: s, price: new, bid: new - 0.5, ask: new + 0.5, time: Date())
                continuation?.yield(q)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func seed(for symbol: String) -> Double {
        switch symbol {
        case "BTC-USD": return 65000
        case "ETH-USD": return 3200
        case "SOL-USD": return 150
        default: return 1000
        }
    }

    private func nextPrice(for symbol: String) -> Double {
        let base = lastPrices[symbol] ?? seed(for: symbol)
        let delta = Double.random(in: -50...50)
        let next = max(0.0001, base + delta)
        lastPrices[symbol] = next
        return next
    }
}

