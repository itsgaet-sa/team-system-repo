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
import mysql.connector
import requests
import sys
from base64 import b64decode
from Crypto.Cipher import AES
from collections import OrderedDict
 
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
# Funzioni esistenti mantenute
def check_db():
    try:
        if 'results' not in morpheus or not morpheus['results']:
            raise KeyError("'morpheus.results' non esiste o è nullo.")
        if 'dbCheck' not in morpheus['results'] or morpheus['results']['dbCheck'] is None:
            raise KeyError("'dbCheck' non è presente nei risultati o è nullo.")
        return morpheus['results']['dbCheck']
    except KeyError as e:
        print(json.dumps({"status": "failed", "message": str(e)}, indent=2))
        sys.exit(1)
 
def handle_response(connection, resource_id, status, message, extra_data=None, is_server=False):
    """
    Gestisce la risposta e registra l'esito nel database.
 
    Args:
        connection: Connessione al database.
        resource_id: ID della risorsa (instance_id o server_id).
        status: Stato della risposta ("success" o "failed").
        message: Messaggio della risposta.
        extra_data: Dati aggiuntivi da includere nella risposta.
        is_server: Booleano che indica se la risorsa è un server.
 
    """
    response = OrderedDict()
    response = {
        "status": status,
        "message": message,
        "alert": None
    }
    if extra_data:
        # Assicurati che extra_data sia un dizionario e che i valori siano serializzabili
        if isinstance(extra_data, dict):
            for key, value in extra_data.items():
                if isinstance(value, bool):
                    extra_data[key] = str(value)  # Converte i booleani in stringhe
            response.update(extra_data)
 
    # Controlla se resource_id è valido
    if resource_id is None:
        response["alert"] = "Attenzione: resource_id è None. Non sarà possibile registrare l'esito del task."
        print(json.dumps(response, indent=2))
        if status == "failed":
            sys.exit(1)
        return
 
    # Registra il messaggio nel database se la connessione è valida
    if connection and connection.is_connected():
        try:
            cursor = connection.cursor()
 
            # Determina la colonna da aggiornare (instance_id o server_id)
            if is_server:
                query_check = """
                    SELECT id FROM xaas_post_provisioning_tasks 
                    WHERE id_server_morpheus = %s
                """
                cursor.execute(query_check, (resource_id,))
            else:
                query_check = """
                    SELECT id FROM xaas_post_provisioning_tasks 
                    WHERE id_instance_morpheus = %s
                """
                cursor.execute(query_check, (resource_id,))
 
            result = cursor.fetchone()
 
            if result:
                query_update = """
                    UPDATE xaas_post_provisioning_tasks
                    SET update_hostname = %s, updated_at = NOW()
                    WHERE {} = %s
                """.format("id_server_morpheus" if is_server else "id_instance_morpheus")
                cursor.execute(query_update, (json.dumps(response), resource_id))
            else:
                query_insert = """
                    INSERT INTO xaas_post_provisioning_tasks ({}, update_hostname, created_at)
                    VALUES (%s, %s, NOW())
                """.format("id_server_morpheus" if is_server else "id_instance_morpheus")
                cursor.execute(query_insert, (resource_id, json.dumps(response)))
 
            connection.commit()
            cursor.close()
        except mysql.connector.Error as db_err:
            response["alert"] = f"Errore durante la registrazione nel DB: {db_err}"
    else:
        response["alert"] = "Errore: Connessione al database non valida o non stabilita."
 
    print(json.dumps(response, indent=2))
 
    if status == "failed":
        sys.exit(1)
 
def get_command_line_args(connection, resource_id, is_server):
    """
    Recupera e valida i parametri della riga di comando.
 
    Args:
        connection: Connessione al database (opzionale per registrare errori).
 
    Returns:
        tuple: I parametri validati (db_pw, db_user, db_server, Key).
 
    Raises:
        Termina lo script se il numero di parametri è insufficiente.
    """
    try:
 
        if len(sys.argv) != 5:
            handle_response(
                connection,
                resource_id,
                "failed",
                "Numero di parametri errato. Fornire esattamente 4 parametri: db_pw, db_user, db_server, Key.",
                None,
                is_server
            )
            sys.exit(1)
 
        db_pw = sys.argv[1].strip()
        db_user = sys.argv[2].strip()
        db_server = sys.argv[3].strip()
        Key = sys.argv[4].strip()
 
        return db_pw, db_user, db_server, Key
 
    except Exception as e:
        # Gestione di errori generali
        error_message = f"Errore imprevisto durante la validazione dei parametri: {str(e)}"
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
 
def get_prefix_fw_result(connection, resource_id, is_server):    
    if 'results' not in morpheus or not morpheus['results']:
        error_message = "'morpheus.results' non esiste o è nullo."
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
    if 'get_prefix' not in morpheus['results'] or morpheus['results']['get_prefix'] is None:
        error_message = "'get_prefix' non è presente nei risultati o è nullo."
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
    return morpheus['results']['get_prefix']['message']
 
def connect_to_database(db_pw, db_user, db_server):
    try:
        connection = mysql.connector.connect(
            host=db_server,
            port="3306",
            database="xaas_ts",
            user=db_user,
            password=db_pw,
            auth_plugin='mysql_native_password'
        )
        return connection
    except mysql.connector.Error as e:
        print(json.dumps({"status": "failed", "message": f"Errore di connessione al database: {e}"}, indent=2))
        sys.exit(1)
 
def decrypt_string(cipher_text, key, connection, resource_id, is_server):
    """
    Decifra una stringa cifrata con AES-128 in modalità CBC.
 
    Args:
        cipher_text (str): La stringa cifrata in formato "IV:EncryptedText", entrambi Base64.
        key (str): La chiave di decriptazione (16 caratteri).
 
    Returns:
        str: Il testo decifrato.
    """
    # Controlla che la chiave sia lunga 16 caratteri
    if len(key) != 16:
        error_message = "La chiave deve essere lunga 16 byte."
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
 
    # Dividi l'IV e il testo cifrato
    iv_b64, encrypted_b64 = cipher_text.split(":")
    iv = b64decode(iv_b64)
    encrypted_bytes = b64decode(encrypted_b64)
 
    # Decripta i dati
    cipher = AES.new(key.encode('utf-8'), AES.MODE_CBC, iv)
    decrypted_bytes = cipher.decrypt(encrypted_bytes)
 
    # Rimuovi eventuale padding (PKCS7)
    pad_len = decrypted_bytes[-1]
    decrypted_text = decrypted_bytes[:-pad_len].decode('utf-8')
 
    return decrypted_text
 
def get_token_morpheus(decrypted_text, connection, resource_id, is_server):
    try:
        # Se decrypted_text è una stringa, proviamo a convertirlo in lista
        if isinstance(decrypted_text, str):
            try:
                decrypted_text = json.loads(decrypted_text)  # Converte la stringa in lista JSON
            except json.JSONDecodeError:
                error_message = "Il valore decriptato non è una lista JSON valida."
                handle_response(connection, resource_id, "failed", error_message, None, is_server)
                sys.exit(1)
 
        # Controlla se ora è una lista
        if not isinstance(decrypted_text, list):
            error_message = "Il valore decriptato non è una lista JSON valida."
            handle_response(connection, resource_id, "failed", error_message, None, is_server)
            sys.exit(1)
 
        # Cerca la chiave che inizia con "TS-SYSUSR-PDEPLOY-API-TOKEN"
        for entry in decrypted_text:
            if entry.startswith("secret/TS-SYSUSR-PDEPLOY-API-TOKEN"):
                parts = entry.split(",")
                if len(parts) == 2:  # Assicura che ci sia una coppia chiave-valore
                    return parts[1]
 
        # Se nessuna chiave viene trovata, solleva un'eccezione
        error_message = "Nessuna chiave TS-SYSUSR-PDEPLOY-API-TOKEN trovata nel testo decriptato."
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
 
    except (KeyError, ValueError, IndexError) as e:
        error_message = f"Errore durante l'estrazione della chiave: {str(e)}"
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
 
def get_generated_hostname(connection, resource_id, is_server):
    """
    Recupera l'hostname generato da Morpheus.
 
    Args:
        connection: Connessione al database.
        resource_id: ID della risorsa (instance_id o server_id).
        is_server: Booleano che indica se la risorsa è un server.
 
    Returns:
        str: L'hostname generato.
 
    Raises:
        Termina lo script se i dati richiesti non sono presenti o validi.
    """
    try:
        # Verifica che 'results' sia presente e non nullo
        results = morpheus.get('results', None)
        if not results:
            error_message = "'morpheus.results' non esiste o è nullo."
            handle_response(connection, resource_id, "failed", error_message, None, is_server)
            sys.exit(1)
        # Verifica che 'add_hostname_hash' sia presente e non nullo
        hostname_data = results.get('add_hostname_hash', None)
        if not hostname_data or 'message' not in hostname_data:
            error_message = "'add_hostname_hash' non è presente nei risultati o è nullo."
            handle_response(connection, resource_id, "failed", error_message, None, is_server)
            sys.exit(1)
 
        return hostname_data['message']
 
    except KeyError as e:
        error_message = f"Errore chiave mancante: {str(e)}"
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
    except Exception as e:
        error_message = f"Errore imprevisto durante il recupero dell'hostname: {str(e)}"
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
 
def get_instance_details(connection, instance_id, TOKEN, HTTP_HEADERS, HOST):
    try:
        instance_id = morpheus['instance']['id']
        url_instance = f"https://{HOST}/api/instances/{instance_id}"
        response = requests.get(url_instance, headers=HTTP_HEADERS, verify=True, timeout=10)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        error_message = f"Errore durante il recupero dei dettagli dell'istanza: {e}"
        handle_response(connection, instance_id, "failed", error_message)
        sys.exit(1)
 
def get_hostname(connection, resource_id, is_server):
    """
    Recupera l'hostname da morpheus['instance']['container']['server']['hostname']
    o, in alternativa, da morpheus['server']['hostname'].
 
    Args:
        connection: Connessione al database.
        resource_id: ID della risorsa (instance_id o server_id).
        is_server: Booleano che indica se la risorsa è un server.
 
    Returns:
        str: L'hostname recuperato.
 
    Raises:
        Termina lo script se nessuna chiave è disponibile o se i valori sono nulli.
    """
    try:
        # Prova ad accedere a morpheus['instance']['container']['server']['hostname']
        instance = morpheus.get("instance", {})
        if isinstance(instance, dict):
            container = instance.get("container", {})
            if isinstance(container, dict):
                server = container.get("server", {})
                if isinstance(server, dict):
                    hostname = server.get("hostname", None)
                    if hostname:
                        return hostname
 
        # Se non trovato, prova ad accedere a morpheus['server']['hostname']
        server = morpheus.get("server", {})
        if isinstance(server, dict):
            hostname = server.get("hostname", None)
            if hostname:
                return hostname
 
        # Se nessun hostname è disponibile, genera un errore
        error_message = "Hostname non trovato né in 'instance' né in 'server'."
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
 
    except Exception as e:
        # Gestione di errori generici
        error_message = f"Errore durante il recupero dell'hostname: {e}"
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
 
 
def update_hostname(new_hostname, TOKEN, connection, resource_id, is_server, instance_id, server_id):
    """
    Aggiorna l'hostname di una VM tramite l'API di Morpheus, utilizzando instance_id o server_id.
 
    Args:
        instance_id (str): ID dell'istanza.
        server_id (str): ID del server.
        new_hostname (str): Nuovo hostname da impostare.
        connection: Connessione al database.
        TOKEN (str): Token di autenticazione.
 
    Returns:
        dict: Risposta JSON dell'API.
 
    Raises:
        SystemExit: Se nessuno dei due ID è disponibile o si verifica un errore.
    """
    try:
        HOST = morpheus.get("morpheus", {}).get("applianceHost", "")
        HTTP_HEADERS = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Authorization": f"BEARER {TOKEN}"
        }
 
        # Se instance_id è presente, aggiorna l'hostname tramite l'API delle istanze
        if instance_id:
            instance_details = get_instance_details(connection, instance_id, TOKEN, HTTP_HEADERS, HOST)
            for container in instance_details['instance']['containerDetails']:
                server_id_instance = container['server']['id']
                url_server = f"https://{HOST}/api/servers/{server_id_instance}"
                payload = {"server": {"hostName": new_hostname}}
                response_server = requests.put(url_server, headers=HTTP_HEADERS, json=payload, verify=True, timeout=10)
                response_server.raise_for_status()
            #url_instance = f"https://{HOST}/api/instances/{instance_id}"
            #payload = {"instance": {"hostname": new_hostname}}
            #response = requests.put(url_instance, headers=HTTP_HEADERS, json=payload, verify=True, timeout=10)
            #response.raise_for_status()
            
 
            handle_response(connection, instance_id, "success", "Hostname aggiornato con successo.", None, is_server)
 
        # Altrimenti, se server_id è presente, aggiorna l'hostname tramite l'API dei server
        elif server_id:
            url_server = f"https://{HOST}/api/servers/{server_id}"
            payload = {"server": {"hostname": new_hostname}}
            response = requests.put(url_server, headers=HTTP_HEADERS, json=payload, verify=True, timeout=10)
            response.raise_for_status()
            handle_response(connection, server_id, "success", "Hostname aggiornato con successo.", {"update_response": response.json()}, is_server)
 
        # Se nessuno dei due ID è disponibile, restituisce un errore
        else:
            handle_response(connection, resource_id, "failed", "Né instance_id né server_id sono disponibili per aggiornare l'hostname.", {"update_response": response.json()}, is_server)
            sys.exit(1)
 
    except requests.exceptions.RequestException as e:
        error_message = f"Errore durante l'aggiornamento dell'hostname: {e}"
        handle_response(connection, resource_id, "failed", error_message, None, is_server)
        sys.exit(1)
 
# Funzione principale
def main():
    check_db()
    connection = None
    try:
        instance_id = morpheus.get("instance", {}).get("id", None)
        server_id = morpheus.get("server", {}).get("id", None)
        resource_id = instance_id if instance_id is not None else server_id
        is_server = server_id is not None
        if not resource_id:
            print(json.dumps({"status": "failed", "message": "ID della risorsa non trovato (né instance_id né server_id)."}, indent=2))
            sys.exit(1)
 
        db_pw, db_user, db_server, Key = get_command_line_args(connection, resource_id, is_server)
        connection = connect_to_database(db_pw, db_user, db_server)
 
        # Ottieni il token Morpheus
        cypher_text = get_prefix_fw_result(connection, resource_id, is_server)
        decrypted_text = decrypt_string(cypher_text, Key, connection, resource_id, is_server)
        TOKEN = get_token_morpheus(decrypted_text, connection, resource_id, is_server)
 
        new_hostname = get_generated_hostname(connection, resource_id, is_server)
        ipv4 = get_ipv4_address()
        fqdn = f"{new_hostname}.cloud.teamsystem.com"
    
        # (facoltativo) aggiungere al file hosts
        # with open(r"C:\Windows\System32\drivers\etc\hosts", "a") as f:
        #     f.write(f"{ipv4} {fqdn}\n")
    
        send_morpheus_output("Success", f"{new_hostname} | {ipv4}")
 
 
    except Exception as e:
        handle_response(connection, resource_id, "failed", f"Errore generico: {e}", None, is_server)
    finally:
        if connection and connection.is_connected():
            connection.close()
 
if __name__ == "__main__":
    main()
