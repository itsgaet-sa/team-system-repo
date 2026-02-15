# Autore: G.ABBATICCHIO
# Revisione: 1.4
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
    
} catch {
    Write-Output "[ERROR] Errore durante l'accodamento della migrazione"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    Update-MigrationStatus -Status "Failed: $($_.Exception.Message)"
    exit 1
}

# Chiude la sessione remota
Remove-PSSession -Session $session
Write-Output "[INFO] Sessione remota chiusa"

Write-Output "[SUCCESS] Processo di accodamento migrazione completato"
