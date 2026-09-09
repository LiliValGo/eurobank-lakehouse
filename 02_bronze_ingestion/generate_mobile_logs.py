import json
import gzip
import random
import uuid
from datetime import datetime, timezone
import os

# Esquema de Logs de Aplicaciones Móviles de EuroBank
# Incluye eventos comunes, metadatos de dispositivo y PII (email, user_id) para probar GDPR
EVENT_TYPES = [
    "LOGIN_SUCCESS", "LOGIN_FAILED", "VIEW_ACCOUNT_BALANCE",
    "TRANSFER_SUBMITTED", "CARD_BLOCKED", "BIOMETRIC_AUTH", "LOGOUT"
]
DEVICE_OS = ["iOS 18.2", "iOS 17.5", "Android 15", "Android 14"]
APP_VERSIONS = ["v3.12.0", "v3.11.4", "v3.12.1"]

SAMPLE_USERS = [
    {"user_id": "usr-1001", "email": "carlos.mendoza@eurobank.com", "device": "iPhone 16 Pro"},
    {"user_id": "usr-1002", "email": "lucia.garcia@eurobank.com", "device": "Samsung Galaxy S24"},
    {"user_id": "usr-1003", "email": "elena.dupont@eurobank.com", "device": "Pixel 9 Pro"},
    {"user_id": "usr-1004", "email": "marco.rossi@eurobank.com", "device": "iPhone 15"},
    {"user_id": "usr-1005", "email": "ana.silva@eurobank.com", "device": "Xiaomi 14"},
]

def generate_mobile_logs(num_records=50):
    logs = []
    for _ in range(num_records):
        user = random.choice(SAMPLE_USERS)
        event = random.choice(EVENT_TYPES)
        log_entry = {
            "event_id": str(uuid.uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "user_id": user["user_id"],
            "user_email": user["email"],
            "event_type": event,
            "device_model": user["device"],
            "os_version": random.choice(DEVICE_OS),
            "app_version": random.choice(APP_VERSIONS),
            "session_id": str(uuid.uuid4())[:8],
            "ip_address": f"192.168.{random.randint(1, 254)}.{random.randint(1, 254)}",
            "metadata": {
                "screen": "HomeView" if "VIEW" in event else "SecurityView",
                "latency_ms": random.randint(35, 320),
                "is_jailbroken_or_rooted": False
            }
        }
        logs.append(log_entry)
    return logs

def save_compressed_json(logs, output_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with gzip.open(output_path, "wt", encoding="utf-8") as gz_file:
        for log in logs:
            # Formato JSON Lines (.jsonl) comprimido con gzip
            gz_file.write(json.dumps(log) + "\n")
    print(f"Archivo generado exitosamente en: {output_path} ({len(logs)} eventos)")

if __name__ == "__main__":
    output_filename = "data_samples/mobile_logs_batch_001.json.gz"
    logs = generate_mobile_logs(100)
    save_compressed_json(logs, output_filename)
