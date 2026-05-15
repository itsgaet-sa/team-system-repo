# Autore: G.ABBATICCHIO
# Revisione: 3.0
# Data: 15/05/2026
# Code: deso_efc_user_disconnect_queue
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Accoda un utente da disconnettere nel file users.txt sul dispatcher.
#              Parametri Catalog:
#              - needMigration  -> se true scrive su users.txt
#              - userToMigrate  -> nome utente da accodare
#              Nessuna migrazione viene avviata.
#              Scrittura concorrente gestita tramite lock file.

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONI DI SUPPORTO
# ──────────────────────────────────────────────────────────────────────────────

function Write-RemoteLog {
    param([object[]]$RemoteOutput)

    foreach ($line in $RemoteOutput) {
        if ($line -is [string]) {
            Write-Output $line
        }
    }
}

function To-BoolString {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "false"
    }

    return $Value.Trim().ToLowerInvariant()
}

# ──────────────────────────────────────────────────────────────────────────────
# PARAMETRI CATALOG
# ──────────────────────────────────────────────────────────────────────────────

$needMigrationRaw = "<%=customOptions.needMigration%>"
$userToMigrate    = "<%=customOptions.userToMigrate%>"

$needMigration = To-BoolString $needMigrationRaw

Write-Output "[INFO] =========================================="
Write-Output "[INFO] ACCODAMENTO UTENTE PER DISCONNESSIONE"
Write-Output "[INFO] =========================================="
Write-Output "[INFO] needMigration : '$needMigration'"
Write-Output "[INFO] userToMigrate : '$userToMigrate'"

# ──────────────────────────────────────────────────────────────────────────────
# SE needMigration NON È true, NON FARE NULLA
# ──────────────────────────────────────────────────────────────────────────────

if ($needMigration -ne "true") {
    Write-Output "[INFO] needMigration diverso da true - nessuna azione richiesta"
    Write-Output "[SUCCESS] Nessun utente accodato"
    exit 0
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE PARAMETRI
# ──────────────────────────────────────────────────────────────────────────────

if ([string]::IsNullOrWhiteSpace($userToMigrate)) {
    Write-Output "[ERROR] Parametro userToMigrate mancante o vuoto"
    exit 1
}

$userToMigrate = $userToMigrate.Trim()

# ──────────────────────────────────────────────────────────────────────────────
# CREDENZIALI DA CYPHER
# EFC-TS_MIG_DANEA-USR → username in chiaro
# EFC-TS_MIG_DANEA_SSH → chiave privata SSH codificata in Base64
# ──────────────────────────────────────────────────────────────────────────────

$migrationUserRaw   = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-USR",true)%>'
$migrationKeyBase64 = '<%=cypher.read("secret/EFC-TS_MIG_DANEA_SSH",true)%>'

if ([string]::IsNullOrWhiteSpace($migrationUserRaw) -or [string]::IsNullOrWhiteSpace($migrationKeyBase64)) {
    Write-Output "[ERROR] Credenziali dispatcher non disponibili dal Cypher"
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# PATH REMOTO SUL DISPATCHER
# Per ora viene usata la folder incoming esistente.
# ──────────────────────────────────────────────────────────────────────────────

$migrationServerIP  = "10.182.1.11"
$remoteIncomingPath = "D:\tools\migration-tool-st\incoming"
$remoteUsersFile    = "users.txt"
$remoteLockFile     = "users.lock"

Write-Output "[INFO] Dispatcher      : $migrationServerIP"
Write-Output "[INFO] Remote folder   : $remoteIncomingPath"
Write-Output "[INFO] Remote file     : $remoteUsersFile"

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
# ──────────────────────────────────────────────────────────────────────────────

$appendUserBlock = {
    param(
        [string]$userToMigrate,
        [string]$queuePath,
        [string]$usersFileName,
        [string]$lockFileName
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
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line      = "$userToMigrate,$timestamp"

        Add-Content -Path $usersFilePath -Value $line -Encoding UTF8 -ErrorAction Stop

        Write-Output "[REMOTE][SUCCESS] Riga accodata su $usersFilePath"
        Write-Output "[REMOTE][INFO] Contenuto aggiunto: $line"

        $fileSize = (Get-Item $usersFilePath).Length

        return [PSCustomObject]@{
            Status    = "Success"
            FilePath  = $usersFilePath
            User      = $userToMigrate
            Timestamp = $timestamp
            FileSize  = $fileSize
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

Write-Output "[INFO] Accodamento utente su users.txt..."

try {
    $rawOutput = Invoke-Command -Session $session -ScriptBlock $appendUserBlock `
        -ArgumentList $userToMigrate, $remoteIncomingPath, $remoteUsersFile, $remoteLockFile `
        -ErrorAction Stop

    Write-RemoteLog -RemoteOutput ($rawOutput | Where-Object { $_ -is [string] })

    $result = $rawOutput | Where-Object { $_ -isnot [string] } | Select-Object -Last 1

    if (-not $result -or $result.Status -ne "Success") {
        Write-Output "[ERROR] Il blocco remoto non ha restituito un risultato valido"
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        exit 1
    }

    Write-Output "[SUCCESS] Utente accodato correttamente"
    Write-Output "[INFO] File remoto : $($result.FilePath)"
    Write-Output "[INFO] Utente      : $($result.User)"
    Write-Output "[INFO] Timestamp   : $($result.Timestamp)"
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
