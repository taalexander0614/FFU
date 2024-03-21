# Possibly add "old" to end of existing ffu file name, copy the new one, then verify the new one is there before deleting the old one

$Win10_Folder = "C:\FFU_Test_Copy"
$Win11_Folder = "C:\FFU_Test_Copy"
$SiteCode = "101" # Site code 
$ProviderMachineName = "anxsccm.rcs.local" # SMS Provider machine name
# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Create Windows 11 FFU
Write-Host "Creating Windows 11 FFU"
C:\FFUDevelopment\BuildFFUVM.ps1 -WindowsSKU 'Pro' -WindowsRelease 11 -WindowsArch 'x64' -MediaType 'business' -Installapps $true -InstallOffice $true -VMSwitchName 'FFU' -VMHostIPAddress '192.168.1.107' -CreateCaptureMedia $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -verbose

Write-Host "Copying Windows 11 FFU to share"
# Copy the Win11 FFU file to share
$Win11_FFU = Get-ChildItem -Path "C:\FFUDevelopment\FFU" -Filter "Win11*.ffu" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (!(Test-Path -Path $Win11_Folder)){
    New-Item -Path $Win11_Folder -ItemType Directory
}
$DestinationPath = Join-Path -Path $Win11_Folder -ChildPath $Win11_FFU.Name
# Remove any existing FFU files
Remove-Item -Path "$Win11_Folder\*.ffu" -Force
Copy-Item -Path $Win11_FFU.FullName -Destination $DestinationPath -Force


# Create Windows 10 FFU
Write-Host "Creating Windows 10 FFU"
C:\FFUDevelopment\BuildFFUVM.ps1 -WindowsSKU 'Pro' -WindowsRelease 10 -WindowsArch 'x64' -MediaType 'business' -Installapps $true -InstallOffice $true -VMSwitchName 'FFU' -VMHostIPAddress '192.168.1.107' -CreateCaptureMedia $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -verbose

Write-Host "Copying Windows 10 FFU to share"
# Copy the Win10 FFU file to share
$Win10_FFU = Get-ChildItem -Path "C:\FFUDevelopment\FFU" -Filter "Win10*.ffu" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (!(Test-Path -Path $Win10_Folder)){
    New-Item -Path $Win10_Folder -ItemType Directory
}
$DestinationPath = Join-Path -Path $Win10_Folder -ChildPath $Win10_FFU.Name
# Remove any existing FFU files
Remove-Item -Path "$Win10_Folder\*.ffu" -Force
Copy-Item -Path $Win10_FFU.FullName -Destination $DestinationPath -Force

<#
# Import the ConfigurationManager.psd1 module 
try {
    if($null -eq (Get-Module ConfigurationManager)) {
        Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams
    }
}
catch {
    Write-Host "Failed to import Configuration Manager Module: $($_.Exception.Message)"
}

# Connect to the site's drive if it is not already present
try {
    if($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
    }
    Write-Host "Connected to Site's Drive"
}
catch {
    Write-Host "Failed to connect to Site's Drive: $($_.Exception.Message)"
}

# Set the current location to be the site code.
try {
    Set-Location "$($SiteCode):\" @initParams
}
catch {
    Write-Host "Failed to set location: $($_.Exception.Message)"
}

# Update package containing FFU files on SCCM distribution points
Write-Host "Updating SCCM package with FFU files"
foreach ($PackageID in $PackageIDs) {
    Write-Host "Running CMUpdatePackage"
    Update-CMDistributionPoint -PackageId $PackageID
}
#>