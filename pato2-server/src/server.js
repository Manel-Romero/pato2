const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const net = require('net');
const dgram = require('dgram');
const { v4: uuidv4 } = require('uuid');
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
        this.udpServers = [];
        this.udpServersByPort = new Map();
        this.udpSessions = new Map();
        this.udpRemoteKeyToClientId = new Map();
        
        this.setupMiddleware();
        this.setupRoutes();
        this.setupWebSocket();
        this.setupTCPProxy();
        this.setupUDPProxy();
        this.setupGracefulShutdown();
    }

    setupMiddleware() {
        // Security and performance middleware
        this.app.use(helmet({
            contentSecurityPolicy: {
                directives: {
                    defaultSrc: ["'self'"],
                    // Permitir Bootstrap y Font Awesome desde CDN
                    styleSrc: [
                        "'self'",
                        "'unsafe-inline'",
                        "https://cdn.jsdelivr.net",
                        "https://cdnjs.cloudflare.com"
                    ],
                    scriptSrc: [
                        "'self'",
                        "https://cdn.jsdelivr.net"
                    ],
                    imgSrc: ["'self'", "data:", "https:"],
                    fontSrc: [
                        "'self'",
                        "data:",
                        "https://cdnjs.cloudflare.com",
                        "https://cdn.jsdelivr.net"
                    ]
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
            case 'udp_data': {
                const { clientId } = message;
                const session = this.udpSessions.get(clientId);
                if (!session) break;
                const udpServer = this.udpServersByPort.get(session.listenPort);
                if (!udpServer) break;
                try {
                    const buf = Buffer.from(data, 'base64');
                    udpServer.send(buf, session.remotePort, session.remoteAddress);
                    session.lastSeen = Date.now();
                } catch (err) {
                    logger.error(`UDP send error for client ${clientId}:`, err);
                }
                break;
            }
            case 'udp_close': {
                const { clientId } = message;
                const session = this.udpSessions.get(clientId);
                if (!session) break;
                const remoteKey = `${session.listenPort}:${session.remoteAddress}:${session.remotePort}`;
                this.udpSessions.delete(clientId);
                this.udpRemoteKeyToClientId.delete(remoteKey);
                break;
            }
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
        const portsEnv = process.env.PROXY_TCP_PORTS || process.env.PROXY_TCP_PORT || '25565';
        const proxyPorts = portsEnv
            .split(',')
            .map(p => parseInt(p.trim()))
            .filter(n => !isNaN(n));

        this.proxyServers = [];

        proxyPorts.forEach((proxyPort) => {
            const server = net.createServer((clientSocket) => {
                this.proxyManager.handleClientConnection(clientSocket, proxyPort);
            });

            server.listen(proxyPort, () => {
                logger.info(`TCP Proxy listening on port ${proxyPort}`);
            });

            server.on('error', (error) => {
                logger.error(`TCP Proxy error on port ${proxyPort}:`, error);
            });

            this.proxyServers.push(server);
        });
    }

    setupUDPProxy() {
        const udpPortsEnv = process.env.PROXY_UDP_PORTS || '';
        const udpPorts = udpPortsEnv
            .split(',')
            .map(p => parseInt(p.trim()))
            .filter(n => !isNaN(n));

        udpPorts.forEach((proxyPort) => {
            const udpServer = dgram.createSocket('udp4');

            udpServer.on('error', (error) => {
                logger.error(`UDP Proxy error on port ${proxyPort}:`, error);
            });

            udpServer.on('message', (msg, rinfo) => {
                const remoteKey = `${proxyPort}:${rinfo.address}:${rinfo.port}`;
                let clientId = this.udpRemoteKeyToClientId.get(remoteKey);
                if (!clientId) {
                    clientId = uuidv4();
                    this.udpRemoteKeyToClientId.set(remoteKey, clientId);
                    this.udpSessions.set(clientId, {
                        listenPort: proxyPort,
                        remoteAddress: rinfo.address,
                        remotePort: rinfo.port,
                        lastSeen: Date.now(),
                    });
                    this.hostManager.sendToActiveHost({
                        type: 'udp_open',
                        clientId,
                        targetPort: proxyPort,
                    });
                }

                const session = this.udpSessions.get(clientId);
                if (session) session.lastSeen = Date.now();

                const dataB64 = msg.toString('base64');
                this.hostManager.sendToActiveHost({
                    type: 'udp_data',
                    clientId,
                    data: dataB64,
                });
            });

            udpServer.on('listening', () => {
                const address = udpServer.address();
                logger.info(`UDP Proxy listening on ${address.address}:${address.port}`);
            });

            udpServer.bind(proxyPort, '0.0.0.0');
            this.udpServers.push(udpServer);
            this.udpServersByPort.set(proxyPort, udpServer);
        });

        if (udpPorts.length > 0) {
            const ttlMs = parseInt(process.env.UDP_SESSION_TTL_MS || '120000');
            setInterval(() => {
                const now = Date.now();
                for (const [clientId, session] of this.udpSessions.entries()) {
                    if (now - session.lastSeen > ttlMs) {
                        this.hostManager.sendToActiveHost({ type: 'udp_close', clientId });
                        const remoteKey = `${session.listenPort}:${session.remoteAddress}:${session.remotePort}`;
                        this.udpSessions.delete(clientId);
                        this.udpRemoteKeyToClientId.delete(remoteKey);
                    }
                }
            }, Math.max(5000, Math.floor(ttlMs / 2)));
        }
    }

    setupGracefulShutdown() {
        const shutdown = (signal) => {
            logger.info(`Received ${signal}, shutting down gracefully...`);
            
            // Close proxy servers
            if (this.proxyServers && this.proxyServers.length) {
                this.proxyServers.forEach(s => {
                    try { s.close(); } catch (e) { /* ignore */ }
                });
            }
            if (this.udpServers && this.udpServers.length) {
                this.udpServers.forEach(s => {
                    try { s.close(); } catch (e) { /* ignore */ }
                });
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

            const portsEnv = process.env.PROXY_TCP_PORTS || process.env.PROXY_TCP_PORT || '25565';
            const portsStr = portsEnv
                .split(',')
                .map(p => p.trim())
                .join(', ');
            logger.info(`TCP Proxy: ${portsStr}`);

            const udpPortsEnv = process.env.PROXY_UDP_PORTS || '';
            const udpStr = udpPortsEnv
                .split(',')
                .map(p => p.trim())
                .filter(p => p.length > 0)
                .join(', ');
            if (udpStr.length > 0) {
                logger.info(`UDP Proxy: ${udpStr}`);
            }
        });
    }
}

// Start server if this file is run directly
if (require.main === module) {
    const server = new Pato2Server();
    server.start();
}

module.exports = Pato2Server;