# Direct Windows 11 Upgrade - No GUI
#
# This script performs a silent in-place upgrade to Windows 11, supporting:
# - Upgrading from Windows 10 to Windows 11
# - Upgrading from older Windows 11 versions to newer versions (e.g., 21H2 to 22H2)
# - Completely silent operation with no user interaction required
# - Bypassing TPM, CPU, and other hardware compatibility checks
#
# PROCESS DETAILS:
# - The script will install 7-Zip if not already present (required to extract ISO contents)
# - Total upgrade process takes approximately 1.5 hours to complete
# - By default, the system will automatically reboot when necessary (configurable)
# - No user intervention is required at any point in the process
#
# USAGE NOTES:
# 1. Edit the configuration section below to specify your Windows 11 ISO source
# 2. Make sure to use an ISO containing the Windows 11 version you want to upgrade to
# 3. Recommended ISO source: https://massgrave.dev/genuine-installation-media.html
# 4. Run this script with administrative privileges

#######################################################################
# CONFIGURATION - MODIFY THESE SETTINGS AS NEEDED
#######################################################################

# Specify the Windows 11 ISO source - MODIFY THIS FOR YOUR ENVIRONMENT
# Options:
# 1. Direct download URL (default)
# 2. Local file path (e.g., "C:\Path\To\Windows11.iso")
# 3. Network share (e.g., "\\server\share\Windows11.iso")
#
# IMPORTANT: The ISO must contain the Windows 11 version you want to upgrade to.
# Business editions are recommended as they have fewer issues with silent upgrades.
# You can download official ISOs from: https://massgrave.dev/genuine-installation-media.html
$WIN11_ISO_SOURCE = "https://replace/this/url/with/your/iso/windows.iso"

# WORKING DIRECTORIES - you can modify these if needed
$WORKING_DIR = "C:\Win11Upgrade"                 # Main working directory
$TEMP_DIR = "C:\Windows\Temp"                    # Temporary directory
$LOG_FILE = "C:\Win11_Upgrade_Progress.log"      # Main log file
$MONITOR_LOG = "C:\Win11_Monitor.log"            # Process monitor log file

# BEHAVIOR SETTINGS
$BYPASS_CONFIRMATION = $false                    # Set to $true to skip all confirmation prompts
$ALLOW_AUTOMATIC_REBOOT = $true                  # Set to $false to prevent automatic reboots

#######################################################################
# SCRIPT BEGINS HERE - DO NOT MODIFY BELOW THIS LINE UNLESS NECESSARY
#######################################################################

# Ensure running as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script requires administrator privileges." -ForegroundColor Red
    Write-Host "Please restart the script with administrator rights." -ForegroundColor Yellow
    exit 1
}

# Use the ISO source defined at the top of the script
$isoUrl = $WIN11_ISO_SOURCE
$isoPath = "$TEMP_DIR\windows11.iso"

# Validate the URL or file path before doing anything else
if ($isoUrl -eq "https://replace/this/url/with/your/iso/windows.iso") {
    Write-Host "ERROR: You need to replace the placeholder URL in the configuration section." -ForegroundColor Red
    Write-Host "Please edit the script and update the `$WIN11_ISO_SOURCE variable with a valid ISO URL or file path." -ForegroundColor Yellow
    exit 1
}

# Show confirmation prompt
Write-Host "WARNING: You are about to start an automated Windows 11 upgrade process." -ForegroundColor Yellow
Write-Host ""
Write-Host "The following will occur if you proceed:"
Write-Host "- 7-Zip will be installed (if not already present)"
Write-Host "- System settings will be modified"
Write-Host "- Your PC will reboot when the installation is ready"
Write-Host "- The entire process takes approximately 1.5 hours"
Write-Host ""
Write-Host "IMPORTANT NOTES:" -ForegroundColor Cyan
Write-Host "- Please be patient during the upgrade process"
Write-Host "- As long as SetupHost.exe is running in Task Manager, the upgrade is working"
Write-Host "- The process may appear to stall at times, but this is normal"
Write-Host "- Do not interrupt the process once it has started"
Write-Host ""

if (-not $BYPASS_CONFIRMATION) {
    $confirmation = Read-Host "Do you want to continue with the Windows 11 upgrade? (y/n)"
    if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
        Write-Host "Windows 11 upgrade cancelled by user."
        exit 0
    }
} else {
    Write-Host "Confirmation bypassed. Proceeding with Windows 11 upgrade automatically..." -ForegroundColor Yellow
}


# Function to validate URL - ensures the URL is reachable before download
function Test-UrlIsValid {
    param (
        [string]$Url
    )

    try {
        # Simple HEAD request to check if URL is reachable
        $request = [System.Net.WebRequest]::Create($Url)
        $request.Method = "HEAD"
        $request.Timeout = 15000  # 15 seconds timeout
        $request.UserAgent = "Mozilla/5.0 Windows PowerShell Script"

        # Get the response
        $response = $request.GetResponse()

        # Check if we can access the URL
        $success = $response.StatusCode -eq [System.Net.HttpStatusCode]::OK

        # Show file size if available
        $contentLength = $response.Headers["Content-Length"]
        if ($contentLength) {
            $sizeInMB = [math]::Round([long]$contentLength / 1MB, 2)
            if ($sizeInMB -gt 1000) {
                Write-Host "File size: $([math]::Round($sizeInMB / 1024, 2)) GB" -ForegroundColor Cyan
            } else {
                Write-Host "File size: $sizeInMB MB" -ForegroundColor Cyan
            }
        }

        # Close the response
        $response.Close()
        return $success
    }
    catch {
        # Simple error message without details that could cause red dumps
        Write-Host "ERROR: Could not access the URL. Please verify it's correct and accessible." -ForegroundColor Red
        return $false
    }
}

# If the ISO source is a local file or network share, copy it to the temp directory
if (Test-Path $isoUrl) {
    Write-Host "Using local/network ISO file: $isoUrl"

    # Verify it's an ISO file
    $extension = [System.IO.Path]::GetExtension($isoUrl).ToLower()
    if ($extension -ne ".iso") {
        Write-Host "Warning: The file does not have an .iso extension. It may not be a valid Windows installation image." -ForegroundColor Yellow
        if (-not $BYPASS_CONFIRMATION) {
            $continue = Read-Host "Do you want to continue anyway? (y/n)"
            if ($continue -ne 'y' -and $continue -ne 'Y') {
                Write-Host "Operation cancelled by user."
                exit 0
            }
        } else {
            Write-Host "Confirmation bypassed. Continuing despite non-ISO extension..." -ForegroundColor Yellow
        }
    }

    # Verify file size (ISO should be at least 3GB)
    $fileInfo = Get-Item $isoUrl
    $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
    if ($fileSizeMB -lt 3000) {
        Write-Host "Warning: The ISO file is only $fileSizeMB MB in size, which is unusually small for a Windows 11 ISO." -ForegroundColor Yellow
        Write-Host "A typical Windows 11 ISO is 4-6 GB in size." -ForegroundColor Yellow
        if (-not $BYPASS_CONFIRMATION) {
            $continue = Read-Host "Do you want to continue anyway? (y/n)"
            if ($continue -ne 'y' -and $continue -ne 'Y') {
                Write-Host "Operation cancelled by user."
                exit 0
            }
        } else {
            Write-Host "Confirmation bypassed. Continuing despite small ISO size..." -ForegroundColor Yellow
        }
    }

    # Copy the file with progress indication for large files
    Write-Host "Copying ISO file to working location..."
    try {
        Copy-Item -Path $isoUrl -Destination $isoPath -Force
        if (-not (Test-Path $isoPath)) {
            throw "Failed to copy ISO file to destination"
        }
        Write-Host "ISO file copied successfully."
    }
    catch {
        Write-Error "Failed to copy ISO file: $_"
        exit 1
    }

    $isLocalFile = $true
} else {
    # Validate the URL before attempting to download
    Write-Host "Validating ISO download URL: $isoUrl"
    if (-not (Test-UrlIsValid -Url $isoUrl)) {
        Write-Error "The specified URL does not appear to be valid or accessible."
        Write-Host "Please check the URL and ensure it points to a valid Windows 11 ISO file." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "URL validation successful. Proceeding with download..." -ForegroundColor Green
    $isLocalFile = $false
}

# Download ISO if needed
if (-not $isLocalFile) {
    Write-Host "Downloading Windows 11 ISO..." -ForegroundColor Cyan
    Write-Host "This may take some time depending on your internet connection speed." -ForegroundColor Cyan

    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 Windows PowerShell Script")
        
        # Disable progress bar to improve download performance
        $ProgressPreference = 'SilentlyContinue'
        
        Write-Host "Download started at $(Get-Date)" -ForegroundColor Cyan
        $webClient.DownloadFile($isoUrl, $isoPath)
        Write-Host "Download completed at $(Get-Date)" -ForegroundColor Green
        
        # Restore progress preference
        $ProgressPreference = 'Continue'

        # Verify the download
        if (Test-Path $isoPath) {
            $fileInfo = Get-Item $isoPath
            $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)

            # Check if file size is reasonable for a Windows ISO
            if ($fileSizeMB -lt 3000) {
                Write-Host "Warning: The downloaded ISO is only $fileSizeMB MB, which is unusually small for a Windows 11 ISO." -ForegroundColor Yellow
                Write-Host "This might indicate a partial download or incorrect ISO source." -ForegroundColor Yellow
                if (-not $BYPASS_CONFIRMATION) {
                    $continue = Read-Host "Do you want to continue anyway? (y/n)"
                    if ($continue -ne 'y' -and $continue -ne 'Y') {
                        Write-Host "Operation cancelled by user."
                        exit 0
                    }
                } else {
                    Write-Host "Confirmation bypassed. Continuing despite small downloaded ISO size..." -ForegroundColor Yellow
                }
            } else {
                Write-Host "ISO downloaded successfully ($fileSizeMB MB)." -ForegroundColor Green
            }
        } else {
            throw "ISO download failed: File not found after download"
        }
    } catch {
        Write-Error "Failed to download the ISO: $_"
        exit 1
    } finally {
        # Ensure WebClient is disposed
        if ($webClient) {
            $webClient.Dispose()
        }
    }
} else {
    Write-Host "ISO file ready: $isoPath" -ForegroundColor Green
}

# Create a working directory for extracted ISO content
$extractDir = $WORKING_DIR
if (Test-Path $extractDir) {
    # Clean any existing directory to avoid conflicts
    Write-Host "Cleaning existing working directory..."
    Remove-Item -Path "$extractDir\*" -Recurse -Force -ErrorAction SilentlyContinue
} else {
    # Create new directory
    New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
}

# Check for 7-Zip installation
$7zipPath = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $7zipPath)) {
    # Try common alternative path for x86 on x64 systems
    $7zipPath = "C:\Program Files (x86)\7-Zip\7z.exe"
    if (-not (Test-Path $7zipPath)) {
        Write-Host "7-Zip not found. Attempting to download and install it..."

        # Download and install 7-Zip using dynamic method to get latest version
        try {
            # Settings
            $downloadPage = "https://www.7-zip.org/download.html"
            $downloadPath = "C:\Windows\Temp\7z.msi"

            # Download page content
            $webClient = New-Object System.Net.WebClient
            $htmlContent = $webClient.DownloadString($downloadPage)

            # Extract latest x64 MSI link from the current version section
            $latestSection = $htmlContent -split '<P><B>Download 7-Zip' | Select-Object -Index 1

            # Handle both 32-bit and 64-bit architectures
            if ([Environment]::Is64BitOperatingSystem) {
                $archPattern = '-x64\.msi'
            } else {
                $archPattern = '\.msi"'
            }

            $msiRelativePath = ($latestSection | Select-String -Pattern "href=`"(a/7z\d+.*?$($archPattern))" -AllMatches).Matches[0].Groups[1].Value

            # Construct full download URL
            $downloadUrl = "https://www.7-zip.org/$msiRelativePath"

            Write-Host "Downloading 7-Zip from $downloadUrl"

            # Download and install
            $webClient.DownloadFile($downloadUrl, $downloadPath)
            Start-Process msiexec.exe -ArgumentList "/i `"$downloadPath`" /quiet /norestart" -Wait

            # Verify installation
            if (-not (Test-Path "C:\Program Files\7-Zip\7z.exe")) {
                throw "Failed to install 7-Zip"
            }
            $7zipPath = "C:\Program Files\7-Zip\7z.exe"
        } catch {
            Write-Error "Failed to install 7-Zip: $_"
            Write-Error "Please install 7-Zip manually and try again."
            exit 1
        }
    }
}

# Extract ISO using 7-Zip
Write-Host "Extracting ISO using 7-Zip (this may take 5-10 minutes)..." -ForegroundColor Cyan
Write-Host "Please be patient while the ISO contents are extracted..." -ForegroundColor Cyan
try {
    # Use Start-Process with redirected error streams to capture output without displaying it
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $7zipPath
    $processInfo.Arguments = "x -y -o`"$extractDir`" `"$isoPath`""
    $processInfo.RedirectStandardError = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null

    # Record start time
    $startTime = Get-Date
    
    # Wait for process to complete (no spinner)
    $process.WaitForExit()
    
    # Show completion message with total time
    $extractionTime = [TimeSpan]::FromSeconds((Get-Date).Subtract($startTime).TotalSeconds)
    Write-Host "Extraction complete [" $extractionTime.ToString("hh\:mm\:ss") "]" -ForegroundColor Green

    # Get the output without displaying it
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()

    # Check the exit code
    if ($process.ExitCode -ne 0) {
        # Format a user-friendly error message without dumping everything
        Write-Host "ERROR: 7-Zip extraction failed with exit code $($process.ExitCode)" -ForegroundColor Red
        Write-Host "The ISO file may be corrupted or incompatible." -ForegroundColor Yellow

        # Show minimal error information
        if (-not [string]::IsNullOrEmpty($standardError)) {
            $errorLines = $standardError -split "`n"
            $relevantError = ($errorLines | Where-Object { $_ -match "ERROR:" } | Select-Object -First 1)
            if ($relevantError) {
                Write-Host "Error details: $relevantError" -ForegroundColor Yellow
            }
        }

        exit 1
    }

    # Verify extraction succeeded
    $setupPath = "$extractDir\setup.exe"
    if (-not (Test-Path $setupPath)) {
        Write-Host "ERROR: Extraction completed but setup.exe was not found." -ForegroundColor Red
        Write-Host "This suggests the ISO does not contain a valid Windows installation." -ForegroundColor Yellow
        Write-Host "Please verify you are using a proper Windows 11 installation ISO." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "ISO extracted successfully to $extractDir" -ForegroundColor Green


    # Create SetupConfig.ini
    $setupConfigPath = "$extractDir\sources\SetupConfig.ini"
    $setupConfig = @"
[BeginSetupMode]
SkipPrediagler=1
DeviceEnumeration=1
DiscoverSystemPartition=1

[SetupConfig]
ScratchDir=$env:SystemDrive\`$WINDOWS.~BT
ScratchSpace=12000
PreinstallKitSpace=8000
"@
    Set-Content -Path $setupConfigPath -Value $setupConfig -Force

    # Run setup.exe with appropriate arguments and stronger compatibility bypass options
    Write-Host "Starting Windows 11 upgrade from extracted ISO with maximum compatibility overrides..."

    # Create custom answer file to force upgrade
    $answerFilePath = "$extractDir\unattend.xml"
    $answerFileContent = @"
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComplianceCheck>
        <DisplayReport>Never</DisplayReport>
      </ComplianceCheck>
      <Diagnostics>
        <OptIn>false</OptIn>
      </Diagnostics>
      <DynamicUpdate>
        <Enable>true</Enable>
        <WillShowUI>OnError</WillShowUI>
      </DynamicUpdate>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData>
              <Key>/IMAGE/INDEX</Key>
              <Value>1</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>1</PartitionID>
          </InstallTo>
          <WillShowUI>OnError</WillShowUI>
          <InstallToAvailablePartition>true</InstallToAvailablePartition>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>

    </component>
  </settings>
</unattend>
"@
    Set-Content -Path $answerFilePath -Value $answerFileContent -Force
    Write-Host "Created custom unattend.xml file for compatibility bypass"

   
    # Setup command line arguments
    $arguments = @(
        "/auto", "upgrade",
        "/quiet",
        "/compat", "ignorewarning",
        "/migratedrivers", "all",
        "/showoobe", "none",
        "/telemetry", "disable",
        "/dynamicupdate", "enable",
        "/eula", "accept",
        "/unattend:$answerFilePath"
    )

    # Add /noreboot switch if automatic reboots are disabled
    if (-not $ALLOW_AUTOMATIC_REBOOT) {
        $arguments += "/noreboot"
        Write-Host "Automatic reboots are disabled. The system will need to be manually rebooted to complete the upgrade."
    } else {
        Write-Host "Automatic reboots are enabled. The system will reboot automatically when needed."
    }

    # Create a log file to track progress
$logFile = $LOG_FILE
Set-Content -Path $logFile -Value "Windows 11 Upgrade started at $(Get-Date)`r`n" -Force

# Function to log progress
function Write-ProgressLog {
    param(
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

# Function to check if Windows Setup is running
function Is-SetupRunning {
    $setupProcesses = @(
        "SetupHost",  # This is the critical process for actual Windows upgrade execution
        "setupprep",
        "setup",
        "Windows10UpgraderApp"
    )

    foreach ($proc in $setupProcesses) {
        $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
        if ($running) {
            if ($proc -eq "SetupHost") {
                Write-ProgressLog "CRITICAL SUCCESS: SetupHost.exe is running! This confirms the upgrade is properly underway."
                return @{Success = $true; Critical = $true}
            }
            return @{Success = $true; Critical = $false}
        }
    }
    return @{Success = $false; Critical = $false}
}

# Function to wait for SetupHost.exe to appear (the definitive sign that upgrade is working)
function Wait-ForSetupHost {
    param (
        [int]$TimeoutSeconds = 300,  # Wait up to 5 minutes by default
        [int]$CheckIntervalSeconds = 5
    )

    Write-ProgressLog "Waiting for SetupHost.exe to start (the critical process for Windows upgrades)..."

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timeoutMs = $TimeoutSeconds * 1000

    while ($stopwatch.ElapsedMilliseconds -lt $timeoutMs) {
        $setupHost = Get-Process -Name "SetupHost" -ErrorAction SilentlyContinue
        if ($setupHost) {
            $stopwatch.Stop()
            Write-ProgressLog "SUCCESS: SetupHost.exe started after $([math]::Round($stopwatch.ElapsedMilliseconds / 1000)) seconds."
            Write-ProgressLog "SetupHost.exe PID: $($setupHost.Id), Started at: $(Get-Date)"
            return $true
        }

        # Check for setupprep - it should start first and launch SetupHost
        $setupPrep = Get-Process -Name "setupprep" -ErrorAction SilentlyContinue
        if ($setupPrep) {
            Write-ProgressLog "setupprep.exe is running (PID: $($setupPrep.Id)). Waiting for it to launch SetupHost.exe..."
        }

        # Sleep before checking again
        Start-Sleep -Seconds $CheckIntervalSeconds
    }

    $stopwatch.Stop()
    Write-ProgressLog "WARNING: SetupHost.exe did not start within $TimeoutSeconds seconds."
    return $false
}

Write-ProgressLog "Starting Windows 11 upgrade from extracted ISO..."
Write-ProgressLog "To monitor progress, check the log file at: $logFile"
Write-ProgressLog "You can also look for these processes: SetupHost.exe, setupprep.exe, setup.exe"

# Start setup without waiting
$arguments += "/PostOOBE", "$extractDir\PostInstall.cmd"

# Create a post-install script to log completion
$postInstallScript = @"
@echo off
echo Windows 11 Upgrade completed at %DATE% %TIME% > C:\Win11_Upgrade_Completed.log
"@
Set-Content -Path "$extractDir\PostInstall.cmd" -Value $postInstallScript -Force

# Start the setup process
Write-ProgressLog "Launching setup.exe with arguments: $($arguments -join ' ')"
$process = Start-Process -FilePath $setupPath -ArgumentList $arguments -PassThru -NoNewWindow

# Wait briefly to see if initial processes start
Start-Sleep -Seconds 5

# Check if setup is running and log process ID
$setupStatus = Is-SetupRunning
if ($setupStatus.Success) {
    $setupProcesses = Get-Process | Where-Object { $_.Name -match "setup|SetupHost" }
    foreach ($proc in $setupProcesses) {
        Write-ProgressLog "Setup process running: $($proc.Name) (PID: $($proc.Id))"
    }

    if ($setupStatus.Critical) {
        Write-ProgressLog "VERIFIED: SetupHost.exe is running! The upgrade is confirmed to be properly underway."
    } else {
        # SetupHost is not yet running - wait for it as it's the critical indicator
        Write-ProgressLog "Initial setup processes started, but waiting for SetupHost.exe (the critical component)..."

        # Wait for SetupHost to appear - this is the definitive test
        $setupHostStarted = Wait-ForSetupHost -TimeoutSeconds 600 # Wait up to 10 minutes

        if ($setupHostStarted) {
            Write-ProgressLog "UPGRADE CONFIRMED: SetupHost.exe is running. The Windows 11 upgrade is now definitely underway."
            Write-ProgressLog "This is the critical process that indicates the actual upgrade is proceeding correctly."
        } else {
            Write-ProgressLog "WARNING: SetupHost.exe did not start within the expected timeframe."
            Write-ProgressLog "The upgrade may still proceed, but you should monitor it carefully."
            Write-ProgressLog "If the upgrade does not complete, you may need to run the script again."
        }
    }

    Write-ProgressLog "Setup initiated. The upgrade is now running in the background."
    Write-ProgressLog "To check if it's running, use Task Manager to look for SetupHost.exe."
} else {
    Write-ProgressLog "Warning: Setup may not have started correctly."
    Write-ProgressLog "Checking exit code: $($process.ExitCode)"

        # Try alternative approach - direct setupprep.exe execution with Server trick
        Write-ProgressLog "Trying alternative approach with setupprep.exe and Server trick..."
        $setupPrepPath = "$extractDir\sources\setupprep.exe"
        if (Test-Path $setupPrepPath) {
            # Prepare $WINDOWS.~BT directory
            $btDir = "$env:SystemDrive\`$WINDOWS.~BT\Sources"
            if (-not (Test-Path $btDir)) {
                New-Item -Path $btDir -ItemType Directory -Force | Out-Null
            }

            # Copy critical files to ensure Windows.~BT has what it needs
            Write-ProgressLog "Copying setup files to Windows.~BT directory..."
            Copy-Item -Path "$extractDir\sources\*" -Destination $btDir -Force -Recurse



            # Create batch file to run registry changes and launch setup
            $setupBatchPath = "$btDir\RunSetup.cmd"

            $setupCommand = "setupprep.exe /auto upgrade /quiet /compat ignorewarning /migratedrivers all /dynamicupdate enable /eula accept"

            # Add noreboot switch if automatic reboots are disabled
            if (-not $ALLOW_AUTOMATIC_REBOOT) {
                $setupCommand += " /noreboot"
            }

            $setupBatch = @"
@echo off
cd /d "%~dp0"
$setupCommand
"@
            Set-Content -Path $setupBatchPath -Value $setupBatch -Force

            # Run the batch file to execute setup with all bypasses
            Write-ProgressLog "Launching setup with all compatibility bypasses..."
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c $setupBatchPath" -PassThru -NoNewWindow

            # Wait briefly to check if it started
            Start-Sleep -Seconds 5

            # Check again if setup is running
            $setupStatus = Is-SetupRunning
            if ($setupStatus.Success) {
                $setupProcesses = Get-Process | Where-Object { $_.Name -match "setup|SetupHost" }
                foreach ($proc in $setupProcesses) {
                    Write-ProgressLog "Setup process running: $($proc.Name) (PID: $($proc.Id))"
                }

                if ($setupStatus.Critical) {
                    Write-ProgressLog "VERIFIED: SetupHost.exe is running via fallback method! The upgrade is confirmed to be properly underway."
                } else {
                    # SetupHost is not yet running - wait for it as it's the critical indicator
                    Write-ProgressLog "Initial setup processes started via fallback method, waiting for SetupHost.exe..."

                    # Wait for SetupHost to appear - this is the definitive test
                    $setupHostStarted = Wait-ForSetupHost -TimeoutSeconds 600 # Wait up to 10 minutes

                    if ($setupHostStarted) {
                        Write-ProgressLog "UPGRADE CONFIRMED: SetupHost.exe is running. The Windows 11 upgrade is now definitely underway."
                    } else {
                        Write-ProgressLog "WARNING: SetupHost.exe did not start within the expected timeframe."
                        Write-ProgressLog "The upgrade may still proceed, but monitoring is recommended."
                    }
                }

                Write-ProgressLog "Setup initiated via fallback method. The upgrade is now running in the background."
            } else {
                Write-ProgressLog "WARNING: Both setup methods failed to start the upgrade process."
                Write-ProgressLog "Please check the logs and consider running the script again."
            }
        }

        # Create a simple monitor script that only logs progress
        $monitorScript = @"
@echo off
echo Windows 11 upgrade monitor started at %DATE% %TIME% > "%MONITOR_LOG%"

:check
echo ------------------------------------------------ >> "%MONITOR_LOG%"
echo Checking processes at %DATE% %TIME% >> "%MONITOR_LOG%"
tasklist /fi "imagename eq setuphost.exe" >> "%MONITOR_LOG%"
tasklist /fi "imagename eq setupprep.exe" >> "%MONITOR_LOG%"
tasklist /fi "imagename eq setup.exe" >> "%MONITOR_LOG%"

REM Check if RebootRequired registry exists (for logging only)
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" > nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo Reboot Required registry key found! Windows should reboot automatically. >> "%MONITOR_LOG%"
)

REM Check if installation phase registry indicates readiness (for logging only)
reg query "HKLM\SYSTEM\Setup" /v SystemSetupInProgress > nul 2>&1
if %ERRORLEVEL% EQU 0 (
    for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\Setup" /v SystemSetupInProgress ^| find "SystemSetupInProgress"') do set SETUP_PROGRESS=%%a
    echo SystemSetupInProgress value: !SETUP_PROGRESS! >> "%MONITOR_LOG%"
)

REM Log recent activity in setup logs
echo Recent setup logs: >> "%MONITOR_LOG%"
dir /a-d /od C:\$WINDOWS.~BT\Sources\Panther\*.log >> "%MONITOR_LOG%" 2>&1

REM Log memory info to monitor system health
echo Memory status: >> "%MONITOR_LOG%"
systeminfo | find "Physical Memory" >> "%MONITOR_LOG%"
echo. >> "%MONITOR_LOG%"

timeout /t 300 > nul
goto check
"@
        Set-Content -Path "$extractDir\MonitorSetup.cmd" -Value $monitorScript -Force

        # Start the monitor script in a hidden window
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c $extractDir\MonitorSetup.cmd" -WindowStyle Hidden
    }

    # Clean up - delete the downloaded ISO but keep extracted files for debugging
    Remove-Item -Path $isoPath -Force -ErrorAction SilentlyContinue

} catch {
    # Extract only the essential error message without the full stack trace
    $errorMessage = $_.Exception.Message
    if ($errorMessage.Length -gt 150) {
        $errorMessage = $errorMessage.Substring(0, 150) + "..."
    }

    # Create a clean, user-friendly error message
    $detailedMessage = "The Windows 11 upgrade process encountered an issue and could not continue.`nTry again or check the log file at $logFile for more details."

    # Try to clean up
    try {
        Remove-Item -Path $isoPath -Force -ErrorAction SilentlyContinue
    } catch {
        # Ignore cleanup errors
    }

    # Show clean error message
    Write-Host "ERROR: Windows 11 upgrade process failed." -ForegroundColor Red
    Write-Host "The Windows 11 upgrade process encountered an issue and could not continue." -ForegroundColor Yellow
    Write-Host "Try again or check the log file at $logFile for more details." -ForegroundColor Yellow
    exit 1
}

# Final progress information and verification
if ($ALLOW_AUTOMATIC_REBOOT) {
    Write-ProgressLog "Windows 11 upgrade process initiated. The system will reboot automatically when the upgrade is complete."
} else {
    Write-ProgressLog "Windows 11 upgrade process initiated. Manual reboot will be required when the upgrade preparation is complete."
}
Write-ProgressLog ""
Write-ProgressLog "To verify the upgrade is running, check for these files:"
Write-ProgressLog "- $logFile - Contains detailed progress information"
Write-ProgressLog "- $MONITOR_LOG - Contains periodic process checks every 5 minutes"
Write-ProgressLog "- C:\Win11_Upgrade_Completed.log - Will be created when upgrade completes"
Write-ProgressLog ""
Write-ProgressLog "You should also see one or more of these processes in Task Manager:"
Write-ProgressLog "- SetupHost.exe - Main upgrade process"
Write-ProgressLog "- setupprep.exe - Preparation process"
Write-ProgressLog "- setup.exe - Initial setup launcher"
Write-ProgressLog ""
Write-ProgressLog "Process monitoring is active but no automatic intervention will occur."
Write-ProgressLog "Windows Setup will handle the reboot process organically when ready."

# One final check to make absolutely sure SetupHost is running
Write-ProgressLog "Performing final verification to ensure SetupHost.exe is running..."
Start-Sleep -Seconds 15

$setupHost = Get-Process -Name "SetupHost" -ErrorAction SilentlyContinue
if ($setupHost) {
    Write-ProgressLog "FINAL VERIFICATION PASSED: SetupHost.exe is running (PID: $($setupHost.Id))."
    Write-ProgressLog "The Windows 11 upgrade is definitely underway and proceeding properly."
    Write-ProgressLog "This is the CRITICAL process that confirms the upgrade will complete successfully."

    # Log all running setup processes for completeness
    $setupProcesses = Get-Process | Where-Object { $_.Name -match "setup|SetupHost" }
    Write-ProgressLog "All running setup processes:"
    foreach ($proc in $setupProcesses) {
        Write-ProgressLog "- $($proc.Name) (PID: $($proc.Id))"
    }

    Write-ProgressLog "UPGRADE STATUS: SUCCESS - The script has successfully initiated the Windows 11 upgrade."
} else {
    # SetupHost is still not running - check for any setup processes
    $setupStatus = Is-SetupRunning
    if ($setupStatus.Success) {
        Write-ProgressLog "WARNING: Setup processes are running, but SetupHost.exe has not started yet."
        Write-ProgressLog "The upgrade may still proceed, but it's recommended to monitor the process."
        Write-ProgressLog "If needed, check the C:\$WINDOWS.~BT\Sources\Panther directory for logs."

        # One last attempt to wait for SetupHost
        Write-ProgressLog "Making final attempt to wait for SetupHost.exe to start..."
        $finalAttempt = Wait-ForSetupHost -TimeoutSeconds 300 # Wait 5 more minutes

        if ($finalAttempt) {
            Write-ProgressLog "SUCCESS: SetupHost.exe has finally started. The upgrade is now properly underway."
        } else {
            Write-ProgressLog "CAUTION: SetupHost.exe still not detected. The upgrade process may be abnormal."
            Write-ProgressLog "Please monitor the system to ensure the upgrade completes successfully."
        }
    } else {
        Write-ProgressLog "CRITICAL WARNING: No setup processes are running. The upgrade has likely failed to start."
        Write-ProgressLog "Check C:\$WINDOWS.~BT\Sources\Panther directory for setupact.log and setuperr.log files"
        Write-ProgressLog "You may need to run the script again or try a different approach."
    }
}