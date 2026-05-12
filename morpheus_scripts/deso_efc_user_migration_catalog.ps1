# Autore: G.ABBATICCHIO
# Revisione: 0.4
# Data: 12/05/2026
# Code: deso_efc_user_migration_catalog_update_debug
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description:
#   Aggiorna customOptions Morpheus da Catalog Item:
#   - MigrateData sempre true
#   - fromUser da Catalog Item
#   - fromServer da Catalog Item
#   - toServer NON modificato
#   - MigrationStatus a null
#   Poi rilegge l'istanza via API e stampa i valori effettivi.

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONI LOG
# ──────────────────────────────────────────────────────────────────────────────

function Format-Value {
    param($Value)

    if ($null -eq $Value) {
        return "<null>"
    }

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return "<vuoto/non valorizzato>"
    }

    return "'$Value'"
}

function Write-Line {
    param(
        [string]$Label,
        $Value
    )

    Write-Output "[INFO] $Label = $(Format-Value $Value)"
}

function Write-Section {
    param([string]$Title)

    Write-Output ""
    Write-Output "[INFO] =========================================="
    Write-Output "[INFO] $Title"
    Write-Output "[INFO] =========================================="
}

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONE API - GET ISTANZA
# ──────────────────────────────────────────────────────────────────────────────

function Get-MorpheusInstance {
    param(
        [string]$InstanceId,
        [string]$ApiUrl,
        [hashtable]$Headers
    )

    $url = "$ApiUrl/api/instances/$InstanceId"

    return Invoke-RestMethod `
        -Uri $url `
        -Method Get `
        -Headers $Headers `
        -ErrorAction Stop
}

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONE API - UPDATE CUSTOM OPTIONS
# ──────────────────────────────────────────────────────────────────────────────

function Update-MigrationCustomOptions {
    param(
        [string]$InstanceId,
        [string]$ApiUrl,
        [hashtable]$Headers,
        [string]$CatalogFromUser,
        [string]$CatalogFromServer
    )

    $url = "$ApiUrl/api/instances/$InstanceId"

    $body = @{
        instance = @{
            config = @{
                customOptions = @{
                    # Sempre forzato a true
                    MigrateData = $true

                    # Valori ricevuti dal Catalog Item
                    fromUser   = $CatalogFromUser
                    fromServer = $CatalogFromServer

                    # toServer NON viene inviato
                    # quindi NON viene modificato

                    # Reset stato migrazione
                    MigrationStatus = $null
                }
            }
        }
    } | ConvertTo-Json -Depth 20

    Write-Section "BODY INVIATO A MORPHEUS"
    Write-Output $body

    Invoke-RestMethod `
        -Uri $url `
        -Method Put `
        -Headers $Headers `
        -Body $body `
        -ErrorAction Stop | Out-Null

    Write-Output "[INFO] PUT eseguita correttamente su Morpheus"
}

# ──────────────────────────────────────────────────────────────────────────────
# VARIABILI MORPHEUS
# ──────────────────────────────────────────────────────────────────────────────

$instanceId = "<%=instance.id%>"
$apiUrl     = "<%=morpheus.applianceUrl%>"
$token      = "<%=morpheus.apiAccessToken%>"

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
    "Accept"        = "application/json"
}

# ──────────────────────────────────────────────────────────────────────────────
# VALORI DA CATALOG ITEM
# ──────────────────────────────────────────────────────────────────────────────

$catalog_fromUser   = "<%=customOptions.fromUser%>"
$catalog_fromServer = "<%=customOptions.fromServer%>"

# ──────────────────────────────────────────────────────────────────────────────
# VALORI ATTUALI TEMPLATE MORPHEUS
# ──────────────────────────────────────────────────────────────────────────────

$instanceName     = "<%=instance.name%>"
$instanceToServer = "<%=instance.containers[0].server.internalIp%>"

$instance_MigrateData     = "<%=instance.config.customOptions.MigrateData%>"
$instance_fromUser        = "<%=instance.config.customOptions.fromUser%>"
$instance_fromServer      = "<%=instance.config.customOptions.fromServer%>"
$instance_MigrationStatus = "<%=instance.config.customOptions.MigrationStatus%>"

# ──────────────────────────────────────────────────────────────────────────────
# LOG PRIMA UPDATE
# ──────────────────────────────────────────────────────────────────────────────

Write-Section "START UPDATE CUSTOMOPTIONS MIGRAZIONE"

Write-Line -Label "Instance ID"   -Value $instanceId
Write-Line -Label "Instance Name" -Value $instanceName
Write-Line -Label "Internal IP"   -Value $instanceToServer

Write-Section "VALORI ISTANZA PRIMA DELL'UPDATE - TEMPLATE"

Write-Line -Label "Instance MigrateData"     -Value $instance_MigrateData
Write-Line -Label "Instance fromUser"        -Value $instance_fromUser
Write-Line -Label "Instance fromServer"      -Value $instance_fromServer
Write-Line -Label "Instance toServer"        -Value $instanceToServer
Write-Line -Label "Instance MigrationStatus" -Value $instance_MigrationStatus

Write-Section "VALORI RICEVUTI DAL CATALOG ITEM"

Write-Line -Label "Catalog fromUser"   -Value $catalog_fromUser
Write-Line -Label "Catalog fromServer" -Value $catalog_fromServer

# ──────────────────────────────────────────────────────────────────────────────
# UPDATE
# ──────────────────────────────────────────────────────────────────────────────

Write-Section "UPDATE CUSTOMOPTIONS MORPHEUS"

Update-MigrationCustomOptions `
    -InstanceId $instanceId `
    -ApiUrl $apiUrl `
    -Headers $headers `
    -CatalogFromUser $catalog_fromUser `
    -CatalogFromServer $catalog_fromServer

# ──────────────────────────────────────────────────────────────────────────────
# VERIFICA POST UPDATE VIA API
# ──────────────────────────────────────────────────────────────────────────────

Write-Section "VERIFICA POST UPDATE - LETTURA DA API MORPHEUS"

try {
    Start-Sleep -Seconds 2

    $updatedInstance = Get-MorpheusInstance `
        -InstanceId $instanceId `
        -ApiUrl $apiUrl `
        -Headers $headers

    $updatedCustomOptions = $updatedInstance.instance.config.customOptions

    Write-Line -Label "API MigrateData"     -Value $updatedCustomOptions.MigrateData
    Write-Line -Label "API fromUser"        -Value $updatedCustomOptions.fromUser
    Write-Line -Label "API fromServer"      -Value $updatedCustomOptions.fromServer
    Write-Line -Label "API toServer"        -Value $updatedCustomOptions.toServer
    Write-Line -Label "API MigrationStatus" -Value $updatedCustomOptions.MigrationStatus

    Write-Output ""
    Write-Output "[INFO] Nota: se questi valori risultano aggiornati qui ma non compaiono nella UI,"
    Write-Output "[INFO] allora Morpheus li ha salvati nel backend ma non li mostra in Runtime > Inputs."
}
catch {
    Write-Output "[WARNING] Update eseguito, ma verifica GET fallita: $($_.Exception.Message)"
}

Write-Section "FINE"

Write-Output "[SUCCESS] Script completato"
exit 0
