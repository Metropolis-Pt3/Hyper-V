
<#
.SUMMARY
  Creates an Hyper-V Environment for Intune Testing

.DESCRIPTION
  Creates and configures Hyper-V Virtual machine for Intune AutoPilot Development and testing

.PARAMETERS
  -Name = Name of the VM (Ex. MYVM01)
  
  -CPUCount = # of CPUs (1-6) is the typical compute range autopilot testing (recommended = 4)

  -HyperV = Installs Hyper-V feature on-demand

  -IncludeGuiTools = Forces install of the Hyper-V GUI Tools

  -Autopilot = Gathers ComputerInfo and Corporate Identifier

  -NoRestart = Prevents the restart of the computer

  -PowerOn = Start the Hyper-V VM  <---- Disabled, Not Supported

  -ProductKey = Displays Windows 11 Product Key from Hyper-V host (If host if Windows 11)

  EXAMPLE
    .\Install-HyperV-CreateVM-2.2.38.ps1 -Name <Name> -CPUCount <1-6> -HyperV -IncludeGuiTools -Autopilot -NoRestart -ProductKey

    .\Install-HyperV-CreateVM-2.2.38.ps1 -Name <Name> -CPUCount <1-6> -Autopilot -ProductKey

.NOTES/REFERENCES
  Current Version=2.2.51
  Date: 3.6.2026
  Author: Steve Molzahn
  
  References:
  Required: Please download Windows 11 .iso from Microsoft.
  https://www.microsoft.com/en-us/software-download/windows11
    -Two options are available for media creation
        1. Download the Media Creation Tool, follow instructions to create the .iso
        or
        2. Download the actual Windows 11 x64 (English) .iso

  VM Memory is hardcoded to 6GB. This can be increased by editing the value (line 288)

  Notes:
  1. Must run as administrator
  2. Download WIndows Install Media and place the .iso in C:\Temp\Virtual\Media

  Changelog:
  3.6.2026
     -Initial Script Creation. v2.0.0
     -Added use parameters. v2.1.1
     -Massive additions of functionality and logic. Too many to list. v2.2.28
     -Added PowerOn to start the Hyper-V VM after build. v2.2.35

  3.7.2026 - Fixed issue with variables and adding the DVD/ISO drive to the VM. v2.2.38
  4.2.2026 - Added Product Key functionality. v2.2.40
  4.6.2026 - Updated Logic, added instruction. v2.2.42
  4.10.2026 
     -Removed power-on functionality, due to required manual input to boot to iso. v2.2.44
     -Update Operating system build check and instructions. v2.2.48
  4.13.2026 - Update information syntax. v2.2.50
  4.14.2026 - Update ISO Creation naming standard. v2.2.51

#>


#======================================
# INSTALL HYPER-V ROLE AND GUI TOOLS
#======================================

[CmdletBinding(SupportsShouldProcess = $true)]
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$Name,

    [Parameter(Mandatory=$True,Position=2)]
    [string]$CPUCount,

    [Parameter(Mandatory=$False,Position=3)]
    [switch]$HyperV=$False,

    [Parameter(Mandatory=$False,Position=4)]
    [switch]$IncludeGuiTools=$False,

    [Parameter(Mandatory=$False,Position=5)]
    [switch]$Autopilot = $False,

    [Parameter(Mandatory=$False,Position=6)]
    [switch]$NoRestart = $False,

    #[Parameter(Mandatory=$False,Position=7)]
    #[switch]$PowerOn = $False,

    [Parameter(Mandatory=$False,Position=8)]
    [switch]$ProductKey = $False
)


# VARIABLES (RUN)
$ErrorActionPreference = "SilentlyContinue"
$timestamp = (Get-Date).ToString("MM-dd-yyyy-HH:mm:ss")

# START LOGGING
#Get-timestamp for logging
function Get-TimeStamp {  
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)  
}

#Log path/name/location
$LogPath = "C:\Windows\Logs\Install-HyperV-CreateVM.log"
$LogDir = Split-Path $LogPath
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
Start-Transcript -Path $logPath -Append

# RUNTIME STATUS
$64Bit=[Environment]::Is64BitProcess
Write-Host "$(Get-TimeStamp) Is64BitProcess = $64Bit" -ForegroundColor Green

#Virtual location
Write-Host "$(Get-TimeStamp) Create Hyper-V Directories" -ForegroundColor Green
$VirtualPath = "C:\Temp\Virtual"
$VirtualMedia = "C:\Temp\Virtual\Media"
$VirtualTemplate = "C:\Temp\Virtual\Template"

#Create Hyper-V Directories 
$VirtualDir = Split-Path $VirtualPath
if (-not (Test-Path $VirtualDir)) {
    New-Item -ItemType Directory -Path $VirtualDir -Force | Out-Null
}

$MediaDir = Split-Path $VirtualMedia
if (-not (Test-Path $MediaDir)) {
    New-Item -ItemType Directory -Path $MediaDir -Force | Out-Null
}

$TemplateDir = Split-Path $VirtualTemplate
if (-not (Test-Path $TemplateDir)) {
    New-Item -ItemType Directory -Path $TemplateDir -Force | Out-Null
}

function Get-TempIso {
    $iso = Get-ChildItem "C:\Temp\Virtual\Media" -Filter "*.iso" -ErrorAction SilentlyContinue |
           Select-Object -First 1

    if ($null -eq $iso) {
        return $null
    } else {
        return $iso.FullName
    }
}

# If no .iso found exit the script
$IsoPath = Get-ChildItem -Path "$VirtualMedia" -Filter "Win11_25H2_English_x64-New.iso" -File -Recurse -ErrorAction SilentlyContinue |
           Select-Object -First 1 -ExpandProperty FullName

if ($null -eq $IsoPath) {
    Write-Host "$(Get-TimeStamp) No Windows 11 Media ISO found." -ForegroundColor Yellow
    Write-Host "$(Get-TimeStamp) Exiting script, please download Windows installation Media." -ForegroundColor Yellow
    Exit 1

} else {
    Write-Host "$(Get-TimeStamp) Windows Installation Media ISO: $IsoPath" -ForegroundColor Green
}

if($HyperV -eq $True)
{
function Get-ClientOsInfo {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{
        Caption     = $os.Caption
        Version     = $os.Version
        BuildNumber = [int]$os.BuildNumber
        EditionID   = $cv.EditionID
        ReleaseId   = $cv.DisplayVersion
        IsClient    = ($os.ProductType -eq 1)
    }
}

function Test-Win11ClientSupportedEdition {
    param([string]$EditionID)
    $supported = @(
        'Professional','ProfessionalN',
        'Enterprise','EnterpriseN','EnterpriseG','EnterpriseGN',
        'Education','EducationN','Pro','ProN'
    )
    return $supported -contains $EditionID
}

function Test-FeatureInstalled {
    param([string] $FeatureName)
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
    return ($feature.State -eq 'Enabled')
}

function Enable-ClientFeature {
    param([string] $FeatureName)
    if (-not (Test-FeatureInstalled -FeatureName $FeatureName)) {
        Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -All -NoRestart -ErrorAction Stop | Out-Null
        return $true
    }
    return $false
}

try {
    if ($LogPath) {
        $dir = Split-Path -Path $LogPath -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    if (-not (Test-IsAdmin)) {
        throw "Run this script in an elevated PowerShell session (Run as Administrator)."
    }

    $os = Get-ClientOsInfo
    if (-not $os.IsClient) { throw "Detected Server OS. Use a Server-targeted script for Hyper-V role." }

    # Basic Windows 11 check: Version starts with 10.0 and build >= 22000
    if ($os.BuildNumber -lt 22000) {
        throw "This script targets Windows 11 (build >= 22000). Detected: $($os.Caption) build $($os.BuildNumber)."
    }

    if (-not (Test-Win11ClientSupportedEdition -EditionID $os.EditionID)) {
        throw "Windows edition '$($os.EditionID)' does not support Hyper-V (Windows 11 Home is unsupported)."
    }

    Write-Host "$(Get-TimeStamp) Windows 11 detected: $($os.Caption) ($($os.ReleaseId)), Edition: $($os.EditionID), Build: $($os.BuildNumber)" -ForegroundColor Yellow

    $restartNeeded = $false

    # Core Hyper-V platform (includes hypervisor, services, and tools baseline)
    $restartNeeded = (Enable-ClientFeature -FeatureName 'Microsoft-Hyper-V-All') -or $restartNeeded

    if ($IncludeGuiTools) {
        # GUI + PowerShell mgmt tools for client
        $restartNeeded = (Enable-ClientFeature -FeatureName 'Microsoft-Hyper-V-Tools-All') -or $restartNeeded
        $restartNeeded = (Enable-ClientFeature -FeatureName 'Microsoft-Hyper-V-Management-PowerShell') -or $restartNeeded
    }

    if ($restartNeeded) {
        if ($NoRestart) {
            Write-Warning "$(Get-TimeStamp) A restart is required to complete Hyper-V installation. Returning code 3010." -ForegroundColor Yellow
            exit 3010
        } else {
            Write-Host "$(Get-TimeStamp) Restarting now to complete Hyper-V installation..." -ForegroundColor Yellow
            Restart-Computer -Force
        }
    } else {
        Write-Host "$(Get-TimeStamp) Hyper-V is already installed. No restart required." -ForegroundColor Green
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
  }
}


#======================================
# CREATE HYPER-V VIRTUAL MACHINE
#======================================
$VMName = $Name
$VMPath = "C:\Temp\Virtual\$VMName"
$VhdxPath = "C:\Temp\Virtual\$VMName\Virtual hard disks\$VMName.vhdx"
$VMSwitchName = "External Switch"
$VMTemplate = "C:\Temp\Virtual\Template"
$VMTemplateFile = "C:\Temp\Virtual\Template\BlankTemplate.vhdx"

# Copy disk from "TEMPLATES" folder and place in Hyper-V directory with VM name
Write-Host "$(Get-TimeStamp) Copy Hyper-V Virtual Machine Template" -ForegroundColor Green

if (Test-Path $VMTemplateFile) {
    Write-Host "File already exists: $VMTemplateFile" -ForegroundColor Yellow
} else {
    Write-Host "File not found. Creating file: $VMTemplateFile" -ForegroundColor Yellow
    New-VHD -Path "C:\Temp\Virtual\Template\BlankTemplate.vhdx" -SizeBytes 80GB | Out-Host
}

Write-Host "$(Get-TimeStamp) Creating Hyper-V Virtual Machine $VMName" -ForegroundColor Green

New-Item -ItemType Directory -Path "C:\Temp\Virtual\$VMName\Virtual hard disks" -Force | Out-Null
Copy-Item -Path "C:\Temp\Virtual\Template\BlankTemplate.vhdx" -Destination "C:\Temp\Virtual\$VMName\Virtual hard disks\$VMName.vhdx" -Force | Out-Null

# VM settings and create the VM
Write-Host "$(Get-TimeStamp) Setting Hyper-V Virtual Machine Configuration" -ForegroundColor Green

New-VM -Name $VMName -BootDevice VHD -VHDPath $VhdxPath -Path $VMPath -Generation 2 -Switch $VMSwitchName
Set-VM -VMName $VMName -ProcessorCount $CPUCount
Set-VMMemory -VMName $VMName -StartupBytes 6GB -DynamicMemoryEnabled $false
Set-VMSecurity -VMName $VMName -VirtualizationBasedSecurityOptOut $false
Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector
Enable-VMTPM -VMName $VMName
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"
Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $false | Out-Host

Write-Host "$(Get-TimeStamp) Hyper-V Virtual Machine $VMName Created" -ForegroundColor Green

#Check secure Boot Config and enable if not set
Write-Host "$(Get-TimeStamp) Verifying Hyper-V Virtual Machine $VMName Configuration" -ForegroundColor Green
$gen2 = (Get-VM -Name "VMName").Generation
$secureboot = (Get-VMFirmware -VMName "VMName").SecureBoot

try {
    # Get VM
    $vm = Get-VM -Name $VMName -ErrorAction Stop

    # Check Generation
    if ($vm.Generation -eq 1) {
        Write-Host "VM Not Compatible - Generation=$($vm.Generation)" -ForegroundColor Yellow
        exit 1
    }

    # Get current firmware settings
    $fw = Get-VMFirmware -VMName $VMName -ErrorAction Stop

    # If Secure Boot is OFF, enable it with Windows template
    if ($fw.SecureBoot -ne 'On') {
        Write-Host "$(Get-TimeStamp) Secure Boot is OFF. Enabling with Microsoft Windows template..." -ForegroundColor Cyan
        Set-VMFirmware -VMName $VMName -EnableSecureBoot On -SecureBootTemplate "MicrosoftWindows" -ErrorAction Stop
    }
    else {
        # Secure Boot is ON   make sure it's using the Windows template (not the Microsoft UEFI CA)
        if ($fw.SecureBootTemplate -ne 'MicrosoftWindows') {
            Write-Host "$(Get-TimeStamp) Secure Boot is ON but template is '$($fw.SecureBootTemplate)'. Switching to Microsoft Windows..." -ForegroundColor Cyan
            Set-VMFirmware -VMName $VMName -SecureBootTemplate "MicrosoftWindows" -ErrorAction Stop
        } else {
            Write-Host "$(Get-TimeStamp) Secure Boot already enabled with Microsoft Windows template." -ForegroundColor Green
        }
    }
    # Verify and report
    $fw = Get-VMFirmware -VMName $VMName
    Write-Host "$(Get-TimeStamp) Status: SecureBoot=$($fw.SecureBoot); Template=$($fw.SecureBootTemplate)" -ForegroundColor Green
}
catch {
    Write-Error $_.Exception.Message  
}

# Configure VM to Boot to DVD/ISO
Write-Host "$(Get-TimeStamp) Adding DVD/ISO to Hyper-V Virtual Machine $VMName" -ForegroundColor Green
Write-Host "$(Get-TimeStamp) Setting Hyper-V Virtual Machine $VMName DVD/ISO Boot Order" -ForegroundColor Green

Add-VMDvdDrive -VMName "$VMName" -Path $IsoPath
Set-VMFirmware -VMName "$VMName" -FirstBootDevice (Get-VMDvdDrive -VMName "$VMName")

Write-Host "$(Get-TimeStamp) Gathering Hyper-V Computer Hash and Corporate Identifier." -ForegroundColor Green

if($Autopilot -eq $True)
{
    # make a path to export the csv to
    $AutopilotPath = "$VMPath\Autopilot"
    if(!(Test-Path $AutopilotPath))
    {
        New-Item -ItemType Directory -Path "$AutopilotPath" -Force | Out-Null
    }
    # get the hardware info: manufacturer, model, serial
    $serial = Get-WmiObject -ComputerName localhost -Namespace root\virtualization\v2 -class Msvm_VirtualSystemSettingData | Where-Object {$_.elementName -eq $VMName} | Select-Object -ExpandProperty BIOSSerialNumber
    $data = "Microsoft Corporation,Virtual Machine,$($serial)"
    # add to CSV file in path
    Set-Content -Path "$($AutopilotPath)\$($VMName).csv" -Value $data
}

<#
if($PowerOn -eq $True)
{
$vm = Get-VM -Name "$VMName"
}

Write-Host "$(Get-TimeStamp) Powering On Hyper-V Virtual Machine $VMName." -ForegroundColor Green

if ($vm.State -ne 'Running') {
    Start-VM -Name "$VMName"
    Write-Host "$(Get-TimeStamp) No Power-on Requirment for Hyper-V Virtual Machine." -ForegroundColor Yellow
} else {
    Write-Host "$(Get-TimeStamp) Hyper-V Virtual Machine is already running." -ForegroundColor Yellow
}

Write-Host "$(Get-TimeStamp) Hyper-V Virtual Machine $VMName ready for Intune Autopilot Testing" -ForegroundColor Green
#>

if($ProductKey -eq $True)
{
$OS = Get-CimInstance Win32_OperatingSystem
$Reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

# Use DisplayVersion if available (Win 10/11), else ReleaseId
$Release = if ($Reg.DisplayVersion) { $Reg.DisplayVersion } else { $Reg.ReleaseId }

Write-Host "Hyper-V Host Operating System:" -ForegroundColor Cyan
Write-Host "Windows Edition: $($OS.Caption)" -ForegroundColor Cyan
Write-Host "Version Release: $Release" -ForegroundColor Cyan
Write-Host "Build Number:    $($OS.Version)" -ForegroundColor Cyan
Write-Host ""

  if ($OS.Caption -like "Microsoft Windows 11*") {
    Write-Host "HYPER-V HOST OPERATING SYSTEM IS WINDOWS 11." -ForegroundColor Green
    Write-Host "Microsoft Windows 11 Activation Key:" -ForegroundColor Green
    
    # Gather WIndows 11 Product Key
    $value = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform" -Name "BackupProductKeyDefault"
    Write-Host "$value" -ForegroundColor Green
    Write-Host ""
    Write-Host "Use this key for Virtual Machine Windows activation during OOBE" -ForegroundColor Green

  } else {
    Write-Host "HYPER-V HOST OPERATING SYSTEM IS NOT WINDOWS 11." -ForegroundColor Red
    Write-Host "A Windows 11 Product Key will be required for activation" -ForegroundColor Cyan
    Write-Host "during first boot/OOBE setup." -ForegroundColor Cyan
  } 

}

Write-Host ""
Write-Host "IMPORTANT INFORMATION - PLEASE READ" -ForegroundColor Green
Write-Host ""
Write-Host "VIRTUAL MACHINE WINDOWS ACTIVATION:" -ForegroundColor Yellow
Write-Host "The Microsoft Windows embedded retail Activation Key gathered from the Hyper-V" -ForegroundColor Yellow
Write-Host "host bios allows for virtual machine activation. If the Hyper-V host is not" -ForegroundColor Yellow
Write-Host "Windows 11, the activation key will not be provided to prevent any potential" -ForegroundColor Yellow
Write-Host "for licensing violations. It may be neccessary to provide a separate activation" -ForegroundColor Yellow
Write-Host "key depending on the type of license being used by the Hyper-V host." -ForegroundColor Yellow
Write-Host ""
Write-Host "------------------------------------------------------------------------------"
Write-Host ""
Write-Host "NETWORK DRIVERS:" -ForegroundColor Yellow
Write-Host "Hyper-V binds to the local physical Nic on the host computer when using the" -ForegroundColor Yellow
Write-Host "External Switch. Because of this drivers maybe need to be added to the Windows" -ForegroundColor Yellow
Write-Host "Installation Media ISO for seamless setup. This will be evident if the VM cannot" -ForegroundColor Yellow
Write-Host "communicate with Entra, Intune or Autopilot or prompts for Wifi drivers during" -ForegroundColor Yellow
Write-Host "OOBE. First check to ensure the External Switch is configured on the VM (Required)." -ForegroundColor Yellow
Write-Host "A script has been create to assist with injecting drivers into the Windows" -ForegroundColor Yellow
Write-Host "Installation Media ISO." -ForegroundColor Yellow
Write-Host ""
Write-Host "Get the powershell script here:" -ForegroundColor Cyan
Write-Host "https://gitlab.com/ClientEngineering" -ForegroundColor Cyan
Write-Host ""
Write-Host "------------------------------------------------------------------------------"
Write-Host ""
Write-Host "AUTOPILOTINFO:" -ForegroundColor Yellow
Write-Host "Once Windows has been installed, during first boot before selecting languages" -ForegroundColor Yellow
Write-Host "or regions, press SHIFT + fn + F10 to being up the command prompt. The computer" -ForegroundColor Yellow
Write-Host "hash of the device will need to be gathered and imported into Intune prior to" -ForegroundColor Yellow
Write-Host "autopilot assignment. PowerShell, PowerShell-Ise and Explorer can be run from" -ForegroundColor Yellow
Write-Host "this command prompt to assist in navigating the import process. The following" -ForegroundColor Yellow
Write-Host "Powershell script will generate the file that can be imported into Intune." -ForegroundColor Yellow
Write-Host ""
Write-Host "For convienence, add the Autopilot script to the install media ISO." -ForegroundColor Yellow
Write-Host ""
Write-Host "Reference: https://learn.microsoft.com/en-us/autopilot/add-devices" -ForegroundColor Green
Write-Host ""
Write-Host "There are two scripts available in the article above. Please read about them" -ForegroundColor Yellow
Write-Host "both and choose the best option for your environment." -ForegroundColor Yellow
Write-Host ""
Write-Host "Get the powershell script here:" -ForegroundColor Cyan
Write-Host "https://gitlab.com/ClientEngineering" -ForegroundColor Cyan
Write-Host ""
Write-Host "------------------------------------------------------------------------------"
Write-Host ""
Write-Host "CORPORATE IDENTIFIERS:" -ForegroundColor Yellow
Write-Host "In the virtual Machine Directory (C:\Temp\Virtual\<ComputerName>) is a folder" -ForegroundColor Yellow
Write-Host "named (Autopilot). The file in this folder can be imported into Intune as the" -ForegroundColor Yellow
Write-Host "corporate identifier. This will ensure Intune considers the new Hyper-V " -ForegroundColor Yellow
Write-Host "virtual machine a (Corporate) device, not personal device." -ForegroundColor Yellow
Write-Host ""
Write-Host "SCROLL UP TO READ IMPORTANT INFORMATION" -ForegroundColor Green
Write-Host ""

Stop-Transcript
