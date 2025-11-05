import Foundation
import Observation

@Observable
final class TradingSafetySettings {
    var paperMode: Bool = false
    var maxNotionalPerOrderUSD: Double = 5000
    var dailyExposureLimitUSD: Double = 25000
    // Empty whitelist means all symbols allowed
    var symbolWhitelistCSV: String = "" // e.g., "BTC-USD,ETH-USD"

    func whitelist() -> Set<String> {
        let parts = symbolWhitelistCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        return Set(parts.filter { !$0.isEmpty })
    }
}
