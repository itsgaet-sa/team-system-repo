# Autore: g.abbaticchio
# Revisione: 1.1
# Data: 10/10/2025
# Code: update_instance_metadata
# Source: Local
# Result Type: JSON
# Elevated Shell: False
# Execute Target: Resource
# Visibility: Private
# Continue on error: False
# Retryable: False
# Description: Aggiorna i metadati dell'istanza con hostname, ipv4, domain e url.
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
 
function Send-MorpheusOutput {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Status,
        
        [Parameter(Mandatory = $true)]
        [string]$Message
        )
    
    $output = @{
        status  = $Status
        message = $Message
    }
 
    $output | ConvertTo-Json -Depth 10 | Write-Output
}
 
# Imposta il nome univoco della VM (sostituisci con il valore corretto oppure passalo come parametro)
$instanceName = "<%=instance.name%>"
if (-not $instanceName) { $instanceName = "ENT002-TT-L-ACME01" }
 
# Calcola l'MD5 dell'instance name
$md5 = [System.Security.Cryptography.MD5]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($instanceName)
$hashBytes = $md5.ComputeHash($bytes)
$md5.Dispose()
 
# Converte l'hash in stringa esadecimale
$hashHex = [System.BitConverter]::ToString($hashBytes) -replace '-',''
 
# Converte la stringa esadecimale in un BigInteger (aggiungendo uno 0 iniziale per evitare problemi di segno)
$bigInt = [System.Numerics.BigInteger]::Parse("0$hashHex", [System.Globalization.NumberStyles]::HexNumber)
 
# Funzione per convertire un BigInteger in Base62
function ConvertTo-Base62($bigInt) {
    $chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    $result = ""
    while ($bigInt -gt 0) {
        $remainder = [int]($bigInt % 62)
        $result = $chars[$remainder] + $result
        $bigInt = [System.Numerics.BigInteger]::Divide($bigInt, 62)
    }
    if ([string]::IsNullOrEmpty($result)) { $result = "0" }
    return $result
}
 
$base62Val = ConvertTo-Base62 $bigInt
 
# Prendi i primi 2 caratteri (se il risultato ha meno di 2 caratteri, prendi l'intera stringa)
$shortHash = $base62Val.Substring(0, [Math]::Min(2, $base62Val.Length))
 
# Recupera l'hostname corrente
$currentHostname = $env:COMPUTERNAME
 
# Rileva ipv4
$ipv4 = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
# Se non viene trovato un indirizzo IPv4, usa l'indirizzo di loopback
if (-not $ipv4) {
    $ipv4 = "127.0.0.1"
}
 
 
# Aggiungi ipv4 con hostname e FQDN completo .cloud.teamsystem.com al file hosts
$fqdn = "$currentHostname.cloud.teamsystem.com"
 
Send-MorpheusOutput -Status "Success" -Message "$currentHostname | $ipv4"
