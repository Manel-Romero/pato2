#!/usr/bin/env python3
"""
Pato2 Host Agent
Connects to Pato2 server and provides reverse tunnel for Minecraft server
"""

import asyncio
import json
import logging
import os
import signal
import socket
import sys
import time
import threading
from typing import Dict, Optional
import base64
import subprocess
import psutil

import requests
import websocket
from urllib.parse import urlparse
from dotenv import load_dotenv

from backup_manager import BackupManager
from minecraft_manager import MinecraftManager

# Load environment variables
load_dotenv(dotenv_path='.env')

class HostAgent:
    def __init__(self):
        self.setup_logging()
        self.load_config()
        
        # State
        self.lease_id: Optional[str] = None
        self.websocket: Optional[websocket.WebSocketApp] = None
        self.running = False
        self.connections: Dict[str, socket.socket] = {}
        self.udp_connections: Dict[str, socket.socket] = {}
        self.udp_recv_threads: Dict[str, threading.Thread] = {}
        self.exit_backup_done: bool = False
        
        # Managers
        self.minecraft_manager = MinecraftManager(
            self.config['minecraft_dir'],
            self.config['minecraft_port']
        )
        self.backup_manager = BackupManager(self.config)
        
        # Threading
        self.heartbeat_thread: Optional[threading.Thread] = None
        self.websocket_thread: Optional[threading.Thread] = None
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

    def setup_logging(self):
        """Setup logging configuration"""
        log_level = os.getenv('LOG_LEVEL', 'INFO').upper()
        logging.basicConfig(
            level=getattr(logging, log_level),
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler(sys.stdout),
                logging.FileHandler('host_agent.log')
            ]
        )
        self.logger = logging.getLogger('HostAgent')

    def load_config(self):
        """Load configuration from environment variables"""
        self.config = {
            'host_token': os.getenv('HOST_TOKEN'),
            'pato2_endpoint': os.getenv('PATO2_ENDPOINT', 'http://pato2.duckdns.org:5000'),
            'minecraft_dir': os.getenv('MINECRAFT_DIR', './minecraft'),
            'minecraft_port': int(os.getenv('MINECRAFT_PORT', '25565')),
            'heartbeat_interval': int(os.getenv('HEARTBEAT_INTERVAL_SECONDS', '15')),
            'reconnect_delay': int(os.getenv('RECONNECT_DELAY_SECONDS', '5')),
            'max_reconnect_attempts': int(os.getenv('MAX_RECONNECT_ATTEMPTS', '10')),
            # Google Drive credentials
            'google_drive_client_id': os.getenv('GOOGLE_CLIENT_ID'),
            'google_drive_client_secret': os.getenv('GOOGLE_CLIENT_SECRET'),
            'google_drive_refresh_token': os.getenv('GOOGLE_REFRESH_TOKEN'),
            'google_drive_folder_id': os.getenv('GOOGLE_DRIVE_FOLDER_ID'),
            # Backup settings
            'backup_interval_hours': max(1, int(int(os.getenv('BACKUP_INTERVAL', '3600').split()[0]) / 3600)),
            'backup_retention_days': int(os.getenv('BACKUP_RETENTION', '7').split()[0]),
        }

        # Resolve Pato2 endpoint to IP address once
        parsed_url = urlparse(self.config['pato2_endpoint'])
        hostname = parsed_url.hostname
        if hostname:
            try:
                self.pato2_ip = socket.gethostbyname(hostname)
                self.logger.info(f"Resolved Pato2 endpoint {hostname} to IP {self.pato2_ip}")
            except socket.gaierror as e:
                self.logger.error(f"Could not resolve Pato2 endpoint {hostname}: {e}")
                self.pato2_ip = None
        else:
            self.pato2_ip = None

        # Validate required config
        if not self.config['host_token']:
            raise ValueError("HOST_TOKEN environment variable is required")
        
        self.logger.info(f"Loaded configuration: {self.config['pato2_endpoint']}")

    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum}, shutting down...")
        self.shutdown()

    def offer_host(self) -> bool:
        """Offer this host to become the active server"""
        try:
            endpoint_info = f"{socket.gethostname()}:{self.config['minecraft_port']}"
            
            
            # Use the resolved IP address for requests
            if self.pato2_ip:
                parsed_url = urlparse(self.config['pato2_endpoint'])
                base_url = f"http://{self.pato2_ip}:{parsed_url.port}"
            else:
                base_url = self.config['pato2_endpoint']

            response = requests.post(
                f"{base_url}/api/host/offer",
                json={
                    'token': self.config['host_token'],
                    'endpoint': endpoint_info
                },
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('accepted'):
                    self.lease_id = data['leaseId']
                    self.logger.info(f"Host offer accepted. Lease ID: {self.lease_id}")
                    return True
                else:
                    self.logger.error(f"Host offer rejected: {data.get('error')}")
                    return False
            elif response.status_code == 409:
                self.logger.warning("Another host is already active")
                return False
            else:
                self.logger.error(f"Host offer failed: {response.status_code} {response.text}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error offering host: {e}")
            return False

    def send_heartbeat(self) -> bool:
        """Send heartbeat to maintain lease"""
        if not self.lease_id:
            return False
            
        try:
            minecraft_running = self.minecraft_manager.is_server_running()
            minecraft_ready = self.minecraft_manager.is_server_ready()
            
            
            # Use the resolved IP address for requests
            if self.pato2_ip:
                parsed_url = urlparse(self.config['pato2_endpoint'])
                base_url = f"http://{self.pato2_ip}:{parsed_url.port}"
            else:
                base_url = self.config['pato2_endpoint']

            response = requests.post(
                f"{base_url}/api/host/heartbeat",
                json={
                    'token': self.config['host_token'],
                    'leaseId': self.lease_id,
                    'ready': minecraft_ready,
                    'serverRunning': minecraft_running
                },
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('ok'):
                    self.logger.debug("Heartbeat sent successfully")
                    return True
                else:
                    self.logger.error(f"Heartbeat rejected: {data.get('error')}")
                    return False
            else:
                self.logger.error(f"Heartbeat failed: {response.status_code}")
                return False
                
        except Exception as e:
            self.logger.error(f"Error sending heartbeat: {e}")
            return False

    def end_lease(self):
        """End the current lease"""
        if not self.lease_id:
            return
            
        try:
            
            # Use the resolved IP address for requests
            if self.pato2_ip:
                parsed_url = urlparse(self.config['pato2_endpoint'])
                base_url = f"http://{self.pato2_ip}:{parsed_url.port}"
            else:
                base_url = self.config['pato2_endpoint']

            response = requests.post(
                f"{base_url}/api/host/end",
                json={'token': self.config['host_token']},
                timeout=10
            )
            
            if response.status_code == 200:
                self.logger.info("Lease ended successfully")
            else:
                self.logger.error(f"Failed to end lease: {response.status_code}")
                
        except Exception as e:
            self.logger.error(f"Error ending lease: {e}")
        
        self.lease_id = None

    def connect_websocket(self):
        """Connect to Pato2 WebSocket"""
        if not self.lease_id:
            self.logger.error("Cannot connect WebSocket without lease ID")
            return False
            
        # Use the resolved IP address for WebSocket connection
        if self.pato2_ip:
            parsed_url = urlparse(self.config['pato2_endpoint'])
            ws_url = f"ws://{self.pato2_ip}:{parsed_url.port}/ws/host?token={self.config['host_token']}&leaseId={self.lease_id}"
        else:
            ws_url = f"{self.config['pato2_endpoint'].replace('http', 'ws')}/ws/host?token={self.config['host_token']}&leaseId={self.lease_id}"
        
        self.logger.info(f"Connecting to WebSocket: {ws_url}")
        
        self.websocket = websocket.WebSocketApp(
            ws_url,
            on_open=self.on_websocket_open,
            on_message=self.on_websocket_message,
            on_error=self.on_websocket_error,
            on_close=self.on_websocket_close
        )
        
        return True

    def on_websocket_open(self, ws):
        """WebSocket connection opened"""
        self.logger.info("WebSocket connected")

    def on_websocket_message(self, ws, message):
        """Handle WebSocket message from Pato2"""
        try:
            data = json.loads(message)
            message_type = data.get('type')
            
            if message_type == 'open':
                self.handle_open_stream(data)
            elif message_type == 'data':
                self.handle_stream_data(data)
            elif message_type == 'close':
                self.handle_close_stream(data)
            elif message_type == 'udp_open':
                self.handle_udp_open(data)
            elif message_type == 'udp_data':
                self.handle_udp_data(data)
            elif message_type == 'udp_close':
                self.handle_udp_close(data)
            elif message_type == 'backup_command':
                self.handle_backup_command(data)
            elif message_type == 'ping':
                self.send_websocket_message({'type': 'pong'})
            else:
                self.logger.warning(f"Unknown message type: {message_type}")
                
        except Exception as e:
            self.logger.error(f"Error handling WebSocket message: {e}")

    def on_websocket_error(self, ws, error):
        """WebSocket error occurred"""
        self.logger.error(f"WebSocket error: {error}")

    def on_websocket_close(self, ws, close_status_code, close_msg):
        """WebSocket connection closed"""
        self.logger.warning(f"WebSocket closed: {close_status_code} {close_msg}")
        self.close_all_connections()

    def handle_open_stream(self, data):
        """Handle new stream open request"""
        stream_id = data.get('streamId')
        client_address = data.get('clientAddress', 'unknown')
        target_port = data.get('targetPort')
        try:
            target_port = int(target_port) if target_port is not None else None
        except Exception:
            target_port = None
        
        port_to_use = target_port or self.config['minecraft_port']
        self.logger.info(f"Opening stream {stream_id} for client {client_address} -> 127.0.0.1:{port_to_use}")
        
        try:
            # Connect to local Minecraft server
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(10)
            sock.connect(('127.0.0.1', port_to_use))
            
            self.connections[stream_id] = sock
            
            # Start thread to handle data from Minecraft server
            thread = threading.Thread(
                target=self.handle_minecraft_data,
                args=(stream_id, sock),
                daemon=True
            )
            thread.start()
            
        except Exception as e:
            self.logger.error(f"Failed to open stream {stream_id}: {e}")
            self.send_websocket_message({
                'type': 'error',
                'streamId': stream_id,
                'data': str(e)
            })

    def handle_udp_open(self, data: dict):
        client_id = data.get('clientId')
        target_port = data.get('targetPort')
        try:
            target_port = int(target_port) if target_port is not None else self.config['minecraft_port']
        except Exception:
            target_port = self.config['minecraft_port']
        if not client_id:
            return
        if client_id in self.udp_connections:
            return
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(1.0)
            try:
                sock.connect(('127.0.0.1', target_port))
            except Exception:
                pass
            self.udp_connections[client_id] = sock
            t = threading.Thread(target=self.udp_receive_loop, args=(client_id, sock), daemon=True)
            self.udp_recv_threads[client_id] = t
            t.start()
            self.logger.info(f"Opened UDP client {client_id} -> 127.0.0.1:{target_port}")
        except Exception as e:
            self.logger.error(f"Failed to open UDP client {client_id}: {e}")

    def handle_udp_data(self, data: dict):
        client_id = data.get('clientId')
        payload_b64 = data.get('data')
        if not client_id or payload_b64 is None:
            return
        sock = self.udp_connections.get(client_id)
        if not sock:
            # Implicit open using default port
            self.handle_udp_open({'clientId': client_id, 'targetPort': self.config['minecraft_port']})
            sock = self.udp_connections.get(client_id)
            if not sock:
                return
        try:
            payload = base64.b64decode(payload_b64)
            sock.send(payload)
        except Exception as e:
            self.logger.error(f"UDP send error for client {client_id}: {e}")

    def handle_udp_close(self, data: dict):
        client_id = data.get('clientId')
        if not client_id:
            return
        try:
            if client_id in self.udp_connections:
                try:
                    self.udp_connections[client_id].close()
                except Exception:
                    pass
                del self.udp_connections[client_id]
            if client_id in self.udp_recv_threads:
                del self.udp_recv_threads[client_id]
            self.logger.info(f"Closed UDP client {client_id}")
        except Exception as e:
            self.logger.error(f"Error closing UDP client {client_id}: {e}")

    def udp_receive_loop(self, client_id: str, sock: socket.socket):
        while self.running and client_id in self.udp_connections:
            try:
                data = sock.recv(65535)
                if not data:
                    time.sleep(0.05)
                    continue
                self.send_websocket_message({
                    'type': 'udp_data',
                    'clientId': client_id,
                    'data': base64.b64encode(data).decode('ascii')
                })
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    self.logger.error(f"UDP receive error for {client_id}: {e}")
                break

    def handle_stream_data(self, data):
        """Handle data for existing stream"""
        stream_id = data.get('streamId')
        base64_data = data.get('data')
        
        if stream_id not in self.connections:
            self.logger.warning(f"Received data for unknown stream: {stream_id}")
            return
            
        try:
            # Decode and send to Minecraft server
            raw_data = base64.b64decode(base64_data)
            sock = self.connections.get(stream_id)
            # Validate socket before using it
            try:
                if not sock or sock.fileno() == -1:
                    raise OSError(10038, 'Socket is invalid or closed')
                sock.send(raw_data)
            except Exception as e:
                raise e
            
        except Exception as e:
            self.logger.error(f"Error handling stream data for {stream_id}: {e}")
            self.close_stream(stream_id)

    def handle_close_stream(self, data):
        """Handle stream close request"""
        stream_id = data.get('streamId')
        self.logger.debug(f"Closing stream {stream_id}")
        self.close_stream(stream_id)

    def handle_backup_command(self, data):
        """Handle backup command from Pato2"""
        command = data.get('command', 'backup_now')
        self.logger.info(f"Received backup command: {command}")
        
        if command == 'backup_now':
            # Run backup in background thread
            thread = threading.Thread(
                target=self.backup_manager.create_backup,
                daemon=True
            )
            thread.start()

    def handle_minecraft_data(self, stream_id: str, sock: socket.socket):
        """Handle data from Minecraft server for a specific stream"""
        try:
            while stream_id in self.connections and self.running:
                try:
                    # Always fetch current socket reference to avoid using a closed one
                    current_sock = self.connections.get(stream_id)
                    if not current_sock or current_sock.fileno() == -1:
                        raise OSError(10038, 'Socket is invalid or closed')

                    data = current_sock.recv(4096)
                    if not data:
                        break
                        
                    # Encode and send to Pato2
                    base64_data = base64.b64encode(data).decode('utf-8')
                    self.send_websocket_message({
                        'type': 'data',
                        'streamId': stream_id,
                        'data': base64_data
                    })
                    
                except socket.timeout:
                    continue
                except Exception as e:
                    self.logger.error(f"Error reading from Minecraft server for {stream_id}: {e}")
                    break
                    
        except Exception as e:
            self.logger.error(f"Error in Minecraft data handler for {stream_id}: {e}")
        finally:
            self.close_stream(stream_id)

    def close_stream(self, stream_id: str):
        """Close a specific stream"""
        if stream_id in self.connections:
            try:
                self.connections[stream_id].close()
            except:
                pass
            del self.connections[stream_id]
            
            # Notify Pato2
            self.send_websocket_message({
                'type': 'close',
                'streamId': stream_id
            })

    def close_all_connections(self):
        """Close all active connections"""
        for stream_id in list(self.connections.keys()):
            self.close_stream(stream_id)
        for client_id in list(self.udp_connections.keys()):
            try:
                self.udp_connections[client_id].close()
            except Exception:
                pass
            if client_id in self.udp_connections:
                del self.udp_connections[client_id]
            if client_id in self.udp_recv_threads:
                del self.udp_recv_threads[client_id]

    def send_websocket_message(self, message: dict):
        """Send message via WebSocket"""
        if self.websocket and self.websocket.sock and self.websocket.sock.connected:
            try:
                self.websocket.send(json.dumps(message))
            except Exception as e:
                self.logger.error(f"Error sending WebSocket message: {e}")

    def heartbeat_loop(self):
        """Heartbeat loop thread"""
        while self.running:
            if not self.send_heartbeat():
                self.logger.error("Heartbeat failed, attempting to reconnect...")
                break
            time.sleep(self.config['heartbeat_interval'])

    def websocket_loop(self):
        """WebSocket connection loop with reconnection"""
        reconnect_attempts = 0
        
        while self.running and reconnect_attempts < self.config['max_reconnect_attempts']:
            try:
                if self.connect_websocket():
                    self.websocket.run_forever()
                    
                if self.running:
                    reconnect_attempts += 1
                    self.logger.warning(f"WebSocket disconnected, reconnecting... (attempt {reconnect_attempts})")
                    time.sleep(self.config['reconnect_delay'])
                    
            except Exception as e:
                self.logger.error(f"WebSocket error: {e}")
                reconnect_attempts += 1
                time.sleep(self.config['reconnect_delay'])
        
        if reconnect_attempts >= self.config['max_reconnect_attempts']:
            self.logger.error("Max reconnection attempts reached, shutting down")
            self.shutdown()

    def run(self):
        """Main run loop"""
        self.logger.info("Starting Pato2 Host Agent...")
        
        # Check if Minecraft server directory exists
        if not os.path.exists(self.config['minecraft_dir']):
            self.logger.error(f"Minecraft directory not found: {self.config['minecraft_dir']}")
            return False
        
        # Offer to become host
        if not self.offer_host():
            self.logger.error("Failed to become active host")
            return False
        
        self.running = True
        
        # Start heartbeat thread
        self.heartbeat_thread = threading.Thread(target=self.heartbeat_loop, daemon=True)
        self.heartbeat_thread.start()
        
        # Start WebSocket thread
        self.websocket_thread = threading.Thread(target=self.websocket_loop, daemon=True)
        self.websocket_thread.start()
        
        # Start Minecraft server if not running
        if not self.minecraft_manager.is_server_running():
            self.logger.info("Starting Minecraft server...")
            # Descargar último backup (si existe) antes de iniciar el servidor
            try:
                self.logger.info("Descargando backup más reciente de Google Drive (si existe)...")
                self.backup_manager.download_latest_backup()
            except Exception as e:
                self.logger.error(f"No se pudo descargar el backup más reciente: {e}")
            self.minecraft_manager.start_server()
        
        # Main loop
        try:
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            self.logger.info("Received keyboard interrupt")
            # Flush y detener servidor antes de crear backup
            try:
                if self.minecraft_manager.is_server_running():
                    self.logger.info("Enviando save-all al servidor antes de backup...")
                    self.minecraft_manager.send_command("save-all")
                    time.sleep(2)
                    self.logger.info("Deteniendo servidor Minecraft para liberar archivos...")
                    self.minecraft_manager.stop_server()
                    time.sleep(2)
            except Exception as e:
                self.logger.warning(f"No se pudo detener/flush el servidor antes del backup: {e}")
            
            # Al salir: crear y subir backup comprimiendo mundos y plugins
            try:
                self.logger.info("Creando y subiendo backup antes de salir...")
                self.backup_manager.create_backup()
                self.exit_backup_done = True
            except Exception as e:
                self.logger.error(f"No se pudo crear/subir el backup tras Ctrl+C: {e}")

        self.shutdown()
        return True

    def shutdown(self):
        """Shutdown the host agent"""
        if not self.running:
            return
            
        self.logger.info("Shutting down Host Agent...")
        self.running = False
        
        # Detener el servidor antes de crear backup
        try:
            if self.minecraft_manager.is_server_running():
                self.logger.info("Deteniendo servidor Minecraft en shutdown...")
                # Intentar flush previo
                self.minecraft_manager.send_command("save-all")
                time.sleep(2)
                self.minecraft_manager.stop_server()
                time.sleep(2)
        except Exception as e:
            self.logger.warning(f"No se pudo detener el servidor en shutdown: {e}")
        
        # Crear y subir backup si no se hizo ya
        if not self.exit_backup_done:
            try:
                self.logger.info("Creando y subiendo backup en shutdown...")
                self.backup_manager.create_backup()
                self.exit_backup_done = True
            except Exception as e:
                self.logger.warning(f"No se pudo crear/subir backup en shutdown: {e}")
        
        # Close all connections
        self.close_all_connections()
        
        # Close WebSocket
        if self.websocket:
            self.websocket.close()
        
        # End lease
        self.end_lease()
        
        # Stop Minecraft server if we started it
        # self.minecraft_manager.stop_server()
        
        self.logger.info("Host Agent shutdown complete")

def main():
    """Main entry point"""
    agent = HostAgent()
    
    try:
        success = agent.run()
        sys.exit(0 if success else 1)
    except Exception as e:
        agent.logger.error(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()