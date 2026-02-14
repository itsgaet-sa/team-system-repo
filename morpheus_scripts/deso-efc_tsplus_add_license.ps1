# Autore: G.ABBATICCHIO
# Revisione: 1.3
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

Write-Output "Instance completa: <%=instance%>"
$nomevm = "<%=instance.name%>"
$users = if ("<%=licenseUsers%>") { [int]"<%=licenseUsers%>" } else { 5 }

Write-Output "Nome VM: $nomevm"
Write-Output "Numero utenti licenza TSPlus: $users"
Write-Output "Data esecuzione: $(Get-Date)"

# & "C:\Program Files (x86)\TSplus\UserDesktop\files\AdminTool.exe" /vl /activate ZXR4-MMTS-G4EW-ZPVG /users $users /edition Enterprise /supportyears 0 /comments $nomevm

Write-Output "========================================"
Write-Output "SCRIPT COMPLETATO CON SUCCESSO"
Write-Output "========================================"
