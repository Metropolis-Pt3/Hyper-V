
<# 
    Revert all Hyper-V VMs to their latest checkpoint (snapshot),
    regardless of powered state. 
    - Stops VMs if required (for production checkpoints).
    - Restores to the latest checkpoint.
    - Returns VMs to their prior running state (starts them if they were running).
#>

# Fail fast on errors in pipeline
$ErrorActionPreference = 'Stop'

# Optional: log file path
$logPath = Join-Path $env:PUBLIC "HyperV-Revert-All-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue } catch {}
}

try {
    # Ensure Hyper-V module is loaded
    if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
        throw "Hyper-V PowerShell module not found. Ensure Hyper-V is enabled and PowerShell module is installed."
    }
    Import-Module Hyper-V -ErrorAction Stop

    $vms = Get-VM
    if (-not $vms) {
        Write-Log "No VMs found on this host." "WARN"
        return
    }

    foreach ($vm in $vms) {
        Write-Log "Processing VM: $($vm.Name)"

        # Capture prior state to restore after snapshot
        $wasRunning = $vm.State -eq 'Running'

        # Get latest checkpoint (snapshot)
        $checkpoint = Get-VMSnapshot -VMName $vm.Name |
            Sort-Object -Property CreationTime -Descending |
            Select-Object -First 1

        if (-not $checkpoint) {
            Write-Log "No checkpoints found for VM '$($vm.Name)'. Skipping." "WARN"
            continue
        }

        Write-Log ("Latest checkpoint for '{0}': Name='{1}', Created='{2}', Type='{3}'" -f `
            $vm.Name, $checkpoint.Name, $checkpoint.CreationTime, $checkpoint.CheckpointType)

        # For Production checkpoints, VM must be off to restore.
        $needsStopForProduction = ($checkpoint.CheckpointType -eq 'Production' -and $vm.State -ne 'Off')

        if ($needsStopForProduction) {
            Write-Log "Production checkpoint requires VM to be powered off. Stopping '$($vm.Name)'..." "INFO"
            try {
                # Graceful stop if possible; fallback to force
                Stop-VM -Name $vm.Name -TurnOff:$false -Force -ErrorAction SilentlyContinue
                # Wait until it's off
                $waitStart = Get-Date
                while ((Get-VM -Name $vm.Name).State -ne 'Off') {
                    Start-Sleep -Seconds 1
                    if ((Get-Date) - $waitStart -gt (New-TimeSpan -Minutes 5)) {
                        throw "Timeout waiting for VM '$($vm.Name)' to stop."
                    }
                }
            } catch {
                Write-Log "Failed to stop VM '$($vm.Name)': $($_.Exception.Message)" "ERROR"
                continue
            }
        }

        # Perform the restore
        try {
            Write-Log "Restoring VM '$($vm.Name)' to checkpoint '$($checkpoint.Name)'..."
            Restore-VMSnapshot -VMName $vm.Name -Name $checkpoint.Name -Confirm:$false

            # After restore, return VM to prior running state if it was running
            if ($wasRunning) {
                Write-Log "VM '$($vm.Name)' was previously running. Starting it..."
                Start-VM -Name $vm.Name | Out-Null
            }

            Write-Log "Restore complete for VM '$($vm.Name)'."
        } catch {
            Write-Log "Restore failed for VM '$($vm.Name)': $($_.Exception.Message)" "ERROR"
            continue
        }
    }

    Write-Log "All VMs processed. Log: $logPath"
} catch {
    Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
    throw
}
