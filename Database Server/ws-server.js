require('dotenv').config();
const WebSocketServer = require('./ws/websocket-server');
const priceDataRepo = require('./db/repository');

const WS_PORT = process.env.WS_PORT || 3001;

// Start WebSocket server
const wsServer = new WebSocketServer(WS_PORT);
wsServer.start();

// Optional: Set up a periodic broadcast of latest prices
// This can be triggered by your data ingestion process instead
async function broadcastLatestPrices() {
  try {
    const symbols = await priceDataRepo.getAllSymbols();
    
    for (const symbol of symbols.slice(0, 50)) { // Limit to 50 symbols to avoid overload
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
        console.error(`Error broadcasting latest price for ${symbol}:`, error);
      }
    }
  } catch (error) {
    console.error('Error broadcasting latest prices:', error);
  }
}

// Broadcast every 5 seconds (adjust as needed)
// Note: In production, you might want to trigger this from your data ingestion endpoint
// instead of polling
const BROADCAST_INTERVAL = 5000;
setInterval(broadcastLatestPrices, BROADCAST_INTERVAL);

console.log(`📡 WebSocket server started. Broadcasting every ${BROADCAST_INTERVAL / 1000} seconds`);

// Export for use in main server
module.exports = wsServer;

