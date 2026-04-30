
<#
.SUMMARY
    Installs Hyper-V feature on-demand (the full hypervisor)

.PARAMETERS
    .\HyperV-Feature-On-Demand-1.0.2.ps1
        -Gui = Installs the Hyper-v management tools.
        
        -Reboot = If parameter used, the system will restart/reboot after the hyper-v installation is complete.

    EXAMPLES
        .\HyperV-Feature-On-Demand-1.0.2.ps1 = Installs Hyper-V Feature On-Demand Hypervisor, no reboot.

        .\HyperV-Feature-On-Demand-1.0.2.ps1 -Reboot = Installs Hyper-V Feature On-Demand Hypervisor, then forces reboot.

        .\HyperV-Feature-On-Demand-1.0.2.ps1 -Gui = Installs Hyper-V Feature On-Demand Hypervisor and Hyper-V management tools, no reboot.

        .\HyperV-Feature-On-Demand-1.0.2.ps1 -Gui -Reboot = Installs Hyper-V Feature On-Demand Hypervisor and Hyper-V management tools, then forces reboot.

.NOTES/REFERENCES
    Current Version = 1.0.2

    Requires Administrator privileges

    Changelog:
    4.30.206 - Initial script created. v1.0.2

#>

[CmdletBinding(SupportsShouldProcess = $true)]
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$Gui,

    [Parameter(Mandatory=$True,Position=2)]
    [string]$Reboot
)

Write-Output "Checking system compatibility for Hyper-V..."

# Verify Windows edition
$edition = (Get-ComputerInfo).WindowsEditionId

if ($edition -eq "Home") {
    Write-Error "Hyper-V is not supported on Windows Home edition."
    exit 1
}

# Verify virtualization support
$cpu = Get-CimInstance Win32_Processor
if (-not $cpu.VirtualizationFirmwareEnabled) {
    Write-Error "Virtualization is not enabled in BIOS/UEFI."
    exit 1
}

# Check if Hyper-V is already installed
$hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($hyperVFeature.State -eq "Enabled") {
    Write-Output "Hyper-V is already installed."
    exit 0
}

Write-Output "Installing Hyper-V feature..."

Enable-WindowsOptionalFeature `
    -Online `
    -FeatureName Microsoft-Hyper-V-All `
    -All `
    -NoRestart

Write-Output "Hyper-V installation completed."

if ($Gui -eq $True) {
        # GUI + PowerShell mgmt tools for client
    Enable-ClientFeature -FeatureName 'Microsoft-Hyper-V-Tools-All'
    Enable-ClientFeature -FeatureName 'Microsoft-Hyper-V-Management-PowerShell'
}

# Determine force reboot
if ($Reboot -eq $True) {
    Write-Output "Rebooting system to complete installation..."
    Restart-Computer -Force
} else {
    Write-Output "Reboot is required to finish installation."
    exit 3010   # Standard 'reboot required' exit code
}