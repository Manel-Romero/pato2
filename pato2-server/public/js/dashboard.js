/**
 * Pato2 Dashboard JavaScript
 * Handles real-time updates and interactive features
 */

class Pato2Dashboard {
    constructor() {
        this.refreshInterval = 30000; // 30 seconds
        this.autoRefreshTimer = null;
        this.isRefreshing = false;
        
        this.init();
    }
    
    init() {
        this.setupEventListeners();
        this.startAutoRefresh();
        this.updateLastRefresh();
    }
    
    setupEventListeners() {
        // Refresh button
        const refreshBtn = document.getElementById('refresh-btn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => this.manualRefresh());
        }
        
        // Backup button
        const backupBtn = document.getElementById('backup-btn');
        if (backupBtn) {
            backupBtn.addEventListener('click', () => this.triggerBackup());
        }
        
        // Auto-refresh toggle
        const autoRefreshToggle = document.getElementById('auto-refresh-toggle');
        if (autoRefreshToggle) {
            autoRefreshToggle.addEventListener('change', (e) => {
                if (e.target.checked) {
                    this.startAutoRefresh();
                } else {
                    this.stopAutoRefresh();
                }
            });
        }
        
        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if (e.ctrlKey && e.key === 'r') {
                e.preventDefault();
                this.manualRefresh();
            }
        });
    }
    
    startAutoRefresh() {
        this.stopAutoRefresh(); // Clear any existing timer
        this.autoRefreshTimer = setInterval(() => {
            this.refreshData();
        }, this.refreshInterval);
        
        this.updateAutoRefreshStatus(true);
    }
    
    stopAutoRefresh() {
        if (this.autoRefreshTimer) {
            clearInterval(this.autoRefreshTimer);
            this.autoRefreshTimer = null;
        }
        
        this.updateAutoRefreshStatus(false);
    }
    
    updateAutoRefreshStatus(enabled) {
        const statusElement = document.getElementById('auto-refresh-status');
        if (statusElement) {
            statusElement.textContent = enabled ? 'Activado' : 'Desactivado';
            statusElement.className = enabled ? 'badge badge-success' : 'badge badge-secondary';
        }
    }
    
    manualRefresh() {
        if (this.isRefreshing) return;
        
        this.showRefreshSpinner();
        this.refreshData().finally(() => {
            this.hideRefreshSpinner();
        });
    }
    
    async refreshData() {
        if (this.isRefreshing) return;
        
        this.isRefreshing = true;
        
        try {
            const response = await fetch('/api/status');
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            
            const data = await response.json();
            this.updateDashboard(data);
            this.updateLastRefresh();
            this.showNotification('Datos actualizados', 'success');
            
        } catch (error) {
            console.error('Error refreshing data:', error);
            this.showNotification('Error al actualizar datos', 'error');
        } finally {
            this.isRefreshing = false;
        }
    }
    
    updateDashboard(data) {
        // Update host status
        this.updateHostStatus(data.host);
        
        // Update proxy status
        this.updateProxyStatus(data.proxy);
        
        // Update metrics
        this.updateMetrics(data.proxy.stats);
        
        // Update system info
        this.updateSystemInfo(data.system);
    }
    
    updateHostStatus(hostData) {
        const hostStatusElement = document.getElementById('host-status');
        const hostDetailsElement = document.getElementById('host-details');
        
        if (hostStatusElement) {
            if (hostData.hasActiveHost) {
                hostStatusElement.innerHTML = '<span class="status-indicator online"></span>Host Activo';
                hostStatusElement.className = 'badge badge-success';
                
                if (hostDetailsElement) {
                    const host = hostData.activeHost;
                    hostDetailsElement.innerHTML = `
                        <strong>Lease ID:</strong> ${host.leaseId.substring(0, 8)}...<br>
                        <strong>Servidor:</strong> ${host.serverRunning ? 'Ejecutándose' : 'Detenido'}<br>
                        <strong>Conexiones:</strong> ${host.connections}<br>
                        <strong>TTL:</strong> ${Math.round(host.timeLeft / 1000)}s
                    `;
                }
            } else {
                hostStatusElement.innerHTML = '<span class="status-indicator offline"></span>Sin Host';
                hostStatusElement.className = 'badge badge-danger';
                
                if (hostDetailsElement) {
                    hostDetailsElement.innerHTML = '<p class="text-muted">No hay host activo</p>';
                }
            }
        }
    }
    
    updateProxyStatus(proxyData) {
        const proxyStatusElement = document.getElementById('proxy-status');
        const proxyDetailsElement = document.getElementById('proxy-details');
        
        if (proxyStatusElement) {
            if (proxyData.ready) {
                proxyStatusElement.innerHTML = '<span class="status-indicator online"></span>Listo';
                proxyStatusElement.className = 'badge badge-success';
            } else {
                proxyStatusElement.innerHTML = '<span class="status-indicator warning"></span>No Disponible';
                proxyStatusElement.className = 'badge badge-warning';
            }
        }
        
        if (proxyDetailsElement) {
            proxyDetailsElement.innerHTML = `
                <strong>Puerto:</strong> ${proxyData.port}<br>
                <strong>Conexiones Activas:</strong> ${proxyData.stats.activeConnections}<br>
                <strong>Total Conexiones:</strong> ${proxyData.stats.totalConnections}<br>
                <strong>Datos Transferidos:</strong> ${this.formatBytes(proxyData.stats.bytesTransferred)}
            `;
        }
    }
    
    updateMetrics(stats) {
        // Active connections
        const activeConnectionsElement = document.getElementById('active-connections');
        if (activeConnectionsElement) {
            activeConnectionsElement.textContent = stats.activeConnections;
        }
        
        // Uptime
        const uptimeElement = document.getElementById('uptime');
        if (uptimeElement) {
            uptimeElement.textContent = this.formatUptime(stats.uptime);
        }
        
        // Data transferred
        const dataTransferredElement = document.getElementById('data-transferred');
        if (dataTransferredElement) {
            dataTransferredElement.textContent = this.formatBytes(stats.bytesTransferred);
        }
        
        // Errors
        const errorsElement = document.getElementById('errors');
        if (errorsElement) {
            errorsElement.textContent = stats.errors;
        }
    }
    
    updateSystemInfo(systemData) {
        const systemInfoElement = document.getElementById('system-info');
        if (systemInfoElement) {
            const memoryUsage = ((systemData.memory.heapUsed / systemData.memory.heapTotal) * 100).toFixed(1);
            
            systemInfoElement.innerHTML = `
                <strong>Uptime:</strong> ${this.formatUptime(systemData.uptime)}<br>
                <strong>Memoria:</strong> ${memoryUsage}% (${this.formatBytes(systemData.memory.heapUsed)})<br>
                <strong>Node.js:</strong> ${systemData.version}<br>
                <strong>Plataforma:</strong> ${systemData.platform}
            `;
        }
    }
    
    async triggerBackup() {
        const backupBtn = document.getElementById('backup-btn');
        if (backupBtn) {
            backupBtn.disabled = true;
            backupBtn.innerHTML = '<span class="loading-spinner"></span> Enviando...';
        }
        
        try {
            const response = await fetch('/api/host/backup-command', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    token: 'admin', // This should be properly authenticated
                    command: 'backup_now'
                })
            });
            
            const result = await response.json();
            
            if (result.success) {
                this.showNotification('Comando de backup enviado al host', 'success');
            } else {
                this.showNotification(`Error: ${result.error}`, 'error');
            }
            
        } catch (error) {
            this.showNotification(`Error de conexión: ${error.message}`, 'error');
        } finally {
            if (backupBtn) {
                backupBtn.disabled = false;
                backupBtn.innerHTML = '<i class="fas fa-save"></i> Backup Manual';
            }
        }
    }
    
    showRefreshSpinner() {
        const refreshBtn = document.getElementById('refresh-btn');
        if (refreshBtn) {
            refreshBtn.innerHTML = '<span class="loading-spinner"></span>';
            refreshBtn.disabled = true;
        }
    }
    
    hideRefreshSpinner() {
        const refreshBtn = document.getElementById('refresh-btn');
        if (refreshBtn) {
            refreshBtn.innerHTML = '<i class="fas fa-sync-alt"></i>';
            refreshBtn.disabled = false;
        }
    }
    
    updateLastRefresh() {
        const lastRefreshElement = document.getElementById('last-refresh');
        if (lastRefreshElement) {
            const now = new Date();
            lastRefreshElement.textContent = now.toLocaleTimeString();
        }
    }
    
    showNotification(message, type = 'info') {
        // Create notification element
        const notification = document.createElement('div');
        notification.className = `alert alert-${type === 'error' ? 'danger' : type} alert-dismissible fade show`;
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 9999;
            min-width: 300px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        `;
        
        notification.innerHTML = `
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        
        document.body.appendChild(notification);
        
        // Auto-remove after 5 seconds
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, 5000);
    }
    
    formatBytes(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }
    
    formatUptime(seconds) {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        
        if (days > 0) {
            return `${days}d ${hours}h ${minutes}m`;
        } else if (hours > 0) {
            return `${hours}h ${minutes}m`;
        } else {
            return `${minutes}m`;
        }
    }
}

// Initialize dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.pato2Dashboard = new Pato2Dashboard();
});

// Export for use in other scripts
if (typeof module !== 'undefined' && module.exports) {
    module.exports = Pato2Dashboard;
}