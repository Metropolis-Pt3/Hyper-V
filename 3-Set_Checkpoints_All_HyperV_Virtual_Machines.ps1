
<#
    Creates a checkpoint for all Hyper-V VMs on a Windows 11 workstation.
    - Uses Production checkpoints by default (falls back to Standard if needed).
    - Adds a timestamped name to each checkpoint.
    - Logs progress and errors to a file in C:\Users\Public.

    Notes:
    - Production checkpoints require integration services/VSS support in the guest.
    - Standard checkpoints can be used as a fallback.
#>

$ErrorActionPreference = 'Stop'

# Configure
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$checkpointBaseName = "AutoCheckpoint-$timestamp"
$preferredType = 'Production'   # 'Production' or 'Standard'
$fallbackToStandard = $true      # Try Standard if Production fails
$logPath = Join-Path $env:PUBLIC "HyperV-Checkpoint-All-$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue } catch {}
}

try {
    # Ensure Hyper-V module is available and loaded
    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        throw "Hyper-V PowerShell module not found. Enable Hyper-V and its PowerShell module in Windows features."
    }
    Import-Module Hyper-V -ErrorAction Stop

    $vms = Get-VM
    if (-not $vms) {
        Write-Log "No VMs found on this host." "WARN"
        return
    }

    Write-Log "Starting checkpoints for $($vms.Count) VM(s). Checkpoint name base: '$checkpointBaseName'. Preferred type: $preferredType"

    foreach ($vm in $vms) {
        $cpName = "$checkpointBaseName-$($vm.Name)"
        Write-Log "Creating checkpoint for VM: '$($vm.Name)' as '$cpName'"

        try {
            # Try preferred checkpoint type first
            Checkpoint-VM -VMName $vm.Name -SnapshotName $cpName -CheckpointType $preferredType -ErrorAction Stop
            Write-Log "Checkpoint created (type=$preferredType) for '$($vm.Name)'."
        } catch {
            $msg = $_.Exception.Message
            Write-Log "Failed to create $preferredType checkpoint for '$($vm.Name)': $msg" "WARN"

            if ($fallbackToStandard -and $preferredType -ne 'Standard') {
                try {
                    Write-Log "Attempting fallback to Standard checkpoint for '$($vm.Name)'."
                    Checkpoint-VM -VMName $vm.Name -SnapshotName $cpName -CheckpointType Standard -ErrorAction Stop
                    Write-Log "Checkpoint created (type=Standard) for '$($vm.Name)'."
                } catch {
                    Write-Log "Failed to create Standard checkpoint for '$($vm.Name)': $($_.Exception.Message)" "ERROR"
                }
            } else {
                Write-Log "No fallback configured; skipping VM '$($vm.Name)'." "ERROR"
            }
        }
    }

    Write-Log "Checkpoint operation complete for all VMs. Log: $logPath"
} catch {
    Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
    throw
}
