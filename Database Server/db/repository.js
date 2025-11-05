const { pool } = require('./connection');

class PriceDataRepository {
  /**
   * Store price data points (batch insert)
   * @param {string} symbol - Trading symbol (e.g., "BTC-USD")
   * @param {Array<{timestamp: number, price: number}>} dataPoints - Array of price data points
   */
  async storePriceData(symbol, dataPoints) {
    if (!dataPoints || dataPoints.length === 0) {
      return { success: true, inserted: 0 };
    }

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();

      const insertSQL = `
        INSERT INTO price_data (symbol, timestamp, price)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE price = VALUES(price)
      `;

      let inserted = 0;
      for (const point of dataPoints) {
        try {
          await connection.execute(insertSQL, [symbol, point.timestamp, point.price]);
          inserted++;
        } catch (error) {
          // Log error but continue with other points
          console.error(`Error inserting data point for ${symbol}:`, error.message);
        }
      }

      await connection.commit();
      return { success: true, inserted };
    } catch (error) {
      await connection.rollback();
      console.error(`Error storing price data for ${symbol}:`, error.message);
      throw error;
    } finally {
      connection.release();
    }
  }

  /**
   * Get price data for a symbol within a time range
   * @param {string} symbol - Trading symbol
   * @param {number} startTimestamp - Start timestamp (Unix timestamp in seconds)
   * @param {number} endTimestamp - End timestamp (Unix timestamp in seconds)
   * @param {number} limit - Maximum number of records to return (optional)
   */
  async getPriceData(symbol, startTimestamp = null, endTimestamp = null, limit = null) {
    try {
      let sql = 'SELECT timestamp, price FROM price_data WHERE symbol = ?';
      const params = [symbol];

      if (startTimestamp !== null) {
        sql += ' AND timestamp >= ?';
        params.push(Math.floor(startTimestamp));
      }

      if (endTimestamp !== null) {
        sql += ' AND timestamp <= ?';
        params.push(Math.floor(endTimestamp));
      }

      sql += ' ORDER BY timestamp ASC';

      if (limit !== null && limit > 0) {
        sql += ' LIMIT ?';
        params.push(limit);
      }

      const [rows] = await pool.execute(sql, params);
      return rows.map(row => ({
        timestamp: row.timestamp,
        price: parseFloat(row.price)
      }));
    } catch (error) {
      console.error(`Error getting price data for ${symbol}:`, error.message);
      throw error;
    }
  }

  /**
   * Get filtered price data by days
   * @param {string} symbol - Trading symbol
   * @param {number} days - Number of days to fetch
   */
  async getPriceDataByDays(symbol, days) {
    const endTimestamp = Math.floor(Date.now() / 1000);
    const startTimestamp = endTimestamp - (days * 24 * 60 * 60);
    return this.getPriceData(symbol, startTimestamp, endTimestamp);
  }

  /**
   * Get latest timestamp for a symbol
   * @param {string} symbol - Trading symbol
   */
  async getLatestTimestamp(symbol) {
    try {
      const [rows] = await pool.execute(
        'SELECT MAX(timestamp) as latest FROM price_data WHERE symbol = ?',
        [symbol]
      );
      return rows[0]?.latest || null;
    } catch (error) {
      console.error(`Error getting latest timestamp for ${symbol}:`, error.message);
      throw error;
    }
  }

  /**
   * Get all symbols that have data
   */
  async getAllSymbols() {
    try {
      const [rows] = await pool.execute(
        'SELECT DISTINCT symbol FROM price_data ORDER BY symbol'
      );
      return rows.map(row => row.symbol);
    } catch (error) {
      console.error('Error getting all symbols:', error.message);
      throw error;
    }
  }

  /**
   * Get database statistics
   */
  async getDatabaseStats() {
    try {
      const [stats] = await pool.execute(`
        SELECT 
          COUNT(*) as totalRecords,
          COUNT(DISTINCT symbol) as symbols,
          MIN(timestamp) as oldestDate,
          MAX(timestamp) as newestDate
        FROM price_data
      `);

      return {
        totalRecords: stats[0].totalRecords,
        symbols: stats[0].symbols,
        oldestDate: stats[0].oldestDate,
        newestDate: stats[0].newestDate
      };
    } catch (error) {
      console.error('Error getting database stats:', error.message);
      throw error;
    }
  }

  /**
   * Get aggregated price data for charting (supports downsampling)
   * @param {string} symbol - Trading symbol
   * @param {number} startTimestamp - Start timestamp
   * @param {number} endTimestamp - End timestamp
   * @param {number} intervalSeconds - Interval for aggregation (e.g., 3600 for hourly)
   */
  async getAggregatedPriceData(symbol, startTimestamp, endTimestamp, intervalSeconds = null) {
    try {
      let sql;
      const params = [symbol, Math.floor(startTimestamp), Math.floor(endTimestamp)];

      if (intervalSeconds && intervalSeconds > 0) {
        // Aggregate by interval using FLOOR to bucket timestamps
        sql = `
          SELECT 
            FLOOR(timestamp / ?) * ? as bucket_timestamp,
            AVG(price) as avg_price,
            MIN(price) as min_price,
            MAX(price) as max_price,
            COUNT(*) as point_count
          FROM price_data
          WHERE symbol = ? AND timestamp >= ? AND timestamp <= ?
          GROUP BY bucket_timestamp
          ORDER BY bucket_timestamp ASC
        `;
        params.unshift(intervalSeconds, intervalSeconds);
      } else {
        // Return all data points
        sql = `
          SELECT timestamp, price
          FROM price_data
          WHERE symbol = ? AND timestamp >= ? AND timestamp <= ?
          ORDER BY timestamp ASC
        `;
      }

      const [rows] = await pool.execute(sql, params);
      
      if (intervalSeconds && intervalSeconds > 0) {
        return rows.map(row => ({
          timestamp: row.bucket_timestamp,
          price: parseFloat(row.avg_price),
          min: parseFloat(row.min_price),
          max: parseFloat(row.max_price),
          count: row.point_count
        }));
      } else {
        return rows.map(row => ({
          timestamp: row.timestamp,
          price: parseFloat(row.price)
        }));
      }
    } catch (error) {
      console.error(`Error getting aggregated price data for ${symbol}:`, error.message);
      throw error;
    }
  }
}

module.exports = new PriceDataRepository();

