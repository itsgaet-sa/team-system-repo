
#!/usr/bin/env python3
# Autore: G.ABBATICCHIO
# Revisione: 1.7-PY-HTTP
# Esecuzione: Morpheus Linux
# Trasporto: WinRM HTTP 5985

import sys
import time
import winrm

# ============================================
# VARIABILI MORPHEUS
# ============================================

migration_value = "<%=customOptions.MIgrateData%>"
from_user       = "<%=customOptions.fromUser%>"
from_server     = "<%=customOptions.fromServer%>"
to_server       = "<%=instance.containers[0].server.internalIp%>"
instance_name   = "<%=instance.name%>"
instance_id     = "<%=instance.id%>"

migration_server_ip = "10.182.1.11"

migration_user = "<%=cypher.read('secret/EFC-TS_MIG_DANEA-USR',true)%>"
migration_pass = "<%=cypher.read('secret/EFC-TS_MIG_DANEA-PWD',true)%>"

# ============================================
# VALIDAZIONE
# ============================================

if migration_value != "true":
    print("[INFO] Migrazione non richiesta - Skip")
    sys.exit(0)

if not migration_user or not migration_pass:
    print("[ERROR] Credenziali mancanti")
    sys.exit(1)

# ============================================
# CONNESSIONE WINRM HTTP 5985
# ============================================

print(f"[INFO] Connessione a {migration_server_ip} via WinRM HTTP 5985...")

try:
    session = winrm.Session(
        target=f"http://{migration_server_ip}:5985/wsman",
        auth=(migration_user, migration_pass),
        transport="ntlm"  # consigliato
    )
    print("[SUCCESS] Connessione stabilita")
except Exception as e:
    print(f"[ERROR] Connessione fallita: {e}")
    sys.exit(1)

# ============================================
# CREAZIONE FILE DI CODA
# ============================================

create_queue_ps = f"""
$fromUser  = "{from_user}"
$fromServer = "{from_server}"
$toServer  = "{to_server}"

$queuePath = "D:\\tools\\migration\\incoming"

if (-not (Test-Path $queuePath)) {{
    New-Item -Path $queuePath -ItemType Directory -Force | Out-Null
}}

$existing = Get-ChildItem $queuePath -Filter "migra_*.txt" -ErrorAction SilentlyContinue |
    Where-Object {{ $_.Name -match 'migra_(\\d+)\\.txt' }} |
    ForEach-Object {{ [int]$matches[1] }} |
    Sort-Object -Descending

$next = if ($existing) {{ $existing[0] + 1 }} else {{ 1 }}

$fileName = "migra_{{0:D6}}.txt" -f $next
$filePath = Join-Path $queuePath $fileName
$content = "$fromUser|$fromServer|$toServer"

Set-Content -Path $filePath -Value $content -Force

Write-Output $fileName
"""

print("[INFO] Creazione file di coda...")

result = session.run_ps(create_queue_ps)

if result.status_code != 0:
    print("[ERROR] Creazione file fallita")
    print(result.std_err.decode())
    sys.exit(1)

queue_file = result.std_out.decode().strip()
queue_base = queue_file.replace(".txt", "")

print(f"[SUCCESS] File creato: {queue_file}")

# ============================================
# AVVIO DISPATCHER
# ============================================

dispatcher_ps = """
$dispatcherScript = "D:\\tools\\migration\\dispatcher.ps1"
if (Test-Path $dispatcherScript) {
    & $dispatcherScript
}
else {
    throw "Dispatcher non trovato"
}
"""

print("[INFO] Avvio dispatcher...")
disp = session.run_ps(dispatcher_ps)

if disp.status_code != 0:
    print("[WARNING] Dispatcher errore:")
    print(disp.std_err.decode())

# ============================================
# MONITORAGGIO
# ============================================

monitor_template = """
$base = "{base}"
$qPath = "D:\\tools\\migration\\incoming"

$done = Join-Path $qPath "$base.done"
$err  = Join-Path $qPath "$base.err"
$work = Join-Path $qPath "$base.work"
$txt  = Join-Path $qPath "$base.txt"

if (Test-Path $done) {{ "Completed" }}
elseif (Test-Path $err) {{ "Failed" }}
elseif (Test-Path $work) {{ "Processing" }}
elseif (Test-Path $txt) {{ "Scheduled" }}
else {{ "Unknown" }}
"""

print("[INFO] Monitoraggio...")

max_time = 5400
interval = 10
elapsed = 0

while elapsed < max_time:

    monitor_ps = monitor_template.format(base=queue_base)
    status = session.run_ps(monitor_ps)

    state = status.std_out.decode().strip()
    print(f"[INFO] Stato: {state} (t={elapsed}s)")

    if state == "Completed":
        print("[SUCCESS] Migrazione completata")
        sys.exit(0)

    if state == "Failed":
        print("[ERROR] Migrazione fallita")
        sys.exit(1)

    if state == "Unknown":
        print("[ERROR] File non trovato")
        sys.exit(1)

    time.sleep(interval)
    elapsed += interval

print("[WARNING] Timeout monitoraggio")
sys.exit(1)
