function Get-USBDrive(){
    $USBDriveLetter = (Get-Volume | Where-Object {$_.DriveType -eq 'Removable' -and $_.FileSystemType -eq 'NTFS'}).DriveLetter
    if ($null -eq $USBDriveLetter){
        #Must be using a fixed USB drive - difficult to grab drive letter from win32_diskdrive. Assume user followed instructions and used Deploy as the friendly name for partition
        $USBDriveLetter = (Get-Volume | Where-Object {$_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' -and $_.FileSystemLabel -eq 'Deploy'}).DriveLetter
        #If we didn't get the drive letter, stop the script.
        if ($null -eq $USBDriveLetter){
            WriteLog 'Cannot find USB drive letter - most likely using a fixed USB drive. Name the 2nd partition with the FFU files as Deploy so the script can grab the drive letter. Exiting'
            Exit
        }

    }
    $USBDriveLetter = $USBDriveLetter + ":\"
    return $USBDriveLetter
}

# Run applyffu.ps1 located on the root of the USB drive and wait for it to complete
$USBDriveLetter = Get-USBDrive
$ApplyFFUPath = $USBDriveLetter + "ApplyFFU.ps1"
Read-Host "Running $ApplyFFUPath"
Write-Host "Running $ApplyFFUPath"
Start-Process powershell -ArgumentList "-ExecutionPolicy "Bypass" -File $ApplyFFUPath" -Wait
Read-Host "Finished running $ApplyFFUPath"




