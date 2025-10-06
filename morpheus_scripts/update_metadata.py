import os
import json

# Morpheus di solito passa le variabili come variabili d'ambiente
hostname = os.getenv('hostname')
ipv4 = os.getenv('ipv4')
url = os.getenv('url')
dominio = 'easyfattincloud'

# Costruisci il dizionario dei metadata
metadata = {
    'hostname': hostname,
    'ipv4': ipv4,
    'url': url,
    'dominio': dominio
}

# Stampa i metadata in formato JSON (o salva su file, se richiesto da Morpheus)
print(json.dumps(metadata, indent=2))

# Se serve scrivere su file, decommenta la riga seguente:
# with open('/tmp/metadata.json', 'w') as f:
#     json.dump(metadata, f, indent=2)
