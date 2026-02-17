# Autore: G.ABBATICCHIO
# Revisione: 1.6
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

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONI DI SUPPORTO
# ──────────────────────────────────────────────────────────────────────────────

# Riemette nel log locale ogni riga di output prodotta da un blocco remoto.
# Invoke-Command restituisce Write-Output del blocco remoto come oggetti nella
# pipeline: questa funzione li intercetta e li stampa prima del valore di ritorno.
function Write-RemoteLog {
    param([object[]]$RemoteOutput)
    foreach ($line in $RemoteOutput) {
        if ($line -is [string]) {
            Write-Output $line
        }
    }
}

# Aggiorna lo stato della migrazione tramite API Morpheus
function Update-MigrationStatus {
    param([string]$Status)
    try {
        $morpheusApiUrl = "<%=morpheus.applianceUrl%>/api/instances/$instanceId"
        $morpheusToken  = "<%=morpheus.apiAccessToken%>"
        $headers = @{
            "Authorization" = "Bearer $morpheusToken"
            "Content-Type"  = "application/json"
        }
        $body = @{
            instance = @{
                customOptions = @{ MigrationStatus = $Status }
            }
        } | ConvertTo-Json -Depth 5

        Invoke-RestMethod -Uri $morpheusApiUrl -Method Put -Headers $headers -Body $body -ErrorAction Stop
        Write-Output "[INFO] Stato migrazione aggiornato in Morpheus: '$Status'"
    } catch {
        Write-Output "[WARNING] Impossibile aggiornare lo stato in Morpheus: $($_.Exception.Message)"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# INIZIO SCRIPT
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] Controllo richiesta migrazione utente..."

# Parametri da Morpheus
$migrationValue  = "<%=customOptions.MigrateData%>"
$fromUser        = "<%=customOptions.fromUser%>"
$fromServer      = "<%=customOptions.fromServer%>"
$toServer        = "<%=instance.containers[0].server.internalIp%>"
$instanceName    = "<%=instance.name%>"
$instanceId      = "<%=instance.id%>"
$migrationServerIP = "10.182.1.11"  # TODO: Configurare IP del server di migrazione

# Recupera credenziali dal Cypher di Morpheus
$migrationUser = "<%=cypher.read('secret/EFC-TS_MIG_DANEA-USR',true)%>"
$migrationPass = "<%=cypher.read('secret/EFC-TS_MIG_DANEA-PWD',true)%>"
$migrationCred = New-Object System.Management.Automation.PSCredential($migrationUser, $migrationPass)

Write-Output "[INFO] Instance: $instanceName"
Write-Output "[INFO] Stato migrazione richiesta: '$migrationValue'"

# Verifica se la migrazione è attiva
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
    exit 1
}
if ([string]::IsNullOrWhiteSpace($fromServer)) {
    Write-Output "[ERROR] Parametro 'fromServer' mancante o vuoto - impossibile procedere"
    exit 1
}

Write-Output "[INFO] Parametri migrazione:"
Write-Output "[INFO]   - Utente origine  : $fromUser"
Write-Output "[INFO]   - Server origine  : $fromServer"
Write-Output "[INFO]   - Server destino  : $toServer"
Write-Output "[INFO]   - Server dispatcher: $migrationServerIP"

# ──────────────────────────────────────────────────────────────────────────────
# CONNESSIONE AL SERVER DI MIGRAZIONE
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] Connessione al server dispatcher ($migrationServerIP) in corso..."
try {
    $session = New-PSSession -ComputerName $migrationServerIP -Credential $migrationCred -ErrorAction Stop
    Write-Output "[SUCCESS] Sessione remota stabilita con $migrationServerIP"
} catch {
    Write-Output "[ERROR] Impossibile connettersi al server dispatcher ($migrationServerIP)"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    Update-MigrationStatus -Status "Failed: connessione dispatcher - $($_.Exception.Message)"
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# CREAZIONE FILE DI CODA SUL SERVER REMOTO
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] Creazione richiesta di migrazione sul dispatcher..."
try {
    # Il blocco remoto usa Write-Output per i log; vengono restituiti nella pipeline
    # insieme all'hashtable di ritorno: li separiamo per tipo.
    $rawOutput = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
        param($fromUser, $fromServer, $toServer)

        $migrationBasePath = "D:\tools\migration"
        $queuePath         = Join-Path $migrationBasePath "incoming"
        $lockFile          = Join-Path $migrationBasePath "queue.lock"

        # Crea directory queue se non esiste
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

        # Acquisizione lock per evitare race condition sulla numerazione
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
            # Calcola il prossimo numero di sequenza
            $existingFiles = Get-ChildItem -Path $queuePath -Filter "migra_*.txt" -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -match 'migra_(\d+)\.txt' } |
                             ForEach-Object {
                                 [PSCustomObject]@{
                                     File     = $_
                                     Sequence = [int]($Matches[1])
                                 }
                             } |
                             Sort-Object Sequence -Descending

            $nextSequence = if ($existingFiles -and $existingFiles.Count -gt 0) {
                $existingFiles[0].Sequence + 1
            } else { 1 }

            $queueFileName = "migra_{0:D6}.txt" -f $nextSequence
            $queueFilePath = Join-Path $queuePath $queueFileName
            $queueContent  = "${fromUser}|${fromServer}|${toServer}"

            Write-Output "[REMOTE][INFO] Prossima sequenza: $nextSequence → file: $queueFileName"

            # Creazione del file di coda
            try {
                Set-Content -Path $queueFilePath -Value $queueContent -Force -ErrorAction Stop
                Write-Output "[REMOTE][SUCCESS] File di coda creato: $queueFilePath"
                Write-Output "[REMOTE][INFO] Contenuto: $queueContent"
            } catch {
                Write-Output "[REMOTE][ERROR] Impossibile creare il file di coda '$queueFilePath': $($_.Exception.Message)"
                throw
            }

            # Verifica che il file esista davvero dopo la scrittura
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
            # Rilascia sempre il lock
            if ($lockHandle) {
                $lockHandle.Close()
                $lockHandle.Dispose()
            }
            if (Test-Path $lockFile) {
                Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                Write-Output "[REMOTE][INFO] Lock rilasciato"
            }
        }

    } -ArgumentList $fromUser, $fromServer, $toServer

    # Separa i messaggi di log (stringhe) dal risultato strutturato (hashtable)
    $remoteMessages = $rawOutput | Where-Object { $_ -is [string] }
    $result         = $rawOutput | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1

    Write-RemoteLog -RemoteOutput $remoteMessages

    if (-not $result -or $result.Status -ne "Success") {
        Write-Output "[ERROR] Il blocco remoto non ha restituito un risultato valido"
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        Update-MigrationStatus -Status "Failed: risultato creazione file non valido"
        exit 1
    }

    Write-Output "[SUCCESS] File di migrazione accodato correttamente"
    Write-Output "[INFO] Percorso: $($result.FilePath)"
    Write-Output "[INFO] Numero sequenza: $($result.Sequence)"

    Update-MigrationStatus -Status "Pending"

} catch {
    Write-Output "[ERROR] Errore durante l'accodamento della migrazione"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    Update-MigrationStatus -Status "Failed: $($_.Exception.Message)"
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# AVVIO DISPATCHER
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] Avvio dispatcher per elaborazione migrazione..."
try {
    $dispatcherRaw = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
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

    $dispatcherMessages = $dispatcherRaw | Where-Object { $_ -is [string] }
    $dispatcherResult   = $dispatcherRaw | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1

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

# Nomi file per il monitoraggio
$queueFileName       = $result.FileName
$queueFileBaseName   = [System.IO.Path]::GetFileNameWithoutExtension($queueFileName)

# ──────────────────────────────────────────────────────────────────────────────
# MONITORAGGIO STATO MIGRAZIONE
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] =========================================="
Write-Output "[INFO] Avvio monitoraggio stato migrazione..."
Write-Output "[INFO] =========================================="

$monitoringMaxTime = 5400   # 90 minuti di timeout totale
$monitoringInterval = 10    # Controlla ogni 10 secondi
$elapsedTime        = 0
$migrationCompleted = $false
$lastReportedStatus = ""

while ($elapsedTime -lt $monitoringMaxTime -and -not $migrationCompleted) {
    try {
        $fileStatus = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            param($baseName, $queuePath)

            $doneFile = Join-Path $queuePath "$baseName.done"
            $errFile  = Join-Path $queuePath "$baseName.err"
            $txtFile  = Join-Path $queuePath "$baseName.txt"
            $workFile = Join-Path $queuePath "$baseName.work"

            if (Test-Path $doneFile) {
                return @{ Status = "Completed";  FilePath = $doneFile }

            } elseif (Test-Path $errFile) {
                $errorContent = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
                return @{ Status = "Failed";     FilePath = $errFile; ErrorMessage = $errorContent }

            } elseif (Test-Path $workFile) {
                return @{ Status = "Processing"; FilePath = $workFile }

            } elseif (Test-Path $txtFile) {
                return @{ Status = "Scheduled";  FilePath = $txtFile }

            } else {
                return @{ Status = "Unknown";    FilePath = $null }
            }

        } -ArgumentList $queueFileBaseName, "D:\tools\migration\incoming"

        $currentStatus = $fileStatus.Status

        # Logga il cambio di stato (evita messaggi ripetitivi)
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
                Update-MigrationStatus -Status "Completed"
                $migrationCompleted = $true
            }

            "Failed" {
                $errorMsg = if ($fileStatus.ErrorMessage) { $fileStatus.ErrorMessage.Trim() } else { "Errore non specificato" }
                Write-Output "[ERROR] =========================================="
                Write-Output "[ERROR] Migrazione fallita!"
                Write-Output "[ERROR] File errore : $($fileStatus.FilePath)"
                Write-Output "[ERROR] Dettaglio   : $errorMsg"
                Write-Output "[ERROR] =========================================="
                Update-MigrationStatus -Status "Failed: $errorMsg"
                $migrationCompleted = $true
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                exit 1
            }

            "Unknown" {
                Write-Output "[ERROR] File di migrazione non trovato sul dispatcher - il processo potrebbe aver perso traccia del file"
                Update-MigrationStatus -Status "Failed: file di migrazione non trovato"
                $migrationCompleted = $true
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
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

# Gestione timeout
if (-not $migrationCompleted) {
    Write-Output "[WARNING] =========================================="
    Write-Output "[WARNING] Timeout monitoraggio raggiunto dopo $monitoringMaxTime secondi"
    Write-Output "[WARNING] La migrazione potrebbe essere ancora in corso"
    Write-Output "[WARNING] Verifica manuale richiesta sul file: $queueFileName"
    Write-Output "[WARNING] =========================================="
    Update-MigrationStatus -Status "Failed: timeout - verifica manuale richiesta"
}

# Chiusura sessione remota
Remove-PSSession -Session $session -ErrorAction SilentlyContinue
Write-Output "[INFO] Sessione remota chiusa"
Write-Output "[SUCCESS] Processo di migrazione terminato"
