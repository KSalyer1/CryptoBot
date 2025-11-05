const express = require('express');
const cors = require('cors');
const priceDataRepo = require('./db/repository');
const { testConnection, initializeDatabase } = require('./db/connection');

const app = express();
const PORT = process.env.SERVER_PORT || 3000;

// WebSocket server instance (will be set after initialization)
let wsServer = null;

// Middleware
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: Date.now() });
});

// Store price data
app.post('/api/v1/data/price', async (req, res) => {
  try {
    const { symbol, dataPoints } = req.body;

    if (!symbol || !dataPoints || !Array.isArray(dataPoints)) {
      return res.status(400).json({
        error: 'Invalid request. Expected { symbol: string, dataPoints: array }'
      });
    }

    // Validate data points format
    const validDataPoints = dataPoints.filter(point => 
      point.timestamp && typeof point.price === 'number'
    );

    if (validDataPoints.length === 0) {
      return res.status(400).json({ error: 'No valid data points provided' });
    }

    // Convert timestamp to Unix timestamp (seconds) if it's in milliseconds
    const normalizedDataPoints = validDataPoints.map(point => ({
      timestamp: point.timestamp > 1e10 ? Math.floor(point.timestamp / 1000) : Math.floor(point.timestamp),
      price: point.price
    }));

    const result = await priceDataRepo.storePriceData(symbol, normalizedDataPoints);

    // Broadcast latest price update via WebSocket if server is running
    if (wsServer && normalizedDataPoints.length > 0) {
      const latest = normalizedDataPoints[normalizedDataPoints.length - 1];
      wsServer.broadcastPriceUpdate(symbol, latest.timestamp, latest.price);
    }

    res.json({
      success: true,
      symbol,
      inserted: result.inserted,
      total: normalizedDataPoints.length
    });
  } catch (error) {
    console.error('Error storing price data:', error);
    res.status(500).json({ error: 'Failed to store price data', message: error.message });
  }
});

// Get price data for a symbol
app.get('/api/v1/data/price/:symbol', async (req, res) => {
  try {
    const { symbol } = req.params;
    const { startDate, endDate, limit } = req.query;

    let startTimestamp = null;
    let endTimestamp = null;
    let maxLimit = null;

    if (startDate) {
      startTimestamp = new Date(startDate).getTime() / 1000;
    }

    if (endDate) {
      endTimestamp = new Date(endDate).getTime() / 1000;
    }

    if (limit) {
      maxLimit = parseInt(limit, 10);
    }

    const data = await priceDataRepo.getPriceData(symbol, startTimestamp, endTimestamp, maxLimit);

    res.json({
      success: true,
      symbol,
      count: data.length,
      data
    });
  } catch (error) {
    console.error('Error getting price data:', error);
    res.status(500).json({ error: 'Failed to get price data', message: error.message });
  }
});

// Get filtered price data by days
app.get('/api/v1/data/price/:symbol/filter', async (req, res) => {
  try {
    const { symbol } = req.params;
    const { days, interval } = req.query;

    if (!days) {
      return res.status(400).json({ error: 'days parameter is required' });
    }

    const daysNum = parseInt(days, 10);
    if (isNaN(daysNum) || daysNum <= 0) {
      return res.status(400).json({ error: 'days must be a positive number' });
    }

    const endTimestamp = Math.floor(Date.now() / 1000);
    const startTimestamp = endTimestamp - (daysNum * 24 * 60 * 60);

    let data;
    if (interval) {
      const intervalSeconds = parseInt(interval, 10);
      if (isNaN(intervalSeconds) || intervalSeconds <= 0) {
        return res.status(400).json({ error: 'interval must be a positive number (seconds)' });
      }
      data = await priceDataRepo.getAggregatedPriceData(symbol, startTimestamp, endTimestamp, intervalSeconds);
    } else {
      data = await priceDataRepo.getPriceData(symbol, startTimestamp, endTimestamp);
    }

    res.json({
      success: true,
      symbol,
      days: daysNum,
      interval: interval ? parseInt(interval, 10) : null,
      count: data.length,
      data
    });
  } catch (error) {
    console.error('Error getting filtered price data:', error);
    res.status(500).json({ error: 'Failed to get filtered price data', message: error.message });
  }
});

// Get latest timestamp for a symbol
app.get('/api/v1/data/:symbol/latest', async (req, res) => {
  try {
    const { symbol } = req.params;
    const latestTimestamp = await priceDataRepo.getLatestTimestamp(symbol);

    if (latestTimestamp === null) {
      return res.status(404).json({ error: 'No data found for symbol' });
    }

    res.json({
      success: true,
      symbol,
      latestTimestamp,
      latestDate: new Date(latestTimestamp * 1000).toISOString()
    });
  } catch (error) {
    console.error('Error getting latest timestamp:', error);
    res.status(500).json({ error: 'Failed to get latest timestamp', message: error.message });
  }
});

// Get all symbols
app.get('/api/v1/data/symbols', async (req, res) => {
  try {
    const symbols = await priceDataRepo.getAllSymbols();
    res.json({
      success: true,
      count: symbols.length,
      symbols
    });
  } catch (error) {
    console.error('Error getting symbols:', error);
    res.status(500).json({ error: 'Failed to get symbols', message: error.message });
  }
});

// Get database statistics
app.get('/api/v1/data/stats', async (req, res) => {
  try {
    const stats = await priceDataRepo.getDatabaseStats();
    res.json({
      success: true,
      stats: {
        ...stats,
        oldestDate: stats.oldestDate ? new Date(stats.oldestDate * 1000).toISOString() : null,
        newestDate: stats.newestDate ? new Date(stats.newestDate * 1000).toISOString() : null
      }
    });
  } catch (error) {
    console.error('Error getting database stats:', error);
    res.status(500).json({ error: 'Failed to get database stats', message: error.message });
  }
});

// Initialize server
async function startServer() {
  // Test database connection
  const connected = await testConnection();
  if (!connected) {
    console.error('❌ Cannot start server without database connection');
    process.exit(1);
  }

  // Initialize database schema
  await initializeDatabase();

  // Start HTTP server
  app.listen(PORT, () => {
    console.log(`🚀 CryptoBot Database Server running on port ${PORT}`);
    console.log(`📊 API endpoints available at http://localhost:${PORT}/api/v1`);
  });

  // Start WebSocket server
  const WebSocketServer = require('./ws/websocket-server');
  const WS_PORT = process.env.WS_PORT || 3001;
  wsServer = new WebSocketServer(WS_PORT);
  wsServer.start();

  // Set up periodic broadcast of latest prices
  setInterval(async () => {
    try {
      const symbols = await priceDataRepo.getAllSymbols();
      
      for (const symbol of symbols.slice(0, 50)) { // Limit to 50 symbols
        try {
          const latestTimestamp = await priceDataRepo.getLatestTimestamp(symbol);
          if (latestTimestamp) {
            const endTimestamp = Math.floor(Date.now() / 1000);
            const startTimestamp = endTimestamp - 60; // Last minute
            const recentData = await priceDataRepo.getPriceData(symbol, startTimestamp, endTimestamp, 1);
            
            if (recentData.length > 0) {
              const latest = recentData[recentData.length - 1];
              wsServer.broadcastPriceUpdate(symbol, latest.timestamp, latest.price);
            }
          }
        } catch (error) {
          // Silent fail for individual symbols
        }
      }
    } catch (error) {
      console.error('Error broadcasting latest prices:', error);
    }
  }, 5000); // Broadcast every 5 seconds
}

// Handle graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('SIGINT signal received: closing HTTP server');
  process.exit(0);
});

startServer().catch(error => {
  console.error('Failed to start server:', error);
  process.exit(1);
});

module.exports = app;

