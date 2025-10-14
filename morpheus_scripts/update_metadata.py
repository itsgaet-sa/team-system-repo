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
import requests
import os
import sys


def send_morpheus_output(status, message):
    """Formatta l'output per Morpheus"""
    output = {
        "status": status,
        "message": message
    }
    print(json.dumps(output, indent=2))


def get_instance_details(instance_id, api_url, token):
    """Recupera i dettagli dell'istanza da Morpheus"""
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    url = f'{api_url}/api/instances/{instance_id}'

    response = requests.get(url, headers=headers)
    if response.status_code != 200:
        raise Exception(f"Errore nel recupero dei dettagli dell'istanza (HTTP {response.status_code}): {response.text}")

    return response.json()


def update_instance_metadata(instance_id, custom_options, api_url, token):
    """Aggiorna le customOptions dell'istanza"""
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }

    payload = {
        "instance": {
            "config": {
                "customOptions": custom_options
            }
        }
    }

    url = f'{api_url}/api/instances/{instance_id}'
    response = requests.put(url, headers=headers, json=payload)

    if response.status_code != 200:
        raise Exception(f"Errore nell'aggiornamento dell'istanza (HTTP {response.status_code}): {response.text}")

    return response.json()


def resolve_parameters():
    """Determina i parametri da usare, da variabili d'ambiente o CLI"""
    instance_id = os.environ.get('MORPHEUS_INSTANCE_ID')
    api_url = os.environ.get('MORPHEUS_API_URL')
    token = os.environ.get('MORPHEUS_API_TOKEN') or os.environ.get('MORPHEUS_API_ACCESS_TOKEN')

    # Se non trovate nelle variabili, prova dagli argomenti CLI
    if not instance_id and len(sys.argv) > 1:
        instance_id = sys.argv[1]
    if not api_url and len(sys.argv) > 2:
        api_url = sys.argv[2]
    if not token and len(sys.argv) > 3:
        token = sys.argv[3]

    if not all([instance_id, api_url, token]):
        usage = (
            "Parametri mancanti.\n\n"
            "Uso:\n"
            "  python3 update_instance_metadata.py <instance_id> <api_url> <token>\n\n"
            "Oppure imposta le variabili d'ambiente:\n"
            "  export MORPHEUS_INSTANCE_ID=<id>\n"
            "  export MORPHEUS_API_URL=<url>\n"
            "  export MORPHEUS_API_TOKEN=<token>\n"
        )
        raise Exception(usage)

    return instance_id, api_url, token


def main():
    try:
        instance_id, api_url, token = resolve_parameters()

        # Recupera i dettagli dell'istanza
        instance_details = get_instance_details(instance_id, api_url, token)
        instance = instance_details.get('instance', {})

        # Estrae le informazioni principali
        hostname = instance.get('hostName')
        connection_info = instance.get('connectionInfo', [])
        ipv4 = connection_info[0].get('ip') if connection_info else None

        domain = "easyfattincloud.it"
        url = f"{hostname}.{domain}" if hostname else None

        # Recupera e aggiorna le customOptions
        current_custom_options = instance.get('config', {}).get('customOptions', {})
        updated_custom_options = {
            **current_custom_options,
            "hostname": hostname,
            "ipv4": ipv4,
            "domain": domain,
            "url": url
        }

        # Aggiorna l'istanza su Morpheus
        update_instance_metadata(instance_id, updated_custom_options, api_url, token)

        # Output finale
        send_morpheus_output("success", {
            "hostname": hostname,
            "ipv4": ipv4,
            "domain": domain,
            "url": url
        })

    except Exception as e:
        send_morpheus_output("error", str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()
