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
                system: {
                    uptime: process.uptime(),
                    memory: process.memoryUsage(),
                    version: process.version,
                    platform: process.platform
                },
                timestamp: new Date().toISOString()
            };

            res.send(generateDashboardHTML(data));
        } catch (error) {
            logger.error('Error in dashboard route:', error);
            res.status(500).send('Internal server error');
        }
    });
    return router;
}

/**
 * Generate main dashboard HTML
 */
function generateDashboardHTML(data) {
    // Badges sin exponer IPs ni datos sensibles
    const hostStatusBadge = data.host.hasActiveHost
        ? `<span class="badge badge-success">Activo</span>`
        : `<span class="badge badge-danger">Sin Host</span>`;

    const proxyStatusBadge = data.proxy.ready
        ? `<span class="badge badge-success">Listo</span>`
        : `<span class="badge badge-warning">No Disponible</span>`;

    // Métricas de sistema
    const mem = data.system?.memory || {};
    const rss = typeof mem.rss === 'number' ? formatBytes(mem.rss) : 'N/A';
    const heapUsed = typeof mem.heapUsed === 'number' ? formatBytes(mem.heapUsed) : 'N/A';
    const uptimeStr = formatUptime((data.system?.uptime) || 0);

    return `
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${data.title}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        :root {
            --accent: #f5b301;
            --accent-dark: #ff8c42;
            --bg: #f7f7f9;
            --card-bg: #ffffff;
            --text: #111111;
            --duck-width: 5vw;
        }
        html, body { margin: 0; overflow-x: hidden; }
        body {
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
            background-image: linear-gradient(180deg, rgba(245,179,1,0.06), rgba(255,255,255,0));
            background-repeat: no-repeat;
            background-size: 100% 180px;
            animation: subtleGlow 10s ease-in-out infinite;
        }
        @keyframes subtleGlow { 0%, 100% { filter: saturate(1) brightness(1); } 50% { filter: saturate(1.05) brightness(1.02); } }
        .navbar { background: #ffffff; color: #111111; box-shadow: 0 6px 24px rgba(0,0,0,0.06); }
        .accent-bar { position: relative; }
        .accent-bar::after { content: ''; position: absolute; bottom: 0; left: 0; width: 100%; height: 4px; background: linear-gradient(90deg, var(--accent) 0%, var(--accent-dark) 100%); opacity: 0.9; }
        .status-card { transition: transform 0.22s ease, box-shadow 0.22s ease; background: #ffffff; border: 1px solid rgba(0,0,0,0.05); box-shadow: 0 6px 16px rgba(0,0,0,0.08); }
        .status-card:hover { transform: translateY(-2px); box-shadow: 0 10px 20px rgba(0,0,0,0.10); }
        .badge { font-size: 0.8em; }
        .metric-value { font-size: 2rem; font-weight: bold; }
        .text-accent { color: var(--accent); }
        .btn-outline-warning { border-color: var(--accent); color: var(--accent); }
        .btn-outline-warning:hover { background: var(--accent); color: #1a1a1a; }
        /* Duck CSS Art */
        .duck { position: fixed; right: 12px; bottom: 12px; transform-origin: bottom right; z-index: 50; pointer-events: none; }
        .duck .duck-art { width: 420px; height: 500px; position: relative; transform: scale(calc(var(--duck-width) / 420px)); transform-origin: bottom right; }
        .duck-body { background-color: #fed72b; height: 150px; width: 150px; border-radius: 50%; position: absolute; top: 100px; left: 100px; }
        .duck-body::before { position: absolute; content: ""; background-color: transparent; height: 150px; width: 150px; box-shadow: 80px 45px 0 #fe9711; border-radius: 50%; left: 10px; top: -5px; transform: rotate(30deg); }
        .duck-body::after { position: absolute; content: ""; background-color: #fed72b; height: 130px; width: 220px; position: absolute; top: 140px; border-radius: 70px; }
        .duck-feather { position: absolute; background-color: #fef53a; width: 170px; height: 110px; top: 220px; left: 190px; border-radius: 31% 69% 69% 31%/ 50% 100% 0 50%; }
        .duck-feather::before { position: absolute; content: ""; background-color: #fe9711; width: 80px; height: 20px; top: -100px; left: -15px; z-index: -1; border-radius: 0 5px 20px 0; }
        .duck-feather::after { position: absolute; content: ""; background-color: #fed72b; width: 70px; height: 25px; top: -120px; left: -15px; border-radius: 0 5px 20px 0; }
        .duck-eye { position: absolute; background-color: #fefefe; height: 53px; width: 53px; top: 147px; left: 167px; border-radius: 50%; overflow: hidden; }
        .duck-iris { position: absolute; background-color: #434453; height: 27px; width: 27px; top: 50%; left: 50%; border-radius: 50%; transform: translate(-50%, -50%); }
        .duck-iris .duck-pupil { position: absolute; height: 14px; width: 14px; background-color: #111111; border-radius: 50%; top: 50%; left: 50%; transform: translate(-50%, -50%); }
        .duck-beak { background-color: #d55326; height: 20px; width: 80px; position: absolute; top: 190px; left: 70px; border-radius: 35% 10% 16% 0 / 100% 0 30% 10%; }
        .duck-beak::before { position: absolute; content: ""; height: 40px; width: 90px; background-color: #fe9711; border-radius: 0 40% 0 40%/0 100% 0 100%; bottom: 12px; right: -1px; }
        .duck-beak::after { position: absolute; content: ""; height: 7px; width: 15px; background-color: #d45326; bottom: 40px; right: 30px; border-radius: 5px; }
        .duck-leg { position: absolute; background-color: #fe9711; width: 12px; height: 30px; top: 370px; left: 220px; box-shadow: -30px 0 #d45326; }
        .duck-leg::before { position: absolute; content: ""; background-color: #fe9711; width: 52px; height: 12px; left: -23px; top: 25px; border-radius: 5px; box-shadow: -30px 0 #d45326; }
        .duck-leg::after { position: absolute; content: ""; background-color: #7e2e4e; height: 15px; width: 540px; top: 38px; right: -340px; border-radius: 7px; }
        @media (max-width: 768px) { .duck { display: none; } }
        @media (pointer: coarse) { .duck { display: none; } }
    </style>
</head>
<body>
    <nav class="navbar navbar-light bg-white accent-bar">
        <div class="container">
            <span class="navbar-brand mb-0 h1">
                <i class="fas fa-cubes"></i> Pato2 Dashboard
            </span>
            <!-- Ocultamos dominio/IP para seguridad -->
        </div>
    </nav>

    <div class="container mt-4">
        <!-- Estado del Host y Proxy -->
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

        <!-- Métricas -->
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

        <!-- Sistema -->
        <div class="row mb-4">
            <div class="col-md-12">
                <div class="card status-card">
                    <div class="card-body">
                        <h5 class="card-title"><i class="fas fa-microchip"></i> Información del Sistema</h5>
                        <div class="row">
                            <div class="col-md-3"><strong>Uptime:</strong> ${uptimeStr}</div>
                            <div class="col-md-3"><strong>Node:</strong> ${data.system?.version || 'N/A'}</div>
                            <div class="col-md-3"><strong>Plataforma:</strong> ${data.system?.platform || 'N/A'}</div>
                            <div class="col-md-3"><strong>Memoria:</strong> RSS ${rss}, Heap ${heapUsed}</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Duck CSS Art -->
    <div class="duck" aria-hidden="true">
        <div class="duck-art">
            <div class="duck-body"></div>
            <div class="duck-feather"></div>
            <div class="duck-eye"><div class="duck-iris"><div class="duck-pupil"></div></div></div>
            <div class="duck-beak"></div>
            <div class="duck-leg"></div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    <script>
    // Movimiento del ojo del pato (inline)
    (function() {
      function onReady() {
        var duck = document.querySelector('.duck');
        var eye = document.querySelector('.duck-eye');
        var iris = document.querySelector('.duck-iris');
        var coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
        if (duck && eye && iris && !coarse) {
          function onMove(e) {
            var eyeRect = eye.getBoundingClientRect();
            var irisRect = iris.getBoundingClientRect();
            var cx = eyeRect.left + eyeRect.width / 2;
            var cy = eyeRect.top + eyeRect.height / 2;
            var dx = e.clientX - cx;
            var dy = e.clientY - cy;
            var angle = Math.atan2(dy, dx);
            var margin = ((Math.min(eyeRect.width, eyeRect.height) - Math.min(irisRect.width, irisRect.height)) / 2);
            var max = Math.max(8, margin + 3);
            var tx = Math.cos(angle) * max;
            var ty = Math.sin(angle) * max;
            iris.style.transform = 'translate(-50%, -50%) translate(' + tx + 'px,' + ty + 'px)';
          }
          window.addEventListener('mousemove', onMove);
        }
      }
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', onReady);
      } else {
        onReady();
      }
    })();
    </script>
</body>
</html>`;
}

// Rutas unificadas: páginas /status y /connections eliminadas

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