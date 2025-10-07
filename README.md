# Pato2 - Sistema de Gestión de Servidores Minecraft

Un sistema completo para gestionar hosts y clientes en red para crear servidores de Minecraft sin necesidad de port forwarding en los hosts.

## Características Principales

- **Proxy TCP Inverso**: Los jugadores se conectan a `pato2.duckdns.org:25565`
- **Sin Port Forwarding**: Los hosts PC establecen conexiones salientes
- **Gestión de Lease**: Un único host activo con modelo push + lease + heartbeat
- **Backups Automáticos**: Subida automática a Google Drive
- **Panel Web**: Monitoreo en tiempo real del estado del sistema

## Estructura del Proyecto

```
Pato2_TRAE/
├── pato2-server/          # Servidor principal (Node.js) - Ejecuta en Termux
├── host-agent/            # Agente para hosts PC (Python)
├── docs/                  # Documentación completa
├── config/                # Archivos de configuración
└── scripts/               # Scripts de instalación y utilidades
```

## Inicio Rápido

### Para Pato2 (Móvil con Termux)
```bash
cd pato2-server
npm install
npm start
```

### Para Host PC
```bash
cd host-agent
pip install -r requirements.txt
python host_agent.py
```

## Documentación

- [Guía de Instalación para Hosts](docs/es/installation/host-agent.md)
- [Manual de Usuario](docs/es/user-guide/player-guide.md)
- [Guía de Instalación para Pato2](docs/es/installation/pato2-server.md)

## Arquitectura

- **Pato2 (Móvil)**: Proxy TCP en puerto 25565, API/Web en puerto 5000
- **Host PC**: Agente que conecta al móvil vía WebSocket
- **Jugadores**: Se conectan a `pato2.duckdns.org:25565`

## Requisitos

- **Pato2**: Android con Termux, Node.js 18+
- **Host PC**: Python 3.7+, servidor Minecraft local
- **Red**: Port forwarding 25565 y 5000 hacia el móvil

## Variables de Entorno

Ver [config/.env.example](config/.env.example) para comprender la estructura esperada.

## Licencia

MIT License - Ver [LICENSE](LICENSE) para más detalles.