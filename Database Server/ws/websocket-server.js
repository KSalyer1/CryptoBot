const WebSocket = require('ws');
const priceDataRepo = require('./db/repository');

class WebSocketServer {
  constructor(port) {
    this.port = port;
    this.wss = null;
    this.clients = new Map(); // Map of WebSocket -> Set of subscribed symbols
    this.subscriptions = new Map(); // Map of symbol -> Set of WebSockets
  }

  start() {
    this.wss = new WebSocket.Server({ port: this.port });

    this.wss.on('connection', (ws) => {
      console.log('📡 New WebSocket client connected');
      this.clients.set(ws, new Set());

      ws.on('message', async (message) => {
        try {
          const data = JSON.parse(message.toString());
          await this.handleMessage(ws, data);
        } catch (error) {
          console.error('Error handling WebSocket message:', error);
          ws.send(JSON.stringify({
            type: 'error',
            message: 'Invalid message format'
          }));
        }
      });

      ws.on('close', () => {
        console.log('📡 WebSocket client disconnected');
        this.handleDisconnect(ws);
      });

      ws.on('error', (error) => {
        console.error('WebSocket error:', error);
        this.handleDisconnect(ws);
      });

      // Send welcome message
      ws.send(JSON.stringify({
        type: 'connected',
        message: 'Connected to CryptoBot Database Server',
        timestamp: Date.now()
      }));
    });

    console.log(`📡 WebSocket server running on port ${this.port}`);
  }

  async handleMessage(ws, data) {
    switch (data.type) {
      case 'subscribe':
        await this.handleSubscribe(ws, data.symbols || []);
        break;

      case 'unsubscribe':
        this.handleUnsubscribe(ws, data.symbols || []);
        break;

      case 'getLatest':
        await this.handleGetLatest(ws, data.symbol);
        break;

      default:
        ws.send(JSON.stringify({
          type: 'error',
          message: `Unknown message type: ${data.type}`
        }));
    }
  }

  async handleSubscribe(ws, symbols) {
    if (!Array.isArray(symbols) || symbols.length === 0) {
      ws.send(JSON.stringify({
        type: 'error',
        message: 'symbols must be a non-empty array'
      }));
      return;
    }

    const clientSubscriptions = this.clients.get(ws) || new Set();
    
    for (const symbol of symbols) {
      clientSubscriptions.add(symbol);
      
      if (!this.subscriptions.has(symbol)) {
        this.subscriptions.set(symbol, new Set());
      }
      this.subscriptions.get(symbol).add(ws);
    }

    this.clients.set(ws, clientSubscriptions);

    // Send initial data for subscribed symbols
    for (const symbol of symbols) {
      try {
        const latestTimestamp = await priceDataRepo.getLatestTimestamp(symbol);
        if (latestTimestamp) {
          // Get recent data (last hour)
          const endTimestamp = Math.floor(Date.now() / 1000);
          const startTimestamp = endTimestamp - 3600;
          const recentData = await priceDataRepo.getPriceData(symbol, startTimestamp, endTimestamp, 100);

          ws.send(JSON.stringify({
            type: 'historical',
            symbol,
            data: recentData,
            timestamp: Date.now()
          }));
        }
      } catch (error) {
        console.error(`Error sending initial data for ${symbol}:`, error);
      }
    }

    ws.send(JSON.stringify({
      type: 'subscribed',
      symbols,
      timestamp: Date.now()
    }));

    console.log(`📡 Client subscribed to: ${symbols.join(', ')}`);
  }

  handleUnsubscribe(ws, symbols) {
    if (!Array.isArray(symbols) || symbols.length === 0) {
      ws.send(JSON.stringify({
        type: 'error',
        message: 'symbols must be a non-empty array'
      }));
      return;
    }

    const clientSubscriptions = this.clients.get(ws) || new Set();
    
    for (const symbol of symbols) {
      clientSubscriptions.delete(symbol);
      
      if (this.subscriptions.has(symbol)) {
        this.subscriptions.get(symbol).delete(ws);
        if (this.subscriptions.get(symbol).size === 0) {
          this.subscriptions.delete(symbol);
        }
      }
    }

    this.clients.set(ws, clientSubscriptions);

    ws.send(JSON.stringify({
      type: 'unsubscribed',
      symbols,
      timestamp: Date.now()
    }));

    console.log(`📡 Client unsubscribed from: ${symbols.join(', ')}`);
  }

  async handleGetLatest(ws, symbol) {
    if (!symbol) {
      ws.send(JSON.stringify({
        type: 'error',
        message: 'symbol is required'
      }));
      return;
    }

    try {
      const latestTimestamp = await priceDataRepo.getLatestTimestamp(symbol);
      if (latestTimestamp) {
        const endTimestamp = Math.floor(Date.now() / 1000);
        const startTimestamp = latestTimestamp - 3600; // Last hour
        const data = await priceDataRepo.getPriceData(symbol, startTimestamp, endTimestamp, 1);

        ws.send(JSON.stringify({
          type: 'latest',
          symbol,
          data: data.length > 0 ? data[0] : null,
          timestamp: Date.now()
        }));
      } else {
        ws.send(JSON.stringify({
          type: 'latest',
          symbol,
          data: null,
          timestamp: Date.now()
        }));
      }
    } catch (error) {
      console.error(`Error getting latest for ${symbol}:`, error);
      ws.send(JSON.stringify({
        type: 'error',
        message: `Failed to get latest data for ${symbol}`
      }));
    }
  }

  handleDisconnect(ws) {
    const clientSubscriptions = this.clients.get(ws);
    if (clientSubscriptions) {
      for (const symbol of clientSubscriptions) {
        if (this.subscriptions.has(symbol)) {
          this.subscriptions.get(symbol).delete(ws);
          if (this.subscriptions.get(symbol).size === 0) {
            this.subscriptions.delete(symbol);
          }
        }
      }
      this.clients.delete(ws);
    }
  }

  /**
   * Broadcast price update to all subscribed clients
   * This should be called when new price data is received
   */
  broadcastPriceUpdate(symbol, timestamp, price) {
    if (!this.subscriptions.has(symbol)) {
      return;
    }

    const message = JSON.stringify({
      type: 'price',
      symbol,
      timestamp,
      price,
      serverTime: Date.now()
    });

    const clients = this.subscriptions.get(symbol);
    const disconnectedClients = [];

    clients.forEach(ws => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(message);
      } else {
        disconnectedClients.push(ws);
      }
    });

    // Clean up disconnected clients
    disconnectedClients.forEach(ws => {
      this.handleDisconnect(ws);
    });
  }

  /**
   * Get subscription statistics
   */
  getStats() {
    return {
      totalClients: this.clients.size,
      totalSubscriptions: this.subscriptions.size,
      symbols: Array.from(this.subscriptions.keys())
    };
  }
}

module.exports = WebSocketServer;

