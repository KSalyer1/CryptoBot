import Foundation
import SQLite3

/// Manages local SQLite database for historical cryptocurrency data
class HistoricalDatabaseManager {
    static let shared = HistoricalDatabaseManager()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    private init() {
        // Create database in Documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        dbPath = documentsPath.appendingPathComponent("crypto_historical.db").path
        
        print("🗄️ [HistoricalDatabaseManager] Database path: \(dbPath)")
        initializeDatabase()
    }
    
    deinit {
        closeDatabase()
    }
    
    private func initializeDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("❌ [HistoricalDatabaseManager] Unable to open database")
            return
        }
        
        print("✅ [HistoricalDatabaseManager] Database opened successfully")
        createTables()
    }
    
    private func createTables() {
        let createPriceDataTable = """
            CREATE TABLE IF NOT EXISTS price_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                symbol TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                price REAL NOT NULL,
                created_at INTEGER DEFAULT (strftime('%s', 'now')),
                UNIQUE(symbol, timestamp)
            );
        """
        
        let createMetadataTable = """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at INTEGER DEFAULT (strftime('%s', 'now'))
            );
        """
        
        let createIndexes = """
            CREATE INDEX IF NOT EXISTS idx_symbol_timestamp ON price_data(symbol, timestamp);
            CREATE INDEX IF NOT EXISTS idx_symbol ON price_data(symbol);
        """
        
        executeSQL(createPriceDataTable)
        executeSQL(createMetadataTable)
        executeSQL(createIndexes)
        
        print("✅ [HistoricalDatabaseManager] Tables created successfully")
    }
    
    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("❌ [HistoricalDatabaseManager] Failed to prepare statement: \(sql)")
            return
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            print("❌ [HistoricalDatabaseManager] Failed to execute statement: \(sql)")
            return
        }
    }
    
    /// Store historical price data points
    func storePriceData(symbol: String, dataPoints: [PriceDataPoint]) async {
        guard !dataPoints.isEmpty else { return }
        
        print("💾 [HistoricalDatabaseManager] Storing \(dataPoints.count) data points for \(symbol)")
        
        // Use transaction for better performance
        guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            print("❌ [HistoricalDatabaseManager] Failed to begin transaction")
            return
        }
        
        let insertSQL = """
            INSERT OR REPLACE INTO price_data (symbol, timestamp, price)
            VALUES (?, ?, ?);
        """
        
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            print("❌ [HistoricalDatabaseManager] Failed to prepare insert statement")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return
        }
        
        var successCount = 0
        for dataPoint in dataPoints {
            // Clear previous bindings
            sqlite3_clear_bindings(statement)
            
            // Use SQLITE_TRANSIENT to copy the string
            sqlite3_bind_text(statement, 1, (symbol as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int64(statement, 2, Int64(dataPoint.timestamp.timeIntervalSince1970))
            sqlite3_bind_double(statement, 3, dataPoint.price)
            
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                successCount += 1
            } else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("❌ [HistoricalDatabaseManager] Failed to insert data point for \(symbol) at \(dataPoint.timestamp): \(errorMsg) (code: \(result))")
            }
            
            // Reset the statement for the next iteration
            sqlite3_reset(statement)
        }
        
        // Commit transaction
        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK {
            print("✅ [HistoricalDatabaseManager] Successfully stored \(successCount)/\(dataPoints.count) data points for \(symbol)")
        } else {
            print("❌ [HistoricalDatabaseManager] Failed to commit transaction for \(symbol)")
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        }
    }
    
    /// Retrieve all historical price data for a symbol
    func getPriceData(symbol: String) async -> [PriceDataPoint] {
        return await getPriceData(symbol: symbol, from: nil, to: nil)
    }
    
    /// Retrieve historical price data for a symbol within a time range
    func getPriceData(symbol: String, from startDate: Date? = nil, to endDate: Date? = nil) async -> [PriceDataPoint] {
        print("🔍 [HistoricalDatabaseManager] Querying data for \(symbol) from \(startDate?.description ?? "nil") to \(endDate?.description ?? "nil")")
        var sql = "SELECT timestamp, price FROM price_data WHERE symbol = ?"
        var parameters: [Any] = [symbol]
        
        if let startDate = startDate {
            sql += " AND timestamp >= ?"
            parameters.append(Int64(startDate.timeIntervalSince1970))
        }
        
        if let endDate = endDate {
            sql += " AND timestamp <= ?"
            parameters.append(Int64(endDate.timeIntervalSince1970))
        }
        
        sql += " ORDER BY timestamp ASC"
        
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("❌ [HistoricalDatabaseManager] Failed to prepare select statement")
            return []
        }
        
        // Bind parameters
        for (index, param) in parameters.enumerated() {
            if let stringParam = param as? String {
                sqlite3_bind_text(statement, Int32(index + 1), (stringParam as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else if let intParam = param as? Int64 {
                sqlite3_bind_int64(statement, Int32(index + 1), intParam)
            }
        }
        
        var dataPoints: [PriceDataPoint] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(statement, 0)
            let price = sqlite3_column_double(statement, 1)
            
            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            dataPoints.append(PriceDataPoint(timestamp: date, price: price))
        }
        
        print("📊 [HistoricalDatabaseManager] Retrieved \(dataPoints.count) data points for \(symbol)")

        // Debug: Show first few data points if any
        if !dataPoints.isEmpty {
            print("📊 [HistoricalDatabaseManager] First point: \(dataPoints.first!.price) at \(dataPoints.first!.timestamp)")
            print("📊 [HistoricalDatabaseManager] Last point: \(dataPoints.last!.price) at \(dataPoints.last!.timestamp)")
        }

        return dataPoints
    }
    
    /// Get the latest timestamp for a symbol
    func getLatestTimestamp(for symbol: String) async -> Date? {
        let sql = "SELECT MAX(timestamp) FROM price_data WHERE symbol = ?"
        
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        sqlite3_bind_text(statement, 1, symbol, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(statement, 0)
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
        
        return nil
    }
    
    /// Get all symbols that have data
    func getAllSymbols() async -> [String] {
        let sql = "SELECT DISTINCT symbol FROM price_data ORDER BY symbol"
        
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        
        var symbols: [String] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let symbolCString = sqlite3_column_text(statement, 0) {
                let symbol = String(cString: symbolCString)
                symbols.append(symbol)
            }
        }
        
        return symbols
    }
    
    /// Store metadata (like last update time)
    func storeMetadata(key: String, value: String) {
        let sql = "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)"
        
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        
        sqlite3_bind_text(statement, 1, key, -1, nil)
        sqlite3_bind_text(statement, 2, value, -1, nil)
        
        sqlite3_step(statement)
    }
    
    /// Get metadata
    func getMetadata(key: String) -> String? {
        let sql = "SELECT value FROM metadata WHERE key = ?"
        
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        sqlite3_bind_text(statement, 1, key, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            if let valueCString = sqlite3_column_text(statement, 0) {
                return String(cString: valueCString)
            }
        }
        
        return nil
    }
    
    /// Get database statistics
    func getDatabaseStats() async -> (totalRecords: Int, symbols: Int, oldestDate: Date?, newestDate: Date?) {
        let sql = """
            SELECT 
                COUNT(*) as total_records,
                COUNT(DISTINCT symbol) as symbols,
                MIN(timestamp) as oldest_date,
                MAX(timestamp) as newest_date
            FROM price_data
        """
        
        var statement: OpaquePointer?
        defer {
            sqlite3_finalize(statement)
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return (0, 0, nil, nil)
        }
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let totalRecords = Int(sqlite3_column_int(statement, 0))
            let symbols = Int(sqlite3_column_int(statement, 1))
            let oldestTimestamp = sqlite3_column_int64(statement, 2)
            let newestTimestamp = sqlite3_column_int64(statement, 3)
            
            let oldestDate = oldestTimestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(oldestTimestamp)) : nil
            let newestDate = newestTimestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(newestTimestamp)) : nil
            
            return (totalRecords, symbols, oldestDate, newestDate)
        }
        
        return (0, 0, nil, nil)
    }
    
    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
}
