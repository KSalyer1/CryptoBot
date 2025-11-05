# CryptoBot Database Server - Ubuntu Setup Guide

## Ubuntu Installation

### 1. Install Prerequisites

```bash
# Update package list
sudo apt update

# Install Node.js (v18 LTS recommended)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install MySQL Server
sudo apt install -y mysql-server

# Secure MySQL installation (optional but recommended)
sudo mysql_secure_installation
```

### 2. Configure MySQL

```bash
# Login to MySQL
sudo mysql -u root -p

# Create database user (recommended: don't use root)
CREATE USER 'cryptobot'@'localhost' IDENTIFIED BY 'your_secure_password';
GRANT ALL PRIVILEGES ON CryptoBot.* TO 'cryptobot'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 3. Deploy the Server

```bash
# Clone or copy the Database Server folder to your Ubuntu server
cd /path/to/Database Server

# Make start script executable
chmod +x start.sh

# Copy environment file
cp .env.example .env

# Edit .env with your MySQL credentials
nano .env
```

Update `.env`:
```env
DB_HOST=localhost
DB_PORT=3306
DB_USER=cryptobot
DB_PASSWORD=your_secure_password
DB_NAME=CryptoBot
SERVER_PORT=3000
WS_PORT=3001
```

### 4. Install and Start

```bash
# Install dependencies
npm install

# Set up database
npm run setup-db

# Test run
npm start
```

### 5. Run as a System Service (Production)

Create a systemd service file:

```bash
sudo nano /etc/systemd/system/cryptobot-db.service
```

Add this content (use `cryptobot-db.service.example` as a template):

```ini
[Unit]
Description=CryptoBot Database Server
After=network.target mysql.service

[Service]
Type=simple
User=your_username
WorkingDirectory=/path/to/Database Server
Environment="NODE_ENV=production"
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=cryptobot-db

[Install]
WantedBy=multi-user.target
```

**Important:** Replace:
- `your_username` with your actual Ubuntu username
- `/path/to/Database Server` with the actual path to the Database Server directory

Enable and start the service:

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable cryptobot-db

# Start the service
sudo systemctl start cryptobot-db

# Check status
sudo systemctl status cryptobot-db

# View logs
sudo journalctl -u cryptobot-db -f
```

### 6. Configure Firewall (if using UFW)

```bash
# Allow HTTP API port
sudo ufw allow 3000/tcp

# Allow WebSocket port
sudo ufw allow 3001/tcp

# Check status
sudo ufw status
```

### 7. Reverse Proxy with Nginx (Optional)

For production, you may want to use Nginx as a reverse proxy:

```bash
sudo apt install nginx
sudo nano /etc/nginx/sites-available/cryptobot-db
```

Add configuration:

```nginx
server {
    listen 80;
    server_name your-domain.com;

    location /api {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location /ws {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Enable and restart:

```bash
sudo ln -s /etc/nginx/sites-available/cryptobot-db /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## Troubleshooting Ubuntu-Specific Issues

### Node.js not found
```bash
# Check Node.js version
node --version
npm --version

# If not installed, use NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
```

### MySQL connection refused
```bash
# Check MySQL is running
sudo systemctl status mysql

# Start MySQL if stopped
sudo systemctl start mysql

# Check MySQL is listening
sudo netstat -tlnp | grep 3306
```

### Permission denied errors
```bash
# Make sure user has permissions
sudo chown -R $USER:$USER /path/to/Database Server

# Make scripts executable
chmod +x start.sh
```

### Port already in use
```bash
# Check what's using the port
sudo lsof -i :3000
sudo lsof -i :3001

# Kill the process if needed (replace PID with actual process ID)
sudo kill -9 PID
```

## Performance Optimization for Ubuntu

### Increase MySQL connection limits

Edit `/etc/mysql/mysql.conf.d/mysqld.cnf`:

```ini
max_connections = 200
innodb_buffer_pool_size = 1G
```

Restart MySQL:
```bash
sudo systemctl restart mysql
```

### Use PM2 for Process Management (Alternative to systemd)

```bash
# Install PM2 globally
sudo npm install -g pm2

# Start server with PM2
pm2 start server.js --name cryptobot-db

# Save PM2 configuration
pm2 save

# Setup PM2 to start on boot
pm2 startup
```

## Security Best Practices

1. **Use a non-root MySQL user** (as shown above)
2. **Configure firewall** to only allow necessary ports
3. **Use SSL/TLS** for production (configure in Nginx)
4. **Regular backups** of MySQL database
5. **Keep Node.js and dependencies updated**
6. **Monitor logs** regularly

```bash
# Backup database
mysqldump -u cryptobot -p CryptoBot > backup_$(date +%Y%m%d).sql

# Restore database
mysql -u cryptobot -p CryptoBot < backup_YYYYMMDD.sql
```

