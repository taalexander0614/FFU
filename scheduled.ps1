# Create Windows 11 FFU
Write-Host "Creating Windows 11 FFU"
C:\FFUDevelopment\BuildFFUVM.ps1 -WindowsSKU 'Pro' -WindowsRelease 11 -WindowsArch 'x64' -MediaType 'business' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -verbose

Write-Host "Copying Windows 11 FFU to share"
# Copy the Win11 FFU file to share
$LatestFFUFile = Get-ChildItem -Path "C:\FFUDevelopment\FFU" -Filter "Win11*.ffu" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
#Copy-Item -Path $LatestFFUFile.FullName -Destination "\\ANXSCCM\OperatingSystems" -Force
Copy-Item -Path $LatestFFUFile.FullName -Destination "C:\FFU_Test_Copy" -Force

# Create Windows 10 FFU
Write-Host "Creating Windows 10 FFU"
C:\FFUDevelopment\BuildFFUVM.ps1 -WindowsSKU 'Pro' -WindowsRelease 10 -WindowsArch 'x64' -MediaType 'business' -Installapps $true -InstallOffice $true -InstallDrivers $true -VMSwitchName 'Name of your VM Switch in Hyper-V' -VMHostIPAddress 'Your IP Address' -CreateCaptureMedia $true -UpdateLatestCU $true -UpdateLatestNet $true -UpdateLatestDefender $true -UpdateEdge $true -UpdateOneDrive $true -verbose

Write-Host "Copying Windows 10 FFU to share"
# Copy the Win10 FFU file to share
$LatestFFUFile = Get-ChildItem -Path "C:\FFUDevelopment\FFU" -Filter "Win10*.ffu" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
#Copy-Item -Path $LatestFFUFile.FullName -Destination "\\ANXSCCM\OperatingSystems" -Force
Copy-Item -Path $LatestFFUFile.FullName -Destination "C:\FFU_Test_Copy" -Force

# Update package containing FFU files on SCCM distribution points
<#
### Want to do something like this, but need to figure out how to do it

Write-Host "Updating SCCM package with FFU files"
$packageIDs = @("ANX00001", "ANX00002")
foreach ($packageID in $packageIDs){
    $Get_WmiObject = @{
        'Namespace' = 'root\SMS\Site_ANX';
        'Class' = 'SMS_Package';
        'Filter' = "PackageID='$packageID'";
    }
    (Get-Wmiobject @Get_WmiObject).Commit() | Out-null
}
#>