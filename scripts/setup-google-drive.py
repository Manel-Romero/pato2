#!/usr/bin/env python3
"""
Google Drive Setup Script for Pato2 Backups
This script helps configure Google Drive OAuth credentials for automatic backups.
"""

import os
import sys
import json
import webbrowser
from pathlib import Path
import subprocess

# Colors for terminal output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_header(text):
    print(f"\n{Colors.HEADER}{Colors.BOLD}=== {text} ==={Colors.ENDC}")

def print_success(text):
    print(f"{Colors.OKGREEN}[SUCCESS]{Colors.ENDC} {text}")

def print_info(text):
    print(f"{Colors.OKBLUE}[INFO]{Colors.ENDC} {text}")

def print_warning(text):
    print(f"{Colors.WARNING}[WARNING]{Colors.ENDC} {text}")

def print_error(text):
    print(f"{Colors.FAIL}[ERROR]{Colors.ENDC} {text}")

def print_step(step, text):
    print(f"{Colors.OKCYAN}[STEP {step}]{Colors.ENDC} {text}")

def check_dependencies():
    """Check if required Python packages are installed."""
    print_header("Checking Dependencies")
    
    required_packages = ['google-auth', 'google-auth-oauthlib', 'google-api-python-client']
    missing_packages = []
    
    for package in required_packages:
        try:
            __import__(package.replace('-', '_'))
            print_success(f"{package} is installed")
        except ImportError:
            missing_packages.append(package)
            print_warning(f"{package} is not installed")
    
    if missing_packages:
        print_info("Installing missing packages...")
        try:
            subprocess.check_call([sys.executable, '-m', 'pip', 'install'] + missing_packages)
            print_success("All dependencies installed successfully")
        except subprocess.CalledProcessError:
            print_error("Failed to install dependencies")
            print_info("Please install manually: pip install " + " ".join(missing_packages))
            return False
    
    return True

def setup_google_cloud_console():
    """Guide user through Google Cloud Console setup."""
    print_header("Google Cloud Console Setup")
    
    print_step(1, "Create a Google Cloud Project")
    print("1. Go to: https://console.cloud.google.com/")
    print("2. Click 'Select a project' -> 'New Project'")
    print("3. Enter project name: 'Pato2 Backups'")
    print("4. Click 'Create'")
    
    input("\nPress Enter when you've created the project...")
    
    print_step(2, "Enable Google Drive API")
    print("1. In the Google Cloud Console, go to 'APIs & Services' -> 'Library'")
    print("2. Search for 'Google Drive API'")
    print("3. Click on it and press 'Enable'")
    
    input("\nPress Enter when you've enabled the API...")
    
    print_step(3, "Create OAuth 2.0 Credentials")
    print("1. Go to 'APIs & Services' -> 'Credentials'")
    print("2. Click '+ CREATE CREDENTIALS' -> 'OAuth client ID'")
    print("3. If prompted, configure OAuth consent screen:")
    print("   - User Type: External")
    print("   - App name: Pato2 Backup System")
    print("   - User support email: your email")
    print("   - Developer contact: your email")
    print("4. For OAuth client ID:")
    print("   - Application type: Desktop application")
    print("   - Name: Pato2 Desktop Client")
    print("5. Click 'Create'")
    print("6. Download the JSON file (client_secret_xxx.json)")
    
    input("\nPress Enter when you've downloaded the credentials file...")

def get_credentials_file():
    """Get the path to the credentials file."""
    print_header("Credentials File Setup")
    
    while True:
        cred_path = input("Enter the path to your downloaded credentials JSON file: ").strip()
        
        if not cred_path:
            print_warning("Please enter a valid path")
            continue
            
        cred_path = Path(cred_path).expanduser().resolve()
        
        if not cred_path.exists():
            print_error(f"File not found: {cred_path}")
            continue
            
        if not cred_path.suffix == '.json':
            print_error("File must be a JSON file")
            continue
            
        try:
            with open(cred_path, 'r') as f:
                cred_data = json.load(f)
                
            if 'installed' not in cred_data:
                print_error("Invalid credentials file format")
                continue
                
            print_success(f"Valid credentials file found: {cred_path}")
            return cred_path, cred_data
            
        except json.JSONDecodeError:
            print_error("Invalid JSON file")
            continue

def authenticate_google_drive(cred_path):
    """Authenticate with Google Drive and get refresh token."""
    print_header("Google Drive Authentication")
    
    try:
        from google_auth_oauthlib.flow import InstalledAppFlow
        from google.auth.transport.requests import Request
        
        # Scopes required for Google Drive access
        SCOPES = ['https://www.googleapis.com/auth/drive.file']
        
        print_info("Starting OAuth flow...")
        
        flow = InstalledAppFlow.from_client_secrets_file(
            str(cred_path), SCOPES)
        
        # Run the OAuth flow
        creds = flow.run_local_server(port=0)
        
        print_success("Authentication successful!")
        
        # Extract credentials
        client_id = creds.client_id
        client_secret = creds.client_secret
        refresh_token = creds.refresh_token
        
        return {
            'client_id': client_id,
            'client_secret': client_secret,
            'refresh_token': refresh_token
        }
        
    except Exception as e:
        print_error(f"Authentication failed: {e}")
        return None

def create_backup_folder(credentials):
    """Create a backup folder in Google Drive."""
    print_header("Creating Backup Folder")
    
    try:
        from googleapiclient.discovery import build
        from google.oauth2.credentials import Credentials
        
        # Create credentials object
        creds = Credentials(
            token=None,
            refresh_token=credentials['refresh_token'],
            token_uri='https://oauth2.googleapis.com/token',
            client_id=credentials['client_id'],
            client_secret=credentials['client_secret']
        )
        
        # Build the service
        service = build('drive', 'v3', credentials=creds)
        
        # Create folder
        folder_metadata = {
            'name': 'Pato2 Backups',
            'mimeType': 'application/vnd.google-apps.folder'
        }
        
        folder = service.files().create(body=folder_metadata, fields='id').execute()
        folder_id = folder.get('id')
        
        print_success(f"Backup folder created with ID: {folder_id}")
        return folder_id
        
    except Exception as e:
        print_error(f"Failed to create backup folder: {e}")
        return None

def generate_env_config(credentials, folder_id):
    """Generate .env configuration for Google Drive."""
    print_header("Generating Configuration")
    
    env_config = f"""
# Google Drive Backup Configuration
GOOGLE_CLIENT_ID={credentials['client_id']}
GOOGLE_CLIENT_SECRET={credentials['client_secret']}
GOOGLE_REFRESH_TOKEN={credentials['refresh_token']}
GOOGLE_DRIVE_FOLDER_ID={folder_id}

# Backup Settings
BACKUP_ENABLED=true
BACKUP_INTERVAL=3600  # 1 hour in seconds
BACKUP_RETENTION=7    # days
BACKUP_COMPRESSION=true
"""
    
    # Write to file
    config_file = Path('.env.google-drive')
    with open(config_file, 'w') as f:
        f.write(env_config.strip())
    
    print_success(f"Configuration saved to: {config_file.absolute()}")
    
    print_info("Add these lines to your main .env file:")
    print(env_config)
    
    return config_file

def test_backup_functionality(credentials, folder_id):
    """Test the backup functionality."""
    print_header("Testing Backup Functionality")
    
    try:
        from googleapiclient.discovery import build
        from google.oauth2.credentials import Credentials
        import io
        from googleapiclient.http import MediaIoBaseUpload
        
        # Create credentials object
        creds = Credentials(
            token=None,
            refresh_token=credentials['refresh_token'],
            token_uri='https://oauth2.googleapis.com/token',
            client_id=credentials['client_id'],
            client_secret=credentials['client_secret']
        )
        
        # Build the service
        service = build('drive', 'v3', credentials=creds)
        
        # Create a test file
        test_content = "This is a test backup file created by Pato2 setup script."
        test_file = io.BytesIO(test_content.encode())
        
        file_metadata = {
            'name': 'pato2-test-backup.txt',
            'parents': [folder_id]
        }
        
        media = MediaIoBaseUpload(test_file, mimetype='text/plain')
        
        file = service.files().create(
            body=file_metadata,
            media_body=media,
            fields='id'
        ).execute()
        
        print_success(f"Test backup successful! File ID: {file.get('id')}")
        
        # Clean up test file
        service.files().delete(fileId=file.get('id')).execute()
        print_info("Test file cleaned up")
        
        return True
        
    except Exception as e:
        print_error(f"Backup test failed: {e}")
        return False

def main():
    """Main setup function."""
    print(f"{Colors.HEADER}{Colors.BOLD}")
    print("=" * 50)
    print("  Google Drive Setup for Pato2 Backups")
    print("=" * 50)
    print(f"{Colors.ENDC}")
    
    print_info("This script will help you set up Google Drive backups for Pato2")
    print_info("You'll need a Google account and about 10 minutes")
    
    if not input("\nDo you want to continue? (y/N): ").lower().startswith('y'):
        print_info("Setup cancelled")
        return
    
    # Check dependencies
    if not check_dependencies():
        return
    
    # Guide through Google Cloud Console setup
    setup_google_cloud_console()
    
    # Get credentials file
    cred_path, cred_data = get_credentials_file()
    
    # Authenticate with Google Drive
    credentials = authenticate_google_drive(cred_path)
    if not credentials:
        return
    
    # Create backup folder
    folder_id = create_backup_folder(credentials)
    if not folder_id:
        return
    
    # Generate configuration
    config_file = generate_env_config(credentials, folder_id)
    
    # Test backup functionality
    if test_backup_functionality(credentials, folder_id):
        print_header("Setup Complete!")
        print_success("Google Drive backup is now configured for Pato2!")
        print_info(f"Configuration saved to: {config_file}")
        print_info("Copy the configuration to your main .env file")
        print_info("Restart your Pato2 server to enable backups")
    else:
        print_error("Setup completed but backup test failed")
        print_info("Check your configuration and try again")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print_info("\nSetup cancelled by user")
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        sys.exit(1)