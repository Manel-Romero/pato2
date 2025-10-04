const express = require('express');
const { logger } = require('../utils/logger');

function createApiRoutes(hostManager, proxyManager) {
    const router = express.Router();

    // Middleware for API logging
    router.use((req, res, next) => {
        logger.debug(`API ${req.method} ${req.path}`, { 
            body: req.body, 
            query: req.query,
            ip: req.ip 
        });
        next();
    });

    /**
     * POST /api/host/offer
     * Host offers to become the active server
     */
    router.post('/host/offer', (req, res) => {
        try {
            const { token, endpoint } = req.body;

            if (!token) {
                return res.status(400).json({ 
                    accepted: false, 
                    error: 'Token is required' 
                });
            }

            const result = hostManager.offerHost(token, endpoint);
            
            if (!result.accepted) {
                const statusCode = result.code === 'ALREADY_ACTIVE' ? 409 : 401;
                return res.status(statusCode).json(result);
            }

            logger.info(`Host offer accepted: ${result.leaseId}`);
            res.json(result);
        } catch (error) {
            logger.error('Error in /api/host/offer:', error);
            res.status(500).json({ 
                accepted: false, 
                error: 'Internal server error' 
            });
        }
    });

    /**
     * POST /api/host/heartbeat
     * Host sends heartbeat to maintain lease
     */
    router.post('/host/heartbeat', (req, res) => {
        try {
            const { token, leaseId, ready, serverRunning } = req.body;

            if (!token || !leaseId) {
                return res.status(400).json({ 
                    ok: false, 
                    error: 'Token and leaseId are required' 
                });
            }

            const result = hostManager.heartbeat(
                token, 
                leaseId, 
                Boolean(ready), 
                Boolean(serverRunning)
            );

            if (!result.ok) {
                return res.status(401).json(result);
            }

            res.json(result);
        } catch (error) {
            logger.error('Error in /api/host/heartbeat:', error);
            res.status(500).json({ 
                ok: false, 
                error: 'Internal server error' 
            });
        }
    });

    /**
     * POST /api/host/end
     * Host ends its lease
     */
    router.post('/host/end', (req, res) => {
        try {
            const { token } = req.body;

            if (!token) {
                return res.status(400).json({ 
                    success: false, 
                    error: 'Token is required' 
                });
            }

            const result = hostManager.endHost(token);
            
            if (!result.success) {
                return res.status(401).json(result);
            }

            logger.info('Host ended lease');
            res.json(result);
        } catch (error) {
            logger.error('Error in /api/host/end:', error);
            res.status(500).json({ 
                success: false, 
                error: 'Internal server error' 
            });
        }
    });

    /**
     * GET /api/status
     * Get system status
     */
    router.get('/status', (req, res) => {
        try {
            const hostStatus = hostManager.getStatus();
            const proxyStats = proxyManager.getStats();
            
            const status = {
                system: {
                    uptime: process.uptime(),
                    memory: process.memoryUsage(),
                    version: process.version,
                    platform: process.platform
                },
                host: hostStatus,
                proxy: {
                    ready: proxyManager.isReady(),
                    port: parseInt(process.env.PROXY_TCP_PORT) || 25565,
                    stats: proxyStats
                },
                timestamp: new Date().toISOString()
            };

            res.json(status);
        } catch (error) {
            logger.error('Error in /api/status:', error);
            res.status(500).json({ 
                error: 'Internal server error' 
            });
        }
    });

    /**
     * GET /api/proxy/status
     * Get detailed proxy statistics
     */
    router.get('/proxy/status', (req, res) => {
        try {
            const stats = proxyManager.getStats();
            res.json(stats);
        } catch (error) {
            logger.error('Error in /api/proxy/status:', error);
            res.status(500).json({ 
                error: 'Internal server error' 
            });
        }
    });

    /**
     * POST /api/proxy/reset-stats
     * Reset proxy statistics (admin only)
     */
    router.post('/proxy/reset-stats', (req, res) => {
        try {
            const { token } = req.body;
            
            if (token !== process.env.HOST_PC_TOKEN) {
                return res.status(401).json({ 
                    success: false, 
                    error: 'Unauthorized' 
                });
            }

            proxyManager.resetStats();
            logger.info('Proxy statistics reset');
            
            res.json({ success: true });
        } catch (error) {
            logger.error('Error in /api/proxy/reset-stats:', error);
            res.status(500).json({ 
                success: false, 
                error: 'Internal server error' 
            });
        }
    });

    /**
     * POST /api/host/backup-command
     * Send backup command to active host
     */
    router.post('/host/backup-command', (req, res) => {
        try {
            const { token, command } = req.body;
            
            if (token !== process.env.HOST_PC_TOKEN) {
                return res.status(401).json({ 
                    success: false, 
                    error: 'Unauthorized' 
                });
            }

            const status = hostManager.getStatus();
            if (!status.hasActiveHost || !status.activeHost.connected) {
                return res.status(404).json({ 
                    success: false, 
                    error: 'No active host connected' 
                });
            }

            const message = {
                type: 'backup_command',
                command: command || 'backup_now'
            };

            const sent = hostManager.sendToActiveHost(message);
            
            if (!sent) {
                return res.status(500).json({ 
                    success: false, 
                    error: 'Failed to send command to host' 
                });
            }

            logger.info(`Backup command sent to host: ${command}`);
            res.json({ success: true });
        } catch (error) {
            logger.error('Error in /api/host/backup-command:', error);
            res.status(500).json({ 
                success: false, 
                error: 'Internal server error' 
            });
        }
    });

    /**
     * GET /api/health
     * Health check endpoint
     */
    router.get('/health', (req, res) => {
        res.json({ 
            status: 'ok', 
            timestamp: new Date().toISOString(),
            uptime: process.uptime()
        });
    });

    // Error handler for API routes
    router.use((error, req, res, next) => {
        logger.error('API Error:', error);
        res.status(500).json({ 
            error: 'Internal server error',
            timestamp: new Date().toISOString()
        });
    });

    return router;
}

module.exports = createApiRoutes;