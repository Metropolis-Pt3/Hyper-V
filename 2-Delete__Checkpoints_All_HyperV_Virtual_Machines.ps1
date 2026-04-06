
<#
    Deletes all checkpoints (snapshots) from all Hyper-V VMs on a Windows 11 workstation.

    Features:
    - Enumerates all VMs and removes every checkpoint found.
    - Optional DRY-RUN mode (preview without changes).
    - Logs actions and errors to C:\Users\Public with a timestamped file.
    - Shows progress and handles absent checkpoints gracefully.

    Notes:
    - Removing checkpoints triggers merge operations of differencing disks.
      This can take time and consume disk/IO; it usually runs online while the VM continues operating.
    - Ensure sufficient free space before mass deletions.
#>

$ErrorActionPreference = 'Stop'

# ==== Configuration ====
$timestamp        = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath          = Join-Path $env:PUBLIC "HyperV-DeleteAllCheckpoints-$timestamp.log"
$dryRun           = $false   # Set to $true to preview without deleting
$maxMergeWarnGB   = 10       # Warn if a VM's checkpoint chain size appears large (heuristic, optional)

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

    Write-Log "Starting checkpoint deletion for $($vms.Count) VM(s). DRY-RUN=$dryRun. Log: $logPath"

    $vmIndex = 0
    foreach ($vm in $vms) {
        $vmIndex++
        Write-Progress -Activity "Deleting checkpoints" -Status "Processing VM $vmIndex of $($vms.Count): $($vm.Name)" -PercentComplete (($vmIndex / $vms.Count) * 100)

        Write-Log "VM: '$($vm.Name)' (State=$($vm.State))"

        # Gather all checkpoints for this VM
        $snapshots = Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue
        if (-not $snapshots -or $snapshots.Count -eq 0) {
            Write-Log "No checkpoints found for '$($vm.Name)'. Skipping." "INFO"
            continue
        }

        # Optional heuristic: estimate total differencing size by summing AVHDX sizes (best-effort)
        try {
            $chainSizeGB = 0
            # Enumerate VM's hard drives and attempt to accumulate sizes of AVHDX (checkpoint) files
            $drives = Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue
            foreach ($d in $drives) {
                if ($d.Path -and (Test-Path $d.Path)) {
                    $fileInfo = Get-Item $d.Path
                    $chainSizeGB += [math]::Round($fileInfo.Length / 1GB, 2)
                }
            }
            if ($chainSizeGB -ge $maxMergeWarnGB) {
                Write-Log "Estimated disk chain size for '$($vm.Name)': ~${chainSizeGB} GB. Merges may take time." "WARN"
            }
        } catch {
            Write-Log "Size estimation failed for '$($vm.Name)': $($_.Exception.Message)" "WARN"
        }

        Write-Log "Found $($snapshots.Count) checkpoint(s) for '$($vm.Name)': " +
                 ($snapshots | ForEach-Object { "'$($_.Name)' (Type=$($_.CheckpointType), Created=$($_.CreationTime))" } -join "; ")

        if ($dryRun) {
            Write-Log "DRY-RUN: Would remove all checkpoints for '$($vm.Name)'."
            continue
        }

        try {
            # Remove all checkpoints; pipeline supports snapshot objects directly
            $snapshots | Remove-VMSnapshot -Confirm:$false -ErrorAction Stop
            Write-Log "Checkpoint removal initiated for '$($vm.Name)'."

            # Note: merges run in background. You can monitor with Get-VM or storage I/O.
        } catch {
            Write-Log "Failed to remove checkpoints for '$($vm.Name)': $($_.Exception.Message)" "ERROR"
            continue
        }
    }

    Write-Log "Checkpoint deletion process completed for all VMs. Review merge progress in Hyper-V Manager or via storage monitoring. Log: $logPath"
} catch {
    Write-Log "Fatal error: $($_.Exception.Message)" "ERROR"
    throw
}
