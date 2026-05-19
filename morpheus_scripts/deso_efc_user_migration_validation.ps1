# Autore: G.ABBATICCHIO
# Revisione: 0.2
# Data: 19/05/2026
# Code: deso_efc_user_migration_validation
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Valida i valori ricevuti dal Catalog Item.
#              Verifica inoltre che instanceId, se valorizzato/richiesto,
#              sia presente su Morpheus e riferito a una instance deployata.
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

function Invoke-MorpheusGetInstance {
    param(
        [string]$InstanceId,
        [string]$ApplianceUrl,
        [string]$AccessToken
    )

    $baseUrl = $ApplianceUrl.TrimEnd("/")
    $uri     = "$baseUrl/api/instances/$InstanceId"

    Write-Output "[INFO] Verifica presenza instanceId su Morpheus tramite GET /api/instances/$InstanceId"

    $headers = @{
        "Authorization" = "BEARER $AccessToken"
        "Accept"        = "application/json"
    }

    try {
        $response = Invoke-RestMethod `
            -Method Get `
            -Uri $uri `
            -Headers $headers `
            -ContentType "application/json"

        return $response
    }
    catch {
        $statusCode = $null

        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        if ($statusCode -eq 404) {
            Add-ValidationError "instanceId $(Format-Value $InstanceId) non presente su Morpheus"
        }
        elseif ($statusCode -eq 401 -or $statusCode -eq 403) {
            Add-ValidationError "Impossibile verificare instanceId $(Format-Value $InstanceId): token Morpheus non autorizzato. HTTP $statusCode"
        }
        elseif ($statusCode) {
            Add-ValidationError "Errore durante verifica instanceId $(Format-Value $InstanceId) su Morpheus. HTTP $statusCode"
        }
        else {
            Add-ValidationError "Errore durante verifica instanceId $(Format-Value $InstanceId) su Morpheus: $($_.Exception.Message)"
        }

        return $null
    }
}

function Test-MorpheusInstanceDeployed {
    param(
        [string]$InstanceId,
        [object]$ApiResponse
    )

    if ($null -eq $ApiResponse) {
        return $false
    }

    if ($null -eq $ApiResponse.instance) {
        Add-ValidationError "Risposta Morpheus non valida: oggetto 'instance' non presente per instanceId $(Format-Value $InstanceId)"
        return $false
    }

    $instance = $ApiResponse.instance

    if ([string]$instance.id -ne [string]$InstanceId) {
        Add-ValidationError "instanceId restituito da Morpheus non coincide. Richiesto: $(Format-Value $InstanceId), ricevuto: $(Format-Value ([string]$instance.id))"
        return $false
    }

    $instanceName   = [string]$instance.name
    $instanceStatus = [string]$instance.status

    Write-Line -Label "Morpheus instance.id"     -Value ([string]$instance.id)
    Write-Line -Label "Morpheus instance.name"   -Value $instanceName
    Write-Line -Label "Morpheus instance.status" -Value $instanceStatus

    # Stati considerati validi per una instance effettivamente deployata.
    # Se nel vostro ambiente Morpheus usate altri stati validi, aggiungerli qui.
    $allowedDeployedStatuses = @(
        "running",
        "stopped"
    )

    if ([string]::IsNullOrWhiteSpace($instanceStatus)) {
        Add-ValidationError "instanceId $(Format-Value $InstanceId) presente su Morpheus ma senza status valorizzato"
        return $false
    }

    if ($allowedDeployedStatuses -notcontains $instanceStatus.ToLower()) {
        Add-ValidationError "instanceId $(Format-Value $InstanceId) presente su Morpheus ma non in stato deployato valido. Status ricevuto: $(Format-Value $instanceStatus). Stati ammessi: $($allowedDeployedStatuses -join ', ')"
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

# Valori Morpheus per chiamata API
$morpheus_applianceUrl = "<%=morpheus.applianceUrl%>"
$morpheus_accessToken  = "<%=morpheus.apiAccessToken%>"

# Normalizzazione valori ricevuti
$catalog_migrationType     = $catalog_migrationType.Trim().ToLower()
$catalog_migrationMode     = $catalog_migrationMode.Trim().ToLower()
$catalog_sourceServer      = $catalog_sourceServer.Trim()
$catalog_destinationServer = $catalog_destinationServer.Trim()
$catalog_targetUser        = $catalog_targetUser.Trim()
$catalog_instanceId        = $catalog_instanceId.Trim()

$morpheus_applianceUrl = $morpheus_applianceUrl.Trim()
$morpheus_accessToken  = $morpheus_accessToken.Trim()

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

Write-Output ""
Write-Output "[INFO] ----- PARAMETRI MORPHEUS API -----"
Write-Line -Label "Morpheus applianceUrl" -Value $morpheus_applianceUrl

if ([string]::IsNullOrWhiteSpace($morpheus_accessToken)) {
    Write-Line -Label "Morpheus apiAccessToken" -Value ""
}
else {
    Write-Output "[INFO] Morpheus apiAccessToken = <valorizzato>"
}

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

$instanceIdIsValidForApiCheck = $false

if ($catalog_migrationType -eq "m2s") {
    if (Test-Required -Name "instanceId" -Value $catalog_instanceId) {
        if (Test-NumericId -Name "instanceId" -Value $catalog_instanceId) {
            $instanceIdIsValidForApiCheck = $true
        }
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
# CHECK MORPHEUS INSTANCE
# Verifica che instanceId sia presente e deployato su Morpheus
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- CHECK MORPHEUS INSTANCE -----"

if ($instanceIdIsValidForApiCheck) {

    if ([string]::IsNullOrWhiteSpace($morpheus_applianceUrl)) {
        Add-ValidationError "Impossibile verificare instanceId: morpheus.applianceUrl non valorizzato"
    }

    if ([string]::IsNullOrWhiteSpace($morpheus_accessToken)) {
        Add-ValidationError "Impossibile verificare instanceId: morpheus.apiAccessToken non valorizzato"
    }

    if (
        -not [string]::IsNullOrWhiteSpace($morpheus_applianceUrl) -and
        -not [string]::IsNullOrWhiteSpace($morpheus_accessToken)
    ) {
        $instanceResponse = Invoke-MorpheusGetInstance `
            -InstanceId $catalog_instanceId `
            -ApplianceUrl $morpheus_applianceUrl `
            -AccessToken $morpheus_accessToken

        Test-MorpheusInstanceDeployed `
            -InstanceId $catalog_instanceId `
            -ApiResponse $instanceResponse | Out-Null
    }
}
else {
    Write-Output "[INFO] Check Morpheus instance non eseguito: instanceId non richiesto o non valido"
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