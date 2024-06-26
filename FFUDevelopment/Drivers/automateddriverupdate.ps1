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

function global:WriteLog($LogText){ 
    Add-Content -path $LogFile -value "$((Get-Date).ToString()) $LogText"
}

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

$USBDrive = Get-USBDrive
# LogFile
$logFIle = Join-Path $USBDrive "Invoke-MSIntuneDriverUpdate.log"
if (Test-Path -Path $LogFile) {
	Remove-Item -Path $LogFile
}

# Set Temp & Log Location
[string]$TempDirectory = Join-Path $USBDrive "\DriverTemp"

# Set Temp & Log Location
[string]$TempDirectory = Join-Path $TempLocation "\Temp"
[string]$LogDirectory = Join-Path $TempLocation "\Logs"

# Create Temp Folder 
if ((Test-Path -Path $TempDirectory) -eq $false) {
	New-Item -Path $TempDirectory -ItemType Dir
}

# Create Logs Folder 
if ((Test-Path -Path $LogDirectory) -eq $false) {
	New-Item -Path $LogDirectory -ItemType Dir
}

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
WriteLog "Manufacturer determined as: $($ComputerManufacturer)"

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
WriteLog "Computer model determined as: $($ComputerModel)"

if (-not [string]::IsNullOrEmpty($SystemSKU)) {
	WriteLog "Computer SKU determined as: $($SystemSKU)"
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
WriteLog "Operating system determined as: $OSName"

# Get operating system architecture
switch -wildcard ((Get-CimInstance Win32_operatingsystem).OSArchitecture) {
	"64-*" {
		$OSArchitecture = "64-Bit"
	}
	"32-*" {
		$OSArchitecture = "32-Bit"
	}
}

WriteLog "Architecture determined as: $OSArchitecture"

$WindowsVersion = ($OSName).Split(" ")[1]

function DownloadDriverList {
	WriteLog "======== Download Model Link Information ========"
	if ($ComputerManufacturer -eq "Hewlett-Packard") {
		if ((Test-Path -Path $TempDirectory\$HPCabFile) -eq $false) {
			WriteLog "======== Downloading HP Product List ========"
			# Download HP Model Cabinet File
			WriteLog "Info: Downloading HP driver pack cabinet file from $HPXMLCabinetSource"
			try {
				Start-BitsTransfer -Source $HPXMLCabinetSource -Destination $TempDirectory
				# Expand Cabinet File
				WriteLog "Info: Expanding HP driver pack cabinet file: $HPXMLFile"
				Expand "$TempDirectory\$HPCabFile" -F:* "$TempDirectory\$HPXMLFile"
			}
			catch {
				WriteLog "Error: $($_.Exception.Message)"
			}
		}
		# Read XML File
		if ($null -eq $global:HPModelSoftPaqs) {
			WriteLog "Info: Reading driver pack XML file - $TempDirectory\$HPXMLFile"
			[xml]$global:HPModelXML = Get-Content -Path $TempDirectory\$HPXMLFile
			# Set XML Object
			$global:HPModelXML.GetType().FullName | Out-Null
			$global:HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
		}
	}
	if ($ComputerManufacturer -eq "Dell") {
		if ((Test-Path -Path $TempDirectory\$DellCabFile) -eq $false) {
			WriteLog "Info: Downloading Dell product list"
			WriteLog "Info: Downloading Dell driver pack cabinet file from $DellXMLCabinetSource"
			# Download Dell Model Cabinet File
			try {
				Start-BitsTransfer -Source $DellXMLCabinetSource -Destination $TempDirectory
				# Expand Cabinet File
				WriteLog "Info: Expanding Dell driver pack cabinet file: $DellXMLFile"
				Expand "$TempDirectory\$DellCabFile" -F:* "$TempDirectory\$DellXMLFile"
			}
			catch {
				WriteLog "Error: $($_.Exception.Message)"
			}
		}
		if ($null -eq $DellModelXML) {
			# Read XML File
			WriteLog "Info: Reading driver pack XML file - $TempDirectory\$DellXMLFile"
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
				WriteLog "Error: $($_.Exception.Message)"
			}
			
			# Read Web Site
			WriteLog "Info: Reading driver pack URL - $global:LenovoXMLSource"
			
			# Set XML Object 
			$global:LenovoModelXML.GetType().FullName | Out-Null
			$global:LenovoModelDrivers = $global:LenovoModelXML.Products
		}
	}
}

function FindLenovoDriver {
	
<#
 # This powershell file will extract the link for the specified driver pack or application
 # param $URI The string version of the URL
 # param $64bit A boolean to determine what version to pick if there are multiple
 # param $os A string containing 7, 8, or 10 depending on the os we are deploying 
 #           i.e. 7, Win7, Windows 7 etc are all valid os strings
 #>
	param (
		[parameter(Mandatory = $true, HelpMessage = "Provide the URL to parse.")]
		[ValidateNotNullOrEmpty()]
		[string]
		$URI,
		[parameter(Mandatory = $true, HelpMessage = "Specify the operating system.")]
		[ValidateNotNullOrEmpty()]
		[string]
		$OS,
		[string]
		$Architecture
	)
	
	#Case for direct link to a zip file
	if ($URI.EndsWith(".zip")) {
		return $URI
	}
	
	$err = @()
	
	#Get the content of the website
	try {
		$html = Invoke-WebRequest –Uri $URI
	}
	catch {
		WriteLog "Error: $($_.Exception.Message)"
	}
	
	#Create an array to hold all the links to exe files
	$Links = @()
	$Links.Clear()
	
	#determine if the URL resolves to the old download location
	if ($URI -like "*olddownloads*") {
		#Quickly grab the links that end with exe
		$Links = (($html.Links | Where-Object {
					$_.href -like "*exe"
				}) | Where-Object class -eq "downloadBtn").href
	}
	
	$Links = ((Select-string '(http[s]?)(:\/\/)([^\s,]+.exe)(?=")' -InputObject ($html).Rawcontent -AllMatches).Matches.Value)
	
	if ($Links.Count -eq 0) {
		return $null
	}
	
	# Switch OS architecture
	switch -wildcard ($Architecture) {
		"*64*" {
			$Architecture = "64"
		}
		"*86*" {
			$Architecture = "32"
		}
	}
	
	#if there are multiple links then narrow down to the proper arc and os (if needed)
	if ($Links.Count -gt 0) {
		#Second array of links to hold only the ones we want to target
		$MatchingLink = @()
		$MatchingLink.clear()
		foreach ($Link in $Links) {
			if ($Link -like "*w$($OS)$($Architecture)_*" -or $Link -like "*w$($OS)_$($Architecture)*") {
				$MatchingLink += $Link
			}
		}
	}
	
	if ($null -ne $MatchingLink) {
		return $MatchingLink
	}
	else {
		return "badLink"
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
			WriteLog "Info: Reading driver pack URL - $global:LenovoXMLSource"
			
			# Set XML Object
			$global:LenovoModelXML.GetType().FullName | Out-Null
			$global:LenovoModelDrivers = $global:LenovoModelXML.Products
		}
	}
	catch {
		WriteLog "Error: $($_.Exception.Message)"
	}
	
	if ($ComputerModel.Length -gt 0) {
		$global:LenovoModelType = ($global:LenovoModelDrivers.Product | Where-Object {
				$_.Queries.Version -match "$ComputerModel"
			}).Queries.Types | Select -ExpandProperty Type | Select-Object -first 1
		$global:LenovoSystemSKU = ($global:LenovoModelDrivers.Product | Where-Object {
				$_.Queries.Version -match "$ComputerModel"
			}).Queries.Types | select -ExpandProperty Type | Get-Unique
	}
	
	if ($ComputerModelType.Length -gt 0) {
		$global:LenovoModelType = (($global:LenovoModelDrivers.Product.Queries) | Where-Object {
				($_.Types | Select-Object -ExpandProperty Type) -match $ComputerModelType
			}).Version | Select-Object -first 1
	}
	Return $global:LenovoModelType
}

function InitiateDownloads {
	
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
			WriteLog "Error: $($_.Exception.Message)"
		}
	}
	
	WriteLog "======== Starting Download Processes ========"
	WriteLog "Info: Operating System specified: Windows $($WindowsVersion)"
	WriteLog "Info: Operating System architecture specified: $($OSArchitecture)"
	
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
	WriteLog "Info: Windows 10 build $OSBuild identified for driver match"
	
	# Start driver import processes
	WriteLog "Info: Starting Download,Extract And Import Processes For $ComputerManufacturer Model: $($ComputerModel)"
	
	# =================== DEFINE VARIABLES =====================
	
	if ($ComputerManufacturer -eq "Dell") {
		WriteLog "Info: Setting Dell variables"
		if ($null -eq $DellModelCabFiles) {
			[xml]$DellModelXML = Get-Content -Path $TempDirectory\$DellXMLFile
			# Set XML Object
			$DellModelXML.GetType().FullName | Out-Null
			$DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
		}
		if ($null -ne $SystemSKU) {
			WriteLog "Info: SystemSKU value is present, attempting match based on SKU - $SystemSKU)"
			
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
			WriteLog "Info: Falling back to matching based on model name"
			
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
		WriteLog "Info: Dell System Model ID is : $DellSystemSKU"
	}
	if ($ComputerManufacturer -eq "Hewlett-Packard") {
		WriteLog "Info: Setting HP variables"
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
			WriteLog "Unsupported model / operating system combination found. Exiting."
		}
	}
	if ($ComputerManufacturer -eq "Lenovo") {
		WriteLog "Info: Setting Lenovo variables"
		$global:LenovoModelType = LenovoModelTypeFinder -ComputerModel $ComputerModel -OS $WindowsVersion
		WriteLog "Info: $ComputerManufacturer $ComputerModel matching model type: $global:LenovoModelType"
		
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
			WriteLog "Info: Model URL determined as $ComputerModelURL"
			$DriverDownload = FindLenovoDriver -URI $ComputerModelURL -os $WindowsVersion -Architecture $OSArchitecture
			If ($null -ne $DriverDownload) {
				$DriverCab = $DriverDownload | Split-Path -Leaf
				$DriverRevision = ($DriverCab.Split("_") | Select-Object -Last 1).Trim(".exe")
				WriteLog "Info: Driver cabinet download determined as $DriverDownload"
			}
			else {
				WriteLog "Error: Unable to find driver for $Make $Model"
			}
		}
	}
	
	# Driver location variables
	$DriverSourceCab = ($TempDirectory + "\Driver Cab\" + $DriverCab)
	$DriverExtractDest = ("$TempDirectory" + "\Driver Files")
	WriteLog "Info: Driver extract location set - $DriverExtractDest"
	
	# =================== INITIATE DOWNLOADS ===================			
	
	WriteLog "======== $Product - $ComputerManufacturer $ComputerModel DRIVER PROCESSING STARTED ========"
	
	# =============== ConfigMgr Driver Cab Download =================				
	WriteLog "$($Product): Retrieving ConfigMgr driver pack site For $ComputerManufacturer $ComputerModel"
	WriteLog "$($Product): URL found: $ComputerModelURL"
	
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
			WriteLog "$($Product): Downloading $DriverCab driver cab file"
			WriteLog "$($Product): Downloading from URL: $DriverDownload"
			Start-Job -Name "$ComputerModel-DriverDownload" -ScriptBlock $DriverDownloadJob -ArgumentList ($TempDirectory, $ComputerModel, $DriverCab, $DriverDownload)
			sleep -Seconds 5
			$BitsJob = Get-BitsTransfer | Where-Object {
				$_.DisplayName -match "$ComputerModel-DriverDownload"
			}
			while (($BitsJob).JobState -eq "Connecting") {
				WriteLog "$($Product): Establishing connection to $DriverDownload"
				sleep -seconds 30
			}
			while (($BitsJob).JobState -eq "Transferring") {
				if ($BitsJob.BytesTotal -ne $null) {
					$PercentComplete = [int](($BitsJob.BytesTransferred * 100)/$BitsJob.BytesTotal);
					WriteLog "$($Product): Downloaded $([int]((($BitsJob).BytesTransferred)/ 1MB)) MB of $([int]((($BitsJob).BytesTotal)/ 1MB)) MB ($PercentComplete%). Next update in 30 seconds."
					sleep -seconds 30
				}
				else {
					WriteLog "$($Product): Download issues detected. Cancelling download process"
					Get-BitsTransfer | Where-Object {
						$_.DisplayName -eq "$ComputerModel-DriverDownload"
					} | Remove-BitsTransfer
				}
			}
			Get-BitsTransfer | Where-Object {
				$_.DisplayName -eq "$ComputerModel-DriverDownload"
			} | Complete-BitsTransfer
			WriteLog "$($Product): Driver revision: $DriverRevision"
		}
		else {
			WriteLog "$($Product): Skipping $DriverCab. Driver pack already downloaded."
		}
		
		# Cater for HP / Model Issue
		$ComputerModel = $ComputerModel -replace '/', '-'
		
		if (((Test-Path -Path "$($TempDirectory + '\Driver Cab\' + $DriverCab)") -eq $true) -and ($null -ne $DriverCab)) {
			WriteLog "$($Product): $DriverCab File exists - Starting driver update process"
			# =============== Extract Drivers =================
			
			if ((Test-Path -Path "$DriverExtractDest") -eq $false) {
				New-Item -ItemType Directory -Path "$($DriverExtractDest)"
			}
			if ((Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter *.inf -File).Count -eq 0) {
				WriteLog "==================== $PRODUCT DRIVER EXTRACT ===================="
				WriteLog "$($Product): Expanding driver CAB source file: $DriverCab"
				WriteLog "$($Product): Driver CAB destination directory: $DriverExtractDest"
				if ($ComputerManufacturer -eq "Dell") {
					WriteLog "$($Product): Extracting $ComputerManufacturer drivers to $DriverExtractDest"
					Expand "$DriverSourceCab" -F:* "$DriverExtractDest"
				}
				if ($ComputerManufacturer -eq "Hewlett-Packard") {
					WriteLog "$($Product): Extracting $ComputerManufacturer drivers to $HPTemp"
					# Driver Silent Extract Switches
					$HPSilentSwitches = "-PDF -F" + "$DriverExtractDest" + " -S -E"
					WriteLog "$($Product): Using $ComputerManufacturer silent switches: $HPSilentSwitches"
					Start-Process -FilePath "$($TempDirectory + '\Driver Cab\' + $DriverCab)" -ArgumentList $HPSilentSwitches -Verb RunAs
					$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
					
					# Wait for HP SoftPaq Process To Finish
					While ((Get-Process).name -contains $DriverProcess) {
						WriteLog "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds"
						sleep -Seconds 30
					}
				}
				if ($ComputerManufacturer -eq "Lenovo") {
					# Driver Silent Extract Switches
					$global:LenovoSilentSwitches = "/VERYSILENT /DIR=" + '"' + $DriverExtractDest + '"' + ' /Extract="Yes"'
					WriteLog "$($Product): Using $ComputerManufacturer silent switches: $global:LenovoSilentSwitches"
					WriteLog "$($Product): Extracting $ComputerManufacturer drivers to $DriverExtractDest"
					Unblock-File -Path $($TempDirectory + '\Driver Cab\' + $DriverCab)
					Start-Process -FilePath "$($TempDirectory + '\Driver Cab\' + $DriverCab)" -ArgumentList $global:LenovoSilentSwitches -Verb RunAs
					$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
					# Wait for Lenovo Driver Process To Finish
					While ((Get-Process).name -contains $DriverProcess) {
						WriteLog "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds"
						sleep -seconds 30
					}
				}
			}
			else {
				WriteLog "Skipping. Drivers already extracted."
			}
		}
		else {
			WriteLog "$($Product): $DriverCab file download failed"
		}
	}
	elseif ($DriverDownload -eq "badLink") {
		WriteLog "$($Product): Operating system driver package download path not found.. Skipping $ComputerModel"
	}
	else {
		WriteLog "$($Product): Driver package not found for $ComputerModel running Windows $WindowsVersion $Architecture. Skipping $ComputerModel"
	}
	WriteLog "======== $PRODUCT - $ComputerManufacturer $ComputerModel DRIVER PROCESSING FINISHED ========"
	
	
	if ($ValidationErrors -eq 0) {
		
	}
}

function Update-Drivers {
	$DriverPackagePath = Join-Path $TempDirectory "Driver Files"
	WriteLog "Driver package location is $DriverPackagePath"
	WriteLog "Starting driver installation process"
	WriteLog "Reading drivers from $DriverPackagePath"
	# Apply driver maintenance package
	try {
		if ((Get-ChildItem -Path $DriverPackagePath -Filter *.inf -Recurse).count -gt 0) {
			try {
				Start-Process "$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -WorkingDirectory $DriverPackagePath -ArgumentList "pnputil /add-driver *.inf /subdirs /install | Out-File -FilePath (Join-Path $LogDirectory '\Install-Drivers.txt') -Append" -NoNewWindow -Wait
				WriteLog "Driver installation complete. Restart required"
			}
			catch [System.Exception]
			{
				WriteLog "An error occurred while attempting to apply the driver maintenance package. Error message: $($_.Exception.Message)"
			}
		}
		else {
			WriteLog "No driver inf files found in $DriverPackagePath."
		}
	}
	catch [System.Exception] {
		WriteLog "An error occurred while attempting to apply the driver maintenance package. Error message: $($_.Exception.Message)"
	}
	WriteLog "Finished driver maintenance."
	Return $LastExitCode
}

if ($OSName -eq "Windows 10") {
	# Download manufacturer lists for driver matching
	DownloadDriverList
	# Initiate matched downloads
	InitiateDownloads
	# Update driver repository and install drivers
	Update-Drivers
}
else {
	WriteLog "An upsupported OS was detected. This script only supports Windows 10."
}