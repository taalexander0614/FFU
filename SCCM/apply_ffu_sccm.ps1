# Write log function
function WriteLog {
    param([string]$Message)
    $LogMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Write-Output $LogMessage
    Write-Output $LogMessage | Out-File -Append "$env:SystemRoot\CCM\Logs\smsts.log"
}

# Get script directory
$ScriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
WriteLog "Script directory: $ScriptDirectory"

# Define variables
$FFUFileName = (Get-ChildItem -Path $ScriptDirectory -Filter "*.ffu" | Select-Object -First 1).Name
$FFUFileToInstall = Join-Path $ScriptDirectory $FFUFileName

# Apply FFU using dism
WriteLog "Applying FFU to $PhysicalDeviceID"
WriteLog "Running command dism /apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID"

$result = Start-Process -FilePath "dism.exe" -ArgumentList "/apply-ffu /ImageFile:$FFUFileToInstall /ApplyDrive:$PhysicalDeviceID" -NoNewWindow -Wait -PassThru

if ($result.ExitCode -eq 0) {
    WriteLog 'Successfully applied FFU'
} else {
    WriteLog "Failed to apply FFU - ExitCode = $($result.ExitCode). Also, check dism.log for more info"
    # Copy DISM log to writable location
    $DismLogPath = Join-Path $env:TEMP "dism.log"
    Copy-Item -Path "X:\Windows\logs\dism\dism.log" -Destination $DismLogPath -Force
    exit 1  # Exit with error code
}

# Extend Windows partition and create recovery partition
WriteLog 'Extending Windows partition'
$result = Start-Process -FilePath "diskpart.exe" -ArgumentList "/S $ExtendPartition" -NoNewWindow -Wait -PassThru

if ($result.ExitCode -eq 0) {
    WriteLog 'Successfully extended Windows partition and created recovery partition'
} else {
    WriteLog "Failed to extend Windows partition and/or create recovery partition - LastExitCode = $LASTEXITCODE"
}
