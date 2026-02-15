# Autore: G.ABBATICCHIO
# Revisione: 1.5
# Data: 15/02/2026
# Code: efc_user_migration_prep
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Preparazione per la migrazione dell'utente, creazione del file dichiarativo.

Write-Output "[INFO] Controllo richiesta migrazione utente..."

# Parametri da Morpheus
$migrationValue = "<%=customOptions.MigrateData%>"
$fromUser = "<%=customOptions.fromUser%>"
$fromServer = "<%=customOptions.fromServer%>"
$toServer = "<%=instance.containers[0].server.internalIp%>"
$instanceName = "<%=instance.name%>"
$instanceId = "<%=instance.id%>"
$migrationServerIP = "10.182.X.X"  # TODO: Configurare IP del server di migrazione

# Recupera credenziali dal Cypher di Morpheus
$migrationUser = "<%=cypher.read('secret/migrationServerUser',true)%>"
$migrationPass = "<%=cypher.read('secret/migrationServerPass',true)%>"
$migrationCred = New-Object System.Management.Automation.PSCredential($migrationUser, $migrationPass)

Write-Output "[INFO] Instance: $instanceName"
Write-Output "[INFO] Stato migrazione richiesta: '$migrationValue'"

# Verifica se la migrazione è attiva (stringa "true")
if ($migrationValue -ne "true") {
    Write-Output "[INFO] Migrazione dati NON richiesta - Skip"
    Write-Output "[SUCCESS] Nessuna migrazione da effettuare"
    exit 0
}

Write-Output "[INFO] =========================================="
Write-Output "[INFO] MIGRAZIONE DATI RICHIESTA - Avvio processo"
Write-Output "[INFO] =========================================="

# Validazione parametri
if ([string]::IsNullOrWhiteSpace($fromUser)) {
    Write-Output "[ERROR] Parametro 'fromUser' mancante o vuoto"
    Write-Output "[ERROR] Impossibile procedere con la migrazione"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($fromServer)) {
    Write-Output "[ERROR] Parametro 'fromServer' mancante o vuoto"
    Write-Output "[ERROR] Impossibile procedere con la migrazione"
    exit 1
}

Write-Output "[INFO] Parametri migrazione:"
Write-Output "[INFO]   - Utente origine: $fromUser"
Write-Output "[INFO]   - Server origine: $fromServer"
Write-Output "[INFO]   - Server destinazione: $toServer"
Write-Output "[INFO] Server dispatcher: $migrationServerIP"

# Funzione per aggiornare lo stato della migrazione in Morpheus
function Update-MigrationStatus {
    param(
        [string]$Status
    )
    
    try {
        # Aggiorna lo stato tramite API Morpheus
        $morpheusApiUrl = "<%=morpheus.applianceUrl%>/api/instances/$instanceId"
        $morpheusToken = "<%=morpheus.apiAccessToken%>"
        
        $headers = @{
            "Authorization" = "Bearer $morpheusToken"
            "Content-Type" = "application/json"
        }
        
        $body = @{
            instance = @{
                customOptions = @{
                    MigrationStatus = $Status
                }
            }
        } | ConvertTo-Json -Depth 5
        
        Invoke-RestMethod -Uri $morpheusApiUrl -Method Put -Headers $headers -Body $body -ErrorAction Stop
        Write-Output "[INFO] Stato migrazione aggiornato: $Status"
    } catch {
        Write-Output "[WARNING] Impossibile aggiornare lo stato in Morpheus: $($_.Exception.Message)"
    }
}

# Crea sessione remota verso il server di migrazione
Write-Output "[INFO] Connessione al server dispatcher in corso..."
try {
    $session = New-PSSession -ComputerName $migrationServerIP -Credential $migrationCred -ErrorAction Stop
    Write-Output "[INFO] Sessione remota stabilita"
} catch {
    Write-Output "[ERROR] Impossibile connettersi al server dispatcher"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    Update-MigrationStatus -Status "Failed: $($_.Exception.Message)"
    exit 1
}

# Esegue la creazione del file di coda sul server remoto
Write-Output "[INFO] Creazione richiesta di migrazione sul dispatcher..."
try {
    $result = Invoke-Command -Session $session -ScriptBlock {
        param($fromUser, $fromServer, $toServer)
        
        $migrationBasePath = "D:\tools\migration"
        $queuePath = Join-Path $migrationBasePath "incoming"
        $lockFile = Join-Path $migrationBasePath "queue.lock"
        
        # Crea directory queue se non esiste
        if (-not (Test-Path $queuePath)) {
            New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
        }
        
        # Implementa lock per evitare race condition sulla numerazione
        $lockAcquired = $false
        $maxRetries = 10
        $retryCount = 0
        
        while (-not $lockAcquired -and $retryCount -lt $maxRetries) {
            try {
                # Tenta di creare il file di lock
                $lockHandle = [System.IO.File]::Open($lockFile, 'CreateNew', 'Write', 'None')
                $lockAcquired = $true
            } catch {
                $retryCount++
                Start-Sleep -Milliseconds 100
            }
        }
        
        if (-not $lockAcquired) {
            throw "Impossibile acquisire il lock dopo $maxRetries tentativi"
        }
        
        try {
            # Legge l'ultimo numero di sequenza utilizzato
            $existingFiles = Get-ChildItem -Path $queuePath -Filter "migra_*.txt" -ErrorAction SilentlyContinue | 
                             Where-Object { $_.Name -match 'migra_(\d+)\.txt' } |
                             ForEach-Object { 
                                 [PSCustomObject]@{
                                     File = $_
                                     Sequence = [int]($matches[1])
                                 }
                             } |
                             Sort-Object Sequence -Descending
            
            # Calcola il prossimo numero di sequenza
            $nextSequence = if ($existingFiles -and $existingFiles.Count -gt 0) {
                $existingFiles[0].Sequence + 1
            } else {
                1
            }
            
            # Genera nome file con numerazione sequenziale (6 cifre con zero-padding)
            $queueFileName = "migra_{0:D6}.txt" -f $nextSequence
            $queueFilePath = Join-Path $queuePath $queueFileName
            
            # Crea file per la coda (formato: utente|serverOrigine|serverDest)
            $queueContent = "${fromUser}|${fromServer}|${toServer}"
            Set-Content -Path $queueFilePath -Value $queueContent -Force
            
            Write-Output "[INFO] File creato: $queueFilePath (Sequenza: $nextSequence)"
            
            return @{
                FilePath = $queueFilePath
                FileName = $queueFileName
                Sequence = $nextSequence
                Status = "Success"
            }
            
        } finally {
            # Rilascia il lock
            if ($lockHandle) {
                $lockHandle.Close()
                $lockHandle.Dispose()
            }
            if (Test-Path $lockFile) {
                Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
            }
        }
        
    } -ArgumentList $fromUser, $fromServer, $toServer
    
    Write-Output "[INFO] File di migrazione accodato: $($result.FilePath)"
    Write-Output "[INFO] Numero sequenza: $($result.Sequence)"
    
    # Aggiorna lo stato in Morpheus
    Update-MigrationStatus -Status "Pending"
    
    # Avvia il dispatcher per processare la coda
    Write-Output "[INFO] Avvio dispatcher per elaborazione migrazione..."
    try {
        $dispatcherResult = Invoke-Command -Session $session -ScriptBlock {
            $dispatcherScript = "D:\tools\migration\dispatcher.ps1"
            
            if (-not (Test-Path $dispatcherScript)) {
                throw "Script dispatcher non trovato: $dispatcherScript"
            }
            
            # Esegue il dispatcher
            & $dispatcherScript
            
            return @{
                Status = "Dispatcher avviato"
            }
        }
        
        Write-Output "[INFO] Dispatcher avviato con successo"
        
    } catch {
        Write-Output "[WARNING] Errore durante l'avvio del dispatcher: $($_.Exception.Message)"
        Write-Output "[WARNING] La migrazione rimarrà in coda fino al prossimo avvio del dispatcher"
    }
    
    # Salva il nome del file per il monitoraggio
    $queueFileName = $result.FileName
    $queueFileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($queueFileName)
    
} catch {
    Write-Output "[ERROR] Errore durante l'accodamento della migrazione"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    Update-MigrationStatus -Status "Failed: $($_.Exception.Message)"
    exit 1
}

# Monitoraggio stato della migrazione
Write-Output "[INFO] =========================================="
Write-Output "[INFO] Avvio monitoraggio stato migrazione..."
Write-Output "[INFO] =========================================="

$monitoringMaxTime = 5400  # 1 ora di timeout
$monitoringInterval = 10    # Controlla ogni 10 secondi
$elapsedTime = 0
$migrationCompleted = $false

while ($elapsedTime -lt $monitoringMaxTime -and -not $migrationCompleted) {
    try {
        $fileStatus = Invoke-Command -Session $session -ScriptBlock {
            param($baseName, $queuePath)
            
            # Cerca il file con estensioni .done o .err
            $doneFile = Join-Path $queuePath "$baseName.done"
            $errFile = Join-Path $queuePath "$baseName.err"
            $txtFile = Join-Path $queuePath "$baseName.txt"
            $workFile = Join-Path $queuePath "$baseName.work"
            if (Test-Path $doneFile) {
                return @{
                    Status = "Completed"
                    FilePath = $doneFile
                }
            } elseif (Test-Path $errFile) {
                # Legge il contenuto del file di errore se presente
                $errorContent = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
                return @{
                    Status = "Failed"
                    FilePath = $errFile
                    ErrorMessage = $errorContent
                }
            } elseif (Test-Path $txtFile) {
                return @{
                    Status = "Scheduled"
                    FilePath = $txtFile
                } elseif (Test-Path $workFile) {
                return @{
                    Status = "Processing"
                    FilePath = $txtFile
                }
            } else {
                return @{
                    Status = "Unknown"
                    FilePath = $null
                }
            }
        } -ArgumentList $queueFileBaseName, "D:\tools\migration\incoming"
        
        Write-Output "[INFO] Stato corrente: $($fileStatus.Status) - Tempo trascorso: $elapsedTime secondi"
        
        if ($fileStatus.Status -eq "Completed") {
            Write-Output "[SUCCESS] Migrazione completata con successo!"
            Update-MigrationStatus -Status "Completed"
            $migrationCompleted = $true
            
        } elseif ($fileStatus.Status -eq "Failed") {
            $errorMsg = if ($fileStatus.ErrorMessage) { $fileStatus.ErrorMessage } else { "Errore durante la migrazione" }
            Write-Output "[ERROR] Migrazione fallita: $errorMsg"
            Update-MigrationStatus -Status "Failed: $errorMsg"
            $migrationCompleted = $true
            
            # Chiude la sessione e esce con errore
            Remove-PSSession -Session $session
            exit 1
            
        } elseif ($fileStatus.Status -eq "Unknown") {
            Write-Output "[WARNING] File di migrazione non trovato - possibile errore nel processo"
            Update-MigrationStatus -Status "Failed: File di migrazione non trovato"
            $migrationCompleted = $true
            
            # Chiude la sessione e esce con errore
            Remove-PSSession -Session $session
            exit 1
        }
        
        if (-not $migrationCompleted) {
            Start-Sleep -Seconds $monitoringInterval
            $elapsedTime += $monitoringInterval
        }
        
    } catch {
        Write-Output "[ERROR] Errore durante il monitoraggio: $($_.Exception.Message)"
        Start-Sleep -Seconds $monitoringInterval
        $elapsedTime += $monitoringInterval
    }
}

# Verifica timeout
if ($elapsedTime -ge $monitoringMaxTime -and -not $migrationCompleted) {
    Write-Output "[WARNING] Timeout monitoraggio raggiunto ($monitoringMaxTime secondi)"
    Write-Output "[WARNING] La migrazione potrebbe essere ancora in corso"
    Update-MigrationStatus -Status "Failed: verifica manuale richiesta"
}

# Chiude la sessione remota
Remove-PSSession -Session $session
Write-Output "[INFO] Sessione remota chiusa"

Write-Output "[SUCCESS] Processo di migrazione completato"
