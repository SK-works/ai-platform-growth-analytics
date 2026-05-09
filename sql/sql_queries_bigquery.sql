-- ============================================================
-- AI PLATFORM GROWTH PRODUCT ANALYTICS PROJECT
-- SQL Query Library
-- ============================================================
-- Author   : Product Analytics Portfolio Project
-- Database : Google BigQuery
-- Dataset  : ai-platform-growth-analytics.growth_analytics
-- Updated  : May 2026
-- ============================================================
-- HOW TO USE THIS FILE
-- Each query is self-contained and runs independently.
-- Copy any query block into the BigQuery console and run it.
-- Every query has:
--   PURPOSE    — what business question it answers
--   TECHNIQUE  — what SQL concept it demonstrates
--   INSIGHT    — what you should look for in the results
-- ============================================================

-- SHORTHAND: To avoid repeating the full project path, BigQuery
-- lets you set a default dataset. All queries below assume you
-- have set your default dataset to:
--   ai-platform-growth-analytics.growth_analytics
-- You can still run them with the full path by replacing any
-- bare table name (e.g. `users`) with the full reference.
-- ============================================================


-- ============================================================
-- SECTION 1: FUNNEL ANALYSIS
-- The onboarding funnel — where do users drop off?
-- ============================================================

-- ── Query 1: Full Onboarding Funnel ─────────────────────────
-- PURPOSE  : Measure conversion at every step of the onboarding
--            funnel, from sign-up to activation. Identifies the
--            single biggest drop-off point so the product team
--            knows where to focus improvement effort.
-- TECHNIQUE: CTEs, conditional COUNT with DISTINCT, division for
--            conversion rates, LAG to compare adjacent steps.
-- INSIGHT  : Look for the step with the biggest % drop. That is
--            your highest-leverage optimisation opportunity.

WITH funnel_steps AS (

  SELECT
    u.product,

    -- Step 1: Everyone who signed up
    COUNT(DISTINCT u.user_id)                                    AS step_1_signups,

    -- Step 2: Reached profile setup
    COUNT(DISTINCT CASE
      WHEN e.event_name = 'onboarding_step_completed'
       AND JSON_EXTRACT_SCALAR(e.properties, '$.step_name') = 'profile_setup'
      THEN u.user_id END)                                        AS step_2_profile_setup,

    -- Step 3: Sent first message
    COUNT(DISTINCT CASE
      WHEN e.event_name = 'onboarding_step_completed'
       AND JSON_EXTRACT_SCALAR(e.properties, '$.step_name') = 'first_message'
      THEN u.user_id END)                                        AS step_3_first_message,

    -- Step 4: Returned for a second session
    COUNT(DISTINCT CASE
      WHEN u.d7_retained = TRUE
      THEN u.user_id END)                                        AS step_4_returned,

    -- Step 5: Reached WAU-5 threshold (activated)
    COUNT(DISTINCT CASE
      WHEN u.segment = 'power_user' OR u.d30_retained = TRUE
      THEN u.user_id END)                                        AS step_5_activated

  FROM `ai-platform-growth-analytics.growth_analytics.users` u
  LEFT JOIN `ai-platform-growth-analytics.growth_analytics.events` e ON u.user_id = e.user_id
  GROUP BY u.product

),

funnel_with_rates AS (

  SELECT
    product,
    step_1_signups,
    step_2_profile_setup,
    step_3_first_message,
    step_4_returned,
    step_5_activated,

    -- Conversion rate from previous step (step-over-step)
    ROUND(step_2_profile_setup  / step_1_signups        * 100, 1) AS step1_to_2_pct,
    ROUND(step_3_first_message  / step_2_profile_setup  * 100, 1) AS step2_to_3_pct,
    ROUND(step_4_returned       / step_3_first_message  * 100, 1) AS step3_to_4_pct,
    ROUND(step_5_activated      / step_4_returned       * 100, 1) AS step4_to_5_pct,

    -- Overall funnel conversion (sign-up → fully activated)
    ROUND(step_5_activated / step_1_signups * 100, 1)             AS overall_conversion_pct

  FROM funnel_steps

)

SELECT *
FROM funnel_with_rates
ORDER BY overall_conversion_pct DESC;


-- ── Query 2: Funnel by A/B Test Variant ─────────────────────
-- PURPOSE  : Compare funnel performance between the control group
--            (blank input) and treatment group (suggested prompts).
--            This tells us whether the experiment improved
--            activation at each funnel step.
-- TECHNIQUE: CTEs, GROUP BY on ab_variant, PIVOT-style aggregation.
-- INSIGHT  : Focus on step_3 (first message) conversion — that is
--            the step the experiment was designed to improve.

WITH ab_funnel AS (

  SELECT
    u.ab_variant,
    COUNT(DISTINCT u.user_id)                                      AS total_users,

    COUNT(DISTINCT CASE
      WHEN e.event_name = 'onboarding_step_completed'
       AND JSON_EXTRACT_SCALAR(e.properties, '$.step_name') = 'profile_setup'
      THEN u.user_id END)                                          AS reached_profile_setup,

    COUNT(DISTINCT CASE
      WHEN e.event_name = 'onboarding_step_completed'
       AND JSON_EXTRACT_SCALAR(e.properties, '$.step_name') = 'first_message'
      THEN u.user_id END)                                          AS sent_first_message,

    COUNT(DISTINCT CASE
      WHEN u.activated = TRUE THEN u.user_id END)                  AS activated

  FROM `ai-platform-growth-analytics.growth_analytics.users` u
  LEFT JOIN `ai-platform-growth-analytics.growth_analytics.events` e ON u.user_id = e.user_id
  GROUP BY u.ab_variant

)

SELECT
  ab_variant,
  total_users,
  reached_profile_setup,
  sent_first_message,
  activated,
  ROUND(sent_first_message / total_users * 100, 2)  AS activation_rate_pct,
  ROUND(activated          / total_users * 100, 2)  AS full_activation_pct
FROM ab_funnel
ORDER BY ab_variant;


-- ── Query 3: Time-to-Activate Distribution ──────────────────
-- PURPOSE  : How long does it take users to send their first
--            message after signing up? Products that activate
--            users faster have lower friction onboarding.
-- TECHNIQUE: TIMESTAMP_DIFF, CASE bucketing, window percentiles.
-- INSIGHT  : If the median time-to-activate is > 10 minutes, the
--            onboarding flow likely has too many steps.

WITH activation_times AS (

  SELECT
    u.user_id,
    u.product,
    u.ab_variant,
    TIMESTAMP_DIFF(
      MIN(CASE
        WHEN e.event_name = 'onboarding_step_completed'
         AND JSON_EXTRACT_SCALAR(e.properties, '$.step_name') = 'first_message'
        THEN TIMESTAMP(e.event_timestamp) END),
      TIMESTAMP(u.signup_date),
      MINUTE
    ) AS minutes_to_first_message

  FROM `ai-platform-growth-analytics.growth_analytics.users` u
  JOIN `ai-platform-growth-analytics.growth_analytics.events` e ON u.user_id = e.user_id
  WHERE u.activated = TRUE
  GROUP BY u.user_id, u.product, u.ab_variant

)

SELECT
  product,
  ab_variant,
  COUNT(*)                                                          AS activated_users,
  ROUND(AVG(minutes_to_first_message), 1)                          AS avg_minutes,
  ROUND(APPROX_QUANTILES(minutes_to_first_message, 100)[OFFSET(50)], 1) AS median_minutes,
  ROUND(APPROX_QUANTILES(minutes_to_first_message, 100)[OFFSET(75)], 1) AS p75_minutes,
  COUNTIF(minutes_to_first_message <= 5)                           AS activated_within_5min,
  COUNTIF(minutes_to_first_message <= 10)                          AS activated_within_10min,
  COUNTIF(minutes_to_first_message > 30)                           AS activated_after_30min

FROM activation_times
GROUP BY product, ab_variant
ORDER BY product, ab_variant;


-- ============================================================
-- SECTION 2: RETENTION & COHORT ANALYSIS
-- Who comes back — and when do they stop?
-- ============================================================

-- ── Query 4: Classic N-Day Retention by Product ─────────────
-- PURPOSE  : Calculate Day 1, 3, 7, 14, 21, and 30 retention
--            rates for each product. This is the single most
--            important retention metric in any product analytics role.
-- TECHNIQUE: Self-join on sessions, DATEDIFF, conditional aggregation.
--            This is the standard cohort retention pattern —
--            memorise the structure, it comes up in every interview.
-- INSIGHT  : A healthy consumer product has >40% D7 retention.
--            Look at which product retains best and at which
--            day the biggest cliff occurs.

WITH user_first_session AS (

  -- Anchor each user to their first active session date
  SELECT
    user_id,
    MIN(DATE(session_start)) AS first_session_date
  FROM `ai-platform-growth-analytics.growth_analytics.sessions`
  WHERE session_type = 'active'
  GROUP BY user_id

),

user_return_sessions AS (

  -- For each user, find all distinct session dates after Day 0
  SELECT DISTINCT
    s.user_id,
    DATE_DIFF(DATE(s.session_start), f.first_session_date, DAY) AS day_number
  FROM `ai-platform-growth-analytics.growth_analytics.sessions` s
  JOIN user_first_session f ON s.user_id = f.user_id
  WHERE s.session_type = 'active'
    AND DATE(s.session_start) > f.first_session_date

)

SELECT
  u.product,
  COUNT(DISTINCT u.user_id)                                        AS cohort_size,

  -- Count users who returned on each specific day (±1 day tolerance)
  COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 1  AND 2  THEN u.user_id END) AS returned_d1,
  COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 2  AND 4  THEN u.user_id END) AS returned_d3,
  COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 6  AND 8  THEN u.user_id END) AS returned_d7,
  COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 13 AND 15 THEN u.user_id END) AS returned_d14,
  COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 20 AND 22 THEN u.user_id END) AS returned_d21,
  COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 28 AND 31 THEN u.user_id END) AS returned_d30,

  -- Convert to retention rates
  ROUND(COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 1  AND 2  THEN u.user_id END) / COUNT(DISTINCT u.user_id) * 100, 1) AS d1_retention_pct,
  ROUND(COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 2  AND 4  THEN u.user_id END) / COUNT(DISTINCT u.user_id) * 100, 1) AS d3_retention_pct,
  ROUND(COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 6  AND 8  THEN u.user_id END) / COUNT(DISTINCT u.user_id) * 100, 1) AS d7_retention_pct,
  ROUND(COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 13 AND 15 THEN u.user_id END) / COUNT(DISTINCT u.user_id) * 100, 1) AS d14_retention_pct,
  ROUND(COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 20 AND 22 THEN u.user_id END) / COUNT(DISTINCT u.user_id) * 100, 1) AS d21_retention_pct,
  ROUND(COUNT(DISTINCT CASE WHEN r.day_number BETWEEN 28 AND 31 THEN u.user_id END) / COUNT(DISTINCT u.user_id) * 100, 1) AS d30_retention_pct

FROM `ai-platform-growth-analytics.growth_analytics.users` u
LEFT JOIN user_return_sessions r ON u.user_id = r.user_id
WHERE u.activated = TRUE
GROUP BY u.product
ORDER BY d7_retention_pct DESC;


-- ── Query 5: Weekly Cohort Retention Heatmap ────────────────
-- PURPOSE  : Build a cohort heatmap table — rows are signup weeks,
--            columns are weeks since signup, values are retention %.
--            This is the standard output for a retention heatmap
--            in Looker or any BI tool.
-- TECHNIQUE: DATE_TRUNC for cohort bucketing, self-join, window
--            aggregation. One of the most commonly asked SQL
--            patterns in product analyst interviews.
-- INSIGHT  : Are newer cohorts retaining better than older ones?
--            Improving cohort curves over time = product is getting
--            better at retaining users.

WITH cohorts AS (

  SELECT
    user_id,
    product,
    DATE_TRUNC(DATE(signup_date), WEEK) AS cohort_week
  FROM `ai-platform-growth-analytics.growth_analytics.users`
  WHERE activated = TRUE

),

weekly_activity AS (

  SELECT
    s.user_id,
    DATE_TRUNC(DATE(s.session_start), WEEK) AS activity_week
  FROM `ai-platform-growth-analytics.growth_analytics.sessions` s
  WHERE s.session_type = 'active'
  GROUP BY s.user_id, activity_week

),

cohort_activity AS (

  SELECT
    c.cohort_week,
    c.product,
    DATE_DIFF(w.activity_week, c.cohort_week, WEEK) AS weeks_since_signup,
    COUNT(DISTINCT c.user_id)                        AS cohort_size,
    COUNT(DISTINCT w.user_id)                        AS active_users

  FROM cohorts c
  LEFT JOIN weekly_activity w ON c.user_id = w.user_id
  GROUP BY c.cohort_week, c.product, weeks_since_signup

)

SELECT
  cohort_week,
  product,
  weeks_since_signup,
  cohort_size,
  active_users,
  ROUND(active_users / cohort_size * 100, 1) AS retention_pct
FROM cohort_activity
WHERE weeks_since_signup BETWEEN 0 AND 12
ORDER BY product, cohort_week, weeks_since_signup;


-- ── Query 6: Churn Analysis — Who Churned and When ──────────
-- PURPOSE  : Identify churned users (no session in 30+ days),
--            segment them by product and user type, and calculate
--            the average days-to-churn from signup.
-- TECHNIQUE: MAX session date, DATE_DIFF, CASE classification.
-- INSIGHT  : If task_triager users churn at Day 5 on average,
--            that is your re-engagement window. Target them with
--            a campaign before Day 5.

WITH last_activity AS (

  SELECT
    user_id,
    MAX(DATE(session_start)) AS last_session_date,
    COUNT(DISTINCT DATE(session_start)) AS total_active_days
  FROM `ai-platform-growth-analytics.growth_analytics.sessions`
  WHERE session_type = 'active'
  GROUP BY user_id

),

churn_classified AS (

  SELECT
    u.user_id,
    u.product,
    u.segment,
    u.plan_type,
    u.country,
    DATE(u.signup_date)                             AS signup_date,
    l.last_session_date,
    l.total_active_days,
    DATE_DIFF(DATE('2026-04-30'), l.last_session_date, DAY) AS days_since_last_session,

    CASE
      WHEN l.last_session_date IS NULL                                        THEN 'never_activated'
      WHEN DATE_DIFF(DATE('2026-04-30'), l.last_session_date, DAY) >= 30     THEN 'churned'
      WHEN DATE_DIFF(DATE('2026-04-30'), l.last_session_date, DAY) BETWEEN 14 AND 29 THEN 'at_risk'
      ELSE 'active'
    END AS churn_status

  FROM `ai-platform-growth-analytics.growth_analytics.users` u
  LEFT JOIN last_activity l ON u.user_id = l.user_id

)

SELECT
  product,
  segment,
  churn_status,
  COUNT(*)                                          AS user_count,
  ROUND(AVG(total_active_days), 1)                 AS avg_active_days,
  ROUND(AVG(days_since_last_session), 1)           AS avg_days_since_last_session,
  ROUND(COUNT(*) * 100.0
    / SUM(COUNT(*)) OVER (PARTITION BY product), 1) AS pct_of_product_users
FROM churn_classified
GROUP BY product, segment, churn_status
ORDER BY product, churn_status, user_count DESC;


-- ── Query 7: DAU / MAU Ratio by Product ─────────────────────
-- PURPOSE  : Calculate the DAU/MAU ratio — a key engagement health
--            metric. A ratio above 0.20 is decent; above 0.30 is
--            strong (Facebook historically sits around 0.65).
-- TECHNIQUE: Subqueries for DAU and MAU, date spine for every day,
--            rolling 28-day window for MAU.
-- INSIGHT  : A rising DAU/MAU ratio means users are forming a habit.
--            A falling ratio means engagement is becoming more sporadic
--            even if raw user numbers are growing.

WITH daily_active AS (

  SELECT
    product,
    DATE(session_start)          AS activity_date,
    COUNT(DISTINCT user_id)      AS dau
  FROM `ai-platform-growth-analytics.growth_analytics.sessions`
  WHERE session_type = 'active'
  GROUP BY product, activity_date

),

monthly_active AS (

  SELECT
    product,
    DATE(session_start)          AS activity_date,
    COUNT(DISTINCT user_id)      AS mau_28d   -- rolling 28-day MAU
  FROM `ai-platform-growth-analytics.growth_analytics.sessions`
  WHERE session_type = 'active'
  GROUP BY product, activity_date

)

SELECT
  d.product,
  d.activity_date,
  d.dau,
  -- Rolling 28-day unique users (approximated as window sum of DAU)
  SUM(d.dau) OVER (
    PARTITION BY d.product
    ORDER BY d.activity_date
    ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
  )                                                   AS mau_28d,
  ROUND(
    d.dau / NULLIF(
      SUM(d.dau) OVER (
        PARTITION BY d.product
        ORDER BY d.activity_date
        ROWS BETWEEN 27 PRECEDING AND CURRENT ROW
      ), 0
    ), 3
  )                                                   AS dau_mau_ratio
FROM daily_active d
ORDER BY d.product, d.activity_date;


-- ============================================================
-- SECTION 3: A/B TEST ANALYSIS
-- Did the suggested prompts experiment work?
-- ============================================================

-- ── Query 8: A/B Test — Activation Rate Comparison ──────────
-- PURPOSE  : Measure the primary metric for the suggested prompts
--            experiment: activation rate (% who sent first message
--            within 24h of sign-up). Then perform a manual
--            two-proportion z-test to check statistical significance.
-- TECHNIQUE: GROUP BY, proportion calculation, z-score formula
--            using BigQuery math functions.
-- INSIGHT  : If p-value < 0.05, the lift is statistically
--            significant and the treatment should be rolled out.
--            If not, we need more data or the effect is too small.

WITH experiment_results AS (

  SELECT
    ab_variant,
    COUNT(*)                                          AS total_users,
    COUNTIF(activated = TRUE)                         AS activated_users,
    ROUND(COUNTIF(activated = TRUE) / COUNT(*), 4)   AS activation_rate
  FROM `ai-platform-growth-analytics.growth_analytics.users`
  GROUP BY ab_variant

),

z_test_calc AS (

  SELECT
    MAX(CASE WHEN ab_variant = 'control'   THEN total_users     END) AS n_control,
    MAX(CASE WHEN ab_variant = 'treatment' THEN total_users     END) AS n_treatment,
    MAX(CASE WHEN ab_variant = 'control'   THEN activation_rate END) AS p_control,
    MAX(CASE WHEN ab_variant = 'treatment' THEN activation_rate END) AS p_treatment
  FROM experiment_results

),

z_score_calc AS (

  SELECT
    n_control,
    n_treatment,
    p_control,
    p_treatment,
    p_treatment - p_control                          AS absolute_lift,
    ROUND((p_treatment - p_control) / p_control * 100, 2) AS relative_lift_pct,

    -- Pooled proportion for z-test
    (p_control * n_control + p_treatment * n_treatment)
      / (n_control + n_treatment)                   AS p_pooled,

    -- Z-score formula: (p2 - p1) / sqrt(p_pooled * (1 - p_pooled) * (1/n1 + 1/n2))
    (p_treatment - p_control) / SQRT(
      ((p_control * n_control + p_treatment * n_treatment) / (n_control + n_treatment))
      * (1 - (p_control * n_control + p_treatment * n_treatment) / (n_control + n_treatment))
      * (1.0/n_control + 1.0/n_treatment)
    )                                                AS z_score

  FROM z_test_calc

)

SELECT
  n_control,
  n_treatment,
  ROUND(p_control * 100, 2)                          AS control_activation_pct,
  ROUND(p_treatment * 100, 2)                        AS treatment_activation_pct,
  ROUND(absolute_lift * 100, 2)                      AS absolute_lift_pp,  -- percentage points
  relative_lift_pct,
  ROUND(z_score, 3)                                  AS z_score,

  -- At 95% confidence, z > 1.96 = statistically significant
  CASE WHEN ABS(z_score) > 1.96 THEN 'SIGNIFICANT ✓'
       ELSE 'NOT SIGNIFICANT ✗' END                  AS significance_at_95pct,

  CASE WHEN ABS(z_score) > 2.576 THEN 'SIGNIFICANT ✓'
       ELSE 'NOT SIGNIFICANT ✗' END                  AS significance_at_99pct

FROM z_score_calc;


-- ── Query 9: A/B Test — Secondary Metrics ───────────────────
-- PURPOSE  : The primary metric tells us if the experiment worked.
--            Secondary metrics tell us if it caused any unintended
--            side effects — e.g. did treatment users have shorter
--            sessions or lower D7 retention despite activating more?
-- TECHNIQUE: GROUP BY, AVG, COUNTIF, ratio calculations.
-- INSIGHT  : If treatment users activate more BUT retain less,
--            the feature may be creating low-quality activations
--            (users click a prompt out of curiosity but don't return).

SELECT
  u.ab_variant,
  COUNT(DISTINCT u.user_id)                               AS total_users,
  ROUND(AVG(s.duration_seconds) / 60, 1)                 AS avg_session_minutes,
  ROUND(AVG(s.message_count), 1)                         AS avg_messages_per_session,
  ROUND(COUNTIF(u.d7_retained)  / COUNT(DISTINCT u.user_id) * 100, 1) AS d7_retention_pct,
  ROUND(COUNTIF(u.d30_retained) / COUNT(DISTINCT u.user_id) * 100, 1) AS d30_retention_pct,
  ROUND(COUNTIF(sub.user_id IS NOT NULL) / COUNT(DISTINCT u.user_id) * 100, 2) AS pro_conversion_pct
FROM `ai-platform-growth-analytics.growth_analytics.users` u
LEFT JOIN `ai-platform-growth-analytics.growth_analytics.sessions` s          ON u.user_id = s.user_id AND s.session_type = 'active'
LEFT JOIN `ai-platform-growth-analytics.growth_analytics.subscriptions` sub   ON u.user_id = sub.user_id
GROUP BY u.ab_variant
ORDER BY u.ab_variant;


-- ── Query 10: Sample Size Check ─────────────────────────────
-- PURPOSE  : Verify the experiment had enough users per variant
--            to detect the effect size we care about.
--            Running this before interpreting results is good
--            analytical hygiene — it shows you understand power.
-- TECHNIQUE: Simple aggregation, commentary on power analysis.
-- INSIGHT  : For a 3pp lift at 80% power and α=0.05, we need
--            ~1,100 users per group. If we have significantly
--            more, the test is well-powered.

SELECT
  ab_variant,
  COUNT(*)                      AS sample_size,
  COUNTIF(activated = TRUE)     AS conversions,
  ROUND(COUNTIF(activated = TRUE) / COUNT(*) * 100, 2) AS conversion_rate_pct,
  -- Minimum detectable effect at this sample size (rough approximation)
  -- MDE ≈ 2.8 * sqrt(p*(1-p)/n)  for 80% power, α=0.05
  ROUND(
    2.8 * SQRT(
      (COUNTIF(activated = TRUE) / COUNT(*))
      * (1 - COUNTIF(activated = TRUE) / COUNT(*))
      / COUNT(*)
    ) * 100, 2
  )                             AS min_detectable_effect_pp
FROM `ai-platform-growth-analytics.growth_analytics.users`
GROUP BY ab_variant;


-- ============================================================
-- SECTION 4: FEATURE ADOPTION & CORRELATION
-- Which features separate retained users from churned ones?
-- ============================================================

-- ── Query 11: Feature Adoption Rate by Product ──────────────
-- PURPOSE  : Which features (code generation, image input, memory,
--            plugins, file upload) are most adopted, and does
--            adoption differ by product?
-- TECHNIQUE: COUNTIF with string matching, ratio to total users.
-- INSIGHT  : High-adoption features are table stakes — every product
--            needs them. Low-adoption but high-retention features
--            are hidden gems worth investing in.

SELECT
  s.product,
  COUNT(DISTINCT s.user_id)                                        AS active_users,
  COUNTIF(s.features_used = 'code_generation')                    AS uses_code_gen,
  COUNTIF(s.features_used = 'image_input')                        AS uses_image_input,
  COUNTIF(s.features_used = 'memory')                             AS uses_memory,
  COUNTIF(s.features_used = 'plugins')                            AS uses_plugins,
  COUNTIF(s.features_used = 'file_upload')                        AS uses_file_upload,
  COUNTIF(s.features_used != '')                                  AS uses_any_feature,

  ROUND(COUNTIF(s.features_used != '') / COUNT(DISTINCT s.user_id) * 100, 1)
                                                                   AS feature_adoption_pct
FROM `ai-platform-growth-analytics.growth_analytics.sessions` s
WHERE s.session_type = 'active'
GROUP BY s.product
ORDER BY feature_adoption_pct DESC;


-- ── Query 12: Feature Usage vs Retention Correlation ────────
-- PURPOSE  : Do users who adopt advanced features retain better?
--            This is the core product insight question — it helps
--            the team decide what features to push in onboarding.
-- TECHNIQUE: JOIN sessions to users, GROUP BY feature flag,
--            compare retention rates between adopters and non-adopters.
-- INSIGHT  : If feature adopters have 2x the D30 retention of
--            non-adopters, the product team should prioritise
--            getting users to that feature in onboarding.
--            NOTE: This is correlation, not causation. State this
--            clearly whenever you present this finding.

WITH user_feature_flag AS (

  SELECT
    s.user_id,
    MAX(CASE WHEN s.features_used != '' THEN 1 ELSE 0 END)  AS used_any_feature,
    MAX(CASE WHEN s.features_used = 'code_generation' THEN 1 ELSE 0 END) AS used_code_gen,
    MAX(CASE WHEN s.features_used = 'image_input'     THEN 1 ELSE 0 END) AS used_image,
    MAX(CASE WHEN s.features_used = 'memory'          THEN 1 ELSE 0 END) AS used_memory,
    MAX(CASE WHEN s.features_used = 'plugins'         THEN 1 ELSE 0 END) AS used_plugins,
    MAX(CASE WHEN s.features_used = 'file_upload'     THEN 1 ELSE 0 END) AS used_file_upload
  FROM `ai-platform-growth-analytics.growth_analytics.sessions` s
  WHERE s.session_type = 'active'
  GROUP BY s.user_id

)

SELECT
  u.product,

  -- Any feature adoption
  ROUND(COUNTIF(f.used_any_feature = 1 AND u.d7_retained)  / NULLIF(COUNTIF(f.used_any_feature = 1), 0)  * 100, 1) AS d7_ret_with_any_feature,
  ROUND(COUNTIF(f.used_any_feature = 0 AND u.d7_retained)  / NULLIF(COUNTIF(f.used_any_feature = 0), 0)  * 100, 1) AS d7_ret_without_feature,
  ROUND(COUNTIF(f.used_any_feature = 1 AND u.d30_retained) / NULLIF(COUNTIF(f.used_any_feature = 1), 0)  * 100, 1) AS d30_ret_with_any_feature,
  ROUND(COUNTIF(f.used_any_feature = 0 AND u.d30_retained) / NULLIF(COUNTIF(f.used_any_feature = 0), 0)  * 100, 1) AS d30_ret_without_feature,

  -- Code generation specifically
  ROUND(COUNTIF(f.used_code_gen = 1 AND u.d30_retained) / NULLIF(COUNTIF(f.used_code_gen = 1), 0) * 100, 1) AS d30_ret_code_gen_users,

  -- Memory feature specifically
  ROUND(COUNTIF(f.used_memory = 1 AND u.d30_retained)   / NULLIF(COUNTIF(f.used_memory = 1), 0)   * 100, 1) AS d30_ret_memory_users

FROM `ai-platform-growth-analytics.growth_analytics.users` u
JOIN user_feature_flag f ON u.user_id = f.user_id
GROUP BY u.product
ORDER BY d30_ret_with_any_feature DESC;


-- ── Query 13: Power User Behaviour Profile ───────────────────
-- PURPOSE  : Deeply understand what power users do differently.
--            This profile helps the product team design features
--            that move casual users toward power user behaviour.
-- TECHNIQUE: Complex multi-table JOIN, window functions,
--            PERCENTILE_CONT for median calculations.
-- INSIGHT  : The gap between power users and casual explorers
--            on messages/session and feature adoption is your
--            product engagement gap to close.

WITH user_stats AS (

  SELECT
    u.user_id,
    u.product,
    u.segment,
    u.plan_type,
    COUNT(DISTINCT s.session_id)             AS total_sessions,
    SUM(s.message_count)                     AS total_messages,
    AVG(s.message_count)                     AS avg_messages_per_session,
    AVG(s.duration_seconds) / 60.0           AS avg_session_minutes,
    COUNT(DISTINCT s.session_date)           AS total_active_days,
    COUNTIF(s.features_used != '')           AS feature_sessions,
    u.d7_retained,
    u.d30_retained

  FROM `ai-platform-growth-analytics.growth_analytics.users` u
  JOIN `ai-platform-growth-analytics.growth_analytics.sessions` s ON u.user_id = s.user_id AND s.session_type = 'active'
  GROUP BY u.user_id, u.product, u.segment, u.plan_type, u.d7_retained, u.d30_retained

)

SELECT
  product,
  segment,
  COUNT(*)                                    AS user_count,
  ROUND(AVG(total_sessions), 1)              AS avg_sessions,
  ROUND(AVG(total_messages), 1)              AS avg_total_messages,
  ROUND(AVG(avg_messages_per_session), 1)    AS avg_msgs_per_session,
  ROUND(AVG(avg_session_minutes), 1)         AS avg_session_minutes,
  ROUND(AVG(total_active_days), 1)           AS avg_active_days,
  ROUND(AVG(feature_sessions), 1)            AS avg_feature_sessions,
  ROUND(COUNTIF(d7_retained)  / COUNT(*) * 100, 1) AS d7_retention_pct,
  ROUND(COUNTIF(d30_retained) / COUNT(*) * 100, 1) AS d30_retention_pct
FROM user_stats
GROUP BY product, segment
ORDER BY product, avg_total_messages DESC;


-- ============================================================
-- SECTION 5: REVENUE & MONETISATION ANALYSIS
-- ============================================================

-- ── Query 14: Free-to-Pro Conversion Funnel ─────────────────
-- PURPOSE  : Understand when users upgrade and how long it takes.
--            Early upgraders (Day 1-7) vs late upgraders (Day 15+)
--            may have very different behaviour profiles.
-- TECHNIQUE: DATE_DIFF, CASE bucketing into upgrade windows,
--            JOIN to subscriptions table.
-- INSIGHT  : If most upgrades happen on Day 3-7, that is your
--            conversion window — the product team should use
--            that window for upgrade nudges and prompts.

WITH upgrade_timing AS (

  SELECT
    sub.user_id,
    sub.product,
    u.segment,
    sub.to_plan,
    sub.revenue_usd,
    DATE_DIFF(sub.change_date, DATE(u.signup_date), DAY) AS days_to_upgrade,

    CASE
      WHEN DATE_DIFF(sub.change_date, DATE(u.signup_date), DAY) <= 3   THEN '0-3 days'
      WHEN DATE_DIFF(sub.change_date, DATE(u.signup_date), DAY) <= 7   THEN '4-7 days'
      WHEN DATE_DIFF(sub.change_date, DATE(u.signup_date), DAY) <= 14  THEN '8-14 days'
      ELSE '15+ days'
    END AS upgrade_window

  FROM `ai-platform-growth-analytics.growth_analytics.subscriptions` sub
  JOIN `ai-platform-growth-analytics.growth_analytics.users` u ON sub.user_id = u.user_id
  WHERE sub.from_plan = 'free'

)

SELECT
  product,
  upgrade_window,
  COUNT(*)                             AS upgrades,
  ROUND(AVG(days_to_upgrade), 1)      AS avg_days_to_upgrade,
  ROUND(AVG(revenue_usd), 2)          AS avg_revenue_usd,
  SUM(revenue_usd)                    AS total_revenue_usd
FROM upgrade_timing
GROUP BY product, upgrade_window
ORDER BY product,
  CASE upgrade_window
    WHEN '0-3 days'   THEN 1
    WHEN '4-7 days'   THEN 2
    WHEN '8-14 days'  THEN 3
    ELSE 4
  END;


-- ── Query 15: MRR and Revenue Impact Model ──────────────────
-- PURPOSE  : Calculate Monthly Recurring Revenue (MRR) and model
--            the revenue impact of improving D7 retention by 5
--            percentage points. This bridges data analysis to
--            business impact — the most valuable skill in product
--            analytics.
-- TECHNIQUE: Aggregation, scalar subquery, arithmetic modelling.
-- INSIGHT  : Presenting revenue impact alongside retention numbers
--            transforms you from a data reporter into a strategic
--            business partner. Always quantify the "so what".

WITH current_mrr AS (

  SELECT
    sub.product,
    COUNT(DISTINCT sub.user_id)           AS paying_subscribers,
    SUM(sub.revenue_usd)                  AS mrr_usd,
    ROUND(AVG(sub.revenue_usd), 2)        AS arpu_usd,

    -- Churned subscribers (cancelled subscription)
    COUNTIF(sub.churn_date IS NOT NULL AND sub.churn_date != '')  AS churned_subscribers,
    ROUND(
      COUNTIF(sub.churn_date IS NOT NULL AND sub.churn_date != '')
      / COUNT(*) * 100, 1
    )                                     AS subscription_churn_pct

  FROM `ai-platform-growth-analytics.growth_analytics.subscriptions` sub
  GROUP BY sub.product

),

total_users_by_product AS (

  SELECT product, COUNT(*) AS total_users
  FROM `ai-platform-growth-analytics.growth_analytics.users`
  GROUP BY product

),

retention_by_product AS (

  SELECT
    product,
    ROUND(COUNTIF(d7_retained) / COUNT(*) * 100, 1) AS current_d7_ret_pct
  FROM `ai-platform-growth-analytics.growth_analytics.users`
  WHERE activated = TRUE
  GROUP BY product

)

SELECT
  m.product,
  t.total_users,
  m.paying_subscribers,
  ROUND(m.paying_subscribers / t.total_users * 100, 2)  AS conversion_rate_pct,
  m.mrr_usd,
  m.arpu_usd,
  m.subscription_churn_pct,
  r.current_d7_ret_pct,

  -- Revenue impact model: what if D7 retention improves by 5pp?
  -- More retained users → more time to convert → more subscribers
  -- Assumption: each 1pp lift in D7 retention = 0.3pp lift in conversion
  ROUND(
    t.total_users
    * (m.paying_subscribers / t.total_users + 0.015)  -- 5pp × 0.3 = 1.5pp more conversions
    * m.arpu_usd
    - m.mrr_usd
  , 0)                                                  AS incremental_mrr_from_5pp_d7_lift

FROM current_mrr m
JOIN total_users_by_product t  ON m.product = t.product
JOIN retention_by_product r    ON m.product = r.product
ORDER BY m.mrr_usd DESC;


-- ── Query 16: User Lifetime Value (LTV) Estimation ──────────
-- PURPOSE  : Estimate LTV per user segment. LTV = ARPU / churn rate.
--            This is a standard metric in any monetised product.
-- TECHNIQUE: Subquery aggregation, division-based LTV formula.
-- INSIGHT  : LTV/CAC ratio > 3 is considered healthy. If LTV is
--            low, either ARPU needs to increase or churn needs
--            to decrease. This frames retention as a revenue problem.

WITH subscriber_stats AS (

  SELECT
    u.product,
    u.segment,
    COUNT(DISTINCT sub.user_id)            AS subscribers,
    AVG(sub.revenue_usd)                   AS avg_monthly_revenue,
    -- Monthly churn rate approximation
    COUNTIF(sub.churn_date IS NOT NULL AND sub.churn_date != '')
      / NULLIF(COUNT(*), 0)                AS monthly_churn_rate
  FROM `ai-platform-growth-analytics.growth_analytics.users` u
  JOIN `ai-platform-growth-analytics.growth_analytics.subscriptions` sub ON u.user_id = sub.user_id
  GROUP BY u.product, u.segment

)

SELECT
  product,
  segment,
  subscribers,
  ROUND(avg_monthly_revenue, 2)            AS arpu_usd,
  ROUND(monthly_churn_rate * 100, 1)       AS monthly_churn_pct,
  -- LTV = ARPU / Monthly Churn Rate
  ROUND(
    avg_monthly_revenue / NULLIF(monthly_churn_rate, 0)
  , 0)                                     AS estimated_ltv_usd
FROM subscriber_stats
WHERE monthly_churn_rate > 0
ORDER BY estimated_ltv_usd DESC;


-- ── Query 17: Geographic Engagement Analysis ────────────────
-- PURPOSE  : Break down activation and retention by country.
--            Informs decisions about localisation, regional
--            marketing spend, and product prioritisation.
-- TECHNIQUE: Multi-metric GROUP BY, ranking with RANK() window
--            function, percentage calculations.
-- INSIGHT  : If a high-traffic country has low activation rate,
--            that is a localisation or UX friction problem.
--            High traffic + high retention = double down here.

WITH country_metrics AS (

  SELECT
    u.country,
    COUNT(DISTINCT u.user_id)                                      AS total_users,
    COUNTIF(u.activated)                                           AS activated_users,
    COUNTIF(u.d7_retained)                                         AS d7_retained_users,
    COUNTIF(u.d30_retained)                                        AS d30_retained_users,
    COUNT(DISTINCT sub.subscription_id)                            AS subscribers

  FROM `ai-platform-growth-analytics.growth_analytics.users` u
  LEFT JOIN `ai-platform-growth-analytics.growth_analytics.subscriptions` sub ON u.user_id = sub.user_id
  GROUP BY u.country

)

SELECT
  country,
  total_users,
  ROUND(activated_users    / total_users * 100, 1)  AS activation_pct,
  ROUND(d7_retained_users  / total_users * 100, 1)  AS d7_retention_pct,
  ROUND(d30_retained_users / total_users * 100, 1)  AS d30_retention_pct,
  ROUND(subscribers        / total_users * 100, 2)  AS conversion_pct,
  RANK() OVER (ORDER BY total_users DESC)            AS rank_by_volume,
  RANK() OVER (ORDER BY d7_retained_users / total_users DESC) AS rank_by_retention
FROM country_metrics
ORDER BY total_users DESC;


-- ============================================================
-- BONUS QUERY: Executive Summary View
-- One query to rule them all — a single summary table that could
-- sit at the top of the Looker executive dashboard.
-- ============================================================

-- ── Query 18: Executive KPI Summary ─────────────────────────
-- PURPOSE  : A single-query executive summary showing all North
--            Star and L1 metrics side by side for all four products.
--            This is what a Head of Product or VP Growth would
--            look at every Monday morning.
-- TECHNIQUE: Brings together all previous analytical patterns
--            into one clean summary. Tests ability to synthesise.

WITH base AS (
  SELECT
    u.product,
    COUNT(DISTINCT u.user_id)                                       AS total_users,
    COUNTIF(u.activated)                                            AS activated,
    COUNTIF(u.d7_retained)                                          AS d7_retained,
    COUNTIF(u.d30_retained)                                         AS d30_retained,
    COUNTIF(u.segment = 'power_user')                               AS power_users
  FROM `ai-platform-growth-analytics.growth_analytics.users` u
  GROUP BY u.product
),
session_stats AS (
  SELECT
    product,
    COUNT(DISTINCT user_id)                                         AS users_with_sessions,
    ROUND(AVG(duration_seconds)/60, 1)                             AS avg_session_mins,
    ROUND(AVG(message_count), 1)                                   AS avg_msgs_per_session
  FROM `ai-platform-growth-analytics.growth_analytics.sessions`
  WHERE session_type = 'active'
  GROUP BY product
),
revenue_stats AS (
  SELECT
    product,
    COUNT(DISTINCT user_id)                                         AS subscribers,
    SUM(revenue_usd)                                                AS mrr
  FROM `ai-platform-growth-analytics.growth_analytics.subscriptions`
  GROUP BY product
)

SELECT
  b.product,
  b.total_users,
  ROUND(b.activated    / b.total_users * 100, 1)                   AS activation_pct,
  ROUND(b.d7_retained  / b.total_users * 100, 1)                   AS d7_retention_pct,
  ROUND(b.d30_retained / b.total_users * 100, 1)                   AS d30_retention_pct,
  ROUND(b.power_users  / b.total_users * 100, 1)                   AS power_user_pct,
  s.avg_session_mins,
  s.avg_msgs_per_session,
  ROUND(IFNULL(r.subscribers,0) / b.total_users * 100, 2)          AS conversion_pct,
  IFNULL(r.mrr, 0)                                                  AS mrr_usd
FROM base b
LEFT JOIN session_stats s  ON b.product = s.product
LEFT JOIN revenue_stats r  ON b.product = r.product
ORDER BY d7_retention_pct DESC;

-- ============================================================
-- END OF SQL QUERY LIBRARY
-- 18 queries | 5 analytical sections
-- AI Platform Growth Product Analytics Project | May 2026
-- ============================================================
