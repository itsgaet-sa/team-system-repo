# Autore: G.ABBATICCHIO
# Revisione: 0.2
# Data: 12/05/2026
# Code: deso_efc_user_migration_catalog_debug
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Fase diagnostica Catalog Item - stampa prima valori istanza
#              e poi valori catalog, senza eseguire migrazione.

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

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
# LOG DIAGNOSTICO COMPATTO
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] ===== DEBUG PARAMETRI CATALOG ITEM ====="
Write-Output "[INFO] Modalità diagnostica: nessuna migrazione, nessun file, nessun update Morpheus."

Write-Output ""
Write-Output "[INFO] ----- CONTESTO ISTANZA -----"
Write-Line -Label "Instance ID"   -Value $instanceId
Write-Line -Label "Instance Name" -Value $instanceName
Write-Line -Label "Internal IP"   -Value $instanceToServer

Write-Output ""
Write-Output "[INFO] ----- VALORI ISTANZA -----"
Write-Line -Label "Instance MigrateData"     -Value $instance_MigrateData
Write-Line -Label "Instance fromUser"        -Value $instance_fromUser
Write-Line -Label "Instance fromServer"      -Value $instance_fromServer
Write-Line -Label "Instance toServer"        -Value $instanceToServer
Write-Line -Label "Instance MigrationStatus" -Value $instance_MigrationStatus

Write-Output ""
Write-Output "[INFO] ----- VALORI CATALOG ITEM -----"
Write-Line -Label "Catalog MigrateData" -Value $catalog_MigrateData
Write-Line -Label "Catalog fromUser"    -Value $catalog_fromUser
Write-Line -Label "Catalog fromServer"  -Value $catalog_fromServer
Write-Line -Label "Catalog toServer"    -Value $catalog_toServer

Write-Output ""
Write-Output "[INFO] ----- CONFRONTO ISTANZA VS CATALOG -----"
Write-Compare -Label "MigrateData" -InstanceValue $instance_MigrateData -CatalogValue $catalog_MigrateData
Write-Compare -Label "fromUser"    -InstanceValue $instance_fromUser    -CatalogValue $catalog_fromUser
Write-Compare -Label "fromServer"  -InstanceValue $instance_fromServer  -CatalogValue $catalog_fromServer
Write-Compare -Label "toServer"    -InstanceValue $instanceToServer     -CatalogValue $catalog_toServer

Write-Output ""
Write-Output "[SUCCESS] Fase diagnostica completata correttamente"

exit 0
