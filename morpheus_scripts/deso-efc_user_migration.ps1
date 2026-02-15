# Autore: G.ABBATICCHIO
# Revisione: 1.3
# Data: 15/02/2026
# Code: efc_user_migration
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Migrazione utente e dati da server a server tramite sistema TeamSystem Scripts

Write-Output "[INFO] Controllo richiesta migrazione utente..."

# Parametri da Morpheus
$migrationValue = "<%=customOptions.MigrateData%>"
$fromUser = "<%=customOptions.fromUser%>"
$fromServer = "<%=customOptions.fromServer%>"
$toServer = "<%=instance.containers[0].server.internalIp%>"
$instanceName = "<%=instance.name%>"

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

# Server dove gira il sistema di migrazione (dispatcher)
$migrationServerIP = "10.182.X.X"  # TODO: Configurare IP del server di migrazione

Write-Output "[INFO] Server dispatcher: $migrationServerIP"

# Credenziali per la connessione remota al server di migrazione
$migrationCredPath = "C:\Scripts\creds\migration_server.xml"

if (-not (Test-Path $migrationCredPath)) {
    Write-Output "[ERROR] File credenziali non trovato: $migrationCredPath"
    Write-Output "[ERROR] Creare il file con: Get-Credential | Export-Clixml $migrationCredPath"
    exit 1
}

try {
    $migrationCred = Import-Clixml -Path $migrationCredPath
    Write-Output "[INFO] Credenziali dispatcher caricate"
} catch {
    Write-Output "[ERROR] Impossibile caricare credenziali: $($_.Exception.Message)"
    exit 1
}

# Crea sessione remota verso il server di migrazione
Write-Output "[INFO] Connessione al server dispatcher in corso..."

try {
    $session = New-PSSession -ComputerName $migrationServerIP -Credential $migrationCred -ErrorAction Stop
    Write-Output "[INFO] Sessione remota stabilita"
} catch {
    Write-Output "[ERROR] Impossibile connettersi al server dispatcher"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    exit 1
}

# Esegue la creazione del file di coda sul server remoto
Write-Output "[INFO] Creazione richiesta di migrazione sul dispatcher..."

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
                Message = "Errore creazione file coda: $($_.Exception.Message)"
            }
        }
        
    } -ArgumentList $fromUser, $fromServer, $toServer
    
    # Processa risultato
    if ($result.Success) {
        Write-Output "[SUCCESS] Richiesta di migrazione accodata"
        Write-Output "[INFO] File coda: $($result.QueueFile)"
        Write-Output "[INFO] Parametri: $($result.QueueContent)"
        
        if ($result.DispatcherActive) {
            Write-Output "[INFO] Dispatcher ATTIVO - La migrazione verrà elaborata a breve (PID: $($result.DispatcherPID))"
        } else {
            Write-Output "[WARNING] Dispatcher NON ATTIVO - Avviare il dispatcher per processare la migrazione"
            Write-Output "[WARNING] La richiesta rimarrà in coda fino all'avvio del dispatcher"
        }
        
        Write-Output "[INFO] =========================================="
        Write-Output "[INFO] Log da monitorare sul server $($migrationServerIP):"
        Write-Output "[INFO]   Dispatcher: $($result.LogPath)\logs\dispatcher_$(Get-Date -Format 'yyyyMMdd').log"
        Write-Output "[INFO]   Migrazione: $($result.LogPath)\logs\migra_${fromUser}.log"
        Write-Output "[INFO]   Robocopy:   $($result.LogPath)\logs\robocopy_${fromUser}.log"
        Write-Output "[INFO] =========================================="
        
    } else {
        Write-Output "[ERROR] Impossibile accodare la richiesta di migrazione"
        Write-Output "[ERROR] $($result.Message)"
        Remove-PSSession -Session $session
        exit 1
    }
    
} catch {
    Write-Output "[ERROR] Errore durante l'accodamento della migrazione"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    exit 1
}

# Chiude la sessione remota
Remove-PSSession -Session $session
Write-Output "[INFO] Sessione remota chiusa"
Write-Output "[SUCCESS] Processo di accodamento migrazione completato"
