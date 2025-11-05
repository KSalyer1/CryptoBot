import Foundation
import Observation

@Observable
final class ApplicationState {
    // Credentials and config (populate from Settings later)
    var apiKey: String
    var base64PrivateKeySeed: String
    var base64PublicKey: String
    var baseURL: URL

    // Shared clients
    private(set) var broker: RobinhoodCryptoClient
    let ingestionSettings: IngestionSettings
    private(set) var ingestionClient: MySQLIngestionClient
    let safety: TradingSafetySettings

    // Shared poller & execution
    private(set) var quotePoller: QuotePoller
    private(set) var executionManager: ExecutionManager!
    private var baselineSubscription: UUID?

    // Shared caches
    var account: AccountSummary? = nil
    var holdings: [HoldingItem] = [] {
        didSet { ensureBaselineSubscription() }
    }
    var quotes: [String: Quote] = [:] // symbol -> Quote
    var watchlist: Set<String> = ["BTC-USD", "ETH-USD", "SOL-USD"] {
        didSet { ensureBaselineSubscription() }
    }

    var baselinePortfolioValue: Double? = nil

    func updatePortfolioDerivedValues() {
        // Compute total portfolio value using mid prices
        let symbolMap = holdingsToSymbols()
        var total: Double = 0
        for h in holdings {
            let sym = symbolMap[h.asset_code] ?? "\(h.asset_code)-USD"
            let qty = Double(h.quantity) ?? 0
            if let q = quotes[sym] { total += qty * q.price }
        }
        if baselinePortfolioValue == nil { baselinePortfolioValue = total }
        // store total in account_number field? better to add a derived property via computed var
        _cachedPortfolioValue = total
    }

    private var _cachedPortfolioValue: Double = 0
    var portfolioValue: Double { _cachedPortfolioValue }
    var portfolioDelta: Double { guard let base = baselinePortfolioValue else { return 0 }; return portfolioValue - base }
    var portfolioDeltaPct: Double { guard let base = baselinePortfolioValue, base != 0 else { return 0 }; return portfolioDelta / base }

    func holdingsToSymbols() -> [String: String] {
        // Map asset_code (e.g., BTC) to USD symbol (BTC-USD) using trading pairs if available later
        var map: [String: String] = [:]
        for code in Set(holdings.map { $0.asset_code }) {
            map[code] = "\(code)-USD"
        }
        return map
    }

    // Derived convenience
    var heldAssets: [String] {
        let codes = Set(holdings.map { $0.asset_code })
        return Array(codes).sorted()
    }
    init(
        apiKey: String = "rh-api-5be221df-4e1c-4037-92b1-1f22de7d1d22",
        base64PrivateKeySeed: String = "c70+45/bpWUFhbkKoVYYnvaQRF3q7m5Jqpo3znnzOd4=",
        base64PublicKey: String = "ano4h1q25nyYmMEHFOOIU+KtcatvncDQnRW/gRtrCe0=",
        baseURL: URL = URL(string: "https://trading.robinhood.com")!
    ) {
        print("🏗️ [ApplicationState] Initializing with credentials:")
        print("   API Key: \(apiKey.prefix(20))...")
        print("   Private Key: \(base64PrivateKeySeed.prefix(20))...")
        print("   Public Key: \(base64PublicKey.prefix(20))...")
        print("   Base URL: \(baseURL)")
        
        self.apiKey = apiKey
        self.base64PrivateKeySeed = base64PrivateKeySeed
        self.base64PublicKey = base64PublicKey
        self.baseURL = baseURL
        self.ingestionSettings = IngestionSettings()
        self.safety = TradingSafetySettings()
        let broker = RobinhoodCryptoClient(config: .init(baseURL: baseURL, apiKey: apiKey, base64PrivateKeySeed: base64PrivateKeySeed, base64PublicKey: base64PublicKey))
        self.broker = broker
        let ingestionClient = MySQLIngestionClient(settings: ingestionSettings)
        self.ingestionClient = ingestionClient
        self.quotePoller = QuotePoller(broker: broker, ingestion: ingestionClient)
        self.executionManager = ExecutionManager(broker: broker, safety: safety, state: self)
        self.baselineSubscription = quotePoller.subscribe(currentBaselineSymbols())
        print("🏗️ [ApplicationState] Initialization complete")
        
                // Historical data will be built automatically by QuotePoller logging
    }


    func refreshBroker(apiKey: String? = nil, base64Seed: String? = nil, base64PublicKey: String? = nil, baseURL: URL? = nil) {
        print("🔄 [ApplicationState] refreshBroker() called")
        let newAPIKey = apiKey ?? self.apiKey
        let newSeed = base64Seed ?? self.base64PrivateKeySeed
        let newPublicKey = base64PublicKey ?? self.base64PublicKey
        let newURL = baseURL ?? self.baseURL

        print("🔄 [ApplicationState] New credentials:")
        print("   API Key: \(newAPIKey.prefix(20))...")
        print("   Private Key: \(newSeed.prefix(20))...")
        print("   Public Key: \(newPublicKey.prefix(20))...")
        print("   Base URL: \(newURL)")

        guard newAPIKey != self.apiKey || newSeed != self.base64PrivateKeySeed || newPublicKey != self.base64PublicKey || newURL != self.baseURL else { 
            print("🔄 [ApplicationState] No changes detected, skipping refresh")
            return 
        }

        let wasRunning = quotePoller.isRunning
        print("🔄 [ApplicationState] Quote poller was running: \(wasRunning)")
        quotePoller.stop()

        self.apiKey = newAPIKey
        self.base64PrivateKeySeed = newSeed
        self.base64PublicKey = newPublicKey
        self.baseURL = newURL

        let newBroker = RobinhoodCryptoClient(config: .init(baseURL: newURL, apiKey: newAPIKey, base64PrivateKeySeed: newSeed, base64PublicKey: newPublicKey))
        broker = newBroker

        quotePoller.updateBroker(newBroker)
        executionManager.updateBroker(newBroker)
        ensureBaselineSubscription()
        if wasRunning {
            quotePoller.start(state: self)
        }
        print("🔄 [ApplicationState] Broker refresh complete")
        
                // Historical data will continue to be built by QuotePoller logging
    }

    private func ensureBaselineSubscription() {
        let symbols = currentBaselineSymbols()
        if let id = baselineSubscription {
            quotePoller.updateSubscription(id, symbols: symbols)
        } else {
            baselineSubscription = quotePoller.subscribe(symbols)
        }
    }

    private func currentBaselineSymbols() -> Set<String> {
        var symbols = watchlist
        for holding in holdings {
            symbols.insert("\(holding.asset_code)-USD")
        }
        return symbols
    }
}

// Minimal models for account/holdings
struct AccountSummary: Codable, Hashable {
    let account_number: String
    let status: String
    let buying_power: String
    let buying_power_currency: String
}

struct HoldingItem: Codable, Hashable, Identifiable {
    var id: String { asset_code }
    let asset_code: String // e.g., BTC
    let quantity: String // string per API; convert when needed
}
