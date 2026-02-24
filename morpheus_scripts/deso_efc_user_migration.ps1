# Autore: G.ABBATICCHIO
# Revisione: 2.2
# Data: 24/02/2026
# Code: deso_efc_user_migration
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Preparazione per la migrazione dell'utente, creazione del file dichiarativo
#              e monitoraggio stato su Morpheus in base ai file sul dispatcher.
#              La chiave SSH deve essere salvata nel Cypher EFC-TS_MIG_DANEA_SSH
#              come stringa Base64 (ottenibile con: base64 -i chiave | tr -d '\n')

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONI DI SUPPORTO
# ──────────────────────────────────────────────────────────────────────────────
function Write-RemoteLog {
    param([object[]]$RemoteOutput)
    foreach ($line in $RemoteOutput) {
        if ($line -is [string]) { Write-Output $line }
    }
}

function Update-MigrationStatus {
    param(
        [ValidateSet("running", "completed", "failed")]
        [string]$Status
    )
    try {
        $instanceId     = "<%=instance.id%>"
        $morpheusApiUrl = "<%=morpheus.applianceUrl%>/api/instances/$instanceId"
        $morpheusToken  = "<%=morpheus.apiAccessToken%>"
        $headers = @{
            "Authorization" = "Bearer $morpheusToken"
            "Content-Type"  = "application/json"
        }
        $body = @{
            instance = @{
                customOptions = @{
                    MigrationStatus = $Status
                }
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod -Uri $morpheusApiUrl -Method Put -Headers $headers -Body $body -ErrorAction Stop | Out-Null
        Write-Output "[INFO] MigrationStatus aggiornato → '$Status'"
    }
    catch {
        Write-Output "[WARNING] Impossibile aggiornare MigrationStatus in Morpheus: $($_.Exception.Message)"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# PARAMETRI MORPHEUS
# ──────────────────────────────────────────────────────────────────────────────
$migrationValue = "<%=customOptions.migrateData%>"
$fromUser       = "<%=customOptions.fromUser%>"
$fromServer     = "<%=customOptions.fromServer%>"
$toServer       = "<%=instance.containers[0].server.internalIp%>"
$instanceName   = "<%=instance.name%>"

# ──────────────────────────────────────────────────────────────────────────────
# CREDENZIALI DA CYPHER
# EFC-TS_MIG_DANEA-USR → username in chiaro
# EFC-TS_MIG_DANEA_SSH → chiave privata SSH codificata in Base64
# ──────────────────────────────────────────────────────────────────────────────
$migrationUserRaw   = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-USR",true)%>'
$migrationKeyBase64 = '<%=cypher.read("secret/EFC-TS_MIG_DANEA_SSH",true)%>'

# ──────────────────────────────────────────────────────────────────────────────
# PATH REMOTI SUL DISPATCHER
# ──────────────────────────────────────────────────────────────────────────────
$migrationServerIP = "10.182.1.11"
$remoteQueuePath   = "D:\tools\migration-tool-st\incoming"
$remoteDispatcher  = "D:\tools\migration-tool-st\dispatcher.ps1"  # non più usato, lasciato solo a riferimento

# ──────────────────────────────────────────────────────────────────────────────
# INIZIO SCRIPT
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] Istanza     : $instanceName"
Write-Output "[INFO] MigrateData : '$migrationValue'"

if ($migrationValue -ne "true") {
    Write-Output "[INFO] Migrazione NON richiesta - Skip"
    Write-Output "[SUCCESS] Nessuna migrazione da effettuare"
    exit 0
}

# ── Validazione credenziali ───────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($migrationUserRaw) -or [string]::IsNullOrWhiteSpace($migrationKeyBase64)) {
    Write-Output "[ERROR] Credenziali migrazione non disponibili dal Cypher (user o chiave vuoti)"
    Update-MigrationStatus -Status "failed"
    exit 1
}

# ── Validazione parametri obbligatori ────────────────────────────────────────
$validationErrors = @()
if ([string]::IsNullOrWhiteSpace($fromUser))   { $validationErrors += "fromUser mancante" }
if ([string]::IsNullOrWhiteSpace($fromServer)) { $validationErrors += "fromServer mancante" }
if ([string]::IsNullOrWhiteSpace($toServer))   { $validationErrors += "toServer non valorizzato" }

if ($validationErrors.Count -gt 0) {
    foreach ($e in $validationErrors) { Write-Output "[ERROR] $e" }
    Update-MigrationStatus -Status "failed"
    exit 1
}

Write-Output "[INFO] =========================================="
Write-Output "[INFO] MIGRAZIONE RICHIESTA - Avvio processo"
Write-Output "[INFO] - Utente origine  : $fromUser"
Write-Output "[INFO] - Server origine  : $fromServer"
Write-Output "[INFO] - Server destino  : $toServer"
Write-Output "[INFO] - Dispatcher      : $migrationServerIP"
Write-Output "[INFO] =========================================="

# ──────────────────────────────────────────────────────────────────────────────
# DECODIFICA CHIAVE SSH DA BASE64
# La chiave viene salvata nel Cypher come Base64 per preservare i newline.
# Per generarla: base64 -i ~/.ssh/ts_mig_danea | tr -d '\n'
# ──────────────────────────────────────────────────────────────────────────────
$tempKeyPath = $null

try {
    $tempKeyPath = "/tmp/ssh_key_$([System.Guid]::NewGuid().ToString('N'))"
    $keyRaw      = $migrationKeyBase64.Trim()

    # Prova a decodificare come Base64, se fallisce usa la stringa così com'è (PEM grezzo)
    try {
        $keyBytes = [System.Convert]::FromBase64String($keyRaw)
        $keyPem   = [System.Text.Encoding]::UTF8.GetString($keyBytes)
        Write-Output "[INFO] Chiave SSH letta dal Cypher come Base64"
        $keyFirstLine = $keyPem -split "`n" | Select-Object -First 1
        Write-Output "[DEBUG] Prima riga chiave: $keyFirstLine"
    } catch {
        $keyPem = $keyRaw
        Write-Output "[INFO] Chiave SSH letta dal Cypher come PEM grezzo"
    }

    Set-Content -Path $tempKeyPath -Value $keyPem -NoNewline -Encoding UTF8
    chmod 600 $tempKeyPath

    Write-Output "[INFO] Chiave SSH pronta"
} catch {
    Write-Output "[ERROR] Errore preparazione chiave SSH: $($_.Exception.Message)"
    Update-MigrationStatus -Status "failed"
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# CONNESSIONE SSH AL DISPATCHER
# ──────────────────────────────────────────────────────────────────────────────
$session = $null

Write-Output "[INFO] Connessione SSH al dispatcher ($migrationServerIP)..."
try {
    $session = New-PSSession `
        -HostName    $migrationServerIP `
        -Username    $migrationUserRaw `
        -KeyFilePath $tempKeyPath `
        -SSHTransport `
        -ErrorAction Stop

    Write-Output "[SUCCESS] Sessione SSH stabilita con $migrationServerIP"
} catch {
    Write-Output "[ERROR] Impossibile connettersi al dispatcher: $($_.Exception.Message)"
    Update-MigrationStatus -Status "failed"
    exit 1
} finally {
    # Chiave rimossa dal disco subito dopo l'apertura della sessione
    if ($tempKeyPath -and (Test-Path $tempKeyPath)) {
        Remove-Item $tempKeyPath -Force -ErrorAction SilentlyContinue
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# BLOCCO REMOTO: CREAZIONE FILE DI CODA
# ──────────────────────────────────────────────────────────────────────────────
$createQueueBlock = {
    param($fromUser, $fromServer, $toServer, $queuePath)

    $lockFile = Join-Path (Split-Path $queuePath -Parent) "queue.lock"

    if (-not (Test-Path $queuePath)) {
        try {
            New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
            Write-Output "[REMOTE][INFO] Directory di coda creata: $queuePath"
        } catch {
            Write-Output "[REMOTE][ERROR] Impossibile creare la directory di coda: $($_.Exception.Message)"
            throw
        }
    } else {
        Write-Output "[REMOTE][INFO] Directory di coda trovata: $queuePath"
    }

    # Acquisizione lock
    Write-Output "[REMOTE][INFO] Acquisizione lock..."
    $lockAcquired = $false
    $maxRetries   = 10
    $retryCount   = 0
    $lockHandle   = $null

    while (-not $lockAcquired -and $retryCount -lt $maxRetries) {
        try {
            $lockHandle   = [System.IO.File]::Open($lockFile, 'CreateNew', 'Write', 'None')
            $lockAcquired = $true
        } catch {
            $retryCount++
            Start-Sleep -Milliseconds 200
        }
    }

    if (-not $lockAcquired) {
        $msg = "Impossibile acquisire il lock dopo $maxRetries tentativi"
        Write-Output "[REMOTE][ERROR] $msg"
        throw $msg
    }

    try {
        # Calcolo prossima sequenza
        $existingFiles = Get-ChildItem -Path $queuePath -Filter "migra-*.txt" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'migra-(\d+)\.txt' } |
            ForEach-Object { [int]($Matches[1]) } |
            Sort-Object -Descending

        $nextSequence  = if ($existingFiles) { $existingFiles[0] + 1 } else { 1 }
        $queueFileName = "migra-{0:D6}.txt" -f $nextSequence
        $queueFilePath = Join-Path $queuePath $queueFileName
        $queueContent  = "${fromUser}|${fromServer}|${toServer}"

        Write-Output "[REMOTE][INFO] Sequenza: $nextSequence → $queueFileName"

        Set-Content -Path $queueFilePath -Value $queueContent -Force -ErrorAction Stop
        Write-Output "[REMOTE][INFO] Contenuto: $queueContent"

        if (-not (Test-Path $queueFilePath)) {
            throw "File '$queueFilePath' non trovato dopo la creazione"
        }

        $fileSize = (Get-Item $queueFilePath).Length
        Write-Output "[REMOTE][SUCCESS] File creato ($fileSize byte): $queueFilePath"

        return [PSCustomObject]@{
            FilePath = $queueFilePath
            FileName = $queueFileName
            Sequence = $nextSequence
            Status   = "Success"
        }
    } finally {
        if ($lockHandle) { $lockHandle.Close(); $lockHandle.Dispose() }
        if (Test-Path $lockFile) {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
            Write-Output "[REMOTE][INFO] Lock rilasciato"
        }
    }
}

Write-Output "[INFO] Creazione file di coda sul dispatcher..."

try {
    $rawOutput = Invoke-Command -Session $session -ScriptBlock $createQueueBlock `
                 -ArgumentList $fromUser, $fromServer, $toServer, $remoteQueuePath `
                 -ErrorAction Stop

    Write-RemoteLog -RemoteOutput ($rawOutput | Where-Object { $_ -is [string] })

    $result = $rawOutput | Where-Object { $_ -isnot [string] } | Select-Object -Last 1

    if (-not $result -or $result.Status -ne "Success") {
        Write-Output "[ERROR] Il blocco remoto non ha restituito un risultato valido"
        Update-MigrationStatus -Status "failed"
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        exit 1
    }

    Write-Output "[SUCCESS] File di migrazione accodato: $($result.FilePath)"

} catch {
    Write-Output "[ERROR] Errore durante la creazione del file di coda: $($_.Exception.Message)"
    Update-MigrationStatus -Status "failed"
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# AVVIO TASK SCHEDULATO DEL DISPATCHER
# ──────────────────────────────────────────────────────────────────────────────
$startDispatcherTaskBlock = {
    param(
        [string]$taskName,
        [string]$taskPath
    )

    Write-Output "[REMOTE][INFO] Avvio task schedulato '$taskName' (Path: '$taskPath')..."

    try {
        Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
        Write-Output "[REMOTE][SUCCESS] Task '$taskName' avviato correttamente"
    }
    catch {
        Write-Output "[REMOTE][ERROR] Impossibile avviare il task '$taskName': $($_.Exception.Message)"
        throw
    }
}

Write-Output "[INFO] Avvio task schedulato del dispatcher..."

try {
    $taskName = "dispatcher-st"
    $taskPath = "\"  # come da proprietà del task (Percorso: \)

    $taskOutput = Invoke-Command -Session $session -ScriptBlock $startDispatcherTaskBlock `
                   -ArgumentList $taskName, $taskPath -ErrorAction Stop

    Write-RemoteLog -RemoteOutput $taskOutput
}
catch {
    Write-Output "[ERROR] Errore durante l'avvio del task schedulato sul dispatcher: $($_.Exception.Message)"
    Update-MigrationStatus -Status "failed"
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    exit 1
}

$queueFileName     = $result.FileName
$queueFileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($queueFileName)

# File in coda → stato Pending (file .txt appena creato)
Update-MigrationStatus -Status "running"

# ──────────────────────────────────────────────────────────────────────────────
# MONITORAGGIO STATO MIGRAZIONE
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] =========================================="
Write-Output "[INFO] Monitoraggio migrazione in corso..."
Write-Output "[INFO] =========================================="

$monitoringMaxTime  = 5400   # 90 minuti
$monitoringInterval = 10     # polling ogni 10 secondi
$elapsedTime        = 0
$migrationCompleted = $false
$lastStatus         = ""

$monitorBlock = {
    param($baseName, $qPath)
    $doneFile = Join-Path $qPath "$baseName.done"
    $errFile  = Join-Path $qPath "$baseName.fail"
    $workFile = Join-Path $qPath "$baseName.txt.work"
    $txtFile  = Join-Path $qPath "$baseName.txt"

    if     (Test-Path $doneFile) {
        return [PSCustomObject]@{ Status = "completed";  FilePath = $doneFile; ErrorMessage = $null }
    } elseif (Test-Path $errFile) {
        $errMsg = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Status = "failed";     FilePath = $errFile;  ErrorMessage = $errMsg }
    } elseif (Test-Path $workFile) {
        return [PSCustomObject]@{ Status = "running"; FilePath = $workFile; ErrorMessage = $null }
    } elseif (Test-Path $txtFile) {
        return [PSCustomObject]@{ Status = "running";  FilePath = $txtFile;  ErrorMessage = $null }
    } else {
        return [PSCustomObject]@{ Status = "failed";    FilePath = $null;     ErrorMessage = $null }
    }
}

while ($elapsedTime -lt $monitoringMaxTime -and -not $migrationCompleted) {
    try {
        $fileStatus = Invoke-Command -Session $session -ScriptBlock $monitorBlock `
                      -ArgumentList $queueFileBaseName, $remoteQueuePath -ErrorAction Stop

        $currentStatus = $fileStatus.Status

        if ($currentStatus -ne $lastStatus) {
            Write-Output "[INFO] Cambio stato: '$lastStatus' → '$currentStatus' (${elapsedTime}s)"
            $lastStatus = $currentStatus
        } else {
            Write-Output "[INFO] Stato: $currentStatus | Tempo trascorso: ${elapsedTime}s"
        }

        switch ($currentStatus) {

            "Completed" {
                Write-Output "[SUCCESS] =========================================="
                Write-Output "[SUCCESS] Migrazione completata con successo!"
                Write-Output "[SUCCESS] =========================================="
                Update-MigrationStatus -Status "completed"
                $migrationCompleted = $true
            }

            "Failed" {
                $errorMsg = if ($fileStatus.ErrorMessage) { $fileStatus.ErrorMessage.Trim() } else { "Errore non specificato" }
                Write-Output "[ERROR] =========================================="
                Write-Output "[ERROR] Migrazione fallita!"
                Write-Output "[ERROR] Dettaglio: $errorMsg"
                Write-Output "[ERROR] =========================================="
                Update-MigrationStatus -Status "failed"
                $migrationCompleted = $true
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                exit 1
            }

            "Unknown" {
                Write-Output "[ERROR] File di migrazione non trovato sul dispatcher - traccia persa"
                Update-MigrationStatus -Status "failed"
                $migrationCompleted = $true
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                exit 1
            }

            "Scheduled" {
                # File .txt presente → in coda, quindi Pending
                Update-MigrationStatus -Status "running"
            }

            "Processing" {
                # File .work presente → in lavorazione, quindi sempre Pending lato Morpheus
                Update-MigrationStatus -Status "running"
            }

            default {
                # Nessuna azione aggiuntiva
            }
        }

        if (-not $migrationCompleted) {
            Start-Sleep -Seconds $monitoringInterval
            $elapsedTime += $monitoringInterval
        }

    } catch {
        Write-Output "[WARNING] Errore nel polling: $($_.Exception.Message)"
        Start-Sleep -Seconds $monitoringInterval
        $elapsedTime += $monitoringInterval
    }
}

# ── Timeout ───────────────────────────────────────────────────────────────────
if (-not $migrationCompleted) {
    Write-Output "[WARNING] =========================================="
    Write-Output "[WARNING] Timeout raggiunto dopo $monitoringMaxTime secondi"
    Write-Output "[WARNING] Verifica manuale richiesta: $queueFileName"
    Write-Output "[WARNING] =========================================="
    Update-MigrationStatus -Status "failed"
}

# ── Cleanup sessione ──────────────────────────────────────────────────────────
if ($session) {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
}

Write-Output "[INFO] Sessione chiusa"
Write-Output "[SUCCESS] Processo di migrazione terminato"
