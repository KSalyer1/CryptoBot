# CryptoBot Database Server

Node.js MySQL database server for CryptoBot historical data repository. This server handles storage, retrieval, and real-time streaming of cryptocurrency price data.

## Features

- ✅ MySQL database for historical price data storage
- ✅ REST API endpoints for data operations
- ✅ WebSocket server for real-time price streaming
- ✅ Server-side filtering and aggregation (1 day, 1 year, etc.)
- ✅ Efficient querying with proper database indexes
- ✅ Automatic schema initialization

## Prerequisites

- Node.js (v14 or higher)
- MySQL Server (v5.7 or higher, or MariaDB equivalent)
- npm or yarn

**Platform Support:** ✅ Works on Ubuntu, macOS, Windows, and other platforms that support Node.js

## Quick Start

### Option 1: Using the startup script

```bash
./start.sh
```

### Option 2: Manual setup

1. **Configure environment variables:**

   Copy `.env.example` to `.env` and update with your MySQL credentials:
   ```bash
   cp .env.example .env
   ```

   Edit `.env`:
   ```env
   DB_HOST=localhost
   DB_PORT=3306
   DB_USER=root
   DB_PASSWORD=your_password
   DB_NAME=CryptoBot
   SERVER_PORT=3000
   WS_PORT=3001
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Set up database:**
   ```bash
   npm run setup-db
   ```

4. **Start the server:**
   ```bash
   npm start
   ```

For development with auto-reload:
```bash
npm run dev
```

## API Endpoints

### REST API (Port 3000)

- `POST /api/v1/data/price` - Store price data points
- `GET /api/v1/data/price/:symbol` - Get price data for a symbol
- `GET /api/v1/data/price/:symbol/filter` - Get filtered price data (query params: days, startDate, endDate)
- `GET /api/v1/data/symbols` - Get all symbols with data
- `GET /api/v1/data/stats` - Get database statistics
- `GET /api/v1/data/:symbol/latest` - Get latest timestamp for a symbol

### WebSocket (Port 3001)

Connect to `ws://localhost:3001` for real-time price data streaming.

**Connection:**
```javascript
const ws = new WebSocket('ws://localhost:3001');

ws.on('open', () => {
  // Subscribe to symbols
  ws.send(JSON.stringify({
    type: 'subscribe',
    symbols: ['BTC-USD', 'ETH-USD']
  }));
});

ws.on('message', (data) => {
  const message = JSON.parse(data);
  console.log(message);
});
```

**Message Types:**

- **Subscribe:** `{"type": "subscribe", "symbols": ["BTC-USD", "ETH-USD"]}`
- **Unsubscribe:** `{"type": "unsubscribe", "symbols": ["BTC-USD"]}`
- **Get Latest:** `{"type": "getLatest", "symbol": "BTC-USD"}`
- **Price Update (received):** `{"type": "price", "symbol": "BTC-USD", "timestamp": 1234567890, "price": 45000.0, "serverTime": 1234567890123}`
- **Historical Data (on subscribe):** `{"type": "historical", "symbol": "BTC-USD", "data": [...], "timestamp": 1234567890123}`
- **Connection Confirmed:** `{"type": "connected", "message": "Connected to CryptoBot Database Server", "timestamp": 1234567890123}`

## Database Schema

### `price_data` table
- `id` - Primary key (auto-increment)
- `symbol` - Trading symbol (e.g., "BTC-USD")
- `timestamp` - Unix timestamp (seconds)
- `price` - Price value (DECIMAL 20,8)
- `created_at` - Record creation timestamp
- Unique constraint on `(symbol, timestamp)`
- Indexes on `symbol`, `timestamp`, and `(symbol, timestamp)`

### `metadata` table
- `key` - Metadata key (primary key)
- `value` - Metadata value (TEXT)
- `updated_at` - Last update timestamp

## Data Format

### Price Data Point
```json
{
  "timestamp": 1234567890,
  "price": 45000.50
}
```

### Store Price Data Request
```json
{
  "symbol": "BTC-USD",
  "dataPoints": [
    {"timestamp": 1234567890, "price": 45000.50},
    {"timestamp": 1234567900, "price": 45001.00}
  ]
}
```

**Note:** Timestamps can be in seconds or milliseconds (will be automatically normalized to seconds).

## Server-Side Filtering

The server provides efficient filtering and aggregation:

- **By days:** `/api/v1/data/price/:symbol/filter?days=1` - Get last 1 day
- **By time range:** `/api/v1/data/price/:symbol?startDate=2024-01-01&endDate=2024-01-31`
- **With aggregation:** `/api/v1/data/price/:symbol/filter?days=365&interval=3600` - Hourly aggregation for 1 year

Aggregation intervals are in seconds (e.g., 3600 for hourly, 300 for 5-minute).

## Architecture Benefits

✅ **Offloads computation** - Filtering and aggregation happens on the server
✅ **Always available** - Server runs 24/7, independent of macOS app
✅ **Real-time streaming** - WebSocket for live price updates
✅ **Efficient queries** - Proper indexes and optimized SQL
✅ **Scalable** - Can handle multiple clients and high data volumes

## Integration with macOS App

The macOS app should:
1. Store price data via `POST /api/v1/data/price`
2. Fetch filtered data via `GET /api/v1/data/price/:symbol/filter?days=X`
3. Connect to WebSocket for real-time updates
4. Use server-side filtering instead of local processing

## Troubleshooting

**Database connection failed:**
- Check MySQL server is running
- Verify credentials in `.env`
- Ensure database user has proper permissions

**WebSocket not connecting:**
- Check firewall settings for port 3001
- Verify WebSocket server started (check console logs)

**Data not appearing:**
- Check database connection
- Verify data format matches expected schema
- Check server logs for errors

## Ubuntu Production Deployment

See [UBUNTU_SETUP.md](UBUNTU_SETUP.md) for detailed Ubuntu installation and deployment instructions, including:
- Systemd service configuration
- Nginx reverse proxy setup
- Firewall configuration
- Performance optimization
- Security best practices

