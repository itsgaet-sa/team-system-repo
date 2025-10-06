# Autore: g.abbaticchio
# Revisione: 1.0
# Data: 06/10/2025
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
    """Funzione per formattare l'output per Morpheus"""
    output = {
        "status": status,
        "message": message
    }
    print(json.dumps(output))

def get_instance_details(instance_id, api_url, token):
    """Recupera i dettagli dell'istanza da Morpheus"""
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    response = requests.get(
        f'{api_url}/api/instances/{instance_id}',
        headers=headers
    )
    
    if response.status_code != 200:
        raise Exception(f"Errore nel recupero dei dettagli dell'istanza: {response.status_code}")
        
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
    
    response = requests.put(
        f'{api_url}/api/instances/{instance_id}',
        headers=headers,
        json=payload
    )
    
    if response.status_code != 200:
        raise Exception(f"Errore nell'aggiornamento dell'istanza: {response.status_code}")
        
    return response.json()

def main():
    try:
        # Recupera le variabili d'ambiente di Morpheus
        instance_id = os.environ.get('MORPHEUS_INSTANCE_ID')
        api_url = os.environ.get('MORPHEUS_API_URL')
        token = os.environ.get('MORPHEUS_API_TOKEN')
        
        if not all([instance_id, api_url, token]):
            raise Exception("Variabili d'ambiente Morpheus mancanti")
            
        # Recupera i dettagli dell'istanza
        instance_details = get_instance_details(instance_id, api_url, token)
        
        # Estrae le informazioni necessarie
        hostname = instance_details['instance']['hostName']
        ipv4 = instance_details['instance']['connectionInfo'][0]['ip'] if instance_details['instance']['connectionInfo'] else None
        domain = "easyfattincloud.it"
        url = f"{hostname}.{domain}" if hostname else None
        
        # Recupera le customOptions esistenti e aggiunge i nuovi campi
        current_custom_options = instance_details['instance']['config']['customOptions']
        updated_custom_options = {
            **current_custom_options,
            "hostname": hostname,
            "ipv4": ipv4,
            "domain": domain,
            "url": url
        }
        
        # Aggiorna l'istanza con le nuove customOptions
        result = update_instance_metadata(instance_id, updated_custom_options, api_url, token)
        
        # Invia l'output di successo
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