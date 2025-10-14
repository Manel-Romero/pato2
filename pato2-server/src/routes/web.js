const express = require('express');
const path = require('path');
const { logger } = require('../utils/logger');

function createWebRoutes(hostManager, proxyManager) {
    const router = express.Router();

    /**
     * GET /
     * Main dashboard
     */
    router.get('/', (req, res) => {
        try {
            const hostStatus = hostManager.getStatus();
            const proxyStats = proxyManager.getStats();
            
            const data = {
                title: 'Pato2 - Dashboard',
                domain: process.env.DOMAIN || 'localhost',
                proxyPort: parseInt(process.env.PROXY_TCP_PORT) || 25565,
                webPort: parseInt(process.env.PORT) || 5000,
                host: hostStatus,
                proxy: {
                    ready: proxyManager.isReady(),
                    stats: proxyStats
                },
                timestamp: new Date().toISOString()
            };

            res.send(generateDashboardHTML(data));
        } catch (error) {
            logger.error('Error in dashboard route:', error);
            res.status(500).send('Internal server error');
        }
    });

    /**
     * GET /status
     * Status page (JSON or HTML based on Accept header)
     */
    router.get('/status', (req, res) => {
        try {
            const hostStatus = hostManager.getStatus();
            const proxyStats = proxyManager.getStats();
            
            const data = {
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

            // Return JSON if requested
            if (req.headers.accept && req.headers.accept.includes('application/json')) {
                return res.json(data);
            }

            // Return HTML page
            res.send(generateStatusHTML(data));
        } catch (error) {
            logger.error('Error in status route:', error);
            res.status(500).send('Internal server error');
        }
    });

    /**
     * GET /connections
     * Live connections page
     */
    router.get('/connections', (req, res) => {
        try {
            const proxyStats = proxyManager.getStats();
            const hostStatus = hostManager.getStatus();
            
            const data = {
                title: 'Pato2 - Conexiones Activas',
                host: hostStatus,
                proxy: proxyStats,
                timestamp: new Date().toISOString()
            };

            res.send(generateConnectionsHTML(data));
        } catch (error) {
            logger.error('Error in connections route:', error);
            res.status(500).send('Internal server error');
        }
    });

    return router;
}

/**
 * Generate main dashboard HTML
 */
function generateDashboardHTML(data) {
    const hostStatusBadge = data.host.hasActiveHost 
        ? `<span class="badge badge-success">Activo</span>`
        : `<span class="badge badge-danger">Sin Host</span>`;
    
    const proxyStatusBadge = data.proxy.ready
        ? `<span class="badge badge-success">Listo</span>`
        : `<span class="badge badge-warning">No Disponible</span>`;

    return `
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${data.title}</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        .status-card { transition: all 0.3s ease; }
        .status-card:hover { transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0,0,0,0.1); }
        .badge { font-size: 0.8em; }
        .metric-value { font-size: 2rem; font-weight: bold; }
        .refresh-btn { position: fixed; bottom: 20px; right: 20px; }
    </style>
</head>
<body class="bg-light">
    <nav class="navbar navbar-dark bg-primary">
        <div class="container">
            <span class="navbar-brand mb-0 h1">
                <i class="fas fa-server"></i> Pato2 Dashboard
            </span>
            <span class="navbar-text">
                ${data.domain}:${data.proxyPort}
            </span>
        </div>
    </nav>

    <div class="container mt-4">
        <!-- Status Overview -->
        <div class="row mb-4">
            <div class="col-md-6">
                <div class="card status-card">
                    <div class="card-body">
                        <h5 class="card-title">
                            <i class="fas fa-desktop"></i> Estado del Host
                            ${hostStatusBadge}
                        </h5>
                        ${data.host.hasActiveHost ? `
                            <p class="card-text">
                                <strong>Lease ID:</strong> ${data.host.activeHost.leaseId.substring(0, 8)}...<br>
                                <strong>Servidor:</strong> ${data.host.activeHost.serverRunning ? 'Ejecutándose' : 'Detenido'}<br>
                                <strong>Conexiones:</strong> ${data.host.activeHost.connections}<br>
                                <strong>TTL:</strong> ${Math.round(data.host.activeHost.timeLeft / 1000)}s
                            </p>
                        ` : `
                            <p class="card-text text-muted">No hay host activo</p>
                        `}
                    </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="card status-card">
                    <div class="card-body">
                        <h5 class="card-title">
                            <i class="fas fa-network-wired"></i> Estado del Proxy
                            ${proxyStatusBadge}
                        </h5>
                        <p class="card-text">
                            <strong>Puerto:</strong> ${data.proxyPort}<br>
                            <strong>Conexiones Activas:</strong> ${data.proxy.stats.activeConnections}<br>
                            <strong>Total Conexiones:</strong> ${data.proxy.stats.totalConnections}<br>
                            <strong>Datos Transferidos:</strong> ${formatBytes(data.proxy.stats.bytesTransferred)}
                        </p>
                    </div>
                </div>
            </div>
        </div>

        <!-- Metrics -->
        <div class="row mb-4">
            <div class="col-md-3">
                <div class="card text-center status-card">
                    <div class="card-body">
                        <i class="fas fa-users fa-2x text-primary mb-2"></i>
                        <div class="metric-value text-primary">${data.proxy.stats.activeConnections}</div>
                        <small class="text-muted">Jugadores Conectados</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card text-center status-card">
                    <div class="card-body">
                        <i class="fas fa-clock fa-2x text-success mb-2"></i>
                        <div class="metric-value text-success">${formatUptime(data.proxy.stats.uptime)}</div>
                        <small class="text-muted">Tiempo Activo</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card text-center status-card">
                    <div class="card-body">
                        <i class="fas fa-exchange-alt fa-2x text-info mb-2"></i>
                        <div class="metric-value text-info">${formatBytes(data.proxy.stats.bytesTransferred)}</div>
                        <small class="text-muted">Datos Transferidos</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card text-center status-card">
                    <div class="card-body">
                        <i class="fas fa-exclamation-triangle fa-2x text-warning mb-2"></i>
                        <div class="metric-value text-warning">${data.proxy.stats.errors}</div>
                        <small class="text-muted">Errores</small>
                    </div>
                </div>
            </div>
        </div>

        <!-- Quick Actions -->
        <div class="row">
            <div class="col-12">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0"><i class="fas fa-tools"></i> Acciones Rápidas</h5>
                    </div>
                    <div class="card-body">
                        <a href="http://${data.domain}:${data.webPort}/status" class="btn btn-outline-primary me-2">
                            <i class="fas fa-info-circle"></i> Estado Detallado
                        </a>
                        <a href="http://${data.domain}:${data.webPort}/connections" class="btn btn-outline-info me-2">
                            <i class="fas fa-list"></i> Ver Conexiones
                        </a>
                        <button onclick="triggerBackup()" class="btn btn-outline-warning me-2" ${!data.host.hasActiveHost ? 'disabled' : ''}>
                            <i class="fas fa-save"></i> Backup Manual
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <button class="btn btn-primary refresh-btn" onclick="location.reload()">
        <i class="fas fa-sync-alt"></i>
    </button>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }

        function formatUptime(seconds) {
            const hours = Math.floor(seconds / 3600);
            const minutes = Math.floor((seconds % 3600) / 60);
            return hours + 'h ' + minutes + 'm';
        }

        function triggerBackup() {
            if (confirm('¿Iniciar backup manual del servidor?')) {
                fetch('http://${data.domain}:${data.webPort}/api/host/backup-command', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ token: 'admin', command: 'backup_now' })
                })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        alert('Comando de backup enviado al host');
                    } else {
                        alert('Error: ' + data.error);
                    }
                })
                .catch(error => {
                    alert('Error de conexión: ' + error.message);
                });
            }
        }

        // Auto-refresh every 30 seconds
        setTimeout(() => location.reload(), 30000);
    </script>
</body>
</html>`;
}

/**
 * Generate status page HTML
 */
function generateStatusHTML(data) {
    return `
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pato2 - Estado del Sistema</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
</head>
<body class="bg-light">
    <nav class="navbar navbar-dark bg-primary">
        <div class="container">
            <a class="navbar-brand" href="http://${data.domain}:${data.webPort}/">
                <i class="fas fa-arrow-left"></i> Volver al Dashboard
            </a>
            <span class="navbar-text">Estado del Sistema</span>
        </div>
    </nav>

    <div class="container mt-4">
        <div class="row">
            <div class="col-12">
                <div class="card">
                    <div class="card-header">
                        <h5 class="mb-0">Estado Completo del Sistema</h5>
                    </div>
                    <div class="card-body">
                        <pre class="bg-dark text-light p-3 rounded">${JSON.stringify(data, null, 2)}</pre>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>`;
}

/**
 * Generate connections page HTML
 */
function generateConnectionsHTML(data) {
    const connectionsTable = data.proxy.connections.length > 0 
        ? data.proxy.connections.map(conn => `
            <tr>
                <td>${conn.streamId.substring(0, 8)}...</td>
                <td>${conn.clientAddress}</td>
                <td>${Math.round(conn.duration / 1000)}s</td>
                <td>${formatBytes(conn.bytesFromClient)}</td>
                <td>${formatBytes(conn.bytesToClient)}</td>
            </tr>
        `).join('')
        : '<tr><td colspan="5" class="text-center text-muted">No hay conexiones activas</td></tr>';

    return `
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pato2 - Conexiones Activas</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
</head>
<body class="bg-light">
    <nav class="navbar navbar-dark bg-primary">
        <div class="container">
            <a class="navbar-brand" href="http://${data.domain}:${data.webPort}/">
                <i class="fas fa-arrow-left"></i> Volver al Dashboard
            </a>
            <span class="navbar-text">Conexiones Activas (${data.proxy.activeConnections})</span>
        </div>
    </nav>

    <div class="container mt-4">
        <div class="row">
            <div class="col-12">
                <div class="card">
                    <div class="card-header d-flex justify-content-between align-items-center">
                        <h5 class="mb-0">Conexiones de Jugadores</h5>
                        <button class="btn btn-sm btn-outline-primary" onclick="location.reload()">
                            <i class="fas fa-sync-alt"></i> Actualizar
                        </button>
                    </div>
                    <div class="card-body">
                        <div class="table-responsive">
                            <table class="table table-striped">
                                <thead>
                                    <tr>
                                        <th>Stream ID</th>
                                        <th>Dirección Cliente</th>
                                        <th>Duración</th>
                                        <th>Datos Enviados</th>
                                        <th>Datos Recibidos</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    ${connectionsTable}
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }

        // Auto-refresh every 10 seconds
        setTimeout(() => location.reload(), 10000);
    </script>
</body>
</html>`;
}

function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatUptime(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return `${hours}h ${minutes}m`;
}

module.exports = createWebRoutes;