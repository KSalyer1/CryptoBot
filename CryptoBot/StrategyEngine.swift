import Foundation
import Observation

public struct StrategyOrderIntent: Identifiable, Hashable {
    public let id = UUID()
    public let symbol: String
    public let side: Side
    public let type: String // "market", "limit", "stop_limit", "stop_loss"
    public let quantity: Double
    public let limitPrice: Double?
    public let stopPrice: Double?
}

@Observable
final class StrategyEngineState {
    var isConnected: Bool = false
    var status: String = "Disconnected"
    var logs: [String] = []
}

protocol StrategyEngine: AnyObject {
    var state: StrategyEngineState { get }
    func connect(apiKey: String, endpoint: URL) async
    func disconnect()
    func propose(_ intent: StrategyOrderIntent)
}

// Note: OpenAIRealtimeStrategy removed - replaced by ShortSellingAIStrategy in OpenAIClient.swift
