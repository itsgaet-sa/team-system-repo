# Autore: G.ABBATICCHIO
# Revisione: 1.7
# Data: 17/02/2026
# Code: deso_efc_user_migration
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Preparazione per la migrazione dell'utente, creazione del file dichiarativo.

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ──────────────────────────────────────────────────────────────────────────────
# CONFIG (FAKE, eccetto server/utenze)
# ──────────────────────────────────────────────────────────────────────────────

$migrationValue    = "true"
$fromUser          = "userFake"
$fromServer        = "serverFake"
$toServer          = "10.0.0.10"  # FAKE

$migrationServerIP = "10.182.1.11" # REALE

# Utenze REALI da Cypher
$migrationUserRaw = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-USR",true)%>'
$migrationPassRaw = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-PWD",true)%>'

# Percorsi sul dispatcher
$basePath   = "D:\tools\migration"
$queuePath  = Join-Path $basePath "incoming"
$lockFile   = Join-Path $basePath "queue.lock"
$dispatcher = Join-Path $basePath "dispatcher.ps1"

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONI
# ──────────────────────────────────────────────────────────────────────────────

function New-MigrationCredential {
    param([string]$User, [string]$PassPlain)
    if ([string]::IsNullOrWhiteSpace($User) -or [string]::IsNullOrWhiteSpace($PassPlain)) {
        throw "Credenziali migrazione vuote (user/password)"
    }
    $sec = ConvertTo-SecureString $PassPlain -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($User, $sec)
}

function Invoke-Remote {
    param(
        [System.Management.Automation.Runspaces.PSSession]$Session,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @()
    )
    $out = Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    foreach ($line in ($out | Where-Object { $_ -is [string] })) { Write-Output $line }
    return ($out | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1)
}

# ──────────────────────────────────────────────────────────────────────────────
# START
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] Controllo richiesta migrazione utente..."

if ($migrationValue -ne "true") {
    Write-Output "[INFO] Migrazione dati NON richiesta - Skip"
    exit 0
}

Write-Output "[INFO] Parametri migrazione:"
Write-Output "[INFO]   - Utente origine   : $fromUser"
Write-Output "[INFO]   - Server origine   : $fromServer"
Write-Output "[INFO]   - Server destino   : $toServer"
Write-Output "[INFO]   - Server dispatcher: $migrationServerIP"

try {
    $cred = New-MigrationCredential -User $migrationUserRaw -PassPlain $migrationPassRaw
} catch {
    Write-Output "[ERROR] $($_.Exception.Message)"
    exit 1
}

$session = $null
try {
    Write-Output "[INFO] Connessione al dispatcher ($migrationServerIP)..."
    $sessionOption = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 60000
    $session = New-PSSession -ComputerName $migrationServerIP -Credential $cred -SessionOption $sessionOption -ErrorAction Stop
    Write-Output "[SUCCESS] Sessione remota stabilita"
} catch {
    Write-Output "[ERROR] Connessione al dispatcher fallita: $($_.Exception.Message)"
    if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    exit 1
}

# 1) Accoda file (crea migra_XXXXXX.txt)
try {
    Write-Output "[INFO] Accodamento richiesta migrazione..."
    $res = Invoke-Remote -Session $session -ScriptBlock {
        param($fromUser, $fromServer, $toServer, $queuePath, $lockFile)

        if (-not (Test-Path $queuePath)) {
            New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
            Write-Output "[REMOTE][INFO] Directory coda creata: $queuePath"
        }

        # lock semplice (CreateNew)
        $lockHandle = $null
        try {
            $lockHandle = [System.IO.File]::Open($lockFile, 'CreateNew', 'Write', 'None')
            Write-Output "[REMOTE][INFO] Lock acquisito"

            $max = Get-ChildItem -Path $queuePath -Filter "migra_*.txt" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^migra_(\d+)\.txt$' } |
                ForEach-Object { [int]$Matches[1] } |
                Sort-Object -Descending |
                Select-Object -First 1

            $next = if ($null -ne $max) { $max + 1 } else { 1 }

            $name = "migra_{0:D6}.txt" -f $next
            $path = Join-Path $queuePath $name
            $content = "${fromUser}|${fromServer}|${toServer}"

            Set-Content -Path $path -Value $content -Force -ErrorAction Stop
            Write-Output "[REMOTE][SUCCESS] File creato: $path"

            return @{ Status="Success"; FileName=$name; FilePath=$path; Sequence=$next }
        }
        finally {
            if ($lockHandle) { $lockHandle.Close(); $lockHandle.Dispose() }
            if (Test-Path $lockFile) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
            Write-Output "[REMOTE][INFO] Lock rilasciato"
        }

    } -ArgumentList @($fromUser, $fromServer, $toServer, $queuePath, $lockFile)

    if (-not $res -or $res.Status -ne "Success") { throw "Accodamento non riuscito: risultato non valido" }

    Write-Output "[SUCCESS] Accodamento OK"
    Write-Output "[INFO]   - File: $($res.FileName)"
    Write-Output "[INFO]   - Path: $($res.FilePath)"
} catch {
    Write-Output "[ERROR] Accodamento fallito: $($_.Exception.Message)"
    if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    exit 1
}

# 2) Avvia dispatcher (best effort)
try {
    Write-Output "[INFO] Avvio dispatcher..."
    $disp = Invoke-Remote -Session $session -ScriptBlock {
        param($dispatcher)

        if (-not (Test-Path $dispatcher)) {
            Write-Output "[REMOTE][WARNING] Dispatcher non trovato: $dispatcher"
            return @{ Status="NotFound" }
        }

        try {
            & $dispatcher
            Write-Output "[REMOTE][SUCCESS] Dispatcher eseguito"
            return @{ Status="Success" }
        } catch {
            Write-Output "[REMOTE][WARNING] Dispatcher errore: $($_.Exception.Message)"
            return @{ Status="Failed" }
        }
    } -ArgumentList @($dispatcher)

    if ($disp -and $disp.Status -eq "Success") {
        Write-Output "[SUCCESS] Dispatcher avviato"
    } else {
        Write-Output "[WARNING] Dispatcher non confermato (ok se rimane in coda)"
    }
} catch {
    Write-Output "[WARNING] Avvio dispatcher non riuscito: $($_.Exception.Message)"
}

# 3) Monitoraggio (solo file state)
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($res.FileName)
Write-Output "[INFO] Monitoraggio stato migrazione: $baseName"

$timeoutSec  = 5400
$intervalSec = 10
$elapsed     = 0

while ($elapsed -lt $timeoutSec) {
    try {
        $status = Invoke-Remote -Session $session -ScriptBlock {
            param($baseName, $queuePath)

            $done = Join-Path $queuePath "$baseName.done"
            $err  = Join-Path $queuePath "$baseName.err"
            $txt  = Join-Path $queuePath "$baseName.txt"
            $work = Join-Path $queuePath "$baseName.work"

            if (Test-Path $done) { return @{ Status="Completed"; FilePath=$done } }
            if (Test-Path $err)  {
                $msg = Get-Content $err -Raw -ErrorAction SilentlyContinue
                return @{ Status="Failed"; FilePath=$err; ErrorMessage=$msg }
            }
            if (Test-Path $work) { return @{ Status="Processing"; FilePath=$work } }
            if (Test-Path $txt)  { return @{ Status="Scheduled"; FilePath=$txt } }

            return @{ Status="Unknown"; FilePath=$null }
        } -ArgumentList @($baseName, $queuePath)

        switch ($status.Status) {
            "Completed" {
                Write-Output "[SUCCESS] Migrazione completata: $($status.FilePath)"
                break
            }
            "Failed" {
                $msg = if ($status.ErrorMessage) { $status.ErrorMessage.Trim() } else { "Errore non specificato" }
                Write-Output "[ERROR] Migrazione fallita: $msg"
                break
            }
            "Unknown" {
                Write-Output "[ERROR] File di migrazione non trovato (baseName=$baseName)"
                break
            }
            default {
                Write-Output "[INFO] Stato: $($status.Status) (t=${elapsed}s)"
            }
        }

        if ($status.Status -in @("Completed","Failed","Unknown")) { break }

    } catch {
        Write-Output "[WARNING] Polling errore: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $intervalSec
    $elapsed += $intervalSec
}

if ($elapsed -ge $timeoutSec) {
    Write-Output "[WARNING] Timeout monitoraggio raggiunto (${timeoutSec}s). Verifica manuale del file: $($res.FileName)"
}

if ($session) {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
}

Write-Output "[INFO] Sessione remota chiusa"
Write-Output "[SUCCESS] Processo terminato"
