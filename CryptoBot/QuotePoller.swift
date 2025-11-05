import Foundation

final class QuotePoller {
    private var broker: RobinhoodCryptoClient
    private let ingestion: DataIngestionService
    private let historicalDB = HistoricalDatabaseManager.shared
    private var task: Task<Void, Never>? = nil

    // Symbols to poll (union of active subscriptions)
    private var symbols: Set<String> = []
    private var subscriptions: [UUID: Set<String>] = [:]

    init(broker: RobinhoodCryptoClient, ingestion: DataIngestionService) {
        self.broker = broker
        self.ingestion = ingestion
    }

    var trackedSymbols: Set<String> { symbols }
    var isRunning: Bool { task != nil }

    func subscribe(_ newSymbols: Set<String>) -> UUID {
        let id = UUID()
        subscriptions[id] = sanitized(newSymbols)
        recalculateSymbols()
        return id
    }

    func updateSubscription(_ id: UUID, symbols newSymbols: Set<String>) {
        guard subscriptions[id] != nil else { return }
        subscriptions[id] = sanitized(newSymbols)
        recalculateSymbols()
    }

    func unsubscribe(_ id: UUID) {
        subscriptions.removeValue(forKey: id)
        recalculateSymbols()
    }

    func start(state: ApplicationState) {
        stop()
        task = Task { [weak self] in
            guard let self else { return }
            let interval: TimeInterval = 1.5
            var backoff: Double = 1.0
            var buffer: [TickRecord] = []
            while !Task.isCancelled {
                let batch = Array(self.symbols.prefix(50))
                if !batch.isEmpty {
                    do {
                        let quotes = try await broker.getBestBidAsk(symbols: batch)
                        await MainActor.run {
                            for q in quotes { state.quotes[q.id] = q }
                        }
                        // Build tick records
                        let records = quotes.map { q in TickRecord(symbol: q.id, timestamp: q.time, bid: q.bid, ask: q.ask, mid: q.price) }
                        buffer.append(contentsOf: records)
                        
                        // Log price data to historical database - batch by symbol
                        var symbolDataMap: [String: [PriceDataPoint]] = [:]
                        for quote in quotes {
                            // Use current time for more precise timestamps to avoid duplicates
                            let priceDataPoint = PriceDataPoint(timestamp: Date(), price: quote.price)
                            if symbolDataMap[quote.id] == nil {
                                symbolDataMap[quote.id] = []
                            }
                            symbolDataMap[quote.id]?.append(priceDataPoint)
                        }
                        
                        // Store all data points for each symbol in one batch
                        for (symbol, dataPoints) in symbolDataMap {
                            await historicalDB.storePriceData(symbol: symbol, dataPoints: dataPoints)
                        }
                        print("📊 [QuotePoller] Logged price data for \(quotes.count) symbols to historical database")
                        // Flush periodically
                        if buffer.count >= 100 {
                            let toSend = buffer
                            buffer.removeAll()
                            Task { try? await self.ingestion.insertTicks(toSend) }
                        }
                        backoff = 1.0
                    } catch {
                        let msg = (error as NSError).localizedDescription.lowercased()
                        if msg.contains("rate limited") || msg.contains("429") { backoff = min(backoff * 2.0, 8.0) }
                    }
                }
                // Flush any remaining buffer each cycle
                if !buffer.isEmpty {
                    let toSend = buffer
                    buffer.removeAll()
                    Task { try? await self.ingestion.insertTicks(toSend) }
                }
                try? await Task.sleep(nanoseconds: UInt64((interval * backoff) * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func updateBroker(_ newBroker: RobinhoodCryptoClient) {
        broker = newBroker
    }

    private func sanitized(_ symbols: Set<String>) -> Set<String> {
        symbols.compactMap { symbol in
            let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.uppercased()
        }.reduce(into: Set<String>()) { $0.insert($1) }
    }

    private func recalculateSymbols() {
        symbols = subscriptions.values.reduce(into: Set<String>()) { result, entry in
            result.formUnion(entry)
        }
    }
}
