$Win10_Folder = "C:\FFU_Test_Copy"
$Win11_Folder = "C:\FFU_Test_Copy"
$PackageIDs = @("PackageID1", "PackageID2", "PackageID3")
$SCCMServer = "ANXSCCM"
$SCCMSiteCode = "101"

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
Copy-Item -Path $Win10_FFU.FullName -Destination $DestinationPath -Force

<#
### Want to do something like this, but need to figure out how to do it
# Update package containing FFU files on SCCM distribution points
Connect-CMServer -SiteCode $SCCMSiteCode -ServerName $SCCMServer
Write-Host "Updating SCCM package with FFU files"
foreach ($PackageID in $PackageIDs) {
    Invoke-CMUpdatePackage -PackageName $PackageID -Wait
    Invoke-CMDistributionPointUpdate -PackageID $PackageIDs
}
Disconnect-CMServer -Confirm:$false
#>