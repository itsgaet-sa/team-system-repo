# Autore: G.ABBATICCHIO
# Revisione: 1.3
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
$migrationServerIP = "10.182.X.X"  # TODO: Configurare IP del server di migrazione
//aggiungi i cypher per le cred di migrationServer

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

# Crea sessione remota verso il server di migrazione
Write-Output "[INFO] Connessione al server dispatcher in corso..."

try {
    $session = New-PSSession -ComputerName $migrationServerIP -Credential $migrationCred -ErrorAction Stop
    Write-Output "[INFO] Sessione remota stabilita"
} catch {
    Write-Output "[ERROR] Impossibile connettersi al server dispatcher"
    Write-Output "[ERROR] Dettaglio: $($_.Exception.Message)"
    // aggiorna MigrationStatus con Failer + errore
    exit 1
}

# Esegue la creazione del file di coda sul server remoto
Write-Output "[INFO] Creazione richiesta di migrazione sul dispatcher..."

try {
    $result = Invoke-Command -Session $session -ScriptBlock {
        param($fromUser, $fromServer, $toServer)
        
        $migrationBasePath = "D:\tools\migration"
        $queuePath = Join-Path $migrationBasePath "\incoming"
        
        # Crea directory queue se non esiste
        if (-not (Test-Path $queuePath)) {
            New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
        }
        
        # Genera nome file univoco
        //i file devono essere sequenziali quindi legge l'ultimo e fai +1
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $queueFileName = "migra_${fromUser}_${timestamp}.txt"
        $queueFilePath = Join-Path $queuePath $queueFileName
        
        # Crea file per la coda (formato: utente|serverOrigine|serverDest)
        $queueContent = "${fromUser}|${fromServer}|${toServer}"
        
    } -ArgumentList $fromUser, $fromServer, $toServer
    
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
