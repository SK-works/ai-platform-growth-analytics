# AI Platform Growth Product Analytics Project

> **An end-to-end product analytics case study on user activation, retention and growth across Claude, ChatGPT, Gemini and Grok**

---

## Project Overview

This project simulates the work of a product analyst embedded in a growth team, tasked with understanding why AI assistant users activate, what makes them stay, and what drives revenue. It covers the full analyst workflow — from problem framing and data modelling through SQL analysis, event tracking, dashboard creation, and strategic recommendations.

**The central question:** What behavioral signals separate users who become habitual AI assistant users from those who churn within the first week?

---

## Key Findings

| Finding | Result |
|---|---|
| Activation gap | 87.7% complete onboarding but only 46.9% start their first session |
| Day-7 retention | Sharp cliff across all products — ChatGPT leads at 45%, Grok trails at 34% |
| A/B test result | Suggested prompts lifted Day-1 activation by **+7.1 percentage points** (p < 0.05) |
| Feature correlation | Users who adopt any advanced feature retain at **2× the rate** of those who don't |
| Revenue impact | A 5pp D7 retention improvement = est. **$8,000–12,000 additional MRR** |

---

## Tools & Stack

| Tool | Role |
|---|---|
| **Python** (pandas, numpy) | Synthetic data generation — 10,000 users, 98,581 events |
| **Google BigQuery** | Data warehouse — 4 tables, 18 SQL queries |
| **SQL** | Funnel analysis, cohort retention, A/B testing, feature correlation, revenue modelling |
| **Mixpanel** | Product analytics — funnel, retention, and feature adoption dashboards |
| **Looker Studio** | Executive KPI dashboard connected to BigQuery |
| **PowerPoint** | 10-slide insights deck for stakeholder presentation |

---

## Project Structure

```
ai-platform-growth-analytics/
│
├── README.md
│
├── PRD/
│   └── AI_Platform_Growth_PRD_v2.docx     # Full product requirements document
│
├── data/
│   ├── generate_data.py                    # Synthetic data generator
│   ├── users.csv                           # 10,000 users with segments + A/B variants
│   ├── sessions.csv                        # 98,727 sessions
│   ├── subscriptions.csv                   # 261 subscription events
│   └── events_final.csv                    # 98,581 events with all properties
│
├── sql/
│   └── sql_queries_bigquery.sql            # 18 documented queries — BigQuery syntax
│
├── dashboards/
│   └── screenshots/                        # Mixpanel + Looker Studio dashboard screenshots
│
├── deck/
│   └── AI_Platform_Growth_Insights_Deck.pptx   # 10-slide insights presentation
│
└── scripts/
    └── mixpanel_import_final.py            # Mixpanel API import script
```

---

## The Data

All data is **synthetic** — generated using Python to simulate realistic AI assistant product behavior. This is clearly disclosed in all deliverables.

| Table | Rows | Description |
|---|---|---|
| users | 10,000 | One row per user — product, segment, A/B variant, retention flags |
| sessions | 98,727 | One row per session — duration, message count, features used |
| events | 98,581 | One row per event — 4 event types with full property set |
| subscriptions | 261 | One row per subscription change |

**Date range:** November 1 2025 — April 30 2026

**Products:** Claude (Anthropic) · ChatGPT (OpenAI) · Gemini (Google) · Grok (xAI)

---

## SQL Query Library

The `sql/sql_queries_bigquery.sql` file contains 18 documented queries across 5 sections. Every query has a PURPOSE, TECHNIQUE, and INSIGHT comment block.

| Section | Queries | Techniques Covered |
|---|---|---|
| Funnel Analysis | Q1–Q3 | CTEs, conditional aggregation, TIMESTAMP_DIFF, APPROX_QUANTILES |
| Retention & Cohort | Q4–Q7 | Self-joins, DATE_TRUNC, rolling window MAU, cohort heatmap |
| A/B Test Analysis | Q8–Q10 | Two-proportion z-test in SQL, MDE calculation, power analysis |
| Feature Correlation | Q11–Q13 | Multi-table JOINs, COUNTIF, retention vs adoption comparison |
| Revenue & Monetisation | Q14–Q18 | LTV formula, MRR, upgrade timing, executive KPI summary |

---

## Dashboards

### Mixpanel — Product Analytics Dashboard
Three charts built using event data imported via the Mixpanel API:
- Feature Adoption Funnel by Product
- User Retention Curve (weekly)
- Feature Breakdown by Type and Product

### Looker Studio — Executive KPI Dashboard
Six charts connected directly to BigQuery:
- KPI scorecards (Total Users · Activated · D7 Retained · D30 Retained)
- Users by Product
- Activation Rate by Product
- New User Signups Over Time
- D7 Retention by User Segment
- Users by Country (geo map)

---

## The PRD

The Product Requirements Document (`PRD/AI_Platform_Growth_PRD_v2.docx`) is a 12-section document covering:
- Problem statement and scope
- North Star metric and metrics framework
- User personas and segmentation
- Event tracking plan (Mixpanel taxonomy)
- Data model and SQL schema
- Analytical plan for each question
- Key findings and recommendations
- Risks and limitations

---

## The Insights Deck

The 10-slide presentation (`deck/`) follows the Pyramid Principle narrative structure:

| Slide | Content |
|---|---|
| 1 | Title — tools, data, scope |
| 2 | Executive Summary — 4 key findings |
| 3 | Project Architecture — 6-phase pipeline |
| 4 | Funnel Analysis — the activation gap |
| 5 | Retention — the Day-7 cliff |
| 6 | A/B Test — suggested prompts result |
| 7 | Feature Adoption — the 2× retention signal |
| 8 | User Segmentation — 3 behaviour profiles |
| 9 | Revenue Model — quantifying the business case |
| 10 | Recommendations — 4 prioritised actions |

---

## Recommendations

| # | Recommendation | Priority |
|---|---|---|
| 01 | Roll out suggested prompts to 100% of new users — proven by A/B test (p<0.05) | HIGH |
| 02 | Add feature nudge at Day 2 — push users toward code generation based on first query | HIGH |
| 03 | Day-5 re-engagement campaign for task triager segment (31% of base) | MEDIUM |
| 04 | Power user early identification model — flag by Day 3, fast-track to Pro | MEDIUM |

---

## How to Reproduce

### 1. Generate the data
```bash
pip install pandas numpy
python data/generate_data.py
```

### 2. Load into BigQuery
1. Create a Google Cloud project
2. Create dataset `growth_analytics`
3. Upload each CSV as a table (auto-detect schema)

### 3. Run SQL queries
Open `sql/sql_queries_bigquery.sql` in the BigQuery console. Each query is self-contained.

### 4. Import into Mixpanel
```bash
pip install requests pandas
python scripts/mixpanel_import_final.py
```
Update `PROJECT_TOKEN`, `PROJECT_SECRET`, and `PROJECT_ID` with your own Mixpanel credentials.

---

## Limitations

- All data is **synthetic** and generated for portfolio purposes only
- Correlation findings (feature adoption vs retention) do not imply causation
- BigQuery Sandbox free tier was used — some features require billing activation
- Mixpanel free tier (10k MTUs) required trimming events from 667k to 98,581

---

## About This Project

This is a portfolio project built to demonstrate end-to-end product analytics skills for a product analyst role. It covers the full workflow from problem framing (PRD) through data engineering, SQL analysis, product analytics tooling, executive reporting, and stakeholder communication.

**Skills demonstrated:** SQL · Python · Product Analytics · A/B Testing · Cohort Analysis · Funnel Analysis · Data Storytelling · PRD Writing · BigQuery · Mixpanel · Looker Studio

---

*Built May 2026 · Synthetic data · Portfolio project*
