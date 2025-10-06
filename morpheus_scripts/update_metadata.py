import os
import json
import socket


# Prova a leggere l'hostname dell'host se disponibile
def get_host_hostname():
    host_hostname_path = '/host/etc/hostname'
    try:
        with open(host_hostname_path, 'r') as f:
            return f.read().strip()
    except Exception:
        return None

hostname = get_host_hostname() or socket.gethostname()


# Prova a leggere l'IP dell'host da /host/etc/hosts (se montato)
def get_host_ipv4():
    hosts_path = '/host/etc/hosts'
    try:
        with open(hosts_path, 'r') as f:
            lines = f.readlines()
            for line in lines:
                if hostname in line and not line.startswith('127.'):
                    parts = line.split()
                    if parts:
                        return parts[0]
    except Exception:
        pass
    return None

def get_ipv4():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip

ipv4 = get_host_ipv4() or get_ipv4()


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
