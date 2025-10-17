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
import hashlib

def send_morpheus_output(status, message):
    """Formatta l'output per Morpheus"""
    output = {
        "status": status,
        "message": message
    }
    print(json.dumps(output, indent=2))

def md5_to_base62_short(instance_name: str) -> str:
    # Calcola MD5 dell'istanza
    md5_hash = hashlib.md5(instance_name.encode('utf-8')).hexdigest()
    
    # Converte l'MD5 (hex) in un intero
    big_int = int(md5_hash, 16)
    
    # Conversione in Base62
    chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    result = ""
    base = 62

    while big_int > 0:
        big_int, remainder = divmod(big_int, base)
        result = chars[remainder] + result

    if not result:
        result = "0"

    # Prende i primi 2 caratteri
    short_hash = result[:2]
    return short_hash


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


def main():
    try:
        # Estrae le informazioni principali
        # Calcola l'MD5 abbreviato
        md5_short = md5_to_base62_short(morpheus['instance']['name'])
        
        # Costruisce l'hostname unendo il valore originale e l'MD5
        hostname = morpheus['instance']['hostname'] + md5_short        
        domain = "easyfattincloud.it"
        url = f"{hostname}.{domain}" if hostname else None
        internalIp = morpheus['internalIp']
        
        instance_id = morpheus.get("instance", {}).get("id", None)
        api_url = morpheus['morpheus']['applianceUrl']
        token = morpheus['morpheus']['apiAccessToken']

        # Aggiorna i custom options
        updated_custom_options = morpheus['instance']['customOptions']
        updated_custom_options["instance-hostname"] = hostname
        updated_custom_options["instance-ip"] = internalIp
        updated_custom_options["instance-fqdn"] = url
        updated_custom_options["instance-domain"] = domain
        
        # Aggiorna l'istanza su Morpheus
        update_instance_metadata(instance_id, updated_custom_options, api_url, token)

        # Output finale
        send_morpheus_output("success", {
            "hostname": hostname,
            "domain": domain,
            "url": url,
            "ipv4": internalIp
        })

    except Exception as e:
        send_morpheus_output("error", str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()
