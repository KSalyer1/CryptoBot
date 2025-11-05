import Foundation

// MARK: - Core Models

public struct Instrument: Identifiable, Hashable, Codable {
    public let id: String // e.g., symbol like "BTC-USD"
    public let displayName: String
}

public struct Quote: Identifiable, Hashable, Codable {
    public let id: String // same as instrument id
    public let price: Double
    public let bid: Double?
    public let ask: Double?
    public let time: Date
}

public enum Side: String, Codable { case buy, sell }

public struct OrderRequest: Codable, Hashable {
    public let instrumentID: String
    public let side: Side
    public let quantity: Double // in units of the base asset
    public let type: String // e.g., "market"
}

public struct OrderResponse: Codable, Hashable, Identifiable {
    public let id: String
    public let status: String // e.g., "filled", "rejected", "submitted"
    public let filledQuantity: Double?
    public let avgFillPrice: Double?
}

public enum BrokerError: Error, LocalizedError {
    case unauthorized
    case network(String)
    case invalidRequest(String)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized. Check credentials."
        case .network(let msg): return "Network error: \(msg)"
        case .invalidRequest(let msg): return "Invalid request: \(msg)"
        case .unknown: return "Unknown error"
        }
    }
}

// MARK: - Protocols

public protocol BrokerClient {
    func fetchInstruments() async throws -> [Instrument]
    func placeOrder(_ request: OrderRequest) async throws -> OrderResponse
}

public protocol QuoteStream: AnyObject {
    func connect(symbols: [String]) async throws
    func disconnect()
    var quotes: AsyncStream<Quote> { get }
}
