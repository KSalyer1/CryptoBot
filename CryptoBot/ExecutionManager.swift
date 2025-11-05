import Foundation

struct ExecutionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class ExecutionManager {
    private var broker: RobinhoodCryptoClient
    private let safety: TradingSafetySettings
    private let state: ApplicationState

    init(broker: RobinhoodCryptoClient, safety: TradingSafetySettings, state: ApplicationState) {
        self.broker = broker
        self.safety = safety
        self.state = state
    }

    func updateBroker(_ newBroker: RobinhoodCryptoClient) {
        broker = newBroker
    }

    // MARK: - Public API

    func placeMarket(symbol: String, side: Side, quantity: Double) async throws -> OrderResponse {
        try validate(symbol: symbol, side: side, type: "market", quantity: quantity, limitPrice: nil, stopPrice: nil)
        if safety.paperMode {
            // Simulate immediate fill at current mid for paper mode
            let price = state.quotes[symbol]?.price ?? 0
            return OrderResponse(id: UUID().uuidString, status: "paper_filled", filledQuantity: quantity, avgFillPrice: price)
        }
        let req = OrderRequest(instrumentID: symbol, side: side, quantity: quantity, type: "market")
        return try await broker.placeOrder(req)
    }

    func placeLimit(symbol: String, side: Side, quantity: Double, limitPrice: Double) async throws -> OrderResponse {
        try validate(symbol: symbol, side: side, type: "limit", quantity: quantity, limitPrice: limitPrice, stopPrice: nil)
        // TODO: implement limit order placement body when extending Robinhood client
        throw ExecutionError(message: "Limit order placement not implemented yet.")
    }

    func placeLimit(symbol: String, side: Side, quantity: Double, limitPrice: Double, tif: String = "gtc") async throws -> OrderResponse {
        try validate(symbol: symbol, side: side, type: "limit", quantity: quantity, limitPrice: limitPrice, stopPrice: nil)
        if safety.paperMode {
            let _ = state.quotes[symbol]?.price ?? 0
            return OrderResponse(id: UUID().uuidString, status: "paper_submitted", filledQuantity: nil, avgFillPrice: nil)
        }
        let market: [String: String]? = nil
        let limit: [String: Any]? = [
            "asset_quantity": String(quantity),
            "limit_price": limitPrice,
            "time_in_force": tif
        ]
        return try await broker.placeAdvancedOrder(symbol: symbol, side: side.rawValue, type: "limit", market: market, limit: limit, stopLoss: nil, stopLimit: nil)
    }

    func placeStopLoss(symbol: String, side: Side, quantity: Double, stopPrice: Double, tif: String = "gtc") async throws -> OrderResponse {
        try validate(symbol: symbol, side: side, type: "stop_loss", quantity: quantity, limitPrice: nil, stopPrice: stopPrice)
        if safety.paperMode {
            return OrderResponse(id: UUID().uuidString, status: "paper_submitted", filledQuantity: nil, avgFillPrice: nil)
        }
        let stopLoss: [String: Any] = [
            "asset_quantity": String(quantity),
            "stop_price": stopPrice,
            "time_in_force": tif
        ]
        return try await broker.placeAdvancedOrder(symbol: symbol, side: side.rawValue, type: "stop_loss", market: nil, limit: nil, stopLoss: stopLoss, stopLimit: nil)
    }

    func placeStopLimit(symbol: String, side: Side, quantity: Double, stopPrice: Double, limitPrice: Double, tif: String = "gtc") async throws -> OrderResponse {
        try validate(symbol: symbol, side: side, type: "stop_limit", quantity: quantity, limitPrice: limitPrice, stopPrice: stopPrice)
        if safety.paperMode {
            return OrderResponse(id: UUID().uuidString, status: "paper_submitted", filledQuantity: nil, avgFillPrice: nil)
        }
        let stopLimit: [String: Any] = [
            "asset_quantity": String(quantity),
            "stop_price": stopPrice,
            "limit_price": limitPrice,
            "time_in_force": tif
        ]
        return try await broker.placeAdvancedOrder(symbol: symbol, side: side.rawValue, type: "stop_limit", market: nil, limit: nil, stopLoss: nil, stopLimit: stopLimit)
    }

    // MARK: - Validation

    private func validate(symbol: String, side: Side, type: String, quantity: Double, limitPrice: Double?, stopPrice: Double?) throws {
        guard quantity > 0 else { throw ExecutionError(message: "Quantity must be greater than 0.") }
        // Symbol whitelist
        let wl = safety.whitelist()
        if !wl.isEmpty && !wl.contains(symbol.uppercased()) {
            throw ExecutionError(message: "Symbol not allowed by whitelist: \(symbol)")
        }
        // Notional checks (best-effort using current mid)
        let mid = state.quotes[symbol]?.price ?? 0
        let notional = mid * quantity
        if notional > safety.maxNotionalPerOrderUSD {
            throw ExecutionError(message: "Order exceeds max notional per order: $\(safety.maxNotionalPerOrderUSD)")
        }
        // TODO: Track daily exposure usage and compare to dailyExposureLimitUSD
        // Price requirements for advanced types
        if type == "limit" && (limitPrice ?? 0) <= 0 {
            throw ExecutionError(message: "Limit price must be > 0")
        }
        if (type == "stop_loss" || type == "stop_limit") && (stopPrice ?? 0) <= 0 {
            throw ExecutionError(message: "Stop price must be > 0")
        }
    }
}
