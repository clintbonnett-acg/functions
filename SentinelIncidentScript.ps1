<#
.SYNOPSIS
    Creates a local test user, produces seven failed logon attempts,
    then completes one successful logon.

.DESCRIPTION
    - Requires Windows PowerShell 5.1+ or PowerShell 7+
    - Must be run from an *elevated* session
    - Local Account-Lockout Policy may lock the account before seven failures
      (adjust in a test VM if necessary)
#>

$UserName      = "DJ019-i"
$UserName2     = "DSmith"
$PasswordPlain = "P@ssw0rd!123"
# >>> ---------------------------------- <<<

#------- Helper Functions -------#

function New-LabUser {
    param([string]$User, [string]$PwdPlain)

    $securePwd = ConvertTo-SecureString $PwdPlain -AsPlainText -Force

    if (Get-LocalUser -Name $User -ErrorAction SilentlyContinue) {
        Write-Host "User '$User' already exists."
    } else {
        New-LocalUser `
            -Name $User `
            -Password $securePwd `
            -PasswordNeverExpires `
            -AccountNeverExpires `
            -UserMayNotChangePassword | Out-Null
        Write-Host "Created local user '$User'."
    }
}

function Test-Login {
    param([string]$User, [string]$Pwd, [int]$Attempt)

    $cmd = "net use \\localhost\IPC$ /user:$env:COMPUTERNAME\$User `"$Pwd`" /persistent:no"
    if (cmd /c $cmd) {
        Write-Host "Attempt $Attempt : SUCCESS"
        cmd /c "net use \\localhost\IPC$ /delete" | Out-Null
        return $true
    } else {
        Write-Host "Attempt $Attempt : FAILED"
        return $false
    }
}


#------- Safety Checks -------#

if (-not ([bool](Test-Path 'HKLM:\SYSTEM'))) {
    throw "This script must be run on Windows."
}

if (-not ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent() `
        ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    throw "Run this script from an *elevated* PowerShell session."
}

# =======================================================================
#  SentinelSim  –  bootstrap & self-scheduling header (v2)
# =======================================================================

$eventSource   = 'SentinelSim'
$logName       = 'Application'
$delayMinutes  = 5
$taskName      = 'SentinelSim'
$labFolder     = 'C:\Lab'
$scriptDest    = Join-Path $labFolder 'SentinelIncidentScript.ps1'
$gitRaw        = 'https://raw.githubusercontent.com/clintbonnett-acg/functions/main/SentinelIncidentScript.ps1'

# ---------- Ensure event-log source ----------
if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
    New-EventLog -LogName $logName -Source $eventSource
}
function Write-Log($msg, $type='Information') {
    Write-EventLog -LogName $logName -Source $eventSource -EntryType $type -EventId 3000 -Message $msg
}
trap {
    Write-Log "ERROR: $($_.Exception.Message)`n$($_.Exception.StackTrace)" 'Error'
    exit 1
}

# ---------- Bootstrap run ----------
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {

    Write-Log "Bootstrap run – downloading latest script & registering scheduled task."

    # 1. Ensure folder
    New-Item -Path $labFolder -ItemType Directory -Force | Out-Null

    # 2. Always (re)download the latest script from GitHub
    Invoke-WebRequest -Uri $gitRaw -OutFile $scriptDest -UseBasicParsing

    # 3. Schedule one-shot run for +$delayMinutes
    $runTime = (Get-Date).AddMinutes($delayMinutes).ToString('HH:mm')
    schtasks /Create `
        /TN $taskName `
        /SC ONCE `
        /ST $runTime `
        /RL HIGHEST `
        /F `
        /TR "powershell -ExecutionPolicy Bypass -File `"$scriptDest`""

    Write-Log "Scheduled task '$taskName' will run at $runTime. Exiting bootstrap."
    exit 0
}

Write-Log "Scheduled run started – generating authentication noise."


New-LabUser -User $UserName -PwdPlain $PasswordPlain
New-LabUser -User $UserName2 -PwdPlain $PasswordPlain 


$badPassword = "WrongP@ss"

1..9 | ForEach-Object {
    Test-Login -User $UserName -Pwd $badPassword -Attempt $_ | Out-Null
    sleep 0.5
}
sleep 1
Test-Login -User $UserName -Pwd $PasswordPlain -Attempt 10

1..6 | ForEach-Object {
    Test-Login -User $UserName2 -Pwd $badPassword -Attempt $_ | Out-Null
    Start-Sleep -Seconds (Get-Random -Minimum 6 -Maximum 20)
}
sleep 10
Test-Login -User $UserName2 -Pwd $PasswordPlain -Attempt 7
