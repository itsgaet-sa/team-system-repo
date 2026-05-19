# Autore: G.ABBATICCHIO
# Revisione: 0.1
# Data: 19/05/2026
# Code: deso_efc_user_migration_disconnect_queue
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Crea il file di disconnessione sul dispatcher solo per migrationMode planned.
#              Dati usati solo ed esclusivamente dal Catalog Item.
#              Nessun collegamento con instance.
#              Nessuna chiamata API Morpheus.
#              Nessun aggiornamento customOptions su Morpheus.
#              Scrittura concorrente gestita tramite lock file.

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONI DI SUPPORTO
# ──────────────────────────────────────────────────────────────────────────────

function Format-Value {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "<vuoto/non valorizzato>"
    }

    return "'$Value'"
}

function Write-Line {
    param(
        [string]$Label,
        [string]$Value
    )

    Write-Output "[INFO] $Label = $(Format-Value $Value)"
}

function Write-RemoteLog {
    param([object[]]$RemoteOutput)

    foreach ($line in $RemoteOutput) {
        if ($line -is [string]) {
            Write-Output $line
        }
    }
}

function Add-ValidationError {
    param([string]$Message)

    $script:validationErrors += $Message
    Write-Output "[ERROR] $Message"
}

# ──────────────────────────────────────────────────────────────────────────────
# VALORI RICEVUTI DAL CATALOG ITEM / GUI
# ──────────────────────────────────────────────────────────────────────────────

$catalog_migrationType     = "<%=customOptions.migrationType%>"
$catalog_migrationMode     = "<%=customOptions.migrationMode%>"
$catalog_sourceServer      = "<%=customOptions.sourceServer%>"
$catalog_destinationServer = "<%=customOptions.destinationServer%>"
$catalog_targetUser        = "<%=customOptions.targetUser%>"
$catalog_instanceId        = "<%=customOptions.instanceId%>"

# Normalizzazione valori ricevuti
$catalog_migrationType     = $catalog_migrationType.Trim().ToLower()
$catalog_migrationMode     = $catalog_migrationMode.Trim().ToLower()
$catalog_sourceServer      = $catalog_sourceServer.Trim()
$catalog_destinationServer = $catalog_destinationServer.Trim()
$catalog_targetUser        = $catalog_targetUser.Trim()
$catalog_instanceId        = $catalog_instanceId.Trim()

$validationErrors = @()

# ──────────────────────────────────────────────────────────────────────────────
# LOG VALORI RICEVUTI
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] =========================================="
Write-Output "[INFO] CREAZIONE FILE DISCONNESSIONE UTENTE"
Write-Output "[INFO] =========================================="

Write-Output ""
Write-Output "[INFO] ----- VALORI RICEVUTI DAL CATALOG ITEM -----"
Write-Line -Label "Catalog migrationType"     -Value $catalog_migrationType
Write-Line -Label "Catalog migrationMode"     -Value $catalog_migrationMode
Write-Line -Label "Catalog sourceServer"      -Value $catalog_sourceServer
Write-Line -Label "Catalog destinationServer" -Value $catalog_destinationServer
Write-Line -Label "Catalog targetUser"        -Value $catalog_targetUser
Write-Line -Label "Catalog instanceId"        -Value $catalog_instanceId

# ──────────────────────────────────────────────────────────────────────────────
# ESECUZIONE SOLO PER migrationMode planned
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- CHECK migrationMode -----"

if ([string]::IsNullOrWhiteSpace($catalog_migrationMode)) {
    Write-Output "[ERROR] migrationMode non valorizzato"
    exit 1
}

if ($catalog_migrationMode -eq "instant") {
    Write-Output "[INFO] migrationMode = instant"
    Write-Output "[INFO] Nessun file di disconnessione richiesto"
    Write-Output "[SUCCESS] Processo completato senza accodamento"
    exit 0
}

if ($catalog_migrationMode -ne "planned") {
    Write-Output "[ERROR] migrationMode non valido: $(Format-Value $catalog_migrationMode). Valori ammessi: instant, planned"
    exit 1
}

Write-Output "[INFO] migrationMode = planned"
Write-Output "[INFO] Verrà creato/aggiornato il file di disconnessione"

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE MINIMA DATI CATALOG NECESSARI AL FILE
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE DATI PER DISCONNESSIONE -----"

if ([string]::IsNullOrWhiteSpace($catalog_targetUser)) {
    Add-ValidationError "targetUser è required per creare il file di disconnessione"
}

if ([string]::IsNullOrWhiteSpace($catalog_migrationType)) {
    Add-ValidationError "migrationType non valorizzato"
}

if ($catalog_migrationType -ne "m2m" -and $catalog_migrationType -ne "m2s") {
    Add-ValidationError "migrationType non valido: $(Format-Value $catalog_migrationType). Valori ammessi: m2m, m2s"
}

# Per m2s instanceId dovrebbe essere valorizzato perché già validato dal task precedente.
# Qui non chiamiamo Morpheus e non leggiamo instance: usiamo solo il valore Catalog.
if ($catalog_migrationType -eq "m2s" -and [string]::IsNullOrWhiteSpace($catalog_instanceId)) {
    Add-ValidationError "instanceId è required per migrationType m2s"
}

if ($validationErrors.Count -gt 0) {
    Write-Output ""
    Write-Output "[ERROR] ===== VALIDATION FAILED ====="
    Write-Output "[ERROR] Numero errori rilevati: $($validationErrors.Count)"

    for ($i = 0; $i -lt $validationErrors.Count; $i++) {
        Write-Output "[ERROR] $($i + 1). $($validationErrors[$i])"
    }

    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# CREDENZIALI DA CYPHER
# EFC-TS_MIG_DANEA-USR → username in chiaro
# EFC-TS_MIG_DANEA_SSH → chiave privata SSH codificata in Base64 oppure PEM grezzo
# ──────────────────────────────────────────────────────────────────────────────

$migrationUserRaw   = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-USR",true)%>'
$migrationKeyBase64 = '<%=cypher.read("secret/EFC-TS_MIG_DANEA_SSH",true)%>'

if ([string]::IsNullOrWhiteSpace($migrationUserRaw) -or [string]::IsNullOrWhiteSpace($migrationKeyBase64)) {
    Write-Output "[ERROR] Credenziali dispatcher non disponibili dal Cypher"
    exit 1
}

$migrationUserRaw = $migrationUserRaw.Trim()

# ──────────────────────────────────────────────────────────────────────────────
# PATH REMOTO SUL DISPATCHER
# ──────────────────────────────────────────────────────────────────────────────

$migrationServerIP  = "10.182.1.11"
$remoteIncomingPath = "D:\tools\migration-tool-st"
$remoteUsersFile    = "users.txt"
$remoteLockFile     = "users.lock"

# Soglia usata dal codice originale:
# prima delle 18:00 scrive data odierna;
# dalle 18:00 in poi scrive data del giorno successivo.
$thresholdHour = 18

Write-Output ""
Write-Output "[INFO] ----- CONFIGURAZIONE DISPATCHER -----"
Write-Output "[INFO] Dispatcher      : $migrationServerIP"
Write-Output "[INFO] Remote folder   : $remoteIncomingPath"
Write-Output "[INFO] Remote file     : $remoteUsersFile"
Write-Output "[INFO] Remote lock     : $remoteLockFile"
Write-Output "[INFO] Threshold hour  : $thresholdHour"

# ──────────────────────────────────────────────────────────────────────────────
# DECODIFICA CHIAVE SSH DA BASE64
# ──────────────────────────────────────────────────────────────────────────────

$tempKeyPath = $null

try {
    $tempKeyPath = "/tmp/ssh_key_$([System.Guid]::NewGuid().ToString('N'))"
    $keyRaw      = $migrationKeyBase64.Trim()

    try {
        $keyBytes = [System.Convert]::FromBase64String($keyRaw)
        $keyPem   = [System.Text.Encoding]::UTF8.GetString($keyBytes)
        Write-Output "[INFO] Chiave SSH letta dal Cypher come Base64"
    }
    catch {
        $keyPem = $keyRaw
        Write-Output "[INFO] Chiave SSH letta dal Cypher come PEM grezzo"
    }

    Set-Content -Path $tempKeyPath -Value $keyPem -NoNewline -Encoding UTF8
    chmod 600 $tempKeyPath

    Write-Output "[INFO] Chiave SSH pronta"
}
catch {
    Write-Output "[ERROR] Errore preparazione chiave SSH: $($_.Exception.Message)"
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE HOST KEY
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] Validazione Host key ($migrationServerIP)..."

$sshDir = Join-Path $HOME ".ssh"

if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

$knownHosts = Join-Path $sshDir "known_hosts"

ssh-keygen -R $migrationServerIP 2>$null

$keyScan = ssh-keyscan -H $migrationServerIP 2>$null

if ([string]::IsNullOrWhiteSpace($keyScan)) {
    Write-Output "[ERROR] Impossibile recuperare host key da $migrationServerIP"

    if ($tempKeyPath -and (Test-Path $tempKeyPath)) {
        Remove-Item $tempKeyPath -Force -ErrorAction SilentlyContinue
    }

    exit 1
}

$keyScan | Out-File -Append -FilePath $knownHosts -Encoding ascii

chmod 700 $sshDir
chmod 600 $knownHosts

Write-Output "[INFO] Host key registrata correttamente"

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
}
catch {
    Write-Output "[ERROR] Impossibile connettersi al dispatcher: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($tempKeyPath -and (Test-Path $tempKeyPath)) {
        Remove-Item $tempKeyPath -Force -ErrorAction SilentlyContinue
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# BLOCCO REMOTO: APPEND CONCORRENTE SU users.txt
# Formato riga come da codice originale:
# targetUser,timestamp,instanceId
# ──────────────────────────────────────────────────────────────────────────────

$appendUserBlock = {
    param(
        [string]$targetUser,
        [string]$instanceId,
        [string]$queuePath,
        [string]$usersFileName,
        [string]$lockFileName,
        [int]$thresholdHour
    )

    $usersFilePath = Join-Path $queuePath $usersFileName
    $lockFilePath  = Join-Path $queuePath $lockFileName

    if (-not (Test-Path $queuePath)) {
        try {
            New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
            Write-Output "[REMOTE][INFO] Directory creata: $queuePath"
        }
        catch {
            Write-Output "[REMOTE][ERROR] Impossibile creare la directory: $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-Output "[REMOTE][INFO] Directory trovata: $queuePath"
    }

    Write-Output "[REMOTE][INFO] Acquisizione lock: $lockFilePath"

    $lockAcquired = $false
    $maxRetries   = 50
    $retryCount   = 0
    $lockHandle   = $null

    while (-not $lockAcquired -and $retryCount -lt $maxRetries) {
        try {
            $lockHandle   = [System.IO.File]::Open($lockFilePath, 'CreateNew', 'Write', 'None')
            $lockAcquired = $true
        }
        catch {
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
        $now = Get-Date

        if ($now.Hour -lt $thresholdHour) {
            $timestamp = $now.ToString("yyyy-MM-dd")
        }
        else {
            $timestamp = $now.AddDays(1).ToString("yyyy-MM-dd")
        }

        # Formato identico al task originale:
        # user,date,instanceId
        # Se instanceId è vuoto, la riga termina con la virgola finale.
        $line = "$targetUser,$timestamp,$instanceId"

        Add-Content -Path $usersFilePath -Value $line -Encoding UTF8 -ErrorAction Stop

        Write-Output "[REMOTE][SUCCESS] Riga accodata su $usersFilePath"
        Write-Output "[REMOTE][INFO] Contenuto aggiunto: $line"

        $fileSize = (Get-Item $usersFilePath).Length

        return [PSCustomObject]@{
            Status     = "Success"
            FilePath   = $usersFilePath
            User       = $targetUser
            Timestamp  = $timestamp
            InstanceId = $instanceId
            FileSize   = $fileSize
        }
    }
    finally {
        if ($lockHandle) {
            $lockHandle.Close()
            $lockHandle.Dispose()
        }

        if (Test-Path $lockFilePath) {
            Remove-Item $lockFilePath -Force -ErrorAction SilentlyContinue
            Write-Output "[REMOTE][INFO] Lock rilasciato"
        }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# ESECUZIONE REMOTA
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] Accodamento utente su users.txt..."

try {
    $rawOutput = Invoke-Command -Session $session -ScriptBlock $appendUserBlock `
        -ArgumentList `
            $catalog_targetUser, `
            $catalog_instanceId, `
            $remoteIncomingPath, `
            $remoteUsersFile, `
            $remoteLockFile, `
            $thresholdHour `
        -ErrorAction Stop

    Write-RemoteLog -RemoteOutput ($rawOutput | Where-Object { $_ -is [string] })

    $result = $rawOutput | Where-Object { $_ -isnot [string] } | Select-Object -Last 1

    if (-not $result -or $result.Status -ne "Success") {
        Write-Output "[ERROR] Il blocco remoto non ha restituito un risultato valido"

        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }

        exit 1
    }

    Write-Output "[SUCCESS] Utente accodato correttamente"
    Write-Output "[INFO] File remoto : $($result.FilePath)"
    Write-Output "[INFO] Utente      : $($result.User)"
    Write-Output "[INFO] Timestamp   : $($result.Timestamp)"
    Write-Output "[INFO] InstanceId  : $($result.InstanceId)"
    Write-Output "[INFO] File size   : $($result.FileSize) byte"
}
catch {
    Write-Output "[ERROR] Errore durante l'accodamento utente: $($_.Exception.Message)"

    if ($session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }

    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# CLEANUP SESSIONE
# ──────────────────────────────────────────────────────────────────────────────

if ($session) {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
}

Write-Output "[INFO] Sessione chiusa"
Write-Output "[SUCCESS] Processo completato"
exit 0