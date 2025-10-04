const { v4: uuidv4 } = require('uuid');
const { logger } = require('../utils/logger');

class HostManager {
    constructor() {
        this.activeHost = null;
        this.hosts = new Map(); // leaseId -> host info
        this.leaseTTL = parseInt(process.env.HOST_LEASE_TTL_MS) || 45000;
        
        // Start cleanup interval
        this.cleanupInterval = setInterval(() => {
            this.cleanupExpiredLeases();
        }, 5000);
    }

    /**
     * Attempt to register a new host
     * @param {string} token - Host authentication token
     * @param {string} endpoint - Optional host endpoint info
     * @returns {Object} Registration result
     */
    offerHost(token, endpoint = null) {
        if (token !== process.env.HOST_PC_TOKEN) {
            return { accepted: false, error: 'Invalid token' };
        }

        // Check if there's already an active host
        if (this.activeHost && this.isHostActive(this.activeHost.leaseId)) {
            return { 
                accepted: false, 
                error: 'Host already active',
                code: 'ALREADY_ACTIVE'
            };
        }

        // Create new lease
        const leaseId = uuidv4();
        const host = {
            leaseId,
            token,
            endpoint,
            createdAt: Date.now(),
            lastHeartbeat: Date.now(),
            ready: false,
            serverRunning: false,
            websocket: null,
            connections: 0
        };

        this.hosts.set(leaseId, host);
        this.activeHost = host;

        logger.info(`Host registered with lease ${leaseId}`);

        return {
            accepted: true,
            leaseId,
            ttl: this.leaseTTL,
            proxyPort: parseInt(process.env.PROXY_TCP_PORT) || 25565
        };
    }

    /**
     * Update host heartbeat and status
     * @param {string} token - Host token
     * @param {string} leaseId - Host lease ID
     * @param {boolean} ready - Host ready status
     * @param {boolean} serverRunning - Minecraft server status
     * @returns {Object} Heartbeat result
     */
    heartbeat(token, leaseId, ready = false, serverRunning = false) {
        if (token !== process.env.HOST_PC_TOKEN) {
            return { ok: false, error: 'Invalid token' };
        }

        const host = this.hosts.get(leaseId);
        if (!host) {
            return { ok: false, error: 'Invalid leaseId' };
        }

        // Update host status
        host.lastHeartbeat = Date.now();
        host.ready = ready;
        host.serverRunning = serverRunning;

        logger.debug(`Heartbeat from ${leaseId}: ready=${ready}, serverRunning=${serverRunning}`);

        return {
            ok: true,
            proxyStarted: this.activeHost && this.activeHost.leaseId === leaseId
        };
    }

    /**
     * End host lease
     * @param {string} token - Host token
     * @returns {Object} End result
     */
    endHost(token) {
        if (token !== process.env.HOST_PC_TOKEN) {
            return { success: false, error: 'Invalid token' };
        }

        if (this.activeHost) {
            const leaseId = this.activeHost.leaseId;
            
            // Close WebSocket if connected
            if (this.activeHost.websocket) {
                this.activeHost.websocket.close(1000, 'Host ended lease');
            }
            
            this.hosts.delete(leaseId);
            this.activeHost = null;
            
            logger.info(`Host lease ended: ${leaseId}`);
        }

        return { success: true };
    }

    /**
     * Attach WebSocket to host
     * @param {string} leaseId - Host lease ID
     * @param {WebSocket} ws - WebSocket connection
     */
    attachWebSocket(leaseId, ws) {
        const host = this.hosts.get(leaseId);
        if (host) {
            host.websocket = ws;
            host.lastHeartbeat = Date.now();
        }
    }

    /**
     * Detach WebSocket from host
     * @param {string} leaseId - Host lease ID
     */
    detachWebSocket(leaseId) {
        const host = this.hosts.get(leaseId);
        if (host) {
            host.websocket = null;
        }
    }

    /**
     * Update heartbeat timestamp
     * @param {string} leaseId - Host lease ID
     */
    updateHeartbeat(leaseId) {
        const host = this.hosts.get(leaseId);
        if (host) {
            host.lastHeartbeat = Date.now();
        }
    }

    /**
     * Send message to active host
     * @param {Object} message - Message to send
     * @returns {boolean} Success status
     */
    sendToActiveHost(message) {
        if (!this.activeHost || !this.activeHost.websocket) {
            return false;
        }

        try {
            this.activeHost.websocket.send(JSON.stringify(message));
            return true;
        } catch (error) {
            logger.error('Error sending message to host:', error);
            return false;
        }
    }

    /**
     * Get host by lease ID
     * @param {string} leaseId - Host lease ID
     * @returns {Object|null} Host object or null
     */
    getHostByLeaseId(leaseId) {
        return this.hosts.get(leaseId) || null;
    }

    /**
     * Check if host is active (within TTL)
     * @param {string} leaseId - Host lease ID
     * @returns {boolean} Active status
     */
    isHostActive(leaseId) {
        const host = this.hosts.get(leaseId);
        if (!host) return false;
        
        const now = Date.now();
        return (now - host.lastHeartbeat) < this.leaseTTL;
    }

    /**
     * Get current system status
     * @returns {Object} System status
     */
    getStatus() {
        const now = Date.now();
        let activeHostInfo = null;

        if (this.activeHost && this.isHostActive(this.activeHost.leaseId)) {
            const timeLeft = this.leaseTTL - (now - this.activeHost.lastHeartbeat);
            activeHostInfo = {
                leaseId: this.activeHost.leaseId,
                ready: this.activeHost.ready,
                serverRunning: this.activeHost.serverRunning,
                connected: !!this.activeHost.websocket,
                connections: this.activeHost.connections,
                timeLeft: Math.max(0, timeLeft),
                endpoint: this.activeHost.endpoint
            };
        }

        return {
            hasActiveHost: !!activeHostInfo,
            activeHost: activeHostInfo,
            totalHosts: this.hosts.size,
            leaseTTL: this.leaseTTL,
            uptime: process.uptime()
        };
    }

    /**
     * Increment connection count for active host
     */
    incrementConnections() {
        if (this.activeHost) {
            this.activeHost.connections++;
        }
    }

    /**
     * Decrement connection count for active host
     */
    decrementConnections() {
        if (this.activeHost && this.activeHost.connections > 0) {
            this.activeHost.connections--;
        }
    }

    /**
     * Clean up expired leases
     */
    cleanupExpiredLeases() {
        const now = Date.now();
        const expiredLeases = [];

        for (const [leaseId, host] of this.hosts) {
            if ((now - host.lastHeartbeat) > this.leaseTTL) {
                expiredLeases.push(leaseId);
            }
        }

        for (const leaseId of expiredLeases) {
            const host = this.hosts.get(leaseId);
            if (host) {
                if (host.websocket) {
                    host.websocket.close(1000, 'Lease expired');
                }
                this.hosts.delete(leaseId);
                
                if (this.activeHost && this.activeHost.leaseId === leaseId) {
                    this.activeHost = null;
                }
                
                logger.info(`Expired lease cleaned up: ${leaseId}`);
            }
        }
    }

    /**
     * Cleanup resources
     */
    destroy() {
        if (this.cleanupInterval) {
            clearInterval(this.cleanupInterval);
        }
        
        // Close all WebSocket connections
        for (const host of this.hosts.values()) {
            if (host.websocket) {
                host.websocket.close(1000, 'Server shutdown');
            }
        }
        
        this.hosts.clear();
        this.activeHost = null;
    }
}

module.exports = HostManager;