# Autore: G.ABBATICCHIO
# Revisione: 0.4
# Data: 15/05/2026
# Code: deso_efc_user_migration_catalog_debug
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Stampa diagnostica temporanea dei soli valori ricevuti dal Catalog Item.
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

# ──────────────────────────────────────────────────────────────────────────────
# VALORI RICEVUTI DAL CATALOG ITEM / GUI
# ──────────────────────────────────────────────────────────────────────────────

$catalog_migrationType     = "<%=customOptions.migrationType%>"
$catalog_sourceServer      = "<%=customOptions.sourceServer%>"
$catalog_destinationServer = "<%=customOptions.destinationServer%>"
$catalog_targetUser        = "<%=customOptions.targetUser%>"
$catalog_migrationMode     = "<%=customOptions.migrationMode%>"

# ──────────────────────────────────────────────────────────────────────────────
# LOG DIAGNOSTICO SOLO CATALOG ITEM
# ──────────────────────────────────────────────────────────────────────────────

Write-Output "[INFO] ===== START DEBUG CATALOG ITEM MIGRAZIONE ====="

Write-Output ""
Write-Output "[INFO] ----- VALORI RICEVUTI DAL CATALOG ITEM -----"
Write-Line -Label "Catalog migrationType"     -Value $catalog_migrationType
Write-Line -Label "Catalog sourceServer"      -Value $catalog_sourceServer
Write-Line -Label "Catalog destinationServer" -Value $catalog_destinationServer
Write-Line -Label "Catalog targetUser"        -Value $catalog_targetUser
Write-Line -Label "Catalog migrationMode"     -Value $catalog_migrationMode

Write-Output ""
Write-Output "[SUCCESS] Debug Catalog Item completato"
exit 0
