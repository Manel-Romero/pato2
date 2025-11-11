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

    // Rutas unificadas: sin /status ni /connections

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
        :root {
            --bg: #fffdf7;
            --bg-soft: #fff7e9;
            --text: #111111;
            --muted: #545454;
            --accent: #f5b301; /* amarillo elegante */
            --accent-2: #ff7a00; /* naranja */
            --accent-soft: #fff1c7; /* amarillo suave */
            --card: #ffffff;
            --border: rgba(0,0,0,0.08);
        }

        body {
            background: linear-gradient(180deg, #f1f3b2ff 0%, #f8c471ff 100%);
            color: var(--text);
            min-height: 100vh;
        }

        .navbar {
            background: #ffb829ff;
            border-bottom: 1px solid var(--border);
            backdrop-filter: blur(6px);
        }

        .status-card { 
            transition: transform 0.18s ease, box-shadow 0.18s ease; 
            background: var(--card);
            border: 1px solid var(--border);
            box-shadow: 0 10px 24px rgba(0,0,0,0.06);
        }
        .status-card:hover { transform: translateY(-2px); box-shadow: 0 14px 28px rgba(0,0,0,0.08); }
        .badge { font-size: 0.8em; }
        .metric-value { font-size: 2rem; font-weight: bold; }
        .refresh-btn { position: fixed; bottom: 20px; right: 20px; border-radius: 999px; background: linear-gradient(90deg, var(--accent), var(--accent-2)); color: #111; border: none; box-shadow: 0 8px 14px rgba(255,122,0,0.18); }

        .text-accent { color: var(--accent); }
        .btn-outline-warning { border-color: var(--accent-2); color: var(--accent-2); }
        .btn-outline-warning:hover { background: var(--accent-2); color: #ffffff; }

        /* Estanque decorativo al pie */
        .pond { position: fixed; left: 0; right: 0; bottom: 0; height: 120px; pointer-events: none; }
        .pond svg { width: 100%; height: 100%; display: block; }
        .water { opacity: 0.95; animation: shimmer 8s ease-in-out infinite; }
        @keyframes shimmer { 0%,100% { filter: brightness(1);} 50% { filter: brightness(1.06);} }
        .reed { transform-origin: bottom center; animation: sway 6s ease-in-out infinite; will-change: transform; }
        @keyframes sway { 0%,100% { transform: rotate(0deg);} 50% { transform: rotate(0.9deg);} }
    </style>
</head>
<body>
    <nav class="navbar">
        <div class="container">
            <span class="navbar-brand mb-0 h1">
                <i class="fas fa-cubes"></i> Pato2 Dashboard
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
                        <i class="fas fa-users fa-2x text-accent mb-2"></i>
                        <div class="metric-value text-accent">${data.proxy.stats.activeConnections}</div>
                        <small class="text-muted">Jugadores Conectados</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card text-center status-card">
                    <div class="card-body">
                        <i class="fas fa-clock fa-2x text-accent mb-2"></i>
                        <div class="metric-value text-accent">${formatUptime(data.proxy.stats.uptime)}</div>
                        <small class="text-muted">Tiempo Activo</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card text-center status-card">
                    <div class="card-body">
                        <i class="fas fa-exchange-alt fa-2x text-accent mb-2"></i>
                        <div class="metric-value text-accent">${formatBytes(data.proxy.stats.bytesTransferred)}</div>
                        <small class="text-muted">Datos Transferidos</small>
                    </div>
                </div>
            </div>
            <div class="col-md-3">
                <div class="card text-center status-card">
                    <div class="card-body">
                        <i class="fas fa-exclamation-triangle fa-2x text-accent mb-2"></i>
                        <div class="metric-value text-accent">${data.proxy.stats.errors}</div>
                        <small class="text-muted">Errores</small>
                    </div>
                </div>
            </div>
        </div>

        <!-- Comandos de Minecraft -->
        <div class="row">
            <div class="col-12">
                <div class="card status-card">
                    <div class="card-header d-flex align-items-center justify-content-between">
                        <h5 class="mb-0"><i class="fas fa-terminal"></i> Comandos de Minecraft</h5>
                    </div>
                    <div class="card-body">
                        <form id="mc-command-form" class="row g-3" onsubmit="return sendMinecraftCommand(event)">
                            <div class="col-md-4">
                                <label class="form-label">Contraseña</label>
                                <input type="password" class="form-control" id="cmd-password" placeholder="••••••" required>
                            </div>
                            <div class="col-md-6">
                                <label class="form-label">Comando</label>
                                <input type="text" class="form-control" id="cmd-text" placeholder="Ej. say Hola a todos" required>
                            </div>
                            <div class="col-md-2 d-flex align-items-end">
                                <button type="submit" class="btn btn-outline-warning w-100" ${!data.host.hasActiveHost ? 'disabled' : ''}>
                                    <i class="fas fa-paper-plane"></i> Enviar
                                </button>
                            </div>
                        </form>
                        <div id="cmd-result" class="mt-3"></div>

                        <hr class="my-4">
                        <button onclick="triggerBackup()" class="btn btn-outline-warning" ${!data.host.hasActiveHost ? 'disabled' : ''}>
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

    <!-- Estanque decorativo con cañas al pie -->
    <div class="pond">
        <svg viewBox="0 0 1200 120" preserveAspectRatio="none" aria-hidden="true">
            <defs>
                <linearGradient id="waterGradient" x1="0" x2="1" y1="0" y2="0">
                    <stop offset="0%" stop-color="#ffffff" />
                    <stop offset="50%" stop-color="rgba(184, 202, 255, 1)" />
                    <stop offset="100%" stop-color="#6259e4ff" />
                </linearGradient>
            </defs>
            <rect class="water" x="0" y="40" width="1200" height="80" fill="url(#waterGradient)" />
            <g stroke-width="3" fill="none">
                <!-- Cañas más densas e independientes, tonos de verde variados y movimiento más leve -->
                <path class="reed" d="M70,72 C72,60 74,50 76,40" style="stroke:#2e7d32; animation: sway 6.2s ease-in-out infinite 0.8s;" />
                <path class="reed" d="M74,73 C76,61 78,51 80,41" style="stroke:#1b5e20; animation: sway 7.1s ease-in-out infinite 1.6s;" />
                <path class="reed" d="M78,74 C80,62 82,52 84,42" style="stroke:#388e3c; animation: sway 5.7s ease-in-out infinite 0.3s;" />
                <path class="reed" d="M82,71 C84,59 86,49 88,39" style="stroke:#43a047; animation: sway 6.8s ease-in-out infinite 1.2s;" />
                <path class="reed" d="M86,73 C88,61 90,51 92,41" style="stroke:#4caf50; animation: sway 5.9s ease-in-out infinite 0.9s;" />
                <path class="reed" d="M90,70 C92,58 94,48 96,38" style="stroke:#66bb6a; animation: sway 7.3s ease-in-out infinite 1.9s;" />
                <path class="reed" d="M94,73 C96,61 98,51 100,41" style="stroke:#2e7d32; animation: sway 6.5s ease-in-out infinite 0.5s;" />
                <path class="reed" d="M98,71 C100,59 102,49 104,39" style="stroke:#1b5e20; animation: sway 5.8s ease-in-out infinite 1.4s;" />
                <path class="reed" d="M102,73 C104,61 106,51 108,41" style="stroke:#388e3c; animation: sway 6.1s ease-in-out infinite 0.6s;" />
                <path class="reed" d="M106,70 C108,58 110,48 112,38" style="stroke:#43a047; animation: sway 7.0s ease-in-out infinite 1.1s;" />
                <path class="reed" d="M110,75 C112,63 114,53 116,43" style="stroke:#4caf50; animation: sway 5.6s ease-in-out infinite 0.2s;" />
                <path class="reed" d="M114,71 C116,59 118,49 120,39" style="stroke:#66bb6a; animation: sway 6.9s ease-in-out infinite 1.5s;" />
                <path class="reed" d="M118,74 C120,62 122,52 124,42" style="stroke:#2e7d32; animation: sway 5.9s ease-in-out infinite 0.7s;" />
                <path class="reed" d="M122,69 C124,57 126,47 128,37" style="stroke:#1b5e20; animation: sway 6.7s ease-in-out infinite 1.3s;" />
                <path class="reed" d="M126,74 C128,62 130,52 132,42" style="stroke:#388e3c; animation: sway 6.0s ease-in-out infinite 0.4s;" />
                <path class="reed" d="M130,68 C132,56 134,46 136,36" style="stroke:#43a047; animation: sway 7.2s ease-in-out infinite 1.8s;" />
                <path class="reed" d="M134,73 C136,61 138,51 140,41" style="stroke:#4caf50; animation: sway 6.3s ease-in-out infinite 1.0s;" />
                <path class="reed" d="M138,70 C140,58 142,48 144,38" style="stroke:#66bb6a; animation: sway 5.7s ease-in-out infinite 0.1s;" />
                <path class="reed" d="M142,73 C144,61 146,51 148,41" style="stroke:#2e7d32; animation: sway 6.6s ease-in-out infinite 1.7s;" />
                <path class="reed" d="M146,71 C148,59 150,49 152,39" style="stroke:#388e3c; animation: sway 6.4s ease-in-out infinite 0.95s;" />
                <path class="reed" d="M150,72 C152,60 154,50 156,40" style="stroke:#1b5e20; animation: sway 7.1s ease-in-out infinite 1.25s;" />
                <path class="reed" d="M154,69 C156,57 158,47 160,37" style="stroke:#43a047; animation: sway 5.8s ease-in-out infinite 0.45s;" />
                <path class="reed" d="M158,74 C160,62 162,52 164,42" style="stroke:#4caf50; animation: sway 6.7s ease-in-out infinite 1.35s;" />
                <path class="reed" d="M162,70 C164,58 166,48 168,38" style="stroke:#66bb6a; animation: sway 6.0s ease-in-out infinite 0.75s;" />
            </g>
        </svg>
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

        function sendMinecraftCommand(e) {
            e.preventDefault();
            const password = document.getElementById('cmd-password').value.trim();
            const command = document.getElementById('cmd-text').value.trim();
            const resultEl = document.getElementById('cmd-result');

            if (!password || !command) {
                resultEl.innerHTML = '<div class="alert alert-warning">Introduce contraseña y comando.</div>';
                return false;
            }

            resultEl.innerHTML = '<div class="alert alert-info">Enviando comando...</div>';
            fetch('http://${data.domain}:${data.webPort}/api/minecraft/command', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ password, command })
            })
            .then(r => r.json())
            .then(r => {
                if (r.success) {
                    resultEl.innerHTML = '<div class="alert alert-success">Comando enviado correctamente.</div>';
                    document.getElementById('mc-command-form').reset();
                } else {
                    resultEl.innerHTML = '<div class="alert alert-danger">Error: ' + (r.error || 'Solicitud inválida') + '</div>';
                }
            })
            .catch(err => {
                resultEl.innerHTML = '<div class="alert alert-danger">Error de conexión: ' + err.message + '</div>';
            });
            return false;
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
// Páginas separadas eliminadas para mantener todo en una sola vista

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