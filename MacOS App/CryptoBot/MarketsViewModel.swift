import Foundation
import Observation

@Observable
final class MarketsViewModel {
    // Inputs
    var searchText: String = ""

    // Outputs
    var myMarkets: [String] = []
    var otherMarkets: [String] = []
    var errorMessage: String?

    @MainActor
    func load(app: ApplicationState, heldAssets: [String]) async {
        do {
            let pairs = try await app.broker.getTradingPairs(symbols: nil)
            let allSymbols = pairs.results.compactMap { $0.symbol }
            let my = Set(heldAssets.map { "\($0)-USD" })
            myMarkets = allSymbols.filter { my.contains($0) }
            otherMarkets = allSymbols.filter { !my.contains($0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func filteredSymbols(prefix: Int) -> [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        func filter(_ symbols: [String]) -> [String] {
            guard !q.isEmpty else { return Array(symbols.prefix(prefix)) }
            return symbols.filter { $0.contains(q) }.prefix(prefix).map { $0 }
        }
        return filter(myMarkets) + filter(otherMarkets)
    }

    func filtered(_ symbols: [String]) -> [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return symbols }
        
        // More flexible search - search both symbol and asset code
        return symbols.filter { symbol in
            let symbolUpper = symbol.uppercased()
            let assetCode = String(symbol.prefix(symbol.count - 4)).uppercased() // Remove "-USD" suffix
            
            return symbolUpper.contains(q) || assetCode.contains(q)
        }
    }
}
