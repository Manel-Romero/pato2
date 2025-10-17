const { v4: uuidv4 } = require('uuid');
const { logger } = require('../utils/logger');

class ProxyManager {
    constructor(hostManager) {
        this.hostManager = hostManager;
        this.activeConnections = new Map(); // streamId -> connection info
        this.clientSockets = new Map(); // streamId -> client socket
        this.stats = {
            totalConnections: 0,
            activeConnections: 0,
            bytesTransferred: 0,
            errors: 0
        };
    }

    /**
     * Handle new client connection to the proxy
     * @param {net.Socket} clientSocket - Client TCP socket
     * @param {number} listenPort - Proxy listening port that accepted the connection
     */
    handleClientConnection(clientSocket, listenPort) {
        const streamId = uuidv4();
        const clientAddress = `${clientSocket.remoteAddress}:${clientSocket.remotePort}`;
        
        logger.info(`New client connection: ${clientAddress} (stream: ${streamId})`);

        // Attach basic error handler immediately to prevent unhandled errors
        clientSocket.on('error', (error) => {
            logger.error(`Client socket error ${clientAddress} (stream: ${streamId}):`, error);
            try {
                clientSocket.destroy();
            } catch (e) {
                // ignore
            }
            this.stats.errors++;
        });
        
        // Check if we have an active host
        const status = this.hostManager.getStatus();
        if (!status.hasActiveHost || !status.activeHost.ready || !status.activeHost.connected) {
            logger.warn(`Rejecting connection ${streamId}: No active host available`);
            clientSocket.write(Buffer.from('§cServidor no disponible. Intenta más tarde.\n'));
            clientSocket.end();
            return;
        }

        // Store client socket
        this.clientSockets.set(streamId, clientSocket);
        this.activeConnections.set(streamId, {
            streamId,
            clientAddress,
            startTime: Date.now(),
            bytesFromClient: 0,
            bytesToClient: 0
        });

        // Update stats
        this.stats.totalConnections++;
        this.stats.activeConnections++;
        this.hostManager.incrementConnections();

        // Send open message to host
        const openMessage = {
            type: 'open',
            streamId,
            clientAddress,
            targetPort: listenPort
        };

        if (!this.hostManager.sendToActiveHost(openMessage)) {
            logger.error(`Failed to send open message for stream ${streamId}`);
            this.closeClientConnection(streamId, 'Host communication failed');
            return;
        }

        // Set up client socket handlers
        this.setupClientSocketHandlers(streamId, clientSocket);
    }

    /**
     * Set up event handlers for client socket
     * @param {string} streamId - Stream identifier
     * @param {net.Socket} clientSocket - Client socket
     */
    setupClientSocketHandlers(streamId, clientSocket) {
        clientSocket.on('data', (data) => {
            this.handleClientData(streamId, data);
        });

        clientSocket.on('close', () => {
            logger.debug(`Client disconnected: ${streamId}`);
            this.closeClientConnection(streamId, 'Client disconnected');
        });

        clientSocket.on('error', (error) => {
            logger.error(`Client socket error for ${streamId}:`, error);
            this.closeClientConnection(streamId, 'Client socket error');
        });

        // Set timeout for idle connections
        clientSocket.setTimeout(300000, () => { // 5 minutes
            logger.warn(`Client connection timeout: ${streamId}`);
            this.closeClientConnection(streamId, 'Connection timeout');
        });
    }

    /**
     * Handle data from client
     * @param {string} streamId - Stream identifier
     * @param {Buffer} data - Data from client
     */
    handleClientData(streamId, data) {
        const connection = this.activeConnections.get(streamId);
        if (!connection) {
            logger.warn(`Received data for unknown stream: ${streamId}`);
            return;
        }

        // Update stats
        connection.bytesFromClient += data.length;
        this.stats.bytesTransferred += data.length;

        // Send data to host
        const dataMessage = {
            type: 'data',
            streamId,
            data: data.toString('base64')
        };

        if (!this.hostManager.sendToActiveHost(dataMessage)) {
            logger.error(`Failed to send data for stream ${streamId}`);
            this.closeClientConnection(streamId, 'Host communication failed');
        }
    }

    /**
     * Handle data from host
     * @param {string} streamId - Stream identifier
     * @param {string} base64Data - Base64 encoded data from host
     */
    handleHostData(streamId, base64Data) {
        const clientSocket = this.clientSockets.get(streamId);
        const connection = this.activeConnections.get(streamId);
        
        if (!clientSocket || !connection) {
            logger.warn(`Received host data for unknown stream: ${streamId}`);
            return;
        }

        try {
            const data = Buffer.from(base64Data, 'base64');
            
            // Update stats
            connection.bytesToClient += data.length;
            this.stats.bytesTransferred += data.length;
            
            // Send to client
            clientSocket.write(data);
        } catch (error) {
            logger.error(`Error handling host data for ${streamId}:`, error);
            this.closeClientConnection(streamId, 'Data processing error');
        }
    }

    /**
     * Handle close message from host
     * @param {string} streamId - Stream identifier
     */
    handleHostClose(streamId) {
        logger.debug(`Host closed stream: ${streamId}`);
        this.closeClientConnection(streamId, 'Host closed connection');
    }

    /**
     * Handle error message from host
     * @param {string} streamId - Stream identifier
     * @param {string} error - Error message
     */
    handleHostError(streamId, error) {
        logger.error(`Host error for stream ${streamId}: ${error}`);
        this.closeClientConnection(streamId, 'Host error');
    }

    /**
     * Close client connection and clean up
     * @param {string} streamId - Stream identifier
     * @param {string} reason - Reason for closing
     */
    closeClientConnection(streamId, reason = 'Unknown') {
        const clientSocket = this.clientSockets.get(streamId);
        const connection = this.activeConnections.get(streamId);

        if (connection) {
            const duration = Date.now() - connection.startTime;
            logger.debug(`Closing connection ${streamId}: ${reason} (duration: ${duration}ms, bytes: ${connection.bytesFromClient}↑/${connection.bytesToClient}↓)`);
        }

        // Close client socket
        if (clientSocket && !clientSocket.destroyed) {
            clientSocket.destroy();
        }

        // Send close message to host
        if (connection) {
            const closeMessage = {
                type: 'close',
                streamId
            };
            this.hostManager.sendToActiveHost(closeMessage);
        }

        // Clean up
        this.clientSockets.delete(streamId);
        this.activeConnections.delete(streamId);
        
        if (connection) {
            this.stats.activeConnections--;
            this.hostManager.decrementConnections();
        }
    }

    /**
     * Close all active connections
     * @param {string} reason - Reason for closing all connections
     */
    closeAllConnections(reason = 'Server shutdown') {
        logger.info(`Closing all connections: ${reason}`);
        
        const streamIds = Array.from(this.activeConnections.keys());
        for (const streamId of streamIds) {
            this.closeClientConnection(streamId, reason);
        }
    }

    /**
     * Get proxy statistics
     * @returns {Object} Proxy statistics
     */
    getStats() {
        const connections = Array.from(this.activeConnections.values()).map(conn => ({
            streamId: conn.streamId,
            clientAddress: conn.clientAddress,
            duration: Date.now() - conn.startTime,
            bytesFromClient: conn.bytesFromClient,
            bytesToClient: conn.bytesToClient
        }));

        return {
            ...this.stats,
            connections,
            uptime: process.uptime()
        };
    }

    /**
     * Reset statistics
     */
    resetStats() {
        this.stats = {
            totalConnections: 0,
            activeConnections: this.stats.activeConnections, // Keep active count
            bytesTransferred: 0,
            errors: 0
        };
    }

    /**
     * Handle host disconnection
     */
    handleHostDisconnection() {
        logger.warn('Host disconnected, closing all client connections');
        this.closeAllConnections('Host disconnected');
        this.stats.errors++;
    }

    /**
     * Get connection by stream ID
     * @param {string} streamId - Stream identifier
     * @returns {Object|null} Connection info or null
     */
    getConnection(streamId) {
        return this.activeConnections.get(streamId) || null;
    }

    /**
     * Check if proxy is ready to accept connections
     * @returns {boolean} Ready status
     */
    isReady() {
        const status = this.hostManager.getStatus();
        return status.hasActiveHost && 
               status.activeHost.ready && 
               status.activeHost.serverRunning && 
               status.activeHost.connected;
    }

    /**
     * Cleanup resources
     */
    destroy() {
        this.closeAllConnections('Proxy manager destroyed');
    }
}

module.exports = ProxyManager;