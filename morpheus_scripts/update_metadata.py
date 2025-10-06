import os
import json
import socket

# Recupera hostname
hostname = socket.gethostname()

# Recupera ipv4 (prima interfaccia non localhost)
def get_ipv4():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Connessione fittizia per ottenere l'IP locale
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

ipv4 = get_ipv4()


# Costruisci l'URL come richiesto: hostname + '.easyfattincloud.it'
url = f"http://{hostname}.easyfattincloud.it"

dominio = 'easyfattincloud'

metadata = {
    'hostname': hostname,
    'ipv4': ipv4,
    'url': url,
    'dominio': dominio
}

print(json.dumps(metadata, indent=2))

# Se serve scrivere su file, decommenta la riga seguente:
# with open('/tmp/metadata.json', 'w') as f:
#     json.dump(metadata, f, indent=2)
