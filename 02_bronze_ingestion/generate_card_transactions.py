import json
import random
import sys
import uuid
import os
from datetime import datetime, timezone

# Mismos user_ids de los logs móviles y geolocalización para JOINs multicloud
USERS = [
    {"user_id": "usr-1001", "card_last4": "4210", "card_type": "VISA_DEBIT"},
    {"user_id": "usr-1002", "card_last4": "8841", "card_type": "MASTERCARD_CREDIT"},
    {"user_id": "usr-1003", "card_last4": "1903", "card_type": "VISA_PREMIUM"},
    {"user_id": "usr-1004", "card_last4": "7722", "card_type": "MASTERCARD_DEBIT"},
    {"user_id": "usr-1005", "card_last4": "5512", "card_type": "VISA_BUSINESS"},
    {"user_id": "usr-1006", "card_last4": "9934", "card_type": "MASTERCARD_GOLD"},
    {"user_id": "usr-1007", "card_last4": "3341", "card_type": "VISA_CLASSIC"}
]

MERCHANTS = [
    {"name": "Mercadona", "mcc": "5411", "category": "Groceries"},
    {"name": "Amazon EU", "mcc": "5399", "category": "Online Retail"},
    {"name": "Zara Inditex", "mcc": "5651", "category": "Apparel"},
    {"name": "Uber Rides", "mcc": "4121", "category": "Transportation"},
    {"name": "Iberia Airlines", "mcc": "4511", "category": "Travel"},
    {"name": "Starbucks Coffee", "mcc": "5814", "category": "Food & Drink"},
    {"name": "Repsol Gas", "mcc": "5541", "category": "Fuel"}
]

CURRENCIES = ["EUR", "EUR", "EUR", "USD", "GBP"]
STATUSES = ["APPROVED", "APPROVED", "APPROVED", "APPROVED", "DECLINED"]

def generate_card_transactions(num_records=150):
    transactions = []
    for _ in range(num_records):
        user = random.choice(USERS)
        merchant = random.choice(MERCHANTS)
        currency = random.choice(CURRENCIES)
        amount = round(random.uniform(2.50, 480.00), 2)
        
        tx = {
            "transaction_id": f"TXN-{uuid.uuid4().hex[:12].upper()}",
            "user_id": user["user_id"],
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "amount": amount,
            "currency": currency,
            "card_last_four": user["card_last4"],
            "card_type": user["card_type"],
            "merchant_name": merchant["name"],
            "merchant_category_code": merchant["mcc"],
            "category": merchant["category"],
            "status": random.choice(STATUSES),
            "auth_method": random.choice(["CONTACTLESS", "CHIP_PIN", "ECOMMERCE", "APPLE_PAY"]),
            "is_fraud_flag": random.choice([False, False, False, False, True]) # 20% sospecha para analítica
        }
        transactions.append(tx)
    return transactions

def save_json(transactions, output_path):
    # JSONL: un JSON por línea (Auto Loader format=json no soporta arrays multi-línea)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        for tx in transactions:
            f.write(json.dumps(tx, ensure_ascii=False) + "\n")
    print(f"Dataset JSONL generado en: {output_path} ({len(transactions)} registros)")

if __name__ == "__main__":
    output_file = sys.argv[1] if len(sys.argv) > 1 else "data_samples/card_transactions_batch_001.jsonl"
    data = generate_card_transactions(150)
    save_json(data, output_file)
