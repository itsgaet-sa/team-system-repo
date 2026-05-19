# Autore: G.ABBATICCHIO
# Revisione: 0.1
# Data: 19/05/2026
# Code: deso_efc_user_migration_validation
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Valida i soli valori ricevuti dal Catalog Item.
#              Nessun collegamento con instance.
#              Nessun aggiornamento customOptions su Morpheus.

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONI DI SUPPORTO LOG
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

function Add-ValidationError {
    param([string]$Message)

    $script:validationErrors += $Message
    Write-Output "[ERROR] $Message"
}

function Test-Required {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Add-ValidationError "$Name è required ma non risulta valorizzato"
        return $false
    }

    return $true
}

function Test-AllowedValue {
    param(
        [string]$Name,
        [string]$Value,
        [string[]]$AllowedValues
    )

    if ($AllowedValues -notcontains $Value) {
        Add-ValidationError "$Name valorizzato con valore non ammesso: $(Format-Value $Value). Valori ammessi: $($AllowedValues -join ', ')"
        return $false
    }

    return $true
}

function Test-IPv4Address {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $ipAddress = $null

    if (-not [System.Net.IPAddress]::TryParse($Value, [ref]$ipAddress)) {
        Add-ValidationError "$Name deve essere un indirizzo IP valido. Valore ricevuto: $(Format-Value $Value)"
        return $false
    }

    if ($ipAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        Add-ValidationError "$Name deve essere un indirizzo IPv4 valido. Valore ricevuto: $(Format-Value $Value)"
        return $false
    }

    return $true
}

function Test-NumericId {
    param(
        [string]$Name,
        [string]$Value
    )

    if ($Value -notmatch '^[0-9]+$') {
        Add-ValidationError "$Name deve essere un id numerico. Valore ricevuto: $(Format-Value $Value)"
        return $false
    }

    return $true
}

function Test-Username {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    # Nome utente: lettere, numeri, punto, underscore, trattino.
    # Ammesso anche formato dominio\utente.
    if ($Value -notmatch '^[A-Za-z0-9._-]+(\\[A-Za-z0-9._-]+)?$') {
        Add-ValidationError "$Name deve essere un nome utente valido. Valore ricevuto: $(Format-Value $Value)"
        return $false
    }

    return $true
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

Write-Output "[INFO] ===== START VALIDATION CATALOG ITEM MIGRAZIONE ====="

Write-Output ""
Write-Output "[INFO] ----- VALORI RICEVUTI DAL CATALOG ITEM -----"
Write-Line -Label "Catalog migrationType"     -Value $catalog_migrationType
Write-Line -Label "Catalog migrationMode"     -Value $catalog_migrationMode
Write-Line -Label "Catalog sourceServer"      -Value $catalog_sourceServer
Write-Line -Label "Catalog destinationServer" -Value $catalog_destinationServer
Write-Line -Label "Catalog targetUser"        -Value $catalog_targetUser
Write-Line -Label "Catalog instanceId"        -Value $catalog_instanceId

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE migrationType
# required, può essere m2m o m2s
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE migrationType -----"

if (Test-Required -Name "migrationType" -Value $catalog_migrationType) {
    Test-AllowedValue -Name "migrationType" -Value $catalog_migrationType -AllowedValues @("m2m", "m2s") | Out-Null
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE migrationMode
# required, può essere instant o planned
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE migrationMode -----"

if (Test-Required -Name "migrationMode" -Value $catalog_migrationMode) {
    Test-AllowedValue -Name "migrationMode" -Value $catalog_migrationMode -AllowedValues @("instant", "planned") | Out-Null
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE sourceServer
# required, è un indirizzo IP
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE sourceServer -----"

if (Test-Required -Name "sourceServer" -Value $catalog_sourceServer) {
    Test-IPv4Address -Name "sourceServer" -Value $catalog_sourceServer | Out-Null
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE destinationServer
# opzionale se instanceId è popolato
# required se instanceId non popolato
# se valorizzato, deve essere un indirizzo IP
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE destinationServer -----"

if ([string]::IsNullOrWhiteSpace($catalog_instanceId)) {
    if (Test-Required -Name "destinationServer" -Value $catalog_destinationServer) {
        Test-IPv4Address -Name "destinationServer" -Value $catalog_destinationServer | Out-Null
    }
}
else {
    Write-Output "[INFO] destinationServer opzionale perché instanceId è valorizzato"

    if (-not [string]::IsNullOrWhiteSpace($catalog_destinationServer)) {
        Test-IPv4Address -Name "destinationServer" -Value $catalog_destinationServer | Out-Null
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE targetUser
# required, è un nome utente
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE targetUser -----"

if (Test-Required -Name "targetUser" -Value $catalog_targetUser) {
    Test-Username -Name "targetUser" -Value $catalog_targetUser | Out-Null
}

# ──────────────────────────────────────────────────────────────────────────────
# VALIDAZIONE instanceId
# se migrationType è m2s, required ed è un id numerico
# altrimenti deve essere nullo
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- VALIDAZIONE instanceId -----"

if ($catalog_migrationType -eq "m2s") {
    if (Test-Required -Name "instanceId" -Value $catalog_instanceId) {
        Test-NumericId -Name "instanceId" -Value $catalog_instanceId | Out-Null
    }
}
elseif ($catalog_migrationType -eq "m2m") {
    if (-not [string]::IsNullOrWhiteSpace($catalog_instanceId)) {
        Add-ValidationError "instanceId deve essere nullo quando migrationType è m2m. Valore ricevuto: $(Format-Value $catalog_instanceId)"
    }
}
else {
    Write-Output "[WARN] Validazione instanceId parziale: migrationType non valido o non valorizzato"
}

# ──────────────────────────────────────────────────────────────────────────────
# ESITO VALIDAZIONE
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""

if ($validationErrors.Count -gt 0) {
    Write-Output "[ERROR] ===== VALIDATION FAILED ====="
    Write-Output "[ERROR] Numero errori rilevati: $($validationErrors.Count)"

    for ($i = 0; $i -lt $validationErrors.Count; $i++) {
        Write-Output "[ERROR] $($i + 1). $($validationErrors[$i])"
    }

    exit 1
}

Write-Output "[SUCCESS] Validation Catalog Item completata con esito positivo"
exit 0