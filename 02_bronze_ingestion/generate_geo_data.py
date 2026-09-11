import csv
import random
import os
from datetime import datetime, timezone

# Catálogo de ciudades y coordenadas en Europa para EuroBank
EUROPEAN_CITIES = [
    {"city": "Madrid", "country": "ES", "lat_range": (40.38, 40.48), "lon_range": (-3.75, -3.65), "tz": "Europe/Madrid"},
    {"city": "Barcelona", "country": "ES", "lat_range": (41.35, 41.45), "lon_range": (2.10, 2.22), "tz": "Europe/Madrid"},
    {"city": "Paris", "country": "FR", "lat_range": (48.82, 48.90), "lon_range": (2.28, 2.42), "tz": "Europe/Paris"},
    {"city": "Frankfurt", "country": "DE", "lat_range": (50.08, 50.15), "lon_range": (8.62, 8.74), "tz": "Europe/Berlin"},
    {"city": "Milan", "country": "IT", "lat_range": (45.43, 45.50), "lon_range": (9.15, 9.25), "tz": "Europe/Rome"},
    {"city": "Lisbon", "country": "PT", "lat_range": (38.70, 38.78), "lon_range": (-9.18, -9.10), "tz": "Europe/Lisbon"},
    {"city": "Dublin", "country": "IE", "lat_range": (53.30, 53.38), "lon_range": (-6.32, -6.20), "tz": "Europe/Dublin"}
]

# Mismos user_ids de los logs móviles para permitir cruces (JOINs) en la capa Silver/Gold
USERS = ["usr-1001", "usr-1002", "usr-1003", "usr-1004", "usr-1005", "usr-1006", "usr-1007"]
CONNECTION_TYPES = ["WIFI", "5G", "4G", "CELLULAR"]

def generate_geolocation_data(num_records=150):
    records = []
    for i in range(1, num_records + 1):
        location_info = random.choice(EUROPEAN_CITIES)
        user_id = random.choice(USERS)
        
        lat = round(random.uniform(*location_info["lat_range"]), 6)
        lon = round(random.uniform(*location_info["lon_range"]), 6)
        accuracy_meters = round(random.uniform(3.5, 25.0), 1)
        
        records.append({
            "geo_event_id": f"GEO-{10000 + i}",
            "user_id": user_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "latitude": lat,
            "longitude": lon,
            "accuracy_meters": accuracy_meters,
            "city": location_info["city"],
            "country_code": location_info["country"],
            "timezone": location_info["tz"],
            "connection_type": random.choice(CONNECTION_TYPES),
            "is_vpn_detected": random.choice([False, False, False, True]) # 25% prob de VPN
        })
    return records

def save_csv(records, output_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    fields = [
        "geo_event_id", "user_id", "timestamp", "latitude", "longitude",
        "accuracy_meters", "city", "country_code", "timezone", "connection_type", "is_vpn_detected"
    ]
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)
    print(f"Dataset CSV generado exitosamente en: {output_path} ({len(records)} filas)")

if __name__ == "__main__":
    output_csv = "data_samples/geolocation_events_batch_001.csv"
    data = generate_geolocation_data(200)
    save_csv(data, output_csv)
