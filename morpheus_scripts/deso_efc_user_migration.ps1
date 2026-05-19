# Autore: G.ABBATICCHIO
# Revisione: 0.1
# Data: 19/05/2026
# Code: deso_efc_user_migration_catalog_queue
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Preparazione migrazione utente tramite dati ricevuti solo dal Catalog Item.
#              Crea il file dichiarativo sul dispatcher.
#              Se migrationMode = instant, accoda su incoming e avvia il dispatcher.
#              Se migrationMode = planned, accoda su incoming-scheduled e non avvia il dispatcher.
#              Nessun collegamento con instance.
#              Nessuna chiamata API Morpheus.
#              Nessun aggiornamento customOptions su Morpheus.

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
# MAPPING DATI CATALOG → VARIABILI LOGICA MIGRAZIONE
# ──────────────────────────────────────────────────────────────────────────────
# Vecchia logica:
#   fromUser   = customOptions.fromUser
#   fromServer = customOptions.fromServer
#   toServer   = instance.containers[0].server.internalIp
#   migrateNow = customOptions.MigrateNow
#
# Nuova logica:
#   fromUser   = customOptions.targetUser
#   fromServer = customOptions.sourceServer
#   toServer   = customOptions.destinationServer, se presente
#              = customOptions.instanceId, se destinationServer non presente
#   migrateNow = false se migrationMode = planned
#              = true  se migrationMode = instant
# ──────────────────────────────────────────────────────────────────────────────

$fromUser   = $catalog_targetUser
$fromServer = $catalog_sourceServer

if (-not [string]::IsNullOrWhiteSpace($catalog_destinationServer)) {
    $toServer = $catalog_destinationServer
}
else {
    $toServer = $catalog_instanceId
}

$migrateNow = $null

if ($catalog_migrationMode -eq "planned") {
    $migrateNow = "false"
}
elseif ($catalog_migrationMode -eq "instant") {
    $migrateNow = "true"
}

# Nome logico, non letto da instance
$instanceName = "catalog-migration-$catalog_targetUser"

# ──────────────────────────────────────────────────────────────────────────────
# CREDENZIALI DA CYPHER
# EFC-TS_MIG_DANEA-USR → username in chiaro
# EFC-TS_MIG_DANEA_SSH → chiave privata SSH codificata in Base64 oppure PEM grezzo
# ──────────────────────────────────────────────────────────────────────────────

$migrationUserRaw   = '<%=cypher.read("secret/EFC-TS_MIG_DANEA-USR",true)%>'
$migrationKeyBase64 = '<%=cypher.read("secret/EFC-TS_MIG_DANEA_SSH",true)%>'

# ──────────────────────────────────────────────────────────────────────────────
# PATH REMOTI SUL DISPATCHER
# ──────────────────────────────────────────────────────────────────────────────

$migrationServerIP = "10.182.1.11"

$remoteIncomingPath          = "D:\tools\migration-tool-st\incoming"
$remoteIncomingScheduledPath = "D:\tools\migration-tool-st-planned\incoming"
$remoteQueuePath             = ""

if ($migrateNow -eq "false") {
    $remoteQueuePath = $remoteIncomingScheduledPath
}
elseif ($migrateNow -eq "true") {
    $remoteQueuePath = $remoteIncomingPath
}

$remoteDispatcher = "D:\tools\migration-tool-st\dispatcher.ps1"

# ──────────────────────────────────────────────────────────────────────────────
# INIZIO SCRIPT
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] =========================================="
Write-Output "[INFO] MIGRAZIONE UTENTE DA CATALOG ITEM"
Write-Output "[INFO] =========================================="

Write-Output ""
Write-Output "[INFO] ----- VALORI RICEVUTI DAL CATALOG ITEM -----"
Write-Line -Label "Catalog migrationType"     -Value $catalog_migrationType
Write-Line -Label "Catalog migrationMode"     -Value $catalog_migrationMode
Write-Line -Label "Catalog sourceServer"      -Value $catalog_sourceServer
Write-Line -Label "Catalog destinationServer" -Value $catalog_destinationServer
Write-Line -Label "Catalog targetUser"        -Value $catalog_targetUser
Write-Line -Label "Catalog instanceId"        -Value $catalog_instanceId

Write-Output ""
Write-Output "[INFO] ----- MAPPING VARIABILI MIGRAZIONE -----"
Write-Line -Label "fromUser"   -Value $fromUser
Write-Line -Label "fromServer" -Value $fromServer
Write-Line -Label "toServer"   -Value $toServer
Write-Line -Label "migrateNow" -Value $migrateNow

if ($migrateNow -eq "false") {
    Write-Output "[INFO] migrationMode = planned → migrateNow = false → migrazione schedulata"
}
elseif ($migrateNow -eq "true") {
    Write-Output "[INFO] migrationMode = instant → migrateNow = true → migrazione immediata"
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE DATI CATALOG
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE DATI CATALOG -----"

if ([string]::IsNullOrWhiteSpace($catalog_migrationType)) {
    Add-ValidationError "migrationType mancante"
}
elseif ($catalog_migrationType -ne "m2m" -and $catalog_migrationType -ne "m2s") {
    Add-ValidationError "migrationType non valido: $(Format-Value $catalog_migrationType). Valori ammessi: m2m, m2s"
}

if ([string]::IsNullOrWhiteSpace($catalog_migrationMode)) {
    Add-ValidationError "migrationMode mancante"
}
elseif ($catalog_migrationMode -ne "instant" -and $catalog_migrationMode -ne "planned") {
    Add-ValidationError "migrationMode non valido: $(Format-Value $catalog_migrationMode). Valori ammessi: instant, planned"
}

if ([string]::IsNullOrWhiteSpace($fromUser)) {
    Add-ValidationError "targetUser mancante"
}

if ([string]::IsNullOrWhiteSpace($fromServer)) {
    Add-ValidationError "sourceServer mancante"
}

if ([string]::IsNullOrWhiteSpace($toServer)) {
    Add-ValidationError "destinationServer o instanceId mancante: impossibile valorizzare toServer"
}

if ($catalog_migrationType -eq "m2s" -and [string]::IsNullOrWhiteSpace($catalog_instanceId)) {
    Add-ValidationError "instanceId mancante per migrationType m2s"
}

if ($catalog_migrationType -eq "m2m" -and -not [string]::IsNullOrWhiteSpace($catalog_instanceId)) {
    Add-ValidationError "instanceId deve essere vuoto per migrationType m2m"
}

if ([string]::IsNullOrWhiteSpace($migrateNow)) {
    Add-ValidationError "migrateNow non calcolabile da migrationMode $(Format-Value $catalog_migrationMode)"
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
# VALIDAZIONE CREDENZIALI
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE CREDENZIALI DISPATCHER -----"

if ([string]::IsNullOrWhiteSpace($migrationUserRaw) -or [string]::IsNullOrWhiteSpace($migrationKeyBase64)) {
    Write-Output "[ERROR] Credenziali migrazione non disponibili dal Cypher, user o chiave vuoti"
    exit 1
}

$migrationUserRaw = $migrationUserRaw.Trim()

Write-Output "[INFO] Credenziali dispatcher disponibili"

Write-Output ""
Write-Output "[INFO] =========================================="
Write-Output "[INFO] MIGRAZIONE RICHIESTA - Avvio processo"
Write-Output "[INFO] - Utente origine  : $fromUser"
Write-Output "[INFO] - Server origine  : $fromServer"
Write-Output "[INFO] - Server destino  : $toServer"
Write-Output "[INFO] - Dispatcher      : $migrationServerIP"
Write-Output "[INFO] - Queue path      : $remoteQueuePath"
Write-Output "[INFO] =========================================="

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
# BLOCCO REMOTO: CREAZIONE FILE DI CODA
# ──────────────────────────────────────────────────────────────────────────────

$createQueueBlock = {
    param(
        [string]$fromUser,
        [string]$fromServer,
        [string]$toServer,
        [string]$queuePath
    )

    $lockFile = Join-Path (Split-Path $queuePath -Parent) "queue.lock"

    if (-not (Test-Path $queuePath)) {
        try {
            New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
            Write-Output "[REMOTE][INFO] Directory di coda creata: $queuePath"
        }
        catch {
            Write-Output "[REMOTE][ERROR] Impossibile creare la directory di coda: $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-Output "[REMOTE][INFO] Directory di coda trovata: $queuePath"
    }

    Write-Output "[REMOTE][INFO] Acquisizione lock..."

    $lockAcquired = $false
    $maxRetries   = 10
    $retryCount   = 0
    $lockHandle   = $null

    while (-not $lockAcquired -and $retryCount -lt $maxRetries) {
        try {
            $lockHandle   = [System.IO.File]::Open($lockFile, 'CreateNew', 'Write', 'None')
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
        $existingFiles = Get-ChildItem -Path $queuePath -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^migra-(\d+)\.(txt|done|fail|txt\.work)$' } |
            ForEach-Object {
                if ($_.Name -match '^migra-(\d+)') {
                    [int]$Matches[1]
                }
            } |
            Sort-Object -Descending

        $nextSequence = if ($existingFiles) { $existingFiles[0] + 1 } else { 1 }
        $queueFileName = "migra-{0:D6}.txt" -f $nextSequence
        $queueFilePath = Join-Path $queuePath $queueFileName

        # Formato identico alla logica originale:
        # fromUser|fromServer|toServer
        $queueContent = "${fromUser}|${fromServer}|${toServer}"

        Write-Output "[REMOTE][INFO] Sequenza: $nextSequence → $queueFileName"
        Write-Output "[REMOTE][INFO] Contenuto: $queueContent"

        Set-Content -Path $queueFilePath -Value $queueContent -Force -ErrorAction Stop

        if (-not (Test-Path $queueFilePath)) {
            throw "File '$queueFilePath' non trovato dopo la creazione"
        }

        $fileSize = (Get-Item $queueFilePath).Length

        Write-Output "[REMOTE][SUCCESS] File creato ($fileSize byte): $queueFilePath"

        return [PSCustomObject]@{
            FilePath = $queueFilePath
            FileName = $queueFileName
            Sequence = $nextSequence
            Status   = "Success"
        }
    }
    finally {
        if ($lockHandle) {
            $lockHandle.Close()
            $lockHandle.Dispose()
        }

        if (Test-Path $lockFile) {
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
            Write-Output "[REMOTE][INFO] Lock rilasciato"
        }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# CREAZIONE FILE DI CODA
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] Creazione file di coda sul dispatcher..."

try {
    $rawOutput = Invoke-Command -Session $session -ScriptBlock $createQueueBlock `
        -ArgumentList $fromUser, $fromServer, $toServer, $remoteQueuePath `
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

    Write-Output "[SUCCESS] File di migrazione accodato: $($result.FilePath)"
}
catch {
    Write-Output "[ERROR] Errore durante la creazione del file di coda: $($_.Exception.Message)"

    if ($session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }

    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# AVVIO TASK SCHEDULATO DEL DISPATCHER
# Solo se migrationMode = instant → migrateNow = true
# ──────────────────────────────────────────────────────────────────────────────

if ($migrateNow -eq "true") {

    $startDispatcherTaskBlock = {
        param(
            [string]$taskName,
            [string]$taskPath
        )

        Write-Output "[REMOTE][INFO] Avvio task schedulato '$taskName' Path '$taskPath'..."

        try {
            Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
            Write-Output "[REMOTE][SUCCESS] Task '$taskName' avviato correttamente"
        }
        catch {
            Write-Output "[REMOTE][ERROR] Impossibile avviare il task '$taskName': $($_.Exception.Message)"
            throw
        }
    }

    Write-Output ""
    Write-Output "[INFO] migrationMode instant: avvio task schedulato del dispatcher..."

    try {
        $taskName = "dispatcher-st"
        $taskPath = "\"

        $taskOutput = Invoke-Command -Session $session -ScriptBlock $startDispatcherTaskBlock `
            -ArgumentList $taskName, $taskPath `
            -ErrorAction Stop

        Write-RemoteLog -RemoteOutput $taskOutput
    }
    catch {
        Write-Output "[ERROR] Errore durante l'avvio del task schedulato sul dispatcher: $($_.Exception.Message)"

        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }

        exit 1
    }

    # ──────────────────────────────────────────────────────────────────────────
    # MONITORAGGIO STATO MIGRAZIONE
    # Solo per instant, come da logica originale
    # ──────────────────────────────────────────────────────────────────────────

    $queueFileName     = $result.FileName
    $queueFileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($queueFileName)

    Write-Output ""
    Write-Output "[INFO] =========================================="
    Write-Output "[INFO] Monitoraggio migrazione in corso..."
    Write-Output "[INFO] =========================================="

    $monitoringMaxTime  = 5400
    $monitoringInterval = 10
    $elapsedTime        = 0
    $migrationCompleted = $false
    $lastStatus         = ""

    $monitorBlock = {
        param(
            [string]$baseName,
            [string]$qPath
        )

        $doneFile = Join-Path $qPath "$baseName.done"
        $errFile  = Join-Path $qPath "$baseName.fail"
        $workFile = Join-Path $qPath "$baseName.txt.work"
        $txtFile  = Join-Path $qPath "$baseName.txt"

        if (Test-Path $doneFile) {
            return [PSCustomObject]@{
                Status       = "completed"
                FilePath     = $doneFile
                ErrorMessage = $null
            }
        }
        elseif (Test-Path $errFile) {
            $errMsg = Get-Content $errFile -Raw -ErrorAction SilentlyContinue

            return [PSCustomObject]@{
                Status       = "failed"
                FilePath     = $errFile
                ErrorMessage = $errMsg
            }
        }
        elseif (Test-Path $workFile) {
            return [PSCustomObject]@{
                Status       = "running"
                FilePath     = $workFile
                ErrorMessage = $null
            }
        }
        elseif (Test-Path $txtFile) {
            return [PSCustomObject]@{
                Status       = "running"
                FilePath     = $txtFile
                ErrorMessage = $null
            }
        }
        else {
            return [PSCustomObject]@{
                Status       = "failed"
                FilePath     = $null
                ErrorMessage = "File di migrazione non trovato sul dispatcher"
            }
        }
    }

    while ($elapsedTime -lt $monitoringMaxTime -and -not $migrationCompleted) {
        try {
            $fileStatus = Invoke-Command -Session $session -ScriptBlock $monitorBlock `
                -ArgumentList $queueFileBaseName, $remoteQueuePath `
                -ErrorAction Stop

            $currentStatus = $fileStatus.Status

            if ($currentStatus -ne $lastStatus) {
                Write-Output "[INFO] Cambio stato: '$lastStatus' → '$currentStatus' (${elapsedTime}s)"
                $lastStatus = $currentStatus
            }
            else {
                Write-Output "[INFO] Stato: $currentStatus | Tempo trascorso: ${elapsedTime}s"
            }

            switch ($currentStatus.ToLower()) {
                "completed" {
                    Write-Output "[SUCCESS] =========================================="
                    Write-Output "[SUCCESS] Migrazione completata con successo"
                    Write-Output "[SUCCESS] =========================================="
                    $migrationCompleted = $true
                }

                "failed" {
                    $errorMsg = if ($fileStatus.ErrorMessage) {
                        $fileStatus.ErrorMessage.Trim()
                    }
                    else {
                        "Errore non specificato"
                    }

                    Write-Output "[ERROR] =========================================="
                    Write-Output "[ERROR] Migrazione fallita"
                    Write-Output "[ERROR] Dettaglio: $errorMsg"
                    Write-Output "[ERROR] =========================================="

                    $migrationCompleted = $true

                    if ($session) {
                        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                    }

                    exit 1
                }

                "running" {
                    # Nessuna azione aggiuntiva: solo polling
                }

                default {
                    Write-Output "[WARNING] Stato non previsto: $currentStatus"
                }
            }

            if (-not $migrationCompleted) {
                Start-Sleep -Seconds $monitoringInterval
                $elapsedTime += $monitoringInterval
            }
        }
        catch {
            Write-Output "[WARNING] Errore nel polling: $($_.Exception.Message)"
            Start-Sleep -Seconds $monitoringInterval
            $elapsedTime += $monitoringInterval
        }
    }

    if (-not $migrationCompleted) {
        Write-Output "[WARNING] =========================================="
        Write-Output "[WARNING] Timeout raggiunto dopo $monitoringMaxTime secondi"
        Write-Output "[WARNING] Verifica manuale richiesta: $queueFileName"
        Write-Output "[WARNING] =========================================="

        if ($session) {
            Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        }

        exit 1
    }
}
else {
    Write-Output ""
    Write-Output "[INFO] migrationMode planned: file accodato in incoming-scheduled"
    Write-Output "[INFO] Dispatcher non avviato"
    Write-Output "[SUCCESS] Migrazione schedulata correttamente"
}

# ──────────────────────────────────────────────────────────────────────────────
# CLEANUP SESSIONE
# ──────────────────────────────────────────────────────────────────────────────

if ($session) {
    Remove-PSSession -Session $session -ErrorAction SilentlyContinue
}

Write-Output "[INFO] Sessione chiusa"
Write-Output "[SUCCESS] Processo di migrazione terminato"
exit 0