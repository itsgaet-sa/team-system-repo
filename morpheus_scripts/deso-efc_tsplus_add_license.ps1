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

Write-Host "========================================" -ForegroundColor Green
Write-Host "INIZIO SCRIPT TSPLUS LICENSE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$nomevm = "<%=instance.name%>"
$users = if ("<%=licenseUsers%>") { [int]"<%=licenseUsers%>" } else { 5 }

Write-Host "Instance completa: <%=instance%>" -ForegroundColor Yellow
Write-Host "Nome VM: $nomevm" -ForegroundColor Cyan
Write-Host "Numero utenti licenza TSPlus: $users" -ForegroundColor Cyan
Write-Host "Data esecuzione: $(Get-Date)" -ForegroundColor Cyan

# & "C:\Program Files (x86)\TSplus\UserDesktop\files\AdminTool.exe" /vl /activate ZXR4-MMTS-G4EW-ZPVG /users $users /edition Enterprise /supportyears 0 /comments $nomevm

Write-Host "========================================" -ForegroundColor Green
Write-Host "SCRIPT COMPLETATO CON SUCCESSO" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

exit 0
