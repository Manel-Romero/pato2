# Instalación de Pato2 Server (Termux)

Guía completa para instalar y configurar el servidor Pato2 en Android usando Termux.

## Requisitos Previos

### Hardware
- **Dispositivo Android** con al menos 4GB de RAM
- **Almacenamiento**: Mínimo 2GB libres
- **Conexión a internet** estable

### Software
- **Android 7.0** o superior
- **Termux** instalado desde F-Droid (recomendado) o Google Play

## Preparación del Entorno

### Instalar Termux

1. **Descargar Termux**:
   - **F-Droid** (recomendado): https://f-droid.org/packages/com.termux/
   - **Google Play**: https://play.google.com/store/apps/details?id=com.termux

2. **Abrir Termux** y permitir permisos de almacenamiento:
   ```bash
   termux-setup-storage
   ```

3. **Actualizar paquetes**:
   ```bash
   pkg update && pkg upgrade
   ```

### Instalar Node.js

```bash
# Instalar Node.js y npm
pkg install nodejs npm

# Verificar instalación
node --version
npm --version
```

## Descarga e Instalación

### Método Automático (Recomendado)

```bash
# Descargar y ejecutar script de instalación
curl -sSL https://raw.githubusercontent.com/tu-usuario/Pato2_TRAE/main/scripts/install-pato2-server.sh | bash
```

### Método Manual

1. **Instalar dependencias**:
   ```bash
   pkg install git curl wget openssh net-tools
   ```

2. **Clonar repositorio**:
   ```bash
   cd ~
   git clone https://github.com/tu-usuario/Pato2_TRAE.git
   cd Pato2_TRAE/pato2-server
   ```

3. **Instalar dependencias de Node.js**:
   ```bash
   npm install
   ```

4. **Configurar variables de entorno**:
   ```bash
   cp .env.example .env
   nano .env
   ```

   Configurar las siguientes variables:
   ```env
   # Dominio y puertos
   DOMAIN=pato2.duckdns.org
   API_PORT=5000
   PROXY_PORT=25565
   
   # Seguridad
   JWT_SECRET=tu_jwt_secret_muy_seguro
   HOST_TOKEN=tu_host_token_muy_seguro
   
   # Configuración de hosts
   HOST_LEASE_TTL=300000
   MAX_CONNECTIONS_PER_HOST=100
   
   # Logging
   LOG_LEVEL=info
   ```

## Configuración de Red

### DuckDNS (Recomendado)

1. **Crear cuenta** en https://www.duckdns.org
2. **Crear subdominio**: `pato2.duckdns.org`
3. **Configurar IP dinámica**:
   ```bash
   # Instalar cron para actualización automática
   pkg install cronie
   
   # Crear script de actualización
   echo 'curl "https://www.duckdns.org/update?domains=pato2&token=TU_TOKEN&ip=" >/dev/null 2>&1' > ~/duckdns.sh
   chmod +x ~/duckdns.sh
   
   # Programar actualización cada 5 minutos
   crontab -e
   # Agregar: */5 * * * * ~/duckdns.sh
   ```

### Port Forwarding

Configurar en tu router:
- **Puerto 25565** → IP del dispositivo Android
- **Puerto 5000** → IP del dispositivo Android

### IP Estática (Opcional)

1. **Obtener IP actual**:
   ```bash
   ifconfig wlan0
   ```

2. **Configurar IP estática** en la configuración WiFi del dispositivo

## Iniciar el Servidor

### Primera ejecución

```bash
cd ~/Pato2_TRAE/pato2-server
npm start
```

### Verificar funcionamiento

1. **Comprobar puertos**:
   ```bash
   netstat -tlnp | grep -E ':(5000|25565)'
   ```

2. **Acceder al panel web**:
   - Abrir navegador en: `http://localhost:5000`
   - Desde otra red: `http://pato2.duckdns.org:5000`

## Configurar como Servicio

### Instalar PM2

```bash
npm install -g pm2
```

### Configurar aplicación

```bash
cd ~/Pato2_TRAE/pato2-server

# Iniciar con PM2
pm2 start src/server.js --name "pato2-server"

# Guardar configuración
pm2 save

# Configurar inicio automático
pm2 startup
```

### Scripts de utilidad

Crear scripts para gestión fácil:

```bash
# Script de inicio
cat > ~/start-pato2.sh << 'EOF'
#!/bin/bash
cd ~/Pato2_TRAE/pato2-server
pm2 start pato2-server
EOF

# Script de parada
cat > ~/stop-pato2.sh << 'EOF'
#!/bin/bash
pm2 stop pato2-server
EOF

# Script de estado
cat > ~/status-pato2.sh << 'EOF'
#!/bin/bash
pm2 status pato2-server
pm2 logs pato2-server --lines 20
EOF

# Hacer ejecutables
chmod +x ~/start-pato2.sh ~/stop-pato2.sh ~/status-pato2.sh
```

## Configuración de Seguridad

### Firewall básico

```bash
# Instalar iptables (si no está disponible)
pkg install iptables

# Permitir solo puertos necesarios
iptables -A INPUT -p tcp --dport 5000 -j ACCEPT
iptables -A INPUT -p tcp --dport 25565 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
```

### Auto-inicio de Termux

1. **Instalar Termux:Boot** desde F-Droid
2. **Crear script de inicio**:
   ```bash
   mkdir -p ~/.termux/boot
   cat > ~/.termux/boot/start-pato2 << 'EOF'
   #!/data/data/com.termux/files/usr/bin/bash
   cd ~/Pato2_TRAE/pato2-server
   pm2 resurrect
   EOF
   chmod +x ~/.termux/boot/start-pato2
   ```

3. **Configurar permisos** de auto-inicio en Android

## Monitoreo y Logs

### Ver logs en tiempo real

```bash
# Logs de PM2
pm2 logs pato2-server

# Logs del sistema
tail -f ~/Pato2_TRAE/pato2-server/logs/app.log
```

### Monitoreo de recursos

```bash
# Estado de PM2
pm2 monit

# Uso de memoria y CPU
top
```

### Panel web de monitoreo

Acceder a `http://pato2.duckdns.org:5000` para:
- Ver estado del servidor
- Monitorear conexiones activas
- Gestionar hosts conectados
- Ver métricas en tiempo real

## Solución de Problemas

### Error: "Puerto en uso"

```bash
# Encontrar proceso usando el puerto
netstat -tlnp | grep :5000
# o
lsof -i :5000

# Terminar proceso
kill -9 PID_DEL_PROCESO
```

### Error: "No se puede conectar"

1. **Verificar firewall**:
   ```bash
   iptables -L
   ```

2. **Comprobar port forwarding** en el router

3. **Verificar DuckDNS**:
   ```bash
   nslookup pato2.duckdns.org
   ```

### Error: "Memoria insuficiente"

```bash
# Verificar memoria disponible
free -h

# Limpiar caché
sync && echo 3 > /proc/sys/vm/drop_caches
```

### Problemas de permisos

```bash
# Reparar permisos de Termux
termux-fix-shebang ~/Pato2_TRAE/pato2-server/src/server.js
```

## Verificación Final

### Lista de verificación

- [ ] Termux instalado y actualizado
- [ ] Node.js y npm funcionando
- [ ] Repositorio clonado correctamente
- [ ] Variables de entorno configuradas
- [ ] DuckDNS configurado y funcionando
- [ ] Port forwarding configurado
- [ ] Servidor iniciando sin errores
- [ ] Panel web accesible
- [ ] PM2 configurado para auto-inicio
- [ ] Scripts de utilidad creados

### Comandos de prueba

```bash
# Verificar estado del servidor
curl http://localhost:5000/api/status

# Verificar conectividad externa
curl http://pato2.duckdns.org:5000/api/status
```

## Siguientes Pasos

1. **[Configurar Host Agent](host-agent.md)** en tu PC
2. **[Configurar Google Drive](google-drive.md)** para backups
3. **[Configurar red avanzada](network-setup.md)** si es necesario
4. **[Leer manual del administrador](../user-guide/admin-guide.md)**

## Soporte

- **Documentación**: [docs.pato2.example.com](https://docs.pato2.example.com)
- **Issues**: [GitHub Issues](https://github.com/pato2/issues)
- **Comunidad**: [Discord Server](#)