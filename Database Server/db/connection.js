const mysql = require('mysql2/promise');
require('dotenv').config();

const config = {
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'CryptoBot',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  enableKeepAlive: true,
  keepAliveInitialDelay: 0
};

// Create connection pool
const pool = mysql.createPool(config);

// Test connection
async function testConnection() {
  try {
    const connection = await pool.getConnection();
    console.log('✅ Database connection successful');
    connection.release();
    return true;
  } catch (error) {
    console.error('❌ Database connection failed:', error.message);
    return false;
  }
}

// Initialize database schema
async function initializeDatabase() {
  try {
    console.log('📊 Initializing database schema...');
    
    // Create price_data table
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS price_data (
        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        symbol VARCHAR(20) NOT NULL,
        timestamp BIGINT NOT NULL,
        price DECIMAL(20, 8) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_symbol_timestamp (symbol, timestamp),
        INDEX idx_symbol (symbol),
        INDEX idx_timestamp (timestamp),
        INDEX idx_symbol_timestamp (symbol, timestamp)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);
    
    // Create metadata table
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS metadata (
        \`key\` VARCHAR(100) PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);
    
    console.log('✅ Database schema initialized successfully');
  } catch (error) {
    console.error('❌ Failed to initialize database schema:', error.message);
    throw error;
  }
}

module.exports = {
  pool,
  testConnection,
  initializeDatabase
};

