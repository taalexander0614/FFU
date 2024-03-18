<#
.SYNOPSIS

    The purpose of this script is to automate the driver update process when enrolling devices through
    Microsoft Intune.

.DESCRIPTION

    This script will determine the model of the computer, manufacturer and operating system used then download,
    extract & install the latest driver package from the manufacturer. At present Dell, HP and Lenovo devices
    are supported.
	
.NOTES

    FileName:    Invoke-MSIntuneDriverUpdate.ps1

    Author:      Maurice Daly
    Contact:     @MoDaly_IT
    Created:     2017-12-03
    Updated:     2017-12-05

    Version history:

    1.0.0 - (2017-12-03) Script created
	1.0.1 - (2017-12-05) Updated Lenovo matching SKU value and added regex matching for Computer Model values. 
	1.0.2 - (2017-12-05) Updated to cater for language differences in OS architecture returned
#>

# // =================== GLOBAL VARIABLES ====================== //

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

# Set Temp & Log Location
[string]$TempDirectory = Join-Path $USBDrive "\DriverTemp"

# // =================== DELL VARIABLES ================ //

# Define Dell Download Sources
$DellDownloadList = "http://downloads.dell.com/published/Pages/index.html"
$DellDownloadBase = "http://downloads.dell.com"
$DellDriverListURL = "http://en.community.dell.com/techcenter/enterprise-client/w/wiki/2065.dell-command-deploy-driver-packs-for-enterprise-client-os-deployment"
$DellBaseURL = "http://en.community.dell.com"

# Define Dell Download Sources
$DellXMLCabinetSource = "http://downloads.dell.com/catalog/DriverPackCatalog.cab"
$DellCatalogSource = "http://downloads.dell.com/catalog/CatalogPC.cab"

# Define Dell Cabinet/XL Names and Paths
$DellCabFile = [string]($DellXMLCabinetSource | Split-Path -Leaf)
$DellCatalogFile = [string]($DellCatalogSource | Split-Path -Leaf)
$DellXMLFile = $DellCabFile.Trim(".cab")
$DellXMLFile = $DellXMLFile + ".xml"
$DellCatalogXMLFile = $DellCatalogFile.Trim(".cab") + ".xml"

# Define Dell Global Variables
$DellCatalogXML = $null
$DellModelXML = $null
$DellModelCabFiles = $null

# // =================== HP VARIABLES ================ //

# Define HP Download Sources
$HPXMLCabinetSource = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab"
$HPSoftPaqSource = "http://ftp.hp.com/pub/softpaq/"
$HPPlatFormList = "http://ftp.hp.com/pub/caps-softpaq/cmit/imagepal/ref/platformList.cab"

# Define HP Cabinet/XL Names and Paths
$HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
$HPXMLFile = $HPCabFile.Trim(".cab")
$HPXMLFile = $HPXMLFile + ".xml"
$HPPlatformCabFile = [string]($HPPlatFormList | Split-Path -Leaf)
$HPPlatformXMLFile = $HPPlatformCabFile.Trim(".cab")
$HPPlatformXMLFile = $HPPlatformXMLFile + ".xml"

# Define HP Global Variables
$global:HPModelSoftPaqs = $null
$global:HPModelXML = $null
$global:HPPlatformXML = $null

# // =================== LENOVO VARIABLES ================ //

# Define Lenovo Download Sources
$global:LenovoXMLSource = "https://download.lenovo.com/cdrt/td/catalog.xml"

# Define Lenovo Cabinet/XL Names and Paths
$global:LenovoXMLFile = [string]($global:LenovoXMLSource | Split-Path -Leaf)

# Define Lenovo Global Variables
$global:LenovoModelDrivers = $null
$global:LenovoModelXML = $null
$global:LenovoModelType = $null
$global:LenovoSystemSKU = $null

# // =================== COMMON VARIABLES ================ //

# Determine manufacturer
$ComputerManufacturer = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer).Trim()
Write-Output "Manufacturer determined as: $($ComputerManufacturer)"

# Determine manufacturer name and hardware information
switch -Wildcard ($ComputerManufacturer) {
	"*HP*" {
		$ComputerManufacturer = "Hewlett-Packard"
		$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
		$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).BaseBoardProduct
	}
	"*Hewlett-Packard*" {
		$ComputerManufacturer = "Hewlett-Packard"
		$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
		$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).BaseBoardProduct
	}
	"*Dell*" {
		$ComputerManufacturer = "Dell"
		$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
		$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).SystemSku
	}
	"*Lenovo*" {
		$ComputerManufacturer = "Lenovo"
		$ComputerModel = Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version
		$SystemSKU = ((Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI | Select-Object -ExpandProperty BIOSVersion).SubString(0, 4)).Trim()
	}
}
Write-Output "Computer model determined as: $($ComputerModel)"

if (-not [string]::IsNullOrEmpty($SystemSKU)) {
	Write-Output "Computer SKU determined as: $($SystemSKU)"
}

# Get operating system name from version
switch -wildcard (Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty Version) {
	"10.0*" {
		$OSName = "Windows 10"
	}
	"6.3*" {
		$OSName = "Windows 8.1"
	}
	"6.1*" {
		$OSName = "Windows 7"
	}
}
Write-Output "Operating system determined as: $OSName"

# Get operating system architecture
switch -wildcard ((Get-CimInstance Win32_operatingsystem).OSArchitecture) {
	"64-*" {
		$OSArchitecture = "64-Bit"
	}
	"32-*" {
		$OSArchitecture = "32-Bit"
	}
}

Write-Output "Architecture determined as: $OSArchitecture"

$WindowsVersion = ($OSName).Split(" ")[1]

function Invoke-DriverListDownload {
	Write-Output "======== Download Model Link Information ========"
	if ($ComputerManufacturer -eq "Hewlett-Packard") {
		if ((Test-Path -Path $TempDirectory\$HPCabFile) -eq $false) {
			Write-Output "======== Downloading HP Product List ========"
			# Download HP Model Cabinet File
			Write-Output "Info: Downloading HP driver pack cabinet file from $HPXMLCabinetSource"
			try {
				Start-BitsTransfer -Source $HPXMLCabinetSource -Destination $TempDirectory
				# Expand Cabinet File
				Write-Output "Info: Expanding HP driver pack cabinet file: $HPXMLFile"
				Expand "$TempDirectory\$HPCabFile" -F:* "$TempDirectory\$HPXMLFile"
			}
			catch {
				Write-Output "Error: $($_.Exception.Message)" 
			}
		}
		# Read XML File
		if ($null -eq $global:HPModelSoftPaqs) {
			Write-Output "Info: Reading driver pack XML file - $TempDirectory\$HPXMLFile"
			[xml]$global:HPModelXML = Get-Content -Path $TempDirectory\$HPXMLFile
			# Set XML Object
			$global:HPModelXML.GetType().FullName | Out-Null
			$global:HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
		}
	}
	if ($ComputerManufacturer -eq "Dell") {
		if ((Test-Path -Path $TempDirectory\$DellCabFile) -eq $false) {
			Write-Output "Info: Downloading Dell product list"
			Write-Output "Info: Downloading Dell driver pack cabinet file from $DellXMLCabinetSource"
			# Download Dell Model Cabinet File
			try {
				Start-BitsTransfer -Source $DellXMLCabinetSource -Destination $TempDirectory
				# Expand Cabinet File
				Write-Output "Info: Expanding Dell driver pack cabinet file: $DellXMLFile"
				Expand "$TempDirectory\$DellCabFile" -F:* "$TempDirectory\$DellXMLFile"
			}
			catch {
				Write-Output "Error: $($_.Exception.Message)" 
			}
		}
		if ($null -eq $DellModelXML) {
			# Read XML File
			Write-Output "Info: Reading driver pack XML file - $TempDirectory\$DellXMLFile"
			[xml]$DellModelXML = (Get-Content -Path $TempDirectory\$DellXMLFile)
			# Set XML Object
			$DellModelXML.GetType().FullName | Out-Null
		}
		$DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
		
	}
	if ($ComputerManufacturer -eq "Lenovo") {
		if ($null -eq $global:LenovoModelDrivers) {
			try {
				[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $global:LenovoXMLSource
			}
			catch {
				Write-Output "Error: $($_.Exception.Message)" 
			}
			
			# Read Web Site
			Write-Output "Info: Reading driver pack URL - $global:LenovoXMLSource"
			
			# Set XML Object 
			$global:LenovoModelXML.GetType().FullName | Out-Null
			$global:LenovoModelDrivers = $global:LenovoModelXML.Products
		}
	}
}



function Get-RedirectedUrl {
	Param (
		[Parameter(Mandatory = $true)]
		[String]
		$URL
	)
	
	$Request = [System.Net.WebRequest]::Create($URL)
	$Request.AllowAutoRedirect = $false
	$Request.Timeout = 3000
	$Response = $Request.GetResponse()
	
	if ($Response.ResponseUri) {
		$Response.GetResponseHeader("Location")
	}
	$Response.Close()
}

function LenovoModelTypeFinder {
	param (
		[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model to query")]
		[string]
		$ComputerModel,
		[parameter(Mandatory = $false, HelpMessage = "Enter Operating System")]
		[string]
		$OS,
		[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model type to query")]
		[string]
		$ComputerModelType
	)
	try {
		if ($null -eq $global:LenovoModelDrivers) {
			[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $global:LenovoXMLSource
			# Read Web Site
			Write-Output "Info: Reading driver pack URL - $global:LenovoXMLSource"
			
			# Set XML Object
			$global:LenovoModelXML.GetType().FullName | Out-Null
			$global:LenovoModelDrivers = $global:LenovoModelXML.Products
		}
	}
	catch {
		Write-Output "Error: $($_.Exception.Message)" 
	}
	
	if ($ComputerModel.Length -gt 0) {
		$global:LenovoModelType = ($global:LenovoModelDrivers.Product | Where-Object {
				$_.Queries.Version -match "$ComputerModel"
			}).Queries.Types | Select-Object -ExpandProperty Type | Select-Object -first 1
		$global:LenovoSystemSKU = ($global:LenovoModelDrivers.Product | Where-Object {
				$_.Queries.Version -match "$ComputerModel"
			}).Queries.Types | Select-Object -ExpandProperty Type | Get-Unique
	}
	
	if ($ComputerModelType.Length -gt 0) {
		$global:LenovoModelType = (($global:LenovoModelDrivers.Product.Queries) | Where-Object {
				($_.Types | Select-Object -ExpandProperty Type) -match $ComputerModelType
			}).Version | Select-Object -first 1
	}
	Return $global:LenovoModelType
}

function Invoke-DriverDownload {
	
	$Product = "Intune Driver Automation"
	
	# Driver Download ScriptBlock
	$DriverDownloadJob = {
		Param ([string]
			$TempDirectory,
			[string]
			$ComputerModel,
			[string]
			$DriverCab,
			[string]
			$DriverDownloadURL
		)
		
		try {
			# Start Driver Download	
			Start-BitsTransfer -DisplayName "$ComputerModel-DriverDownload" -Source $DriverDownloadURL -Destination "$($TempDirectory + '\Driver Cab\' + $DriverCab)"
		}
		catch [System.Exception] {
			Write-Output "Error: $($_.Exception.Message)" 
		}
	}
	
	Write-Output "======== Starting Download Processes ========"
	Write-Output "Info: Operating System specified: Windows $($WindowsVersion)"
	Write-Output "Info: Operating System architecture specified: $($OSArchitecture)"
	
	# Operating System Version
	$OperatingSystem = ("Windows " + $($WindowsVersion))
	
	# Vendor Make
	$ComputerModel = $ComputerModel.Trim()
	
	# Get Windows Version Number
	switch -Wildcard ((Get-WmiObject -Class Win32_OperatingSystem).Version) {
		"*10.0.16*" {
			$OSBuild = "1709"
		}
		"*10.0.15*" {
			$OSBuild = "1703"
		}
		"*10.0.14*" {
			$OSBuild = "1607"
		}
	}
	Write-Output "Info: Windows 10 build $OSBuild identified for driver match"
	
	# Start driver import processes
	Write-Output "Info: Starting Download,Extract And Import Processes For $ComputerManufacturer Model: $($ComputerModel)"
	
	# =================== DEFINE VARIABLES =====================
	
	if ($ComputerManufacturer -eq "Dell") {
		Write-Output "Info: Setting Dell variables"
		if ($null -eq $DellModelCabFiles) {
			[xml]$DellModelXML = Get-Content -Path $TempDirectory\$DellXMLFile
			# Set XML Object
			$DellModelXML.GetType().FullName | Out-Null
			$DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
		}
		if ($null -ne $SystemSKU) {
			Write-Output "Info: SystemSKU value is present, attempting match based on SKU - $SystemSKU)"
			
			$ComputerModelURL = $DellDownloadBase + "/" + ($DellModelCabFiles | Where-Object {
					((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.SystemID -eq $SystemSKU)
				}).delta
			$ComputerModelURL = $ComputerModelURL.Replace("\", "/")
			$DriverDownload = $DellDownloadBase + "/" + ($DellModelCabFiles | Where-Object {
					((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.SystemID -eq $SystemSKU)
				}).path
			$DriverCab = (($DellModelCabFiles | Where-Object {
						((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.SystemID -eq $SystemSKU)
					}).path).Split("/") | Select-Object -Last 1
		}
		elseif ($null -eq $SystemSKU -or $null -eq $DriverCab) {
			Write-Output "Info: Falling back to matching based on model name"
			
			$ComputerModelURL = $DellDownloadBase + "/" + ($DellModelCabFiles | Where-Object {
					((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$ComputerModel*")
				}).delta
			$ComputerModelURL = $ComputerModelURL.Replace("\", "/")
			$DriverDownload = $DellDownloadBase + "/" + ($DellModelCabFiles | Where-Object {
					((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$ComputerModel")
				}).path
			$DriverCab = (($DellModelCabFiles | Where-Object {
						((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$ComputerModel")
					}).path).Split("/") | Select-Object -Last 1
		}
		$DriverRevision = (($DriverCab).Split("-")[2]).Trim(".cab")
		$DellSystemSKU = ($DellModelCabFiles.supportedsystems.brand.model | Where-Object {
				$_.Name -match ("^" + $ComputerModel + "$")
			} | Get-Unique).systemID
		if ($DellSystemSKU.count -gt 1) {
			$DellSystemSKU = [string]($DellSystemSKU -join ";")
		}
		Write-Output "Info: Dell System Model ID is : $DellSystemSKU"
	}
	if ($ComputerManufacturer -eq "Hewlett-Packard") {
		Write-Output "Info: Setting HP variables"
		if ($null -eq $global:HPModelSoftPaqs) {
			[xml]$global:HPModelXML = Get-Content -Path $TempDirectory\$HPXMLFile
			# Set XML Object
			$global:HPModelXML.GetType().FullName | Out-Null
			$global:HPModelSoftPaqs = $global:HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
		}
		if ($null -ne $SystemSKU) {
			$HPSoftPaqSummary = $global:HPModelSoftPaqs | Where-Object {
				($_.SystemID -match $SystemSKU) -and ($_.OSName -like "$OSName*$OSArchitecture*$OSBuild*")
			} | Sort-Object -Descending | Select-Object -First 1
		}
		else {
			$HPSoftPaqSummary = $global:HPModelSoftPaqs | Where-Object {
				($_.SystemName -match $ComputerModel) -and ($_.OSName -like "$OSName*$OSArchitecture*$OSBuild*")
			} | Sort-Object -Descending | Select-Object -First 1
		}
		if ($null -ne $HPSoftPaqSummary) {
			$HPSoftPaq = $HPSoftPaqSummary.SoftPaqID
			$HPSoftPaqDetails = $global:HPModelXML.newdataset.hpclientdriverpackcatalog.softpaqlist.softpaq | Where-Object {
				$_.ID -eq "$HPSoftPaq"
			}
			$ComputerModelURL = $HPSoftPaqDetails.URL
			# Replace FTP for HTTP for Bits Transfer Job
			$DriverDownload = ($HPSoftPaqDetails.URL).TrimStart("ftp:")
			$DriverCab = $ComputerModelURL | Split-Path -Leaf
			$DriverRevision = "$($HPSoftPaqDetails.Version)"
		}
		else{
			Write-Output "Unsupported model / operating system combination found. Exiting." ; exit 1
		}
	}
	if ($ComputerManufacturer -eq "Lenovo") {
		Write-Output "Info: Setting Lenovo variables"
		$global:LenovoModelType = LenovoModelTypeFinder -ComputerModel $ComputerModel -OS $WindowsVersion
		Write-Output "Info: $ComputerManufacturer $ComputerModel matching model type: $global:LenovoModelType"
		
		if ($null -ne $global:LenovoModelDrivers) {
			[xml]$global:LenovoModelXML = (New-Object System.Net.WebClient).DownloadString("$global:LenovoXMLSource")
			# Set XML Object
			$global:LenovoModelXML.GetType().FullName | Out-Null
			$global:LenovoModelDrivers = $global:LenovoModelXML.Products
			if ($null -ne $SystemSKU) {
				$ComputerModelURL = (($global:LenovoModelDrivers.Product | Where-Object {
							($_.Queries.smbios -match $SystemSKU -and $_.OS -match $WindowsVersion)
						}).driverPack | Where-Object {
						$_.id -eq "SCCM"
					})."#text"
			}
			else {
				$ComputerModelURL = (($global:LenovoModelDrivers.Product | Where-Object {
							($_.Queries.Version -match ("^" + $ComputerModel + "$") -and $_.OS -match $WindowsVersion)
						}).driverPack | Where-Object {
						$_.id -eq "SCCM"
					})."#text"
			}
			Write-Output "Info: Model URL determined as $ComputerModelURL"
			$DriverDownload = FindLenovoDriver -URI $ComputerModelURL -os $WindowsVersion -Architecture $OSArchitecture
			If ($null -ne $DriverDownload) {
				$DriverCab = $DriverDownload | Split-Path -Leaf
				$DriverRevision = ($DriverCab.Split("_") | Select-Object -Last 1).Trim(".exe")
				Write-Output "Info: Driver cabinet download determined as $DriverDownload"
			}
			else {
				Write-Output "Error: Unable to find driver for $Make $Model"
			}
		}
	}
	
	# Driver location variables
	$DriverSourceCab = ($TempDirectory + "\Driver Cab\" + $DriverCab)
	$DriverExtractDest = ("$TempDirectory" + "\Driver Files")
	Write-Output "Info: Driver extract location set - $DriverExtractDest"
	
	# =================== INITIATE DOWNLOADS ===================			
	
	Write-Output "======== $Product - $ComputerManufacturer $ComputerModel DRIVER PROCESSING STARTED ========"
	
	# =============== ConfigMgr Driver Cab Download =================				
	Write-Output "$($Product): Retrieving ConfigMgr driver pack site For $ComputerManufacturer $ComputerModel"
	Write-Output "$($Product): URL found: $ComputerModelURL"
	
	if (($null -ne $ComputerModelURL) -and ($DriverDownload -ne "badLink")) {
		# Cater for HP / Model Issue
		$ComputerModel = $ComputerModel -replace '/', '-'
		$ComputerModel = $ComputerModel.Trim()
		Set-Location -Path $TempDirectory
		# Check for destination directory, create if required and download the driver cab
		if ((Test-Path -Path $($TempDirectory + "\Driver Cab\" + $DriverCab)) -eq $false) {
			if ((Test-Path -Path $($TempDirectory + "\Driver Cab")) -eq $false) {
				New-Item -ItemType Directory -Path $($TempDirectory + "\Driver Cab")
			}
			Write-Output "$($Product): Downloading $DriverCab driver cab file"
			Write-Output "$($Product): Downloading from URL: $DriverDownload"
			Start-Job -Name "$ComputerModel-DriverDownload" -ScriptBlock $DriverDownloadJob -ArgumentList ($TempDirectory, $ComputerModel, $DriverCab, $DriverDownload)
			Start-Sleep -Seconds 5
			$BitsJob = Get-BitsTransfer | Where-Object {
				$_.DisplayName -match "$ComputerModel-DriverDownload"
			}
			while (($BitsJob).JobState -eq "Connecting") {
				Write-Output "$($Product): Establishing connection to $DriverDownload"
				Start-Sleep -seconds 30
			}
			while (($BitsJob).JobState -eq "Transferring") {
				if ($null -ne $BitsJob.BytesTotal) {
					$PercentComplete = [int](($BitsJob.BytesTransferred * 100)/$BitsJob.BytesTotal);
					Write-Output "$($Product): Downloaded $([int]((($BitsJob).BytesTransferred)/ 1MB)) MB of $([int]((($BitsJob).BytesTotal)/ 1MB)) MB ($PercentComplete%). Next update in 30 seconds."
					Start-Sleep -seconds 30
				}
				else {
					Write-Output "$($Product): Download issues detected. Cancelling download process" -Severity 2
					Get-BitsTransfer | Where-Object {
						$_.DisplayName -eq "$ComputerModel-DriverDownload"
					} | Remove-BitsTransfer
				}
			}
			Get-BitsTransfer | Where-Object {
				$_.DisplayName -eq "$ComputerModel-DriverDownload"
			} | Complete-BitsTransfer
			Write-Output "$($Product): Driver revision: $DriverRevision"
		}
		else {
			Write-Output "$($Product): Skipping $DriverCab. Driver pack already downloaded."
		}
		
		# Cater for HP / Model Issue
		$ComputerModel = $ComputerModel -replace '/', '-'
		
		if (((Test-Path -Path "$($TempDirectory + '\Driver Cab\' + $DriverCab)") -eq $true) -and ($null -ne $DriverCab)) {
			Write-Output "$($Product): $DriverCab File exists - Starting driver update process"
			# =============== Extract Drivers =================
			
			if ((Test-Path -Path "$DriverExtractDest") -eq $false) {
				New-Item -ItemType Directory -Path "$($DriverExtractDest)"
			}
			if ((Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter *.inf -File).Count -eq 0) {
				Write-Output "==================== $PRODUCT DRIVER EXTRACT ===================="
				Write-Output "$($Product): Expanding driver CAB source file: $DriverCab"
				Write-Output "$($Product): Driver CAB destination directory: $DriverExtractDest"
				if ($ComputerManufacturer -eq "Dell") {
					Write-Output "$($Product): Extracting $ComputerManufacturer drivers to $DriverExtractDest"
					Expand "$DriverSourceCab" -F:* "$DriverExtractDest"
				}
				if ($ComputerManufacturer -eq "Hewlett-Packard") {
					Write-Output "$($Product): Extracting $ComputerManufacturer drivers to $HPTemp"
					# Driver Silent Extract Switches
					$HPSilentSwitches = "-PDF -F" + "$DriverExtractDest" + " -S -E"
					Write-Output "$($Product): Using $ComputerManufacturer silent switches: $HPSilentSwitches"
					Start-Process -FilePath "$($TempDirectory + '\Driver Cab\' + $DriverCab)" -ArgumentList $HPSilentSwitches -Verb RunAs
					$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
					
					# Wait for HP SoftPaq Process To Finish
					While ((Get-Process).name -contains $DriverProcess) {
						Write-Output "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds"
						Start-Sleep -Seconds 30
					}
				}
				if ($ComputerManufacturer -eq "Lenovo") {
					# Driver Silent Extract Switches
					$global:LenovoSilentSwitches = "/VERYSILENT /DIR=" + '"' + $DriverExtractDest + '"' + ' /Extract="Yes"'
					Write-Output "$($Product): Using $ComputerManufacturer silent switches: $global:LenovoSilentSwitches"
					Write-Output "$($Product): Extracting $ComputerManufacturer drivers to $DriverExtractDest"
					Unblock-File -Path $($TempDirectory + '\Driver Cab\' + $DriverCab)
					Start-Process -FilePath "$($TempDirectory + '\Driver Cab\' + $DriverCab)" -ArgumentList $global:LenovoSilentSwitches -Verb RunAs
					$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
					# Wait for Lenovo Driver Process To Finish
					While ((Get-Process).name -contains $DriverProcess) {
						Write-Output "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds"
						Start-Sleep -seconds 30
					}
				}
			}
			else {
				Write-Output "Skipping. Drivers already extracted."
			}
		}
		else {
			Write-Output "$($Product): $DriverCab file download failed" 
		}
	}
	elseif ($DriverDownload -eq "badLink") {
		Write-Output "$($Product): Operating system driver package download path not found.. Skipping $ComputerModel" 
	}
	else {
		Write-Output "$($Product): Driver package not found for $ComputerModel running Windows $WindowsVersion $Architecture. Skipping $ComputerModel" -Severity 2
	}
	Write-Output "======== $PRODUCT - $ComputerManufacturer $ComputerModel DRIVER PROCESSING FINISHED ========"
	
	
	if ($ValidationErrors -eq 0) {
		
	}
}

function Invoke-DriverUpdate {
	$DriverPackagePath = Join-Path $TempDirectory "Driver Files"
	Write-Output "Driver package location is $DriverPackagePath"
	Write-Output "Starting driver installation process"
	Write-Output "Reading drivers from $DriverPackagePath"
	# Apply driver maintenance package
	try {
		if ((Get-ChildItem -Path $DriverPackagePath -Filter *.inf -Recurse).count -gt 0) {
			try {
				Start-Process powershell.exe -WorkingDirectory $DriverPackagePath -ArgumentList "dism /Image:W:\ /Add-Driver /Driver:*.inf /Recurse | Out-File -FilePath (Join-Path $LogDirectory '\Install-Drivers.txt') -Append" -NoNewWindow -Wait
				#Start-Process "$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -WorkingDirectory $DriverPackagePath -ArgumentList "dism /Image:W:\ /Add-Driver /Driver:*.inf /Recurse | Out-File -FilePath (Join-Path $LogDirectory '\Install-Drivers.txt') -Append" -NoNewWindow -Wait
				Write-Output "Driver installation complete. Restart required"
				Return "success"
			}
			catch [System.Exception]
			{
				Write-Output "An error occurred while attempting to apply the driver maintenance package. Error message: $($_.Exception.Message)" ; exit 1
			}
		}
		else {
			Write-Output "No driver inf files found in $DriverPackagePath." ; exit 1
		}
	}
	catch [System.Exception] {
		Write-Output "An error occurred while attempting to apply the driver maintenance package. Error message: $($_.Exception.Message)" ; exit 1
	}
	Write-Output "Finished driver maintenance."
	#Return $LastExitCode
}


#if ($OSName -eq "Windows 10") {
	# Download manufacturer lists for driver matching
	Invoke-DriverListDownload
	# Initiate matched downloads
	Invoke-DriverDownload
	# Update driver repository and install drivers
	Invoke-DriverUpdate
#}
#else {
#	Write-Output "An upsupported OS was detected. This script only supports Windows 10." ; exit 1
#}