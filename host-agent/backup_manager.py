"""
Google Drive Backup Manager
Handles creating and uploading Minecraft world backups to Google Drive
"""

import os
import zipfile
import logging
import json
import time
from datetime import datetime, timedelta
from typing import List, Optional
import tempfile
import shutil

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload, MediaIoBaseDownload
from googleapiclient.errors import HttpError

class BackupManager:
    def __init__(self, config: dict):
        self.config = config
        self.logger = logging.getLogger('BackupManager')
        
        # Google Drive configuration
        self.folder_id = config.get('google_drive_folder_id')
        self.client_id = config.get('google_drive_client_id')
        self.client_secret = config.get('google_drive_client_secret')
        self.refresh_token = config.get('google_drive_refresh_token')
        
        # Backup configuration
        self.minecraft_dir = config.get('minecraft_dir', './minecraft')
        self.backups_path = config.get('backups_path', './backups')
        self.backup_interval_hours = int(config.get('backup_interval_hours', '24'))
        self.backup_retention_days = int(config.get('backup_retention_days', '7'))
        
        # Ensure backups directory exists
        os.makedirs(self.backups_path, exist_ok=True)
        
        # Google Drive service
        self.drive_service = None
        self._initialize_drive_service()
    
    def _initialize_drive_service(self):
        """Initialize Google Drive service with OAuth credentials"""
        try:
            if not all([self.client_id, self.client_secret, self.refresh_token]):
                self.logger.warning("Google Drive credentials not configured, backups disabled")
                return
            
            # Create credentials from refresh token
            creds = Credentials(
                token=None,
                refresh_token=self.refresh_token,
                token_uri='https://oauth2.googleapis.com/token',
                client_id=self.client_id,
                client_secret=self.client_secret
            )
            
            # Refresh the token
            creds.refresh(Request())
            
            # Build the service
            self.drive_service = build('drive', 'v3', credentials=creds)
            self.logger.info("Google Drive service initialized successfully")
            
        except Exception as e:
            self.logger.error(f"Failed to initialize Google Drive service: {e}")
            self.drive_service = None
    
    def create_backup(self) -> bool:
        """Create a backup of the Minecraft world and upload to Google Drive"""
        if not self.drive_service:
            self.logger.error("Google Drive service not available")
            return False
        
        try:
            # Create local backup first
            backup_file = self._create_local_backup()
            if not backup_file:
                return False
            
            # Upload to Google Drive
            success = self._upload_to_drive(backup_file)
            
            # Clean up local backup file
            try:
                os.remove(backup_file)
                self.logger.debug(f"Cleaned up local backup file: {backup_file}")
            except Exception as e:
                self.logger.warning(f"Failed to clean up local backup file: {e}")
            
            if success:
                # Clean up old backups
                self._cleanup_old_backups()
            
            return success
            
        except Exception as e:
            self.logger.error(f"Error creating backup: {e}")
            return False
    
    def _create_local_backup(self) -> Optional[str]:
        """Create a local ZIP backup with progress"""
        try:
            # Detectar mundos (principal y dimensiones)
            world_name = os.getenv('WORLD_NAME', 'world')
            candidate_worlds = [
                world_name,
                f"{world_name}_nether",
                f"{world_name}_the_end"
            ]
            world_dirs = []
            for w in candidate_worlds:
                p = os.path.join(self.minecraft_dir, w)
                if os.path.exists(p):
                    world_dirs.append((p, w))
            if not world_dirs:
                self.logger.error("No se encontraron directorios de mundo para respaldar")
                return None
            
            # Generate backup filename with timestamp
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            backup_filename = f"minecraft_backup_{timestamp}.zip"
            backup_path = os.path.join(self.backups_path, backup_filename)
            
            self.logger.info(f"Creating local backup: {backup_path}")
            
            # Pre-calcular tamaño total para barra de progreso
            total_bytes = 0
            files_to_zip = []
            for dir_path, arc_name in world_dirs:
                for root, _, files in os.walk(dir_path):
                    for f in files:
                        fp = os.path.join(root, f)
                        try:
                            size = os.path.getsize(fp)
                        except Exception:
                            size = 0
                        files_to_zip.append((fp, os.path.join(arc_name, os.path.relpath(fp, dir_path)), size))
                        total_bytes += size
            plugins_dir = os.path.join(self.minecraft_dir, 'plugins')
            if os.path.exists(plugins_dir):
                for root, _, files in os.walk(plugins_dir):
                    for f in files:
                        fp = os.path.join(root, f)
                        try:
                            size = os.path.getsize(fp)
                        except Exception:
                            size = 0
                        files_to_zip.append((fp, os.path.join('plugins', os.path.relpath(fp, plugins_dir)), size))
                        total_bytes += size
            important_files = [
                'server.properties',
                'whitelist.json',
                'ops.json',
                'banned-players.json',
                'banned-ips.json'
            ]
            for filename in important_files:
                file_path = os.path.join(self.minecraft_dir, filename)
                if os.path.exists(file_path):
                    try:
                        size = os.path.getsize(file_path)
                    except Exception:
                        size = 0
                    files_to_zip.append((file_path, filename, size))
                    total_bytes += size

            # Crear ZIP con barra de progreso
            with zipfile.ZipFile(backup_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                written_bytes = 0
                steps = 6
                thresholds = [int(i * (100 / steps)) for i in range(1, steps)] + [100]
                next_idx = 0
                for fp, arc, size in files_to_zip:
                    try:
                        zipf.write(fp, arc)
                        written_bytes += size
                        percent = int((written_bytes / total_bytes) * 100) if total_bytes > 0 else 100
                        while next_idx < len(thresholds) and percent >= thresholds[next_idx]:
                            bar_len = 30
                            filled_len = int(bar_len * thresholds[next_idx] / 100)
                            bar = '#' * filled_len + '-' * (bar_len - filled_len)
                            self.logger.info(f"Progreso compresión: |{bar}| {thresholds[next_idx]}% ({written_bytes} / {total_bytes} bytes)")
                            next_idx += 1
                    except PermissionError as e:
                        self.logger.warning(f"Skipping locked file during backup: {fp} ({e})")
                    except Exception as e:
                        self.logger.warning(f"Failed to add file to backup: {fp} ({e})")
            
            # Verify backup was created
            if os.path.exists(backup_path):
                file_size = os.path.getsize(backup_path)
                self.logger.info(f"Local backup created successfully: {backup_path} ({file_size} bytes)")
                return backup_path
            else:
                self.logger.error("Backup file was not created")
                return None
                
        except Exception as e:
            self.logger.error(f"Error creating local backup: {e}")
            return None
    
    def _add_directory_to_zip(self, zipf: zipfile.ZipFile, dir_path: str, arc_name: str):
        """Recursively add directory contents to ZIP file"""
        for root, dirs, files in os.walk(dir_path):
            for file in files:
                file_path = os.path.join(root, file)
                arc_path = os.path.join(arc_name, os.path.relpath(file_path, dir_path))
                try:
                    zipf.write(file_path, arc_path)
                except PermissionError as e:
                    self.logger.warning(f"Skipping locked file during backup: {file_path} ({e})")
                except Exception as e:
                    self.logger.warning(f"Failed to add file to backup: {file_path} ({e})")
    
    def _upload_to_drive(self, backup_file: str) -> bool:
        """Upload backup file to Google Drive"""
        try:
            filename = os.path.basename(backup_file)
            self.logger.info(f"Subiendo backup a Google Drive: {filename}")
            
            # File metadata
            file_metadata = {
                'name': filename,
                'parents': [self.folder_id] if self.folder_id else []
            }
            
            media = MediaFileUpload(backup_file, resumable=True)
            request = self.drive_service.files().create(
                body=file_metadata,
                media_body=media,
                fields='id'
            )

            response = None
            last_percent = -1
            try:
                total_size = os.path.getsize(backup_file)
            except Exception:
                total_size = None

            while response is None:
                status, response = request.next_chunk()
                if status:
                    percent = int(status.progress() * 100)
                    if percent != last_percent:
                        bar_len = 30
                        filled_len = int(bar_len * percent / 100)
                        bar = '#' * filled_len + '-' * (bar_len - filled_len)
                        if total_size is not None:
                            uploaded = int(total_size * status.progress())
                            self.logger.info(f"Progreso subida: |{bar}| {percent}% ({uploaded} bytes)")
                        else:
                            self.logger.info(f"Progreso subida: |{bar}| {percent}%")
                        last_percent = percent

            file_id = response.get('id')
            self.logger.info(f"Backup subido correctamente a Google Drive: {file_id}")
            return True
            
        except HttpError as e:
            self.logger.error(f"Error de API de Google Drive: {e}")
            return False
        except Exception as e:
            self.logger.error(f"Error subiendo a Google Drive: {e}")
            return False
    
    def _cleanup_old_backups(self):
        """Remove old backups from Google Drive based on retention policy"""
        try:
            if not self.folder_id:
                self.logger.warning("No folder ID specified, skipping cleanup")
                return
            
            # Calculate cutoff date
            cutoff_date = datetime.now() - timedelta(days=self.backup_retention_days)
            cutoff_str = cutoff_date.isoformat() + 'Z'
            
            # Query for old backup files
            query = f"parents in '{self.folder_id}' and name contains 'minecraft_backup_' and createdTime < '{cutoff_str}'"
            
            results = self.drive_service.files().list(
                q=query,
                fields='files(id, name, createdTime)'
            ).execute()
            
            files = results.get('files', [])
            
            if not files:
                self.logger.debug("No old backups to clean up")
                return
            
            # Delete old files
            deleted_count = 0
            for file in files:
                try:
                    self.drive_service.files().delete(fileId=file['id']).execute()
                    self.logger.info(f"Deleted old backup: {file['name']} (created: {file['createdTime']})")
                    deleted_count += 1
                except Exception as e:
                    self.logger.error(f"Failed to delete backup {file['name']}: {e}")
            
            if deleted_count > 0:
                self.logger.info(f"Cleaned up {deleted_count} old backup(s)")
                
        except Exception as e:
            self.logger.error(f"Error during backup cleanup: {e}")
    
    def list_backups(self) -> List[dict]:
        """List all backups in Google Drive"""
        try:
            if not self.drive_service or not self.folder_id:
                return []
            
            query = f"parents in '{self.folder_id}' and name contains 'minecraft_backup_'"
            
            results = self.drive_service.files().list(
                q=query,
                fields='files(id, name, size, createdTime, modifiedTime)',
                orderBy='createdTime desc'
            ).execute()
            
            return results.get('files', [])
            
        except Exception as e:
            self.logger.error(f"Error listing backups: {e}")
            return []
    
    def download_backup(self, file_id: str, download_path: str) -> bool:
        """Download a backup from Google Drive"""
        try:
            if not self.drive_service:
                self.logger.error("Google Drive service not available")
                return False
            
            # Get file metadata
            file_metadata = self.drive_service.files().get(fileId=file_id).execute()
            filename = file_metadata.get('name', 'backup.zip')
            
            self.logger.info(f"Downloading backup: {filename}")
            
            # Download file
            request = self.drive_service.files().get_media(fileId=file_id)
            
            with open(download_path, 'wb') as f:
                downloader = MediaIoBaseDownload(f, request)
                done = False
                last_percent = -1
                total_size = int(file_metadata.get('size', 0)) if file_metadata.get('size') else None
                while done is False:
                    status, done = downloader.next_chunk()
                    if status:
                        percent = int(status.progress() * 100)
                        if percent != last_percent:
                            bar_len = 30
                            filled_len = int(bar_len * percent / 100)
                            bar = '#' * filled_len + '-' * (bar_len - filled_len)
                            if total_size:
                                downloaded = int(total_size * status.progress())
                                self.logger.info(f"Progreso descarga: |{bar}| {percent}% ({downloaded} bytes)")
                            else:
                                self.logger.info(f"Progreso descarga: |{bar}| {percent}%")
                            last_percent = percent
            
            self.logger.info(f"Backup downloaded successfully: {download_path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Error downloading backup: {e}")
            return False

    def download_latest_backup(self) -> Optional[str]:
        """Download the most recent backup from Google Drive into backups_path"""
        try:
            if not self.drive_service:
                self.logger.error("Google Drive service not available")
                return None

            backups = self.list_backups()
            if not backups:
                self.logger.info("No hay backups disponibles en Google Drive")
                return None

            latest = backups[0]
            filename = latest.get('name', 'backup.zip')
            download_path = os.path.join(self.backups_path, filename)

            self.logger.info(f"Descargando último backup: {filename}")

            request = self.drive_service.files().get_media(fileId=latest['id'])
            with open(download_path, 'wb') as f:
                downloader = MediaIoBaseDownload(f, request)
                done = False
                last_percent = -1
                size_meta = latest.get('size')
                total_size = int(size_meta) if size_meta else None
                while not done:
                    status, done = downloader.next_chunk()
                    if status:
                        percent = int(status.progress() * 100)
                        if percent != last_percent:
                            bar_len = 30
                            filled_len = int(bar_len * percent / 100)
                            bar = '#' * filled_len + '-' * (bar_len - filled_len)
                            if total_size:
                                downloaded = int(total_size * status.progress())
                                self.logger.info(f"Progreso descarga: |{bar}| {percent}% ({downloaded} bytes)")
                            else:
                                self.logger.info(f"Progreso descarga: |{bar}| {percent}%")
                            last_percent = percent

            self.logger.info(f"Backup descargado correctamente: {download_path}")
            return download_path

        except Exception as e:
            self.logger.error(f"Error al descargar el último backup: {e}")
            return None
    
    def restore_backup(self, backup_file: str) -> bool:
        """Restore a backup to the Minecraft directory with progress"""
        try:
            if not os.path.exists(backup_file):
                self.logger.error(f"Backup file not found: {backup_file}")
                return False
            
            self.logger.info(f"Restoring backup: {backup_file}")
            
            # Create temporary extraction directory
            with tempfile.TemporaryDirectory() as temp_dir:
                # Extract backup
                with zipfile.ZipFile(backup_file, 'r') as zipf:
                    infos = zipf.infolist()
                    total_bytes = sum(info.file_size for info in infos)
                    extracted_bytes = 0
                    last_percent = -1
                    for info in infos:
                        zipf.extract(info, temp_dir)
                        extracted_bytes += info.file_size
                        percent = int((extracted_bytes / total_bytes) * 100) if total_bytes > 0 else 100
                        if percent != last_percent:
                            bar_len = 30
                            filled_len = int(bar_len * percent / 100)
                            bar = '#' * filled_len + '-' * (bar_len - filled_len)
                            self.logger.info(f"Progreso descompresión: |{bar}| {percent}% ({extracted_bytes} / {total_bytes} bytes)")
                            last_percent = percent
                
                # Stop Minecraft server if running
                # (This should be handled by the calling code)
                
                # Backup current world (just in case)
                current_world = os.path.join(self.minecraft_dir, 'world')
                if os.path.exists(current_world):
                    backup_current = f"{current_world}_backup_{int(time.time())}"
                    shutil.move(current_world, backup_current)
                    self.logger.info(f"Current world backed up to: {backup_current}")
                
                # Restore world directory
                extracted_world = os.path.join(temp_dir, 'world')
                if os.path.exists(extracted_world):
                    shutil.copytree(extracted_world, current_world)
                    self.logger.info("World directory restored")
                
                # Restore server files
                server_files = [
                    'server.properties',
                    'whitelist.json',
                    'ops.json',
                    'banned-players.json',
                    'banned-ips.json'
                ]
                
                for filename in server_files:
                    extracted_file = os.path.join(temp_dir, filename)
                    target_file = os.path.join(self.minecraft_dir, filename)
                    
                    if os.path.exists(extracted_file):
                        shutil.copy2(extracted_file, target_file)
                        self.logger.debug(f"Restored {filename}")
            
            self.logger.info("Backup restored successfully")
            return True
            
        except Exception as e:
            self.logger.error(f"Error restoring backup: {e}")
            return False
    
    def get_backup_status(self) -> dict:
        """Get backup system status"""
        return {
            'drive_service_available': self.drive_service is not None,
            'folder_id': self.folder_id,
            'backups_path': self.backups_path,
            'backup_interval_hours': self.backup_interval_hours,
            'backup_retention_days': self.backup_retention_days,
            'last_backup': self._get_last_backup_info()
        }
    
    def _get_last_backup_info(self) -> Optional[dict]:
        """Get information about the last backup"""
        try:
            backups = self.list_backups()
            if backups:
                latest = backups[0]  # Already sorted by creation time desc
                return {
                    'id': latest['id'],
                    'name': latest['name'],
                    'size': int(latest.get('size', 0)),
                    'created_time': latest['createdTime']
                }
            return None
        except Exception:
            return None