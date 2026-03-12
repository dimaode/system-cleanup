<#
.SYNOPSIS
    ClawSysAdmin - Database Initialization Module
.DESCRIPTION
    Initialize SQLite database for system monitoring and learning
.AUTHOR
    NightClaw Digital
.VERSION
    0.2.0
#>

# Set encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Database path
$DataDir = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/data"
$DbPath = "$DataDir/clawsysadmin.db"

# Ensure data directory exists
if (!(Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

# Check if SQLite module is available
function Test-SQLiteAvailable {
    try {
        $null = [System.Data.SQLite.SQLiteConnection]
        return $true
    } catch {
        return $false
    }
}

# Initialize database using ADO.NET
function Initialize-Database {
    Write-Host "Initializing ClawSysAdmin database..." -ForegroundColor Cyan
    
    try {
        # Use System.Data.SQLite or fall back to native SQLite3
        if (Test-SQLiteAvailable) {
            Initialize-WithSQLiteNET
        } else {
            Initialize-WithSQLite3
        }
        
        Write-Host "Database initialized successfully!" -ForegroundColor Green
        Write-Host "Database location: $DbPath" -ForegroundColor Gray
        return $true
    } catch {
        Write-Host "Failed to initialize database: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Initialize using System.Data.SQLite
function Initialize-WithSQLiteNET {
    $connectionString = "Data Source=$DbPath;Version=3;"
    $connection = New-Object System.Data.SQLite.SQLiteConnection($connectionString)
    $connection.Open()
    
    # Create tables
    $commands = @"
-- System metrics table
CREATE TABLE IF NOT EXISTS system_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cpu_usage REAL,
    cpu_cores INTEGER,
    memory_total_bytes INTEGER,
    memory_used_bytes INTEGER,
    memory_usage_percent REAL,
    disk_total_bytes INTEGER,
    disk_used_bytes INTEGER,
    disk_usage_percent REAL,
    network_rx_bytes INTEGER,
    network_tx_bytes INTEGER,
    uptime_seconds INTEGER
);

-- Disk details table
CREATE TABLE IF NOT EXISTS disk_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    drive_letter TEXT,
    total_bytes INTEGER,
    used_bytes INTEGER,
    free_bytes INTEGER,
    usage_percent REAL
);

-- Process usage table
CREATE TABLE IF NOT EXISTS process_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    process_name TEXT,
    cpu_percent REAL,
    memory_bytes INTEGER,
    runtime_seconds INTEGER
);

-- Software usage tracking
CREATE TABLE IF NOT EXISTS software_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date DATE,
    software_name TEXT,
    executable_path TEXT,
    launch_count INTEGER DEFAULT 0,
    total_runtime_seconds INTEGER DEFAULT 0,
    last_used DATETIME
);

-- User activity tracking
CREATE TABLE IF NOT EXISTS user_activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    hour_of_day INTEGER,
    day_of_week INTEGER,
    active_window_title TEXT,
    session_duration_seconds INTEGER
);

-- Cleanup history
CREATE TABLE IF NOT EXISTS cleanup_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cleanup_type TEXT,
    files_deleted INTEGER,
    bytes_freed INTEGER,
    duration_seconds INTEGER
);

-- System events
CREATE TABLE IF NOT EXISTS system_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    event_type TEXT,
    event_data TEXT,
    severity TEXT
);

-- Learning configuration
CREATE TABLE IF NOT EXISTS learning_config (
    id INTEGER PRIMARY KEY,
    learning_start_date DATETIME,
    learning_days INTEGER DEFAULT 7,
    is_learning_complete BOOLEAN DEFAULT 0,
    user_profile_generated BOOLEAN DEFAULT 0
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON system_metrics(timestamp);
CREATE INDEX IF NOT EXISTS idx_process_timestamp ON process_usage(timestamp);
CREATE INDEX IF NOT EXISTS idx_software_date ON software_usage(date);
CREATE INDEX IF NOT EXISTS idx_activity_timestamp ON user_activity(timestamp);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON system_events(timestamp);

-- Insert default learning config
INSERT OR IGNORE INTO learning_config (id, learning_start_date, learning_days) 
VALUES (1, CURRENT_TIMESTAMP, 7);
"@

    $command = New-Object System.Data.SQLite.SQLiteCommand($commands, $connection)
    $command.ExecuteNonQuery() | Out-Null
    $connection.Close()
}

# Initialize using sqlite3 command line
function Initialize-WithSQLite3 {
    # Check if sqlite3 is available
    $sqlite3 = Get-Command sqlite3 -ErrorAction SilentlyContinue
    
    if (!$sqlite3) {
        # Fallback: Create a simple JSON-based storage
        Write-Host "SQLite3 not found. Using JSON-based storage as fallback." -ForegroundColor Yellow
        Initialize-WithJSON
        return
    }
    
    $sqlScript = @"
CREATE TABLE IF NOT EXISTS system_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cpu_usage REAL,
    cpu_cores INTEGER,
    memory_total_bytes INTEGER,
    memory_used_bytes INTEGER,
    memory_usage_percent REAL,
    disk_total_bytes INTEGER,
    disk_used_bytes INTEGER,
    disk_usage_percent REAL,
    network_rx_bytes INTEGER,
    network_tx_bytes INTEGER,
    uptime_seconds INTEGER
);

CREATE TABLE IF NOT EXISTS disk_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    drive_letter TEXT,
    total_bytes INTEGER,
    used_bytes INTEGER,
    free_bytes INTEGER,
    usage_percent REAL
);

CREATE TABLE IF NOT EXISTS process_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    process_name TEXT,
    cpu_percent REAL,
    memory_bytes INTEGER,
    runtime_seconds INTEGER
);

CREATE TABLE IF NOT EXISTS software_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date DATE,
    software_name TEXT,
    executable_path TEXT,
    launch_count INTEGER DEFAULT 0,
    total_runtime_seconds INTEGER DEFAULT 0,
    last_used DATETIME
);

CREATE TABLE IF NOT EXISTS cleanup_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cleanup_type TEXT,
    files_deleted INTEGER,
    bytes_freed INTEGER,
    duration_seconds INTEGER
);

CREATE TABLE IF NOT EXISTS system_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    event_type TEXT,
    event_data TEXT,
    severity TEXT
);

CREATE TABLE IF NOT EXISTS learning_config (
    id INTEGER PRIMARY KEY,
    learning_start_date DATETIME,
    learning_days INTEGER DEFAULT 7,
    is_learning_complete BOOLEAN DEFAULT 0,
    user_profile_generated BOOLEAN DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON system_metrics(timestamp);
CREATE INDEX IF NOT EXISTS idx_process_timestamp ON process_usage(timestamp);
CREATE INDEX IF NOT EXISTS idx_software_date ON software_usage(date);

INSERT OR IGNORE INTO learning_config (id, learning_start_date, learning_days) 
VALUES (1, datetime('now'), 7);
"@

    $sqlScript | sqlite3 $DbPath
}

# JSON-based fallback storage
function Initialize-WithJSON {
    $jsonDb = @{
        version = "0.2.0"
        created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        tables = @{
            system_metrics = @()
            disk_metrics = @()
            process_usage = @()
            software_usage = @()
            cleanup_history = @()
            system_events = @()
        }
        config = @{
            learning_start_date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            learning_days = 7
            is_learning_complete = $false
            user_profile_generated = $false
        }
    }
    
    $jsonDb | ConvertTo-Json -Depth 10 | Out-File -FilePath "$DataDir/clawsysadmin.json" -Encoding UTF8
    Write-Host "JSON database created at: $DataDir/clawsysadmin.json" -ForegroundColor Green
}

# Main execution
Initialize-Database
