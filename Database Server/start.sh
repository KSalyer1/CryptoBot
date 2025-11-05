#!/bin/bash

# CryptoBot Database Server Startup Script

echo "🚀 Starting CryptoBot Database Server..."
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "⚠️  .env file not found. Creating from .env.example..."
    cp .env.example .env
    echo "⚠️  Please edit .env file with your database credentials before starting the server"
    exit 1
fi

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Check if database is set up
echo "🔍 Checking database setup..."
npm run setup-db

# Start the server
echo ""
echo "🚀 Starting server..."
npm start

