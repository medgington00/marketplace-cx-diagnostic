-- ============================================================
-- 06_regional_hotspots.sql
-- Question:  Which regions have systemic logistics failures,
--            and what is the CX and financial impact?
-- Stakeholder: Logistics Operations, VP Customer Experience
-- ============================================================


-- ── 1. State-level CX scorecard ──────────────────────────────
-- Full picture per state: late rate, detractor rate, GMV at risk

SELECT
    customer_state,
    COUNT(*)                                            AS reviewed_orders,
    ROUND(AVG(is_late) * 100, 1)                       AS late_rate_pct,
    ROUND(AVG(is_detractor) * 100, 1)                  AS detractor_rate_pct,
    ROUND(AVG(review_score), 2)                        AS avg_review_score,
    ROUND(SUM(CASE WHEN is_detractor = 1
              THEN order_gmv ELSE 0 END), 0)            AS detractor_gmv,
    ROUND(SUM(order_gmv), 0)                           AS total_gmv,
    ROUND(SUM(CASE WHEN is_detractor = 1
              THEN order_gmv ELSE 0 END) * 100.0
          / SUM(order_gmv), 1)                         AS detractor_gmv_pct
FROM vw_order_analysis
WHERE review_score IS NOT NULL
  AND is_late IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC;


-- ── 2. Hotspot vs national comparison ────────────────────────
-- Flag states exceeding 2x the national late rate

WITH national AS (
    SELECT AVG(is_late) AS national_late_rate
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
      AND is_late IS NOT NULL
),
state_stats AS (
    SELECT
        customer_state,
        COUNT(*)                                        AS reviewed_orders,
        AVG(is_late)                                   AS late_rate,
        AVG(is_detractor)                              AS detractor_rate,
        SUM(order_gmv)                                 AS total_gmv,
        SUM(CASE WHEN is_detractor = 1
            THEN order_gmv ELSE 0 END)                 AS detractor_gmv
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
      AND is_late IS NOT NULL
    GROUP BY customer_state
    HAVING COUNT(*) >= 100
)
SELECT
    s.customer_state,
    s.reviewed_orders,
    ROUND(s.late_rate * 100, 1)                        AS late_rate_pct,
    ROUND(n.national_late_rate * 100, 1)               AS national_late_rate_pct,
    ROUND(s.late_rate / n.national_late_rate, 2)       AS late_rate_multiplier,
    ROUND(s.detractor_rate * 100, 1)                   AS detractor_rate_pct,
    ROUND(s.detractor_gmv, 0)                          AS detractor_gmv,
    CASE WHEN s.late_rate >= n.national_late_rate * 2
         THEN 'hotspot' ELSE 'standard' END             AS region_flag
FROM state_stats s
CROSS JOIN national n
ORDER BY late_rate_multiplier DESC;


-- ── 3. Hotspot aggregate summary ─────────────────────────────
-- Total financial exposure from hotspot states combined

WITH national AS (
    SELECT AVG(is_late) AS national_late_rate
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
      AND is_late IS NOT NULL
),
state_stats AS (
    SELECT
        customer_state,
        COUNT(*)                                        AS reviewed_orders,
        AVG(is_late)                                   AS late_rate,
        AVG(is_detractor)                              AS detractor_rate,
        SUM(order_gmv)                                 AS total_gmv,
        SUM(CASE WHEN is_detractor = 1
            THEN order_gmv ELSE 0 END)                 AS detractor_gmv
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
      AND is_late IS NOT NULL
    GROUP BY customer_state
    HAVING COUNT(*) >= 100
),
flagged AS (
    SELECT
        s.*,
        CASE WHEN s.late_rate >= n.national_late_rate * 2
             THEN 'hotspot' ELSE 'standard' END         AS region_flag
    FROM state_stats s
    CROSS JOIN national n
)
SELECT
    region_flag,
    COUNT(*)                                            AS state_count,
    SUM(reviewed_orders)                               AS total_orders,
    ROUND(AVG(late_rate) * 100, 1)                     AS avg_late_rate_pct,
    ROUND(AVG(detractor_rate) * 100, 1)                AS avg_detractor_rate_pct,
    ROUND(SUM(total_gmv), 0)                           AS total_gmv,
    ROUND(SUM(detractor_gmv), 0)                       AS total_detractor_gmv,
    ROUND(SUM(detractor_gmv) /
          SUM(total_gmv) * 100, 1)                     AS detractor_gmv_pct
FROM flagged
GROUP BY region_flag
ORDER BY region_flag;


-- ── 4. Root cause mix in hotspot states ──────────────────────
-- Are hotspot complaints mostly late-delivery or other causes?

WITH national AS (
    SELECT AVG(is_late) AS national_late_rate
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
      AND is_late IS NOT NULL
),
hotspot_states AS (
    SELECT customer_state
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
      AND is_late IS NOT NULL
    GROUP BY customer_state
    HAVING COUNT(*) >= 100
       AND AVG(is_late) >= (SELECT national_late_rate * 2 FROM national)
)
SELECT
    v.root_cause,
    COUNT(*)                                            AS detractor_reviews,
    ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER(), 1)                     AS pct_of_hotspot_detractors
FROM vw_order_analysis v
INNER JOIN hotspot_states hs ON v.customer_state = hs.customer_state
WHERE v.is_detractor = 1
GROUP BY v.root_cause
ORDER BY detractor_reviews DESC;


-- ── 5. Month-over-month late rate by region type ─────────────
-- Are hotspot states improving, worsening, or flat?

WITH national AS (
    SELECT AVG(is_late) AS national_late_rate
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
      AND is_late IS NOT NULL
),
hotspot_states AS (
    SELECT customer_state
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
      AND is_late IS NOT NULL
    GROUP BY customer_state
    HAVING COUNT(*) >= 100
       AND AVG(is_late) >= (SELECT national_late_rate * 2 FROM national)
)
SELECT
    v.order_month,
    CASE WHEN hs.customer_state IS NOT NULL
         THEN 'hotspot' ELSE 'standard' END             AS region_type,
    COUNT(*)                                            AS orders,
    ROUND(AVG(v.is_late) * 100, 1)                     AS late_rate_pct,
    ROUND(AVG(v.is_detractor) * 100, 1)                AS detractor_rate_pct
FROM vw_order_analysis v
LEFT JOIN hotspot_states hs ON v.customer_state = hs.customer_state
WHERE v.review_score IS NOT NULL
  AND v.is_late IS NOT NULL
GROUP BY v.order_month, region_type
ORDER BY v.order_month, region_type;