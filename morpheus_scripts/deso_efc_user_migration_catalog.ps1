# Autore: G.ABBATICCHIO
# Revisione: 0.3
# Data: 12/05/2026
# Code: deso_efc_user_migration_catalog_debug
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Aggiorna customOptions Morpheus da Catalog Item:
#              - MigrateData sempre true
#              - fromUser da Catalog Item
#              - fromServer da Catalog Item
#              - toServer non modificato
#              - MigrationStatus a null
#              e stampa diagnostica valori istanza/catalog.

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

function Write-Compare {
    param(
        [string]$Label,
        [string]$InstanceValue,
        [string]$CatalogValue
    )

    $instancePrintable = Format-Value $InstanceValue
    $catalogPrintable  = Format-Value $CatalogValue

    if ($InstanceValue -eq $CatalogValue) {
        Write-Output "[INFO] $Label = invariato | istanza=$instancePrintable | catalog=$catalogPrintable"
    }
    else {
        Write-Output "[INFO] $Label = diverso   | istanza=$instancePrintable | catalog=$catalogPrintable"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONE UPDATE MORPHEUS
# ──────────────────────────────────────────────────────────────────────────────

function Update-MigrationCustomOptions {
    try {
        $instanceId     = "<%=instance.id%>"
        $morpheusApiUrl = "<%=morpheus.applianceUrl%>/api/instances/$instanceId"
        $morpheusToken  = "<%=morpheus.apiAccessToken%>"

        $catalog_fromUser   = "<%=customOptions.fromUser%>"
        $catalog_fromServer = "<%=customOptions.fromServer%>"

        $headers = @{
            "Authorization" = "Bearer $morpheusToken"
            "Content-Type"  = "application/json"
        }

        $body = @{
            instance = @{
                config = @{
                    customOptions = @{
                        # Sempre forzato a true
                        MigrateData = $true

                        # Valori presi dal Catalog Item
                        fromUser   = $catalog_fromUser
                        fromServer = $catalog_fromServer

                        # toServer NON viene incluso nel body
                        # quindi non viene modificato

                        # Reset stato migrazione
                        MigrationStatus = $null
                    }
                }
            }
        } | ConvertTo-Json -Depth 10

        Invoke-RestMethod `
            -Uri $morpheusApiUrl `
            -Method Put `
            -Headers $headers `
            -Body $body `
            -ErrorAction Stop | Out-Null

        Write-Output "[INFO] CustomOptions aggiornate correttamente su Morpheus"
        Write-Output "[INFO] MigrateData     -> true"
        Write-Output "[INFO] fromUser        -> '$catalog_fromUser'"
        Write-Output "[INFO] fromServer      -> '$catalog_fromServer'"
        Write-Output "[INFO] toServer        -> NON MODIFICATO"
        Write-Output "[INFO] MigrationStatus -> null"
    }
    catch {
        Write-Output "[WARNING] Impossibile aggiornare le customOptions in Morpheus: $($_.Exception.Message)"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# VALORI RICEVUTI DAL CATALOG ITEM / GUI
# ──────────────────────────────────────────────────────────────────────────────

$catalog_MigrateData = "<%=customOptions.MigrateData%>"
$catalog_fromUser    = "<%=customOptions.fromUser%>"
$catalog_fromServer  = "<%=customOptions.fromServer%>"
$catalog_toServer    = "<%=customOptions.toServer%>"

# ──────────────────────────────────────────────────────────────────────────────
# VALORI GIÀ PRESENTI SULL'ISTANZA
# ──────────────────────────────────────────────────────────────────────────────

$instanceId       = "<%=instance.id%>"
$instanceName     = "<%=instance.name%>"
$instanceToServer = "<%=instance.containers[0].server.internalIp%>"

$instance_MigrateData     = "<%=instance.config.customOptions.MigrateData%>"
$instance_fromUser        = "<%=instance.config.customOptions.fromUser%>"
$instance_fromServer      = "<%=instance.config.customOptions.fromServer%>"
$instance_MigrationStatus = "<%=instance.config.customOptions.MigrationStatus%>"

# ──────────────────────────────────────────────────────────────────────────────
# LOG DIAGNOSTICO PRIMA DELL'UPDATE
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] ===== START UPDATE CUSTOMOPTIONS MIGRAZIONE ====="

Write-Output ""
Write-Output "[INFO] ----- CONTESTO ISTANZA -----"
Write-Line -Label "Instance ID"   -Value $instanceId
Write-Line -Label "Instance Name" -Value $instanceName
Write-Line -Label "Internal IP"   -Value $instanceToServer

Write-Output ""
Write-Output "[INFO] ----- VALORI ATTUALI ISTANZA -----"
Write-Line -Label "Instance MigrateData"     -Value $instance_MigrateData
Write-Line -Label "Instance fromUser"        -Value $instance_fromUser
Write-Line -Label "Instance fromServer"      -Value $instance_fromServer
Write-Line -Label "Instance toServer"        -Value $instanceToServer
Write-Line -Label "Instance MigrationStatus" -Value $instance_MigrationStatus

Write-Output ""
Write-Output "[INFO] ----- VALORI RICEVUTI DAL CATALOG ITEM -----"
Write-Line -Label "Catalog MigrateData" -Value $catalog_MigrateData
Write-Line -Label "Catalog fromUser"    -Value $catalog_fromUser
Write-Line -Label "Catalog fromServer"  -Value $catalog_fromServer
Write-Line -Label "Catalog toServer"    -Value $catalog_toServer

Write-Output ""
Write-Output "[INFO] ----- CONFRONTO PRIMA DELL'UPDATE -----"
Write-Compare -Label "MigrateData" -InstanceValue $instance_MigrateData -CatalogValue $catalog_MigrateData
Write-Compare -Label "fromUser"    -InstanceValue $instance_fromUser    -CatalogValue $catalog_fromUser
Write-Compare -Label "fromServer"  -InstanceValue $instance_fromServer  -CatalogValue $catalog_fromServer
Write-Compare -Label "toServer"    -InstanceValue $instanceToServer     -CatalogValue $catalog_toServer

# ──────────────────────────────────────────────────────────────────────────────
# UPDATE CUSTOMOPTIONS
# ──────────────────────────────────────────────────────────────────────────────

Write-Output ""
Write-Output "[INFO] ----- UPDATE CUSTOMOPTIONS MORPHEUS -----"

Update-MigrationCustomOptions

Write-Output ""
Write-Output "[SUCCESS] Update customOptions completato"
exit 0
