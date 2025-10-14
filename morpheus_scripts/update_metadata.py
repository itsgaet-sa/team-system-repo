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
import json
import socket
import subprocess

def send_morpheus_output(status, message):
    """Emette l'output JSON nel formato atteso da Morpheus."""
    output = {
        "status": status,
        "message": message
    }
    print(json.dumps(output, ensure_ascii=False))


def get_ipv4_address():
    """Rileva l'indirizzo IPv4 del sistema (escludendo 169.254.*)."""
    try:
        # Ottiene l'indirizzo IP principale (non loopback)
        ip = socket.gethostbyname(socket.gethostname())
        if ip.startswith("169.254."):
            # Fallback su altro metodo se l’IP è link-local
            ip = None
    except Exception:
        ip = None

    if not ip:
        # Prova con `ipconfig` / `ip addr` (cross-platform fallback)
        try:
            result = subprocess.run(
                ["ipconfig"], capture_output=True, text=True, check=False
            )
            for line in result.stdout.splitlines():
                if "IPv4" in line and "169.254" not in line:
                    ip = line.split(":")[-1].strip()
                    break
        except Exception:
            pass

    if not ip:
        ip = "127.0.0.1"

    return ip


def main():
    current_hostname = socket.gethostname()
    ipv4 = get_ipv4_address()
    fqdn = f"{current_hostname}.cloud.teamsystem.com"

    # (facoltativo) aggiungere al file hosts
    # with open(r"C:\Windows\System32\drivers\etc\hosts", "a") as f:
    #     f.write(f"{ipv4} {fqdn}\n")

    send_morpheus_output("Success", f"{current_hostname} | {ipv4}")


if __name__ == "__main__":
    main()
