param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Status","Free","KillAll","Detect","ClearRam","SecurityScan")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\GuardianCore.ps1"

switch ($Action) {
    "Status" {
        $vram = Get-VramUsage
        $ram  = Get-RamUsage
        $port = Find-ComfyUIPort
        [PSCustomObject]@{
            vram = $vram
            ram  = $ram
            comfy = [PSCustomObject]@{ online = [bool]$port; port = $port }
        } | ConvertTo-Json -Depth 4 -Compress
    }
    "Detect" {
        $port = Find-ComfyUIPort
        [PSCustomObject]@{ online = [bool]$port; port = $port } | ConvertTo-Json -Compress
    }
    "Free" {
        $before = Get-VramUsage
        $port = Find-ComfyUIPort
        $freed = $false
        if ($port) { $freed = Invoke-ComfyUIFree $port }
        $trimmed = Invoke-WorkingSetTrim
        $reloaded = Invoke-BrowserReload
        Start-Sleep -Seconds 1
        $after = Get-VramUsage
        [PSCustomObject]@{
            comfyPort=$port; freed=$freed; trimmedProcesses=$trimmed; reloadedTab=$reloaded
            before=$before; after=$after
        } | ConvertTo-Json -Depth 4 -Compress
    }
    "ClearRam" {
        Invoke-ClearRam | ConvertTo-Json -Depth 4 -Compress
    }
    "SecurityScan" {
        Invoke-SecurityScan | ConvertTo-Json -Depth 5 -Compress
    }
    "KillAll" {
        $killed = Invoke-KillAllPythonAndContainers
        [PSCustomObject]@{ killed=$killed; count=$killed.Count } | ConvertTo-Json -Compress
    }
}
