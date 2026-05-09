"""
AI Chatbot Wars — Synthetic Data Generator
============================================
Generates realistic user behavior data for 4 AI products:
Claude, ChatGPT, Gemini, Grok

Output: 4 CSV files
  - users.csv         (~10,000 rows)
  - sessions.csv      (~180,000 rows)
  - events.csv        (~600,000 rows)
  - subscriptions.csv (~2,500 rows)

Design principles:
  - Each product has distinct retention/engagement characteristics
  - Realistic funnel drop-off (not everyone activates)
  - A/B test baked in (suggested_prompts experiment)
  - Power users, casual users, and churned users all represented
  - Seasonal patterns (weekday vs weekend usage)
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import random
import uuid
import os

# ── Reproducibility ────────────────────────────────────────────────────────────
np.random.seed(42)
random.seed(42)

# ── Config ─────────────────────────────────────────────────────────────────────
START_DATE = datetime(2025, 11, 1)
END_DATE   = datetime(2026, 4, 30)
N_USERS    = 10_000
OUTPUT_DIR = "/home/claude/data"
os.makedirs(OUTPUT_DIR, exist_ok=True)

PRODUCTS = ["Claude", "ChatGPT", "Gemini", "Grok"]

# Product share of new signups (roughly realistic market share)
PRODUCT_WEIGHTS = [0.22, 0.40, 0.25, 0.13]

# Each product has different behavioral DNA
PRODUCT_PROFILES = {
    "Claude": {
        "activation_rate":      0.74,   # % who send first message within 24h
        "d7_retention_base":    0.43,   # Day-7 retention (control group)
        "d30_retention_base":   0.22,
        "pro_conversion_rate":  0.09,
        "avg_session_minutes":  11.2,
        "avg_turns_per_session": 5.1,
        "power_user_pct":       0.18,
        "feature_adoption":     0.35,
    },
    "ChatGPT": {
        "activation_rate":      0.71,
        "d7_retention_base":    0.45,
        "d30_retention_base":   0.24,
        "pro_conversion_rate":  0.11,
        "avg_session_minutes":  9.8,
        "avg_turns_per_session": 4.7,
        "power_user_pct":       0.21,
        "feature_adoption":     0.38,
    },
    "Gemini": {
        "activation_rate":      0.68,
        "d7_retention_base":    0.38,
        "d30_retention_base":   0.18,
        "pro_conversion_rate":  0.07,
        "avg_session_minutes":  8.4,
        "avg_turns_per_session": 4.1,
        "power_user_pct":       0.14,
        "feature_adoption":     0.29,
    },
    "Grok": {
        "activation_rate":      0.61,
        "d7_retention_base":    0.34,
        "d30_retention_base":   0.15,
        "pro_conversion_rate":  0.06,
        "avg_session_minutes":  7.1,
        "avg_turns_per_session": 3.8,
        "power_user_pct":       0.12,
        "feature_adoption":     0.24,
    },
}

COUNTRIES       = ["IN", "US", "GB", "DE", "BR", "CA", "AU", "FR", "SG", "NG"]
COUNTRY_WEIGHTS = [0.22, 0.28, 0.08, 0.07, 0.06, 0.06, 0.04, 0.05, 0.04, 0.04]  # must sum to ~1
PLATFORMS       = ["web", "ios", "android"]
PLATFORM_WEIGHTS= [0.55, 0.28, 0.17]
SIGNUP_SOURCES  = ["organic_search", "social_media", "referral", "direct", "paid_ad", "app_store"]
SIGNUP_WEIGHTS  = [0.30, 0.22, 0.18, 0.15, 0.10, 0.05]
FEATURES        = ["code_generation", "image_input", "memory", "plugins", "file_upload"]
PLAN_TYPES      = ["free", "pro", "team"]
PLAN_WEIGHTS    = [0.78, 0.17, 0.05]

# A/B test: 50/50 split across all users
AB_VARIANTS     = ["control", "treatment"]

# ── Helper functions ────────────────────────────────────────────────────────────

def rand_date(start, end):
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, delta))

def weighted_choice(options, weights):
    return random.choices(options, weights=weights, k=1)[0]

def is_weekday(dt):
    return dt.weekday() < 5  # Monday=0, Friday=4

def session_prob_by_day(dt):
    """Users are ~40% less likely to use AI tools on weekends"""
    return 1.0 if is_weekday(dt) else 0.62

def user_segment(profile, is_power):
    """Assign user segment based on profile and power user flag"""
    if is_power:
        return "power_user"
    # 60% casual, 40% task-triager among non-power users
    return weighted_choice(["casual_explorer", "task_triager"], [0.60, 0.40])


# ── 1. GENERATE USERS TABLE ─────────────────────────────────────────────────────
print("Generating users...")

users = []
for i in range(N_USERS):
    product      = weighted_choice(PRODUCTS, PRODUCT_WEIGHTS)
    profile      = PRODUCT_PROFILES[product]
    signup_date  = rand_date(START_DATE, END_DATE - timedelta(days=30))
    plan_type    = weighted_choice(PLAN_TYPES, PLAN_WEIGHTS)
    is_power     = random.random() < profile["power_user_pct"]
    segment      = user_segment(profile, is_power)
    ab_variant   = weighted_choice(AB_VARIANTS, [0.5, 0.5])

    # Activation: did the user send their first message within 24h?
    # Treatment group gets a boost from suggested prompts
    activation_boost = 0.07 if ab_variant == "treatment" else 0.0
    activated = random.random() < (profile["activation_rate"] + activation_boost)

    # Retained users — did they come back on Day 7 / Day 30?
    # Power users have higher retention
    retention_mult = 1.4 if is_power else (1.0 if segment == "casual_explorer" else 0.6)
    d7_retained  = activated and (random.random() < profile["d7_retention_base"] * retention_mult)
    d30_retained = d7_retained and (random.random() < profile["d30_retention_base"] * retention_mult)

    # Plan upgrade probability (higher for activated + retained users)
    upgrade_prob = profile["pro_conversion_rate"] if d7_retained else profile["pro_conversion_rate"] * 0.2
    will_upgrade = plan_type == "free" and random.random() < upgrade_prob

    users.append({
        "user_id":        f"u_{i+1:06d}",
        "product":        product,
        "signup_date":    signup_date.strftime("%Y-%m-%d"),
        "plan_type":      plan_type,
        "country":        weighted_choice(COUNTRIES, COUNTRY_WEIGHTS),
        "platform":       weighted_choice(PLATFORMS, PLATFORM_WEIGHTS),
        "signup_source":  weighted_choice(SIGNUP_SOURCES, SIGNUP_WEIGHTS),
        "ab_variant":     ab_variant,
        "segment":        segment,
        "activated":      activated,
        "d7_retained":    d7_retained,
        "d30_retained":   d30_retained,
        "will_upgrade":   will_upgrade,  # used later for subscriptions
    })

users_df = pd.DataFrame(users)
print(f"  Users: {len(users_df):,}")

# ── 2. GENERATE SESSIONS TABLE ──────────────────────────────────────────────────
print("Generating sessions...")

sessions = []

for _, user in users_df.iterrows():
    profile   = PRODUCT_PROFILES[user["product"]]
    signup_dt = datetime.strptime(user["signup_date"], "%Y-%m-%d")
    segment   = user["segment"]

    if not user["activated"]:
        # Not activated = at most 1 incomplete session (they bounced)
        if random.random() < 0.4:
            sess_start = signup_dt + timedelta(hours=random.randint(1, 12))
            sessions.append({
                "session_id":        f"s_{len(sessions)+1:08d}",
                "user_id":           user["user_id"],
                "product":           user["product"],
                "session_date":      sess_start.strftime("%Y-%m-%d"),
                "session_start":     sess_start.strftime("%Y-%m-%d %H:%M:%S"),
                "duration_seconds":  random.randint(30, 180),  # bounced quickly
                "message_count":     0,
                "features_used":     "",
                "session_type":      "bounce",
                "days_since_signup": 0,
            })
        continue

    # Activated user — generate a realistic session history
    # Base frequency depends on segment
    base_freq = {
        "power_user":      6.5,   # sessions per week
        "casual_explorer": 2.2,
        "task_triager":    0.8,
    }[segment]

    # Build day-by-day session probability
    max_days = min((END_DATE - signup_dt).days, 180)

    for day_offset in range(max_days):
        current_date = signup_dt + timedelta(days=day_offset)

        # Retention decay — engagement naturally drops over time
        # but power users flatten out
        if segment == "power_user":
            decay = max(0.6, 1.0 - day_offset * 0.001)
        elif segment == "casual_explorer":
            decay = max(0.2, 1.0 - day_offset * 0.006)
        else:
            decay = max(0.05, 1.0 - day_offset * 0.015)

        # Day-7 and Day-30 cliffs (the real drop-off moments)
        if day_offset == 7 and not user["d7_retained"]:
            break  # user churned at Day 7
        if day_offset == 30 and not user["d30_retained"] and segment != "power_user":
            decay *= 0.15  # heavy reduction for non-retained users

        daily_prob = (base_freq / 7) * decay * session_prob_by_day(current_date)
        daily_prob = min(daily_prob, 0.95)  # cap at 95%

        if random.random() > daily_prob:
            continue  # no session today

        # Session happened — build it
        hour = random.choices(range(24), weights=[
            1,1,1,1,1,2, 3,5,7,8,8,8, 7,7,8,8,7,6, 8,9,8,6,4,2
        ])[0]
        sess_start = current_date.replace(hour=hour, minute=random.randint(0,59))

        avg_turns = profile["avg_turns_per_session"]
        msg_count = max(1, int(np.random.normal(avg_turns, avg_turns * 0.4)))

        avg_mins  = profile["avg_session_minutes"]
        duration  = max(60, int(np.random.normal(avg_mins * 60, avg_mins * 20)))

        # Feature usage
        uses_feature = random.random() < profile["feature_adoption"]
        feature_used = random.choice(FEATURES) if uses_feature else ""

        sessions.append({
            "session_id":        f"s_{len(sessions)+1:08d}",
            "user_id":           user["user_id"],
            "product":           user["product"],
            "session_date":      sess_start.strftime("%Y-%m-%d"),
            "session_start":     sess_start.strftime("%Y-%m-%d %H:%M:%S"),
            "duration_seconds":  duration,
            "message_count":     msg_count,
            "features_used":     feature_used,
            "session_type":      "active",
            "days_since_signup": day_offset,
        })

sessions_df = pd.DataFrame(sessions)
print(f"  Sessions: {len(sessions_df):,}")

# ── 3. GENERATE EVENTS TABLE ────────────────────────────────────────────────────
print("Generating events...")

events = []

def add_event(user_id, product, event_name, ts, session_id=None, properties=None):
    events.append({
        "event_id":        f"e_{len(events)+1:09d}",
        "user_id":         user_id,
        "product":         product,
        "event_name":      event_name,
        "event_timestamp": ts.strftime("%Y-%m-%d %H:%M:%S"),
        "session_id":      session_id or "",
        "properties":      str(properties or {}),
    })

for _, user in users_df.iterrows():
    signup_dt = datetime.strptime(user["signup_date"], "%Y-%m-%d")
    uid       = user["user_id"]
    product   = user["product"]

    # account_created
    add_event(uid, product, "account_created", signup_dt, properties={
        "signup_source": user["signup_source"],
        "plan_type":     user["plan_type"],
        "country":       user["country"],
        "platform":      user["platform"],
        "ab_variant":    user["ab_variant"],
    })

    if not user["activated"]:
        # Some non-activated users still hit the first onboarding step
        if random.random() < 0.55:
            add_event(uid, product, "onboarding_step_completed",
                      signup_dt + timedelta(minutes=random.randint(2, 30)),
                      properties={"step_name": "profile_setup", "step_number": 1, "ab_variant": user["ab_variant"]})
        continue

    # Onboarding funnel — step 1: profile setup
    t1 = signup_dt + timedelta(minutes=random.randint(2, 15))
    add_event(uid, product, "onboarding_step_completed", t1, properties={
        "step_name": "profile_setup", "step_number": 1,
        "time_on_step_seconds": random.randint(30, 300), "ab_variant": user["ab_variant"]
    })

    # Step 2: first message — treatment group is faster
    if user["ab_variant"] == "treatment":
        delay_mins = random.randint(1, 8)   # suggested prompts = faster
    else:
        delay_mins = random.randint(3, 20)
    t2 = t1 + timedelta(minutes=delay_mins)
    add_event(uid, product, "onboarding_step_completed", t2, properties={
        "step_name": "first_message", "step_number": 2,
        "time_on_step_seconds": delay_mins * 60, "ab_variant": user["ab_variant"]
    })
    add_event(uid, product, "message_sent", t2, properties={
        "turn_number": 1, "message_length": random.randint(20, 200),
        "feature_used": "", "ab_variant": user["ab_variant"]
    })

# Session-level events
for _, sess in sessions_df[sessions_df["session_type"] == "active"].iterrows():
    sess_dt  = datetime.strptime(sess["session_start"], "%Y-%m-%d %H:%M:%S")
    sid      = sess["session_id"]
    uid      = sess["user_id"]
    product  = sess["product"]

    add_event(uid, product, "session_started", sess_dt, session_id=sid, properties={
        "days_since_signup": int(sess["days_since_signup"]),
        "platform": users_df[users_df["user_id"] == uid]["platform"].values[0],
    })

    # message_sent events within the session
    for turn in range(int(sess["message_count"])):
        msg_time = sess_dt + timedelta(seconds=random.randint(turn * 30, turn * 120 + 60))
        add_event(uid, product, "message_sent", msg_time, session_id=sid, properties={
            "turn_number":    turn + 1,
            "message_length": random.randint(15, 400),
            "feature_used":   sess["features_used"] if turn == 1 else "",
        })

    # feature_used event if applicable
    if sess["features_used"]:
        feat_time = sess_dt + timedelta(seconds=random.randint(60, 300))
        add_event(uid, product, "feature_used", feat_time, session_id=sid, properties={
            "feature_name": sess["features_used"],
        })

    # session_ended
    sess_end = sess_dt + timedelta(seconds=int(sess["duration_seconds"]))
    add_event(uid, product, "session_ended", sess_end, session_id=sid, properties={
        "duration_seconds":    int(sess["duration_seconds"]),
        "messages_in_session": int(sess["message_count"]),
    })

events_df = pd.DataFrame(events)
print(f"  Events: {len(events_df):,}")

# ── 4. GENERATE SUBSCRIPTIONS TABLE ─────────────────────────────────────────────
print("Generating subscriptions...")

subscriptions = []
PLAN_REVENUE = {"free": 0, "pro": 20, "team": 35}

for _, user in users_df[users_df["will_upgrade"] == True].iterrows():
    signup_dt    = datetime.strptime(user["signup_date"], "%Y-%m-%d")
    # Upgrades happen between Day 3 and Day 25
    upgrade_day  = random.randint(3, 25)
    upgrade_date = signup_dt + timedelta(days=upgrade_day)
    if upgrade_date > END_DATE:
        continue
    new_plan = weighted_choice(["pro", "team"], [0.85, 0.15])
    subscriptions.append({
        "subscription_id": f"sub_{len(subscriptions)+1:06d}",
        "user_id":         user["user_id"],
        "product":         user["product"],
        "from_plan":       "free",
        "to_plan":         new_plan,
        "change_date":     upgrade_date.strftime("%Y-%m-%d"),
        "revenue_usd":     PLAN_REVENUE[new_plan],
        "churn_date":      "",  # still active
    })

# Some pro users churn (cancel subscription)
for sub in subscriptions:
    if random.random() < 0.18:  # 18% churn their subscription within the period
        change_dt  = datetime.strptime(sub["change_date"], "%Y-%m-%d")
        churn_days = random.randint(30, 90)
        churn_dt   = change_dt + timedelta(days=churn_days)
        if churn_dt <= END_DATE:
            sub["churn_date"] = churn_dt.strftime("%Y-%m-%d")

subs_df = pd.DataFrame(subscriptions)
print(f"  Subscriptions: {len(subs_df):,}")

# ── 5. SAVE CSVs ─────────────────────────────────────────────────────────────────
print("\nSaving CSVs...")

# Drop internal helper columns before saving
users_df.drop(columns=["will_upgrade"], inplace=True)

users_df.to_csv(f"{OUTPUT_DIR}/users.csv", index=False)
sessions_df.to_csv(f"{OUTPUT_DIR}/sessions.csv", index=False)
events_df.to_csv(f"{OUTPUT_DIR}/events.csv", index=False)
subs_df.to_csv(f"{OUTPUT_DIR}/subscriptions.csv", index=False)

print(f"\n✓ All files saved to {OUTPUT_DIR}/")
print("=" * 50)

# ── 6. QUICK SANITY CHECK ────────────────────────────────────────────────────────
print("\nSANITY CHECK REPORT")
print("=" * 50)

print("\n[ Users by product ]")
print(users_df.groupby("product").size().to_string())

print("\n[ Activation rate by product ]")
act = users_df.groupby("product")["activated"].mean().round(3)
print(act.to_string())

print("\n[ D7 retention by product ]")
d7 = users_df.groupby("product")["d7_retained"].mean().round(3)
print(d7.to_string())

print("\n[ D30 retention by product ]")
d30 = users_df.groupby("product")["d30_retained"].mean().round(3)
print(d30.to_string())

print("\n[ Sessions by product ]")
print(sessions_df[sessions_df["session_type"]=="active"].groupby("product").size().to_string())

print("\n[ A/B test - activation by variant ]")
ab_check = users_df.groupby("ab_variant")["activated"].mean().round(3)
print(ab_check.to_string())

print("\n[ Top event types ]")
print(events_df["event_name"].value_counts().head(10).to_string())

print("\n[ Subscriptions by product ]")
print(subs_df.groupby("product").size().to_string())

print("\n[ File sizes ]")
for fname in ["users.csv", "sessions.csv", "events.csv", "subscriptions.csv"]:
    size_kb = os.path.getsize(f"{OUTPUT_DIR}/{fname}") / 1024
    rows    = sum(1 for _ in open(f"{OUTPUT_DIR}/{fname}")) - 1
    print(f"  {fname}: {rows:,} rows, {size_kb:.0f} KB")
