# Autore: G.ABBATICCHIO
# Revisione: 1.1
# Data: 15/02/2026
# Code: efc_user_migration
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Migrazione utente e dati da server legacy tramite sistema TeamSystem Scripts

Write-Output "[INFO] Avvio processo di migrazione utente..."

# Parametri da Morpheus
$migrationStatus = "<%=customOptions.MigrateData%>"
$fromUser = "<%=customOptions.fromUser%>"
$fromServer = "<%=customOptions.fromServer%>"
$toServer = "<%=instance.containers[0].server.internalIp%>"
$instanceName = "<%=instance.name%>"

# Server dove gira il sistema di migrazione (dispatcher)
$migrationServerIP = "10.182.X.X"  # TODO: Configurare IP del server di migrazione

Write-Output "[INFO] Server corrente (destinazione): $toServer"
Write-Output "[INFO] Instance: $instanceName"
Write-Output "[INFO] Server migrazione: $migrationServerIP"

# Verifica se la migrazione è attiva
if ($migrationStatus -ne "on") {
    Write-Output "[INFO] Migrazione non richiesta (mIgrateData: $migrationStatus)"
    Write-Output "[SUCCESS] Script completato - nessuna azione necessaria"
    exit 0
}

# Validazione parametri
if ([string]::IsNullOrWhiteSpace($fromUser)) {
    Write-Output "[ERROR] Parametro 'fromUser' mancante o vuoto"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($fromServer)) {
    Write-Output "[ERROR] Parametro 'fromServer' mancante o vuoto"
    exit 1
}

Write-Output "[INFO] Migrazione attiva - Parametri:"
Write-Output "[INFO]   - Utente origine: $fromUser"
Write-Output "[INFO]   - Server origine: $fromServer"
Write-Output "[INFO]   - Server destinazione: $toServer"

# Credenziali per la connessione remota al server di migrazione
# TODO: Configurare le credenziali appropriate
$migrationCredPath = "C:\Scripts\creds\migration_server.xml"

if (-not (Test-Path $migrationCredPath)) {
    Write-Output "[ERROR] File credenziali non trovato: $migrationCredPath"
    Write-Output "[ERROR] Creare il file con: Get-Credential | Export-Clixml $migrationCredPath"
    exit 1
}

try {
    $migrationCred = Import-Clixml -Path $migrationCredPath
    Write-Output "[INFO] Credenziali caricate correttamente"
} catch {
    Write-Output "[ERROR] Impossibile caricare credenziali: $($_.Exception.Message)"
    exit 1
}

# Crea sessione remota verso il server di migrazione
Write-Output "[INFO] Connessione al server di migrazione..."

try {
    $session = New-PSSession -ComputerName $migrationServerIP -Credential $migrationCred -ErrorAction Stop
    Write-Output "[INFO] Sessione remota stabilita con successo"
} catch {
    Write-Output "[ERROR] Impossibile connettersi al server di migrazione: $($_.Exception.Message)"
    exit 1
}

# Esegue la creazione del file di coda sul server remoto
try {
    $result = Invoke-Command -Session $session -ScriptBlock {
        param($fromUser, $fromServer, $toServer)
        
        $migrationBasePath = "C:\Scripts\TeamSystemMigration"
        $queuePath = Join-Path $migrationBasePath "queue\incoming"
        
        # Verifica esistenza sistema di migrazione
        if (-not (Test-Path $migrationBasePath)) {
            return @{
                Success = $false
                Message = "Sistema di migrazione non trovato in: $migrationBasePath"
            }
        }
        
        # Crea directory queue se non esiste
        if (-not (Test-Path $queuePath)) {
            New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
        }
        
        # Genera nome file univoco
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $queueFileName = "migra_${fromUser}_${timestamp}.txt"
        $queueFilePath = Join-Path $queuePath $queueFileName
        
        # Crea file per la coda (formato: utente|serverOrigine|serverDest)
        $queueContent = "${fromUser}|${fromServer}|${toServer}"
        
        try {
            $queueContent | Out-File -FilePath $queueFilePath -Encoding ASCII -Force
            
            # Verifica dispatcher attivo
            $dispatcherActive = Get-Process -Name "powershell" -ErrorAction SilentlyContinue | 
                Where-Object { $_.CommandLine -like "*dispatcher.ps1*" }
            
            return @{
                Success = $true
                QueueFile = $queueFileName
                QueueContent = $queueContent
                DispatcherActive = $null -ne $dispatcherActive
                DispatcherPID = if ($dispatcherActive) { $dispatcherActive.Id } else { $null }
                LogPath = $migrationBasePath
            }
        } catch {
            return @{
                Success = $false
                Message = "Errore creazione file: $($_.Exception.Message)"
            }
        }
        
    } -ArgumentList $fromUser, $fromServer, $toServer
    
    # Processa risultato
    if ($result.Success) {
        Write-Output "[INFO] File di coda creato: $($result.QueueFile)"
        Write-Output "[INFO] Contenuto: $($result.QueueContent)"
        
        if ($result.DispatcherActive) {
            Write-Output "[INFO] Dispatcher attivo (PID: $($result.DispatcherPID))"
        } else {
            Write-Output "[WARNING] Dispatcher non in esecuzione sul server di migrazione"
            Write-Output "[WARNING] La migrazione verrà processata quando il dispatcher sarà avviato"
        }
        
        Write-Output "[SUCCESS] File di migrazione accodato con successo"
        Write-Output "[INFO] Monitorare i log sul server $($migrationServerIP):"
        Write-Output "[INFO]   - Dispatcher: $($result.LogPath)\logs\dispatcher_$(Get-Date -Format 'yyyyMMdd').log"
        Write-Output "[INFO]   - Migrazione utente: $($result.LogPath)\logs\migra_${fromUser}.log"
        Write-Output "[INFO]   - Robocopy dettagli: $($result.LogPath)\logs\robocopy_${fromUser}.log"
        
    } else {
        Write-Output "[ERROR] $($result.Message)"
        Remove-PSSession -Session $session
        exit 1
    }
    
} catch {
    Write-Output "[ERROR] Errore durante l'esecuzione remota: $($_.Exception.Message)"
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    exit 1
}

# Chiude la sessione remota
Remove-PSSession -Session $session
Write-Output "[INFO] Sessione remota chiusa"

exit 0
