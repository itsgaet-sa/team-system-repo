# Autore: G.ABBATICCHIO
# Revisione: 1.4
# Data: 14/02/2026
# Code: efc_tsplus_add_license
# Source: repo
# Result Type: none
# Elevated Shell: True
# Execute Target: Resource
# Visibility: Public
# Continue on error: False
# Retryable: False
# Description: Aggiunta della licenza di TSPlus per gli utenti sui server DANEA EFC (default 5 utenti)

Write-Output "========================================"
Write-Output "INIZIO SCRIPT TSPLUS LICENSE"
Write-Output "========================================"

$nomevm = "<%=instance.name%>"

# Gestione sicura del parametro licenseUsers dalla form
$licenseUsersInput = "<%=customOptions.licenseUsers%>"
$users = if ($licenseUsersInput -and $licenseUsersInput -ne '' -and $licenseUsersInput -ne '<%=customOptions.licenseUsers%>') { 
    [int]$licenseUsersInput 
} else { 
    5 
}

Write-Output "Instance completa: <%=instance%>"
Write-Output "Nome VM: $nomevm"
Write-Output "Numero utenti licenza TSPlus: $users"
Write-Output "Data esecuzione: $(Get-Date)"

# & "C:\Program Files (x86)\TSplus\UserDesktop\files\AdminTool.exe" /vl /activate ZXR4-MMTS-G4EW-ZPVG /users $users /edition Enterprise /supportyears 0 /comments $nomevm

Write-Output "========================================"
Write-Output "SCRIPT COMPLETATO CON SUCCESSO"
Write-Output "========================================"
