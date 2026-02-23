# Autore: G.ABBATICCHIO
# Revisione: 1.8
# Data: 23/02/2026
# Code: deso_efc_user_migration
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource (LOCAL SIMULATION)
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Preparazione per la migrazione dell'utente, creazione del file dichiarativo.
#              TEST_MODE = $true  → tutto locale, nessuna connessione remota
#              TEST_MODE = $false → PSSession SSH reale verso il dispatcher

# ──────────────────────────────────────────────────────────────────────────────
$TEST_MODE = $true
# ──────────────────────────────────────────────────────────────────────────────

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
        [ValidateSet("Pending","Completed","Failed")]
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
$migrationValue = "<%=customOptions.MigrateData%>"
$fromUser       = "<%=customOptions.fromUser%>"
$fromServer     = "<%=customOptions.fromServer%>"
$toServer       = "<%=instance.containers[0].server.internalIp%>"
$instanceName   = "<%=instance.name%>"

# ──────────────────────────────────────────────────────────────────────────────
# CREDENZIALI
# ──────────────────────────────────────────────────────────────────────────────
$migrationUserRaw = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-USR",true)%>'
$migrationPassRaw = '<%=cypher.read("secret/EFC-TS_MIG_DANEA_SSH",true)%>'

# Valori di fallback solo in TEST_MODE
if ($TEST_MODE) {
    if ([string]::IsNullOrWhiteSpace($migrationUserRaw)) { $migrationUserRaw = "ts_mig_danea@ad.easyfattincloud.it" }
    if ([string]::IsNullOrWhiteSpace($migrationPassRaw)) { $migrationPassRaw = "testpassword" }
    if ([string]::IsNullOrWhiteSpace($fromUser))         { $fromUser         = "utente.test" }
    if ([string]::IsNullOrWhiteSpace($fromServer))       { $fromServer       = "server-origine-test" }
    if ([string]::IsNullOrWhiteSpace($toServer))         { $toServer         = "server-destino-test" }
    if ([string]::IsNullOrWhiteSpace($migrationValue))   { $migrationValue   = "true" }
}

# ──────────────────────────────────────────────────────────────────────────────
# PATH
# ──────────────────────────────────────────────────────────────────────────────
$migrationServerIP  = "10.182.1.11"
$remoteQueuePath    = "D:\tools\migration\incoming"   # usato in produzione
$remoteDispatcher   = "D:\tools\migration\dispatcher.ps1"

$tempRoot           = [System.IO.Path]::GetTempPath().TrimEnd('\','/')
$migrationBasePath  = Join-Path $tempRoot "migration_test"
$localQueuePath     = Join-Path $migrationBasePath "incoming"

# In TEST_MODE il queuePath effettivo è locale, in produzione remoto
$effectiveQueuePath = if ($TEST_MODE) { $localQueuePath } else { $remoteQueuePath }

# ──────────────────────────────────────────────────────────────────────────────
# INIZIO SCRIPT
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] Istanza      : $instanceName"
Write-Output "[INFO] MigrateData  : '$migrationValue'"

if ($migrationValue -ne "true") {
    Write-Output "[INFO] Migrazione NON richiesta - Skip"
    Write-Output "[SUCCESS] Nessuna migrazione da effettuare"
    exit 0
}

# ── Validazione credenziali ───────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($migrationUserRaw) -or [string]::IsNullOrWhiteSpace($migrationPassRaw)) {
    Write-Output "[ERROR] Credenziali migrazione non disponibili (user o password vuoti)"
    Update-MigrationStatus -Status "Failed"
    exit 1
}

try {
    $migrationPass = ConvertTo-SecureString $migrationPassRaw -AsPlainText -Force
    $migrationCred = New-Object System.Management.Automation.PSCredential($migrationUserRaw, $migrationPass)
} catch {
    Write-Output "[ERROR] Errore creazione PSCredential: $($_.Exception.Message)"
    Update-MigrationStatus -Status "Failed"
    exit 1
}

# ── Validazione parametri obbligatori ────────────────────────────────────────
$validationErrors = @()
if ([string]::IsNullOrWhiteSpace($fromUser))  { $validationErrors += "fromUser mancante" }
if ([string]::IsNullOrWhiteSpace($fromServer)){ $validationErrors += "fromServer mancante" }
if ([string]::IsNullOrWhiteSpace($toServer))  { $validationErrors += "toServer non valorizzato" }

if ($validationErrors.Count -gt 0) {
    foreach ($e in $validationErrors) { Write-Output "[ERROR] $e" }
    Update-MigrationStatus -Status "Failed"
    exit 1
}

Write-Output "[INFO] =========================================="
Write-Output "[INFO] MIGRAZIONE RICHIESTA - Avvio processo"
Write-Output "[INFO] - Utente origine   : $fromUser"
Write-Output "[INFO] - Server origine   : $fromServer"
Write-Output "[INFO] - Server destino   : $toServer"
Write-Output "[INFO] - Dispatcher       : $migrationServerIP$(if ($TEST_MODE) { ' (SIMULATO)' })"
Write-Output "[INFO] =========================================="

# ──────────────────────────────────────────────────────────────────────────────
# CONNESSIONE AL DISPATCHER (solo in produzione)
# ──────────────────────────────────────────────────────────────────────────────
$session     = $null
$tempKeyPath = $null

if (-not $TEST_MODE) {
    Write-Output "[INFO] Connessione SSH al dispatcher ($migrationServerIP)..."
    try {
        $tempKeyPath = Join-Path $tempRoot "temp_ssh_key_$([System.Guid]::NewGuid().ToString('N'))"
        Set-Content -Path $tempKeyPath -Value $migrationPassRaw -NoNewline -Encoding ASCII

        $session = New-PSSession `
            -HostName    $migrationServerIP `
            -Username    $migrationUserRaw `
            -KeyFilePath $tempKeyPath `
            -SSHTransport `
            -ErrorAction Stop

        Write-Output "[SUCCESS] Sessione SSH stabilita con $migrationServerIP"
    } catch {
        Write-Output "[ERROR] Impossibile connettersi al dispatcher: $($_.Exception.Message)"
        Update-MigrationStatus -Status "Failed"
        exit 1
    } finally {
        # La chiave viene rimossa subito dopo l'apertura della sessione
        if ($tempKeyPath -and (Test-Path $tempKeyPath)) {
            Remove-Item $tempKeyPath -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Output "[TEST] Connessione SSH simulata - nessuna PSSession aperta"
}

# ──────────────────────────────────────────────────────────────────────────────
# BLOCCO: CREAZIONE FILE DI CODA
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
        $existingFiles = Get-ChildItem -Path $queuePath -Filter "migra_*.txt" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'migra_(\d+)\.txt' } |
            ForEach-Object { [int]($Matches[1]) } |
            Sort-Object -Descending

        $nextSequence  = if ($existingFiles) { $existingFiles[0] + 1 } else { 1 }
        $queueFileName = "migra_{0:D6}.txt" -f $nextSequence
        $queueFilePath = Join-Path $queuePath $queueFileName
        $queueContent  = "${fromUser}|${fromServer}|${toServer}"

        Write-Output "[REMOTE][INFO] Sequenza: $nextSequence → $queueFileName"

        Set-Content -Path $queueFilePath -Value $queueContent -Force -ErrorAction Stop
        Write-Output "[REMOTE][INFO] Contenuto scritto: $queueContent"

        if (-not (Test-Path $queueFilePath)) {
            throw "Il file '$queueFilePath' non trovato dopo la creazione"
        }

        $fileSize = (Get-Item $queueFilePath).Length
        Write-Output "[REMOTE][SUCCESS] File creato ($fileSize byte): $queueFilePath"

        # Restituzione tramite oggetto PSCustomObject (sopravvive alla deserializzazione remota)
        return [PSCustomObject]@{
            FilePath  = $queueFilePath
            FileName  = $queueFileName
            Sequence  = $nextSequence
            Status    = "Success"
        }
    } finally {
        if ($lockHandle) { $lockHandle.Close(); $lockHandle.Dispose() }
        if (Test-Path $lockFile) {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
            Write-Output "[REMOTE][INFO] Lock rilasciato"
        }
    }
}

# ── Esecuzione creazione file ─────────────────────────────────────────────────
Write-Output "[INFO] Creazione file di coda in corso..."

try {
    if ($TEST_MODE) {
        $rawOutput = & $createQueueBlock $fromUser $fromServer $toServer $effectiveQueuePath
    } else {
        $rawOutput = Invoke-Command -Session $session -ScriptBlock $createQueueBlock `
                     -ArgumentList $fromUser, $fromServer, $toServer, $effectiveQueuePath `
                     -ErrorAction Stop
    }

    Write-RemoteLog -RemoteOutput ($rawOutput | Where-Object { $_ -is [string] })

    # PSCustomObject sopravvive alla deserializzazione (a differenza di [hashtable])
    $result = $rawOutput | Where-Object { $_ -isnot [string] } | Select-Object -Last 1

    if (-not $result -or $result.Status -ne "Success") {
        Write-Output "[ERROR] Il blocco remoto non ha restituito un risultato valido"
        Update-MigrationStatus -Status "Failed"
        if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        exit 1
    }

    Write-Output "[SUCCESS] File di migrazione accodato: $($result.FilePath)"

} catch {
    Write-Output "[ERROR] Errore durante la creazione del file di coda: $($_.Exception.Message)"
    Update-MigrationStatus -Status "Failed"
    if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    exit 1
}

$queueFileName     = $result.FileName
$queueFileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($queueFileName)

# Imposta subito lo stato Pending — il file è in coda
Update-MigrationStatus -Status "Pending"

# ──────────────────────────────────────────────────────────────────────────────
# AVVIO DISPATCHER
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] Avvio dispatcher..."

if ($TEST_MODE) {
    # Job background che simula: .txt → .work (dopo 2s) → .done (dopo altri 2s)
    $null = Start-Job -ScriptBlock {
        param($qPath, $baseName, $fileName)
        $txtFile  = Join-Path $qPath $fileName
        $workFile = Join-Path $qPath "$baseName.work"
        $doneFile = Join-Path $qPath "$baseName.done"

        Start-Sleep -Seconds 2
        if (Test-Path $txtFile)  { Rename-Item -Path $txtFile  -NewName "$baseName.work" }
        Start-Sleep -Seconds 2
        if (Test-Path $workFile) { Rename-Item -Path $workFile -NewName "$baseName.done" }
    } -ArgumentList $effectiveQueuePath, $queueFileBaseName, $queueFileName

    Write-Output "[TEST] Dispatcher simulato avviato (completamento atteso in ~4 secondi)"

} else {
    $dispatcherBlock = {
        param($dispatcherScript)
        if (-not (Test-Path $dispatcherScript)) {
            throw "Script dispatcher non trovato: $dispatcherScript"
        }
        Write-Output "[REMOTE][INFO] Avvio: $dispatcherScript"
        try {
            & $dispatcherScript
            Write-Output "[REMOTE][SUCCESS] Dispatcher eseguito"
        } catch {
            throw "Errore dispatcher: $($_.Exception.Message)"
        }
        return [PSCustomObject]@{ Status = "Success" }
    }

    try {
        $dispRaw = Invoke-Command -Session $session -ScriptBlock $dispatcherBlock `
                   -ArgumentList $remoteDispatcher -ErrorAction Stop

        Write-RemoteLog -RemoteOutput ($dispRaw | Where-Object { $_ -is [string] })

        $dispResult = $dispRaw | Where-Object { $_ -isnot [string] } | Select-Object -Last 1
        if ($dispResult -and $dispResult.Status -eq "Success") {
            Write-Output "[SUCCESS] Dispatcher avviato correttamente"
        } else {
            Write-Output "[WARNING] Dispatcher avviato ma senza conferma - la migrazione rimarrà in coda"
        }
    } catch {
        Write-Output "[WARNING] Errore avvio dispatcher: $($_.Exception.Message)"
        Write-Output "[WARNING] La migrazione resterà in coda fino al prossimo avvio del dispatcher"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# MONITORAGGIO
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] =========================================="
Write-Output "[INFO] Monitoraggio migrazione in corso..."
Write-Output "[INFO] =========================================="

$monitoringMaxTime  = if ($TEST_MODE) { 60    } else { 5400 }  # 1 min test / 90 min prod
$monitoringInterval = if ($TEST_MODE) { 3     } else { 10   }  # 3s test / 10s prod
$elapsedTime        = 0
$migrationCompleted = $false
$lastStatus         = ""

$monitorBlock = {
    param($baseName, $qPath)
    $doneFile = Join-Path $qPath "$baseName.done"
    $errFile  = Join-Path $qPath "$baseName.err"
    $workFile = Join-Path $qPath "$baseName.work"
    $txtFile  = Join-Path $qPath "$baseName.txt"

    if (Test-Path $doneFile) {
        return [PSCustomObject]@{ Status = "Completed"; FilePath = $doneFile; ErrorMessage = $null }
    } elseif (Test-Path $errFile) {
        $errMsg = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Status = "Failed";    FilePath = $errFile;  ErrorMessage = $errMsg }
    } elseif (Test-Path $workFile) {
        return [PSCustomObject]@{ Status = "Processing"; FilePath = $workFile; ErrorMessage = $null }
    } elseif (Test-Path $txtFile) {
        return [PSCustomObject]@{ Status = "Scheduled";  FilePath = $txtFile;  ErrorMessage = $null }
    } else {
        return [PSCustomObject]@{ Status = "Unknown";    FilePath = $null;     ErrorMessage = $null }
    }
}

while ($elapsedTime -lt $monitoringMaxTime -and -not $migrationCompleted) {
    try {
        $fileStatus = if ($TEST_MODE) {
            & $monitorBlock $queueFileBaseName $effectiveQueuePath
        } else {
            Invoke-Command -Session $session -ScriptBlock $monitorBlock `
                           -ArgumentList $queueFileBaseName, $remoteQueuePath -ErrorAction Stop
        }

        $currentStatus = $fileStatus.Status

        if ($currentStatus -ne $lastStatus) {
            Write-Output "[INFO] Cambio stato: '$lastStatus' → '$currentStatus' (${elapsedTime}s)"
            $lastStatus = $currentStatus
        } else {
            Write-Output "[INFO] Stato: $currentStatus | Tempo: ${elapsedTime}s"
        }

        switch ($currentStatus) {

            "Completed" {
                Write-Output "[SUCCESS] =========================================="
                Write-Output "[SUCCESS] Migrazione completata con successo!"
                Write-Output "[SUCCESS] =========================================="
                Update-MigrationStatus -Status "Completed"
                $migrationCompleted = $true
            }

            "Failed" {
                $errorMsg = if ($fileStatus.ErrorMessage) { $fileStatus.ErrorMessage.Trim() } else { "Errore non specificato" }
                Write-Output "[ERROR] =========================================="
                Write-Output "[ERROR] Migrazione fallita!"
                Write-Output "[ERROR] Dettaglio: $errorMsg"
                Write-Output "[ERROR] =========================================="
                Update-MigrationStatus -Status "Failed"
                $migrationCompleted = $true
                if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
                exit 1
            }

            "Unknown" {
                Write-Output "[ERROR] File di migrazione non trovato sul dispatcher - traccia persa"
                Update-MigrationStatus -Status "Failed"
                $migrationCompleted = $true
                if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
                exit 1
            }

            default {
                # Scheduled / Processing: attesa normale
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
    Write-Output "[WARNING] Timeout raggiunto dopo $monitoringMaxTime secondi"
    Write-Output "[WARNING] Verifica manuale richiesta: $queueFileName"
    Update-MigrationStatus -Status "Failed"
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
if ($TEST_MODE) {
    Get-Job | Where-Object { $_.State -in @('Completed','Running') } |
        Stop-Job -PassThru | Remove-Job -ErrorAction SilentlyContinue
    Write-Output "[TEST] Cartella locale: $migrationBasePath"
    Write-Output "[TEST] Per pulire: Remove-Item '$migrationBasePath' -Recurse -Force"
}

if ($session) {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
}

Write-Output "[INFO] Sessione chiusa"
Write-Output "[SUCCESS] Processo di migrazione terminato"
