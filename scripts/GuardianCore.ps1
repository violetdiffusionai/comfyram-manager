# GuardianCore.ps1 - shared functions for ComfyUI Guardian (used by the Electron app)
$ComfyUIPorts = @(8188, 8189, 8000, 7860)

function Get-VramUsage {
    try {
        $raw = & nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits
        $parts = $raw -split ",\s*"
        $used = [int]$parts[0]; $total = [int]$parts[1]
        [PSCustomObject]@{ used=$used; total=$total; percent=[math]::Round(($used/$total)*100,1) }
    } catch { [PSCustomObject]@{ used=0; total=0; percent=0; error="nvidia-smi unavailable" } }
}

function Get-RamUsage {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMB = [math]::Round($os.TotalVisibleMemorySize/1024,0)
        $freeMB  = [math]::Round($os.FreePhysicalMemory/1024,0)
        $usedMB  = $totalMB - $freeMB
        [PSCustomObject]@{ usedMB=$usedMB; totalMB=$totalMB; percent=[math]::Round(($usedMB/$totalMB)*100,1) }
    } catch { [PSCustomObject]@{ usedMB=0; totalMB=0; percent=0 } }
}

function Find-ComfyUIPort {
    foreach ($p in $ComfyUIPorts) {
        try {
            Invoke-RestMethod -Uri "http://127.0.0.1:$p/system_stats" -TimeoutSec 2 -ErrorAction Stop | Out-Null
            return $p
        } catch { continue }
    }
    return $null
}

function Invoke-ComfyUIFree($port) {
    try {
        $body = @{ unload_models = $true; free_memory = $true } | ConvertTo-Json
        Invoke-RestMethod -Uri "http://127.0.0.1:$port/free" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 5 | Out-Null
        return $true
    } catch { return $false }
}

if (-not ("GuardianNative" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class GuardianNative {
    [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@
}

function Invoke-WorkingSetTrim {
    $targets = Get-Process | Where-Object {
        $_.ProcessName -in @("nvcontainer","NVDisplay.Container") -or
        ($_.ProcessName -match "^python" -and
         ((Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine -match "comfy|main\.py"))
    }
    $n = 0
    foreach ($proc in $targets) {
        try { [GuardianNative]::EmptyWorkingSet($proc.Handle) | Out-Null; $n++ } catch {}
    }
    return $n
}

function Find-ComfyUIWindow {
    $handles = New-Object System.Collections.Generic.List[IntPtr]
    $cb = {
        param($hWnd, $lParam)
        if ([GuardianNative]::IsWindowVisible($hWnd)) {
            $sb = New-Object System.Text.StringBuilder 256
            [GuardianNative]::GetWindowText($hWnd, $sb, 256) | Out-Null
            if ($sb.ToString() -match "ComfyUI") { $handles.Add($hWnd) }
        }
        $true
    }
    [GuardianNative]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
    if ($handles.Count -gt 0) { $handles[0] } else { $null }
}

function Invoke-BrowserReload {
    $hwnd = Find-ComfyUIWindow
    if ($null -eq $hwnd) { return $false }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $prev = [GuardianNative]::GetForegroundWindow()
    [GuardianNative]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait("^r")
    Start-Sleep -Milliseconds 150
    [GuardianNative]::SetForegroundWindow($prev) | Out-Null
    return $true
}

function Invoke-ClearRam {
    $exclude = @("System","Idle","Registry","csrss","wininit","winlogon","services","lsass","smss","dwm","MemCompression")
    $before = Get-RamUsage
    $n = 0
    Get-Process | Where-Object { $exclude -notcontains $_.ProcessName } | ForEach-Object {
        try { [GuardianNative]::EmptyWorkingSet($_.Handle) | Out-Null; $n++ } catch {}
    }
    [System.GC]::Collect()
    Start-Sleep -Milliseconds 500
    $after = Get-RamUsage
    [PSCustomObject]@{ trimmed=$n; before=$before; after=$after }
}

function Invoke-SecurityScan {
    # Heuristic scan for likely-fraudulent / malicious processes.
    # A process is only flagged when it trips one of the "hard" signals below —
    # pure "unsigned" alone is NOT enough to flag (too many legit dev/AI tools are
    # unsigned on this machine) but it raises the score of anything else flagged.
    $suspiciousPathFragments = @('\Temp\', '\AppData\Local\Temp\', '\Downloads\', '\AppData\Roaming\', '\$Recycle.Bin\')
    $spoofableSystemNames = @('svchost','csrss','winlogon','lsass','services','smss','wininit','dwm','conhost','spoolsv','taskhost','taskhostw','explorer')
    $trustedSystemDirs = @('C:\Windows\System32','C:\Windows\SysWOW64','C:\Windows','C:\Windows\WinSxS')

    $listeners = @{}
    try {
        Get-NetTCPConnection -State Listen -ErrorAction Stop | ForEach-Object {
            if (-not $listeners.ContainsKey($_.OwningProcess)) { $listeners[$_.OwningProcess] = @() }
            if ($listeners[$_.OwningProcess] -notcontains $_.LocalPort) { $listeners[$_.OwningProcess] += $_.LocalPort }
        }
    } catch {}

    $procs = Get-Process | Where-Object { $_.Path }
    $findings = @()

    foreach ($p in $procs) {
        $path = $null
        try { $path = $p.Path } catch { continue }
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $name = $p.ProcessName
        $dir = $null
        try { $dir = Split-Path $path -Parent } catch { continue }
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }

        # Cheap checks first (string/hashtable comparisons) — Get-AuthenticodeSignature
        # is relatively slow, so it only runs on processes that already look suspicious
        # by path, name, or open listening port. This keeps a full-process scan fast.
        $inSuspiciousPath = $false
        foreach ($frag in $suspiciousPathFragments) {
            if ($path -like "*$frag*") { $inSuspiciousPath = $true; break }
        }

        $isSpoofedSystemName = $false
        if ($spoofableSystemNames -contains $name.ToLower()) {
            $trusted = $false
            foreach ($td in $trustedSystemDirs) { if ($dir -ieq $td) { $trusted = $true; break } }
            if (-not $trusted) { $isSpoofedSystemName = $true }
        }

        $procListens = $listeners[[int]$p.Id]
        $hasListener = $null -ne $procListens

        if (-not ($inSuspiciousPath -or $isSpoofedSystemName -or $hasListener)) { continue }

        $sigValid = $true
        try {
            $sig = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
            if ($sig.Status -ne 'Valid') { $sigValid = $false }
        } catch { $sigValid = $false }

        $trigger = $inSuspiciousPath -or $isSpoofedSystemName -or ($hasListener -and -not $sigValid)
        if (-not $trigger) { continue }

        $reasons = @()
        $score = 0
        if ($isSpoofedSystemName) { $score += 60; $reasons += "impersonating system process '$name' outside a trusted system folder" }
        if ($inSuspiciousPath) { $score += 35; $reasons += "running from $dir" }
        if (-not $sigValid) { $score += 15; $reasons += "no valid digital signature" }
        if ($hasListener) { $score += 25; $reasons += "listening on port(s) $($procListens -join ', ')" }

        $level = if ($score -ge 60) { "HIGH" } elseif ($score -ge 30) { "MEDIUM" } else { "LOW" }
        $findings += [PSCustomObject]@{
            pid = $p.Id; name = $name; path = $path
            score = $score; level = $level; reasons = $reasons
        }
    }

    $findings = $findings | Sort-Object -Property score -Descending
    [PSCustomObject]@{
        scanned = $procs.Count
        flagged = $findings.Count
        findings = $findings
    }
}

function Invoke-KillAllPythonAndContainers {
    $killed = @()
    Get-Process -Name "python","pythonw" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; $killed += "python:$($_.Id)" } catch {}
    }
    Get-Process -Name "nvcontainer","NVDisplay.Container" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; $killed += "$($_.ProcessName):$($_.Id)" } catch {}
    }
    return $killed
}
