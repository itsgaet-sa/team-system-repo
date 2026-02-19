# Autore: G.ABBATICCHIO
# Revisione: 1.7-TEST
# Data: 17/02/2026
# Code: deso_efc_user_migration
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource (LOCAL SIMULATION)
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: [TEST] Preparazione per la migrazione dell'utente, creazione del file dichiarativo.
#              Questa versione gira interamente in locale senza dipendenze da Morpheus o server remoti.

# ──────────────────────────────────────────────────────────────────────────────
# MODALITÀ TEST - tutte le connessioni remote sono simulate localmente
# ──────────────────────────────────────────────────────────────────────────────
$TEST_MODE = $false


# Impostazioni runtime
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

# Aggiorna lo stato della migrazione tramite API Morpheus (DISABILITATO PER ORA)
function Update-MigrationStatus {
    param([string]$Status)
    # TODO: riabilitare quando serve aggiornare customOptions.MigrationStatus
    # try {
    #     $instanceId    = "<%=instance.id%>"
    #     $morpheusApiUrl = "<%=morpheus.applianceUrl%>/api/instances/$instanceId"
    #     $morpheusToken  = "<%=morpheus.apiAccessToken%>"
    #     $headers = @{
    #         "Authorization" = "Bearer $morpheusToken"
    #         "Content-Type"  = "application/json"
    #     }
    #     $body = @{
    #         instance = @{
    #             customOptions = @{
    #                 MigrationStatus = $Status
    #             }
    #         }
    #     } | ConvertTo-Json -Depth 10
    #     Invoke-RestMethod -Uri $morpheusApiUrl -Method Put -Headers $headers -Body $body -ErrorAction Stop | Out-Null
    #     Write-Output "[INFO] Stato migrazione aggiornato in Morpheus: '$Status'"
    # }
    # catch {
    #     Write-Output "[WARNING] Impossibile aggiornare lo stato in Morpheus: $($_.Exception.Message)"
    # }
}

# ──────────────────────────────────────────────────────────────────────────────
# INIZIO SCRIPT
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] Controllo richiesta migrazione utente..."

# ── Parametri (FAKE) ──────────────────────────────────────────────────────────
$migrationValue  = "<%=customOptions.MigrateData%>"
$fromUser        = "<%=customOptions.fromUser%>"
$fromServer      = "<%=customOptions.fromServer%>"
$toServer        = "<%=instance.containers[0].server.internalIp%>"
$instanceName    = "<%=instance.name%>"
$instanceId      = "<%=instance.id%>"

# ── Credenziali (FAKE - in produzione vengono dal Cypher di Morpheus) ─────────
# PRODUZIONE:
$migrationUserRaw = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-USR",true)%>'
$migrationPassRaw = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-PWD",true)%>'
#$migrationUserRaw = "testuser"
#$migrationPassRaw = "testpassword"

# ── Path locali per simulazione (sostituiscono D:\tools\migration sul dispatcher) ──
$tempRoot = [System.IO.Path]::GetTempPath()
$migrationBasePath = Join-Path $tempRoot "migration_test"
$queuePath         = Join-Path $migrationBasePath "incoming"

# ── Server dispatcher (non usato in test mode) ────────────────────────────────
$migrationServerIP = "10.182.1.11"   # REALE - non contattato in TEST_MODE

Test-NetConnection 10.182.1.11 -Port 5985
Test-WsMan 10.182.1.11




# ──────────────────────────────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($migrationUserRaw) -or [string]::IsNullOrWhiteSpace($migrationPassRaw)) {
    Write-Output "[ERROR] Credenziali migrazione non recuperate dal Cypher (user o password vuoti)"
    # Update-MigrationStatus -Status "Failed: credenziali migrazione non disponibili"
    exit 1
}

try {
    $migrationPass = ConvertTo-SecureString $migrationPassRaw -AsPlainText -Force
    $migrationCred = New-Object System.Management.Automation.PSCredential($migrationUserRaw, $migrationPass)
} catch {
    Write-Output "[ERROR] Errore creazione PSCredential: $($_.Exception.Message)"
    # Update-MigrationStatus -Status "Failed: errore creazione PSCredential - $($_.Exception.Message)"
    exit 1
}

Write-Output "[INFO] Instance: $instanceName"
Write-Output "[INFO] Stato migrazione richiesta: '$migrationValue'"

if ($migrationValue -ne "true") {
    Write-Output "[INFO] Migrazione dati NON richiesta - Skip"
    Write-Output "[SUCCESS] Nessuna migrazione da effettuare"
    exit 0
}

Write-Output "[INFO] =========================================="
Write-Output "[INFO] MIGRAZIONE DATI RICHIESTA - Avvio processo"
Write-Output "[INFO] =========================================="

# Validazione parametri obbligatori
if ([string]::IsNullOrWhiteSpace($fromUser)) {
    Write-Output "[ERROR] Parametro 'fromUser' mancante o vuoto - impossibile procedere"
    # Update-MigrationStatus -Status "Failed: fromUser mancante"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($fromServer)) {
    Write-Output "[ERROR] Parametro 'fromServer' mancante o vuoto - impossibile procedere"
    # Update-MigrationStatus -Status "Failed: fromServer mancante"
    exit 1
}
if ([string]::IsNullOrWhiteSpace($toServer)) {
    Write-Output "[ERROR] Parametro 'toServer' non valorizzato"
    # Update-MigrationStatus -Status "Failed: toServer non valorizzato"
    exit 1
}

Write-Output "[INFO] Parametri migrazione:"
Write-Output "[INFO] - Utente origine  : $fromUser"
Write-Output "[INFO] - Server origine  : $fromServer"
Write-Output "[INFO] - Server destino  : $toServer"
Write-Output "[INFO] - Server dispatcher: $migrationServerIP $(if ($TEST_MODE) { '(SIMULATO LOCALMENTE)' })"

# ──────────────────────────────────────────────────────────────────────────────
# CONNESSIONE AL SERVER DI MIGRAZIONE
# In TEST_MODE viene saltata la PSSession e tutto gira in locale
# ──────────────────────────────────────────────────────────────────────────────
if ($TEST_MODE) {
    Write-Output "[TEST]  Simulazione connessione al dispatcher ($migrationServerIP) - SKIP PSSession"
    Write-Output "[SUCCESS] Sessione remota stabilita con $migrationServerIP (SIMULATA)"
} else {
    Write-Output "[INFO] Connessione al server dispatcher ($migrationServerIP) in corso..."
    $session = $null
    try {
        $sessionOption = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 60000
        $session = New-PSSession -ComputerName $migrationServerIP -Credential $migrationCred -SessionOption $sessionOption -ErrorAction Stop
        Write-Output "[SUCCESS] Sessione remota stabilita con $migrationServerIP"
    } catch {
        Write-Output "[ERROR] Impossibile connettersi al server dispatcher ($migrationServerIP)"
        Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
        # Update-MigrationStatus -Status "Failed: connessione dispatcher - $($_.Exception.Message)"
        if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        exit 1
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# CREAZIONE FILE DI CODA
# In TEST_MODE: eseguito direttamente in locale
# In PRODUZIONE: Invoke-Command -Session $session
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] Creazione richiesta di migrazione sul dispatcher..."

$result = $null

$createQueueBlock = {
    param($fromUser, $fromServer, $toServer, $migrationBasePath, $queuePath)

    $lockFile = Join-Path $migrationBasePath "queue.lock"

    if (-not (Test-Path $queuePath)) {
        try {
            New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
            Write-Output "[REMOTE][INFO] Directory di coda creata: $queuePath"
        } catch {
            Write-Output "[REMOTE][ERROR] Impossibile creare la directory di coda: $($_.Exception.Message)"
            throw
        }
    } else {
        Write-Output "[REMOTE][INFO] Directory di coda già esistente: $queuePath"
    }

    Write-Output "[REMOTE][INFO] Acquisizione lock sulla coda..."
    $lockAcquired = $false
    $maxRetries   = 10
    $retryCount   = 0
    $lockHandle   = $null

    while (-not $lockAcquired -and $retryCount -lt $maxRetries) {
        try {
            $lockHandle   = [System.IO.File]::Open($lockFile, 'CreateNew', 'Write', 'None')
            $lockAcquired = $true
            Write-Output "[REMOTE][INFO] Lock acquisito al tentativo $($retryCount + 1)"
        } catch {
            $retryCount++
            Start-Sleep -Milliseconds 100
        }
    }

    if (-not $lockAcquired) {
        $msg = "Impossibile acquisire il lock dopo $maxRetries tentativi"
        Write-Output "[REMOTE][ERROR] $msg"
        throw $msg
    }

    try {
        $existingFiles = Get-ChildItem -Path $queuePath -Filter "migra_*.txt" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'migra_(\d+)\.txt' } |
            ForEach-Object { [PSCustomObject]@{ File = $_; Sequence = [int]($Matches[1]) } } |
            Sort-Object Sequence -Descending

        $nextSequence = if ($existingFiles -and $existingFiles.Count -gt 0) {
            $existingFiles[0].Sequence + 1
        } else { 1 }

        $queueFileName  = "migra_{0:D6}.txt" -f $nextSequence
        $queueFilePath  = Join-Path $queuePath $queueFileName
        $queueContent   = "${fromUser}|${fromServer}|${toServer}"

        Write-Output "[REMOTE][INFO] Prossima sequenza: $nextSequence → file: $queueFileName"

        try {
            Set-Content -Path $queueFilePath -Value $queueContent -Force -ErrorAction Stop
            Write-Output "[REMOTE][SUCCESS] File di coda creato: $queueFilePath"
            Write-Output "[REMOTE][INFO] Contenuto: $queueContent"
        } catch {
            Write-Output "[REMOTE][ERROR] Impossibile creare il file di coda '$queueFilePath': $($_.Exception.Message)"
            throw
        }

        if (Test-Path $queueFilePath) {
            $fileSize = (Get-Item $queueFilePath).Length
            Write-Output "[REMOTE][SUCCESS] Verifica file OK - dimensione: $fileSize byte"
        } else {
            $msg = "Il file '$queueFilePath' non risulta presente dopo la creazione"
            Write-Output "[REMOTE][ERROR] $msg"
            throw $msg
        }

        return @{
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

try {
    if ($TEST_MODE) {
        $rawOutput = & $createQueueBlock $fromUser $fromServer $toServer $migrationBasePath $queuePath
    } else {
        $rawOutput = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock $createQueueBlock `
                     -ArgumentList $fromUser, $fromServer, $toServer, $migrationBasePath, $queuePath
    }

    $remoteMessages = $rawOutput | Where-Object { $_ -is [string] }
    $result         = $rawOutput | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1

    Write-RemoteLog -RemoteOutput $remoteMessages

    if (-not $result -or $result.Status -ne "Success") {
        Write-Output "[ERROR] Il blocco remoto non ha restituito un risultato valido"
        # Update-MigrationStatus -Status "Failed: risultato creazione file non valido"
        if (-not $TEST_MODE -and $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        exit 1
    }

    Write-Output "[SUCCESS] File di migrazione accodato correttamente"
    Write-Output "[INFO] Percorso   : $($result.FilePath)"
    Write-Output "[INFO] N° sequenza: $($result.Sequence)"
    # Update-MigrationStatus -Status "Pending"

} catch {
    Write-Output "[ERROR] Errore durante l'accodamento della migrazione"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    # Update-MigrationStatus -Status "Failed: accodamento - $($_.Exception.Message)"
    if (-not $TEST_MODE -and $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    exit 1
}

$queueFileName    = $result.FileName
$queueFileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($queueFileName)

# ──────────────────────────────────────────────────────────────────────────────
# DISPATCHER SIMULATO
# In TEST_MODE: un job in background che dopo 2s rinomina .txt → .work → .done
# In PRODUZIONE: chiama dispatcher.ps1 sul server remoto
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] Avvio dispatcher per elaborazione migrazione..."

if ($TEST_MODE) {
    Write-Output "[TEST]  Avvio dispatcher simulato (job background - completerà in ~4 secondi)..."

    $jobQueuePath      = $queuePath
    $jobBaseName       = $queueFileBaseName
    $jobQueueFileName  = $queueFileName

    $null = Start-Job -ScriptBlock {
        param($qPath, $baseName, $fileName)
        Start-Sleep -Seconds 2

        $txtFile  = Join-Path $qPath "$fileName"
        $workFile = Join-Path $qPath "$baseName.work"
        $doneFile = Join-Path $qPath "$baseName.done"

        # Simula fase "in lavorazione"
        if (Test-Path $txtFile) { Rename-Item $txtFile $workFile }
        Start-Sleep -Seconds 2

        # Simula completamento
        if (Test-Path $workFile) { Rename-Item $workFile $doneFile }
    } -ArgumentList $jobQueuePath, $jobBaseName, $jobQueueFileName

    Write-Output "[SUCCESS] Dispatcher simulato avviato"
} else {
    $dispatcherBlock = {
        $dispatcherScript = "D:\tools\migration\dispatcher.ps1"
        if (-not (Test-Path $dispatcherScript)) {
            $msg = "Script dispatcher non trovato: $dispatcherScript"
            Write-Output "[REMOTE][ERROR] $msg"
            throw $msg
        }
        Write-Output "[REMOTE][INFO] Avvio dispatcher: $dispatcherScript"
        try {
            & $dispatcherScript
            Write-Output "[REMOTE][SUCCESS] Dispatcher eseguito correttamente"
        } catch {
            Write-Output "[REMOTE][ERROR] Errore durante l'esecuzione del dispatcher: $($_.Exception.Message)"
            throw
        }
        return @{ Status = "Success" }
    }

    try {
        $dispatcherRaw     = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock $dispatcherBlock
        $dispatcherMessages = $dispatcherRaw | Where-Object { $_ -is [string] }
        $dispatcherResult  = $dispatcherRaw | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
        Write-RemoteLog -RemoteOutput $dispatcherMessages

        if ($dispatcherResult -and $dispatcherResult.Status -eq "Success") {
            Write-Output "[SUCCESS] Dispatcher avviato con successo"
        } else {
            Write-Output "[WARNING] Il dispatcher non ha confermato il completamento - la migrazione rimarrà in coda"
        }
    } catch {
        Write-Output "[WARNING] Errore durante l'avvio del dispatcher: $($_.Exception.Message)"
        Write-Output "[WARNING] La migrazione rimarrà in coda fino al prossimo avvio del dispatcher"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# MONITORAGGIO STATO MIGRAZIONE
# ──────────────────────────────────────────────────────────────────────────────
Write-Output "[INFO] =========================================="
Write-Output "[INFO] Avvio monitoraggio stato migrazione..."
Write-Output "[INFO] =========================================="

$monitoringMaxTime = if ($TEST_MODE) { 60 } else { 5400 }   # 1 min in test, 90 min in prod
$monitoringInterval = 3    # ogni 3 secondi in test (10 in prod)
$elapsedTime        = 0
$migrationCompleted = $false
$lastReportedStatus = ""

$monitorBlock = {
    param($baseName, $qPath)
    $doneFile = Join-Path $qPath "$baseName.done"
    $errFile  = Join-Path $qPath "$baseName.err"
    $txtFile  = Join-Path $qPath "$baseName.txt"
    $workFile = Join-Path $qPath "$baseName.work"

    if     (Test-Path $doneFile) { return @{ Status = "Completed";  FilePath = $doneFile } }
    elseif (Test-Path $errFile)  {
        $errorContent = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
        return @{ Status = "Failed"; FilePath = $errFile; ErrorMessage = $errorContent }
    }
    elseif (Test-Path $workFile) { return @{ Status = "Processing"; FilePath = $workFile } }
    elseif (Test-Path $txtFile)  { return @{ Status = "Scheduled";  FilePath = $txtFile  } }
    else                          { return @{ Status = "Unknown";    FilePath = $null      } }
}

while ($elapsedTime -lt $monitoringMaxTime -and -not $migrationCompleted) {
    try {
        $fileStatus = if ($TEST_MODE) {
            & $monitorBlock $queueFileBaseName $queuePath
        } else {
            Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock $monitorBlock `
                           -ArgumentList $queueFileBaseName, "D:\tools\migration\incoming"
        }

        $currentStatus = $fileStatus.Status

        if ($currentStatus -ne $lastReportedStatus) {
            Write-Output "[INFO] >>> Cambio stato: '$lastReportedStatus' → '$currentStatus' (t=${elapsedTime}s)"
            $lastReportedStatus = $currentStatus
        } else {
            Write-Output "[INFO] Stato corrente: $currentStatus - Tempo trascorso: ${elapsedTime}s"
        }

        switch ($currentStatus) {
            "Completed" {
                Write-Output "[SUCCESS] =========================================="
                Write-Output "[SUCCESS] Migrazione completata con successo!"
                Write-Output "[SUCCESS] File risultato: $($fileStatus.FilePath)"
                Write-Output "[SUCCESS] =========================================="
                # Update-MigrationStatus -Status "Completed"
                $migrationCompleted = $true
            }
            "Failed" {
                $errorMsg = if ($fileStatus.ErrorMessage) { $fileStatus.ErrorMessage.Trim() } else { "Errore non specificato" }
                Write-Output "[ERROR] =========================================="
                Write-Output "[ERROR] Migrazione fallita!"
                Write-Output "[ERROR] File errore  : $($fileStatus.FilePath)"
                Write-Output "[ERROR] Dettaglio    : $errorMsg"
                Write-Output "[ERROR] =========================================="
                # Update-MigrationStatus -Status "Failed: $errorMsg"
                $migrationCompleted = $true
                if (-not $TEST_MODE -and $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
                exit 1
            }
            "Unknown" {
                Write-Output "[ERROR] File di migrazione non trovato sul dispatcher - il processo potrebbe aver perso traccia del file"
                # Update-MigrationStatus -Status "Failed: file di migrazione non trovato"
                $migrationCompleted = $true
                if (-not $TEST_MODE -and $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
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
        Write-Output "[ERROR] Errore durante il polling di monitoraggio: $($_.Exception.Message)"
        Start-Sleep -Seconds $monitoringInterval
        $elapsedTime += $monitoringInterval
    }
}

if (-not $migrationCompleted) {
    Write-Output "[WARNING] =========================================="
    Write-Output "[WARNING] Timeout monitoraggio raggiunto dopo $monitoringMaxTime secondi"
    Write-Output "[WARNING] La migrazione potrebbe essere ancora in corso"
    Write-Output "[WARNING] Verifica manuale richiesta sul file: $queueFileName"
    Write-Output "[WARNING] =========================================="
    # Update-MigrationStatus -Status "Failed: timeout - verifica manuale richiesta"
}

# Cleanup job di simulazione
if ($TEST_MODE) {
    Get-Job | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Running' } |
        Stop-Job -PassThru | Remove-Job -ErrorAction SilentlyContinue

    Write-Output "[TEST]  Cartella di test: $migrationBasePath"
    Write-Output "[TEST]  Per pulire: Remove-Item '$migrationBasePath' -Recurse -Force"
}

if (-not $TEST_MODE -and $session) {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
}

Write-Output "[INFO] Sessione remota chiusa"
Write-Output "[SUCCESS] Processo di migrazione terminato"
