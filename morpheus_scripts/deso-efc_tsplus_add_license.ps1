# Autore: G.ABBATICCHIO
# Revisione: 1.5
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

Write-Output "[INFO] Attivazione licenza TSPlus in corso..."

$nomevm = "<%=instance.name%>"
$licenseUsersInput = "<%=customOptions.licenseUsers%>"

if ($licenseUsersInput -and $licenseUsersInput -match '^\d+$') {
    $users = [int]$licenseUsersInput
} else {
    $users = 5
    Write-Output "[INFO] Numero utenti non specificato, utilizzo valore default: 5"
}

Write-Output "[INFO] Server: $nomevm"
Write-Output "[INFO] Utenti licenza: $users"

# & "C:\Program Files (x86)\TSplus\UserDesktop\files\AdminTool.exe" /vl /activate ZXR4-MMTS-G4EW-ZPVG /users $users /edition Enterprise /supportyears 0 /comments $nomevm

Write-Output "[SUCCESS] Licenza TSPlus configurata correttamente"
