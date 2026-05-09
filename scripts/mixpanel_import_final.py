"""
AI Platform Growth Product Analytics Project
Mixpanel Data Import Script
============================================================
HOW TO RUN:
1. Put this file in the same folder as events_final.csv
2. Open terminal in that folder
3. Run:
   pip install requests pandas
   python mixpanel_import_final.py
============================================================
"""

import requests
import pandas as pd
import json
import time
from datetime import datetime

PROJECT_TOKEN  = "368737542e11080ee9f1536147ca6e5b"
PROJECT_SECRET = "05402e18d75644f11adb90b76feb602d"

CSV_FILE   = "events_final.csv"
BATCH_SIZE = 2000
API_URL    = "https://api.mixpanel.com/import"

print("Loading events_final.csv...")
df = pd.read_csv(CSV_FILE)
print(f"Loaded {len(df):,} events")
print(f"Columns: {list(df.columns)}")
print()

def row_to_event(row):
    try:
        unix_time = int(pd.to_datetime(row['time']).timestamp())
    except:
        unix_time = int(datetime.now().timestamp())

    props = {
        "distinct_id": str(row['user_id']),
        "time":        unix_time,
        "$insert_id":  str(row['insert_id']),
        "token":       PROJECT_TOKEN,
    }

    for col in df.columns:
        if col not in ['insert_id', 'user_id', 'event_type', 'time']:
            val = row[col]
            if pd.notna(val) and str(val).strip() not in ['', 'nan']:
                props[col] = str(val)

    return {"event": str(row['event_type']), "properties": props}

print("Converting events...")
events = [row_to_event(row) for _, row in df.iterrows()]
print(f"Ready: {len(events):,} events")
print()

total   = len(events)
sent    = 0
errors  = 0
batches = (total + BATCH_SIZE - 1) // BATCH_SIZE
print(f"Sending in {batches} batches...")
print("=" * 50)

for i in range(0, total, BATCH_SIZE):
    batch     = events[i:i + BATCH_SIZE]
    batch_num = (i // BATCH_SIZE) + 1
    try:
        resp = requests.post(
            API_URL,
            params  = {"strict": "1"},
            auth    = (PROJECT_SECRET, ""),
            headers = {"Content-Type": "application/json"},
            data    = json.dumps(batch),
            timeout = 30
        )
        if resp.status_code == 200:
            sent += len(batch)
            print(f"  Batch {batch_num}/{batches} ✓  {sent:,}/{total:,} sent")
        else:
            errors += len(batch)
            print(f"  Batch {batch_num}/{batches} ✗  HTTP {resp.status_code}: {resp.text[:200]}")
    except Exception as e:
        errors += len(batch)
        print(f"  Batch {batch_num}/{batches} ✗  {e}")
    time.sleep(0.2)

print()
print("=" * 50)
print(f"DONE — {sent:,} sent, {errors:,} errors")
print("Go to Mixpanel → Data → Events to verify")
print("Properties: product, ab variant, segment, country, plan type")
