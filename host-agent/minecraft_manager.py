"""
Minecraft Server Manager
Handles starting, stopping, and monitoring Minecraft server
"""

import os
import subprocess
import time
import logging
import psutil
import socket
from typing import Optional

class MinecraftManager:
    def __init__(self, minecraft_dir: str, minecraft_port: int = 25565):
        self.minecraft_dir = minecraft_dir
        self.minecraft_port = minecraft_port
        self.server_process: Optional[subprocess.Popen] = None
        self.logger = logging.getLogger('MinecraftManager')
        
        # Server configuration
        self.server_jar = os.getenv('SERVER_JAR', 'server.jar')
        self.java_args = os.getenv('JAVA_ARGS', '-Xmx2G -Xms1G')
        
    def is_server_running(self) -> bool:
        """Check if Minecraft server is running"""
        try:
            # Check if our process is still alive
            if self.server_process and self.server_process.poll() is None:
                return True
            
            # Check if any process is using the Minecraft port
            for conn in psutil.net_connections():
                if conn.laddr.port == self.minecraft_port and conn.status == 'LISTEN':
                    return True
                    
            return False
        except Exception as e:
            self.logger.error(f"Error checking server status: {e}")
            return False
    
    def is_server_ready(self) -> bool:
        """Check if Minecraft server is ready to accept connections"""
        if not self.is_server_running():
            return False
            
        try:
            # Try to connect to the server port
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            result = sock.connect_ex(('127.0.0.1', self.minecraft_port))
            sock.close()
            return result == 0
        except Exception:
            return False
    
    def start_server(self) -> bool:
        """Start the Minecraft server"""
        if self.is_server_running():
            self.logger.info("Minecraft server is already running")
            return True
            
        try:
            # Change to Minecraft directory
            if not os.path.exists(self.minecraft_dir):
                self.logger.error(f"Minecraft directory does not exist: {self.minecraft_dir}")
                return False
                
            server_jar_path = os.path.join(self.minecraft_dir, self.server_jar)
            if not os.path.exists(server_jar_path):
                self.logger.error(f"Server JAR not found: {server_jar_path}")
                return False
            
            # Prepare command
            java_cmd = [
                'java',
                *self.java_args.split(),
                '-jar',
                self.server_jar,
                'nogui'
            ]
            
            self.logger.info(f"Starting Minecraft server: {' '.join(java_cmd)}")
            
            # Start server process
            self.server_process = subprocess.Popen(
                java_cmd,
                cwd=self.minecraft_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                stdin=subprocess.PIPE,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            # Wait a moment and check if it started successfully
            time.sleep(2)
            if self.server_process.poll() is not None:
                self.logger.error("Minecraft server failed to start")
                return False
            
            self.logger.info("Minecraft server started successfully")
            
            # Wait for server to be ready (up to 60 seconds)
            for i in range(60):
                if self.is_server_ready():
                    self.logger.info("Minecraft server is ready")
                    return True
                time.sleep(1)
            
            self.logger.warning("Minecraft server started but may not be fully ready")
            return True
            
        except Exception as e:
            self.logger.error(f"Error starting Minecraft server: {e}")
            return False
    
    def stop_server(self) -> bool:
        """Stop the Minecraft server gracefully"""
        if not self.is_server_running():
            self.logger.info("Minecraft server is not running")
            return True
            
        try:
            if self.server_process:
                # Send stop command
                self.logger.info("Sending stop command to Minecraft server")
                self.server_process.stdin.write("stop\n")
                self.server_process.stdin.flush()
                
                # Wait for graceful shutdown (up to 30 seconds)
                for i in range(30):
                    if self.server_process.poll() is not None:
                        self.logger.info("Minecraft server stopped gracefully")
                        self.server_process = None
                        return True
                    time.sleep(1)
                
                # Force kill if still running
                self.logger.warning("Force killing Minecraft server")
                self.server_process.terminate()
                time.sleep(5)
                
                if self.server_process.poll() is None:
                    self.server_process.kill()
                
                self.server_process = None
            
            # Double-check by killing any process using the port
            self._kill_processes_on_port()
            
            return True
            
        except Exception as e:
            self.logger.error(f"Error stopping Minecraft server: {e}")
            return False
    
    def restart_server(self) -> bool:
        """Restart the Minecraft server"""
        self.logger.info("Restarting Minecraft server")
        
        if not self.stop_server():
            return False
            
        time.sleep(5)  # Wait a bit between stop and start
        
        return self.start_server()
    
    def send_command(self, command: str) -> bool:
        """Send a command to the Minecraft server"""
        if not self.server_process or self.server_process.poll() is not None:
            self.logger.error("Cannot send command: server is not running")
            return False
            
        try:
            self.logger.debug(f"Sending command to server: {command}")
            self.server_process.stdin.write(f"{command}\n")
            self.server_process.stdin.flush()
            return True
        except Exception as e:
            self.logger.error(f"Error sending command to server: {e}")
            return False
    
    def get_server_info(self) -> dict:
        """Get information about the Minecraft server"""
        return {
            'running': self.is_server_running(),
            'ready': self.is_server_ready(),
            'port': self.minecraft_port,
            'directory': self.minecraft_dir,
            'server_jar': self.server_jar,
            'process_id': self.server_process.pid if self.server_process else None
        }
    
    def _kill_processes_on_port(self):
        """Kill any processes using the Minecraft port"""
        try:
            for proc in psutil.process_iter(['pid', 'name', 'connections']):
                try:
                    for conn in proc.info['connections'] or []:
                        if conn.laddr.port == self.minecraft_port:
                            self.logger.warning(f"Killing process {proc.info['pid']} ({proc.info['name']}) using port {self.minecraft_port}")
                            psutil.Process(proc.info['pid']).terminate()
                            break
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
        except Exception as e:
            self.logger.error(f"Error killing processes on port {self.minecraft_port}: {e}")
    
    def get_world_directory(self) -> str:
        """Get the path to the world directory"""
        world_name = os.getenv('WORLD_NAME', 'world')
        return os.path.join(self.minecraft_dir, world_name)
    
    def backup_world(self, backup_path: str) -> bool:
        """Create a backup of the world directory"""
        import shutil
        
        world_dir = self.get_world_directory()
        if not os.path.exists(world_dir):
            self.logger.error(f"World directory not found: {world_dir}")
            return False
            
        try:
            # Send save-all command if server is running
            if self.is_server_running():
                self.send_command("save-all")
                time.sleep(2)  # Wait for save to complete
            
            # Create backup
            self.logger.info(f"Creating world backup: {backup_path}")
            shutil.copytree(world_dir, backup_path)
            return True
            
        except Exception as e:
            self.logger.error(f"Error creating world backup: {e}")
            return False