
# Autore: G.ABBATICCHIO
# Revisione: 0.1
# Data: 11/05/2026
# Code: deso_efc_user_migration_catalog_debug
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Fase diagnostica Catalog Item - stampa valori ricevuti da GUI
#              e valori già presenti sull'istanza, senza eseguire migrazione.

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ──────────────────────────────────────────────────────────────────────────────
# FUNZIONI DI SUPPORTO
# ──────────────────────────────────────────────────────────────────────────────
function Write-Section {
    param([string]$Title)

    Write-Output ""
    Write-Output "[INFO] =========================================="
    Write-Output "[INFO] $Title"
    Write-Output "[INFO] =========================================="
}

function Write-Value {
    param(
        [string]$Label,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Output "[INFO] $Label : <vuoto/non valorizzato>"
    }
    else {
        Write-Output "[INFO] $Label : '$Value'"
    }
}

function Write-Compare {
    param(
        [string]$Label,
        [string]$OldValue,
        [string]$NewValue
    )

    $oldPrintable = if ([string]::IsNullOrWhiteSpace($OldValue)) { "<vuoto/non valorizzato>" } else { "'$OldValue'" }
    $newPrintable = if ([string]::IsNullOrWhiteSpace($NewValue)) { "<vuoto/non valorizzato>" } else { "'$NewValue'" }

    if ($OldValue -eq $NewValue) {
        Write-Output "[INFO] $Label : invariato | istanza=$oldPrintable | catalog=$newPrintable"
    }
    else {
        Write-Output "[INFO] $Label : diverso   | istanza=$oldPrintable | catalog=$newPrintable"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# VALORI RICEVUTI DAL CATALOG ITEM / GUI
# ──────────────────────────────────────────────────────────────────────────────
# Questi sono i valori che l'utente inserisce nel nuovo Catalog Item.
# I nomi devono corrispondere agli input definiti nel Catalog Item.

$catalog_MigrateData = "<%=customOptions.MigrateData%>"
$catalog_fromUser    = "<%=customOptions.fromUser%>"
$catalog_fromServer  = "<%=customOptions.fromServer%>"

# Eventuale input esplicito, se lo hai previsto nel Catalog Item.
# Se non esiste, resterà vuoto o non sostituito a seconda del contesto Morpheus.
$catalog_toServer    = "<%=customOptions.toServer%>"

# ──────────────────────────────────────────────────────────────────────────────
# VALORI GIÀ PRESENTI SULL'ISTANZA
# ──────────────────────────────────────────────────────────────────────────────
# Questi sono i valori attualmente associati all'istanza Morpheus.

$instanceId      = "<%=instance.id%>"
$instanceName    = "<%=instance.name%>"
$instanceToServer = "<%=instance.containers[0].server.internalIp%>"

$instance_MigrateData     = "<%=instance.config.customOptions.MigrateData%>"
$instance_fromUser        = "<%=instance.config.customOptions.fromUser%>"
$instance_fromServer      = "<%=instance.config.customOptions.fromServer%>"
$instance_MigrationStatus = "<%=instance.config.customOptions.MigrationStatus%>"

# ──────────────────────────────────────────────────────────────────────────────
# LOG DIAGNOSTICO
# ──────────────────────────────────────────────────────────────────────────────

Write-Section "FASE 1 - DEBUG PARAMETRI CATALOG ITEM"

Write-Output "[INFO] Questo task è in modalità diagnostica."
Write-Output "[INFO] Nessuna migrazione verrà avviata."
Write-Output "[INFO] Nessun file verrà creato sul dispatcher."
Write-Output "[INFO] Nessun valore verrà aggiornato su Morpheus."

Write-Section "CONTESTO ISTANZA MORPHEUS"

Write-Value -Label "Instance ID"   -Value $instanceId
Write-Value -Label "Instance Name" -Value $instanceName
Write-Value -Label "Internal IP"   -Value $instanceToServer

Write-Section "VALORI INSERITI DA INTERFACCIA GRAFICA / CATALOG ITEM"

Write-Value -Label "Catalog MigrateData" -Value $catalog_MigrateData
Write-Value -Label "Catalog fromUser"    -Value $catalog_fromUser
Write-Value -Label "Catalog fromServer"  -Value $catalog_fromServer
Write-Value -Label "Catalog toServer"    -Value $catalog_toServer

Write-Section "VALORI GIÀ PRESENTI SULL'ISTANZA"

Write-Value -Label "Instance MigrateData"     -Value $instance_MigrateData
Write-Value -Label "Instance fromUser"        -Value $instance_fromUser
Write-Value -Label "Instance fromServer"      -Value $instance_fromServer
Write-Value -Label "Instance toServer"        -Value $instanceToServer
Write-Value -Label "Instance MigrationStatus" -Value $instance_MigrationStatus

Write-Section "CONFRONTO VALORI CATALOG ITEM VS ISTANZA"

Write-Compare -Label "MigrateData" -OldValue $instance_MigrateData -NewValue $catalog_MigrateData
Write-Compare -Label "fromUser"    -OldValue $instance_fromUser    -NewValue $catalog_fromUser
Write-Compare -Label "fromServer"  -OldValue $instance_fromServer  -NewValue $catalog_fromServer

# Per toServer il valore attuale dell'istanza viene preso dall'IP interno.
# Se nel Catalog Item non esiste un campo toServer, questo confronto serve solo come debug.
Write-Compare -Label "toServer"    -OldValue $instanceToServer     -NewValue $catalog_toServer

Write-Section "FINE DEBUG"

Write-Output "[SUCCESS] Fase diagnostica completata correttamente"
exit 0
