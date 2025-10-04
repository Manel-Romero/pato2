const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const net = require('net');
const path = require('path');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
require('dotenv').config();

const HostManager = require('./managers/HostManager');
const ProxyManager = require('./managers/ProxyManager');
const apiRoutes = require('./routes/api');
const webRoutes = require('./routes/web');
const { logger } = require('./utils/logger');

class Pato2Server {
    constructor() {
        this.app = express();
        this.server = http.createServer(this.app);
        this.wss = new WebSocket.Server({ server: this.server });
        
        this.hostManager = new HostManager();
        this.proxyManager = new ProxyManager(this.hostManager);
        
        this.setupMiddleware();
        this.setupRoutes();
        this.setupWebSocket();
        this.setupTCPProxy();
        this.setupGracefulShutdown();
    }

    setupMiddleware() {
        // Security and performance middleware
        this.app.use(helmet({
            contentSecurityPolicy: {
                directives: {
                    defaultSrc: ["'self'"],
                    styleSrc: ["'self'", "'unsafe-inline'"],
                    scriptSrc: ["'self'"],
                    imgSrc: ["'self'", "data:", "https:"],
                }
            }
        }));
        this.app.use(compression());
        this.app.use(cors());
        this.app.use(morgan('combined', { stream: { write: msg => logger.info(msg.trim()) } }));
        this.app.use(express.json({ limit: '10mb' }));
        this.app.use(express.urlencoded({ extended: true }));
        
        // Static files
        this.app.use(express.static(path.join(__dirname, '../public')));
    }

    setupRoutes() {
        // API routes
        this.app.use('/api', apiRoutes(this.hostManager, this.proxyManager));
        
        // Web interface routes
        this.app.use('/', webRoutes(this.hostManager, this.proxyManager));
        
        // 404 handler
        this.app.use('*', (req, res) => {
            res.status(404).json({ error: 'Endpoint not found' });
        });
        
        // Error handler
        this.app.use((err, req, res, next) => {
            logger.error('Unhandled error:', err);
            res.status(500).json({ error: 'Internal server error' });
        });
    }

    setupWebSocket() {
        this.wss.on('connection', (ws, req) => {
            const url = new URL(req.url, `http://${req.headers.host}`);
            const pathname = url.pathname;
            
            if (pathname === '/ws/host') {
                this.handleHostWebSocket(ws, url);
            } else {
                ws.close(1000, 'Invalid WebSocket endpoint');
            }
        });
    }

    handleHostWebSocket(ws, url) {
        const token = url.searchParams.get('token');
        const leaseId = url.searchParams.get('leaseId');
        
        if (!token || !leaseId) {
            ws.close(1008, 'Missing token or leaseId');
            return;
        }
        
        if (token !== process.env.HOST_PC_TOKEN) {
            ws.close(1008, 'Invalid token');
            return;
        }
        
        const host = this.hostManager.getHostByLeaseId(leaseId);
        if (!host) {
            ws.close(1008, 'Invalid leaseId');
            return;
        }
        
        // Attach WebSocket to host
        this.hostManager.attachWebSocket(leaseId, ws);
        logger.info(`Host WebSocket connected: ${leaseId}`);
        
        ws.on('message', (data) => {
            try {
                const message = JSON.parse(data);
                this.handleHostMessage(leaseId, message);
            } catch (error) {
                logger.error('Invalid WebSocket message:', error);
            }
        });
        
        ws.on('close', () => {
            logger.info(`Host WebSocket disconnected: ${leaseId}`);
            this.hostManager.detachWebSocket(leaseId);
        });
        
        ws.on('error', (error) => {
            logger.error(`Host WebSocket error for ${leaseId}:`, error);
        });
        
        // Send ping every 30 seconds
        const pingInterval = setInterval(() => {
            if (ws.readyState === WebSocket.OPEN) {
                ws.ping();
            } else {
                clearInterval(pingInterval);
            }
        }, 30000);
    }

    handleHostMessage(leaseId, message) {
        const { type, streamId, data } = message;
        
        switch (type) {
            case 'pong':
                this.hostManager.updateHeartbeat(leaseId);
                break;
            case 'data':
                this.proxyManager.handleHostData(streamId, data);
                break;
            case 'close':
                this.proxyManager.handleHostClose(streamId);
                break;
            case 'error':
                this.proxyManager.handleHostError(streamId, data);
                break;
            default:
                logger.warn(`Unknown message type from host ${leaseId}: ${type}`);
        }
    }

    setupTCPProxy() {
        const proxyPort = parseInt(process.env.PROXY_TCP_PORT) || 25565;
        
        this.proxyServer = net.createServer((clientSocket) => {
            this.proxyManager.handleClientConnection(clientSocket);
        });
        
        this.proxyServer.listen(proxyPort, () => {
            logger.info(`TCP Proxy listening on port ${proxyPort}`);
        });
        
        this.proxyServer.on('error', (error) => {
            logger.error('TCP Proxy error:', error);
        });
    }

    setupGracefulShutdown() {
        const shutdown = (signal) => {
            logger.info(`Received ${signal}, shutting down gracefully...`);
            
            // Close proxy server
            if (this.proxyServer) {
                this.proxyServer.close();
            }
            
            // Close WebSocket server
            this.wss.close();
            
            // Close HTTP server
            this.server.close(() => {
                logger.info('Server closed');
                process.exit(0);
            });
            
            // Force exit after 10 seconds
            setTimeout(() => {
                logger.error('Forced shutdown');
                process.exit(1);
            }, 10000);
        };
        
        process.on('SIGTERM', () => shutdown('SIGTERM'));
        process.on('SIGINT', () => shutdown('SIGINT'));
    }

    start() {
        const port = parseInt(process.env.PORT) || 5000;
        
        this.server.listen(port, () => {
            logger.info(`Pato2 Server started on port ${port}`);
            logger.info(`Domain: ${process.env.DOMAIN || 'localhost'}`);
            logger.info(`TCP Proxy: ${process.env.PROXY_TCP_PORT || 25565}`);
        });
    }
}

// Start server if this file is run directly
if (require.main === module) {
    const server = new Pato2Server();
    server.start();
}

module.exports = Pato2Server;