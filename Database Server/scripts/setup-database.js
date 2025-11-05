require('dotenv').config();
const mysql = require('mysql2/promise');

const config = {
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  multipleStatements: true
};

async function setupDatabase() {
  let connection;
  
  try {
    console.log('🔧 Connecting to MySQL server...');
    connection = await mysql.createConnection(config);
    console.log('✅ Connected to MySQL server');

    const dbName = process.env.DB_NAME || 'CryptoBot';
    
    // Create database if it doesn't exist
    console.log(`📊 Creating database '${dbName}' if it doesn't exist...`);
    await connection.execute(`CREATE DATABASE IF NOT EXISTS \`${dbName}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`);
    console.log(`✅ Database '${dbName}' ready`);

    // Switch to the database
    await connection.execute(`USE \`${dbName}\``);

    // Create tables
    console.log('📊 Creating tables...');
    
    await connection.execute(`
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

    await connection.execute(`
      CREATE TABLE IF NOT EXISTS metadata (
        \`key\` VARCHAR(100) PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);

    console.log('✅ Tables created successfully');
    console.log('\n📋 Database setup complete!');
    console.log(`   Database: ${dbName}`);
    console.log('   Tables: price_data, metadata');
    
  } catch (error) {
    console.error('❌ Error setting up database:', error.message);
    process.exit(1);
  } finally {
    if (connection) {
      await connection.end();
    }
  }
}

setupDatabase();

