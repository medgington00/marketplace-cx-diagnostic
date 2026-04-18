-- ============================================================
-- 04_late_delivery_impact.sql
-- Question:  What is the measurable impact of late delivery on
--            customer satisfaction, and what is the dollar
--            exposure tied to late-delivery complaints?
-- Stakeholder: Logistics Ops, VP Customer Experience
-- ============================================================


-- ── 1. Detractor rate by delivery bucket ─────────────────────
-- How does CSAT degrade as lateness increases?

SELECT
    delivery_bucket,
    COUNT(*)                                            AS orders,
    ROUND(AVG(is_detractor) * 100, 1)                  AS detractor_rate_pct,
    ROUND(AVG(is_promoter) * 100, 1)                   AS promoter_rate_pct,
    ROUND(AVG(review_score), 2)                        AS avg_review_score
FROM vw_order_analysis
WHERE review_score IS NOT NULL
GROUP BY delivery_bucket
ORDER BY
    CASE delivery_bucket
        WHEN 'on_time'        THEN 1
        WHEN 'late_1_3_days'  THEN 2
        WHEN 'late_4_7_days'  THEN 3
        WHEN 'late_8_plus_days' THEN 4
        ELSE 5
    END;


-- ── 2. GMV at risk from late delivery ────────────────────────
-- Dollar value of orders that were late AND generated a complaint

SELECT
    delivery_bucket,
    COUNT(*)                                            AS total_orders,
    SUM(is_detractor)                                   AS detractor_orders,
    ROUND(SUM(CASE WHEN is_detractor = 1
              THEN order_gmv ELSE 0 END), 0)            AS gmv_at_risk,
    ROUND(AVG(CASE WHEN is_detractor = 1
              THEN order_gmv END), 2)                   AS avg_gmv_at_risk_per_order
FROM vw_order_analysis
WHERE review_score IS NOT NULL
  AND delivery_bucket != 'not_delivered'
GROUP BY delivery_bucket
ORDER BY
    CASE delivery_bucket
        WHEN 'on_time'          THEN 1
        WHEN 'late_1_3_days'    THEN 2
        WHEN 'late_4_7_days'    THEN 3
        WHEN 'late_8_plus_days' THEN 4
        ELSE 5
    END;


-- ── 3. Monthly late rate trend ───────────────────────────────
-- Is late delivery getting better or worse over time?

SELECT
    order_month,
    COUNT(*)                                            AS delivered_orders,
    SUM(is_late)                                        AS late_orders,
    ROUND(AVG(is_late) * 100, 1)                       AS late_rate_pct,
    ROUND(AVG(CASE WHEN is_late = 1
              THEN review_score END), 2)                AS avg_score_late,
    ROUND(AVG(CASE WHEN is_late = 0
              THEN review_score END), 2)                AS avg_score_on_time
FROM vw_order_analysis
WHERE review_score IS NOT NULL
  AND is_late IS NOT NULL
GROUP BY order_month
ORDER BY order_month;


-- ── 4. Late delivery by customer state ───────────────────────
-- Which states have the worst late rates?

SELECT
    customer_state,
    COUNT(*)                                            AS delivered_orders,
    SUM(is_late)                                        AS late_orders,
    ROUND(AVG(is_late) * 100, 1)                       AS late_rate_pct,
    ROUND(AVG(is_detractor) * 100, 1)                  AS detractor_rate_pct,
    ROUND(SUM(CASE WHEN is_detractor = 1
              THEN order_gmv ELSE 0 END), 0)            AS gmv_at_risk
FROM vw_order_analysis
WHERE review_score IS NOT NULL
  AND is_late IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 200
ORDER BY late_rate_pct DESC;


-- ── 5. Late delivery impact summary (single headline numbers) ─
-- The three numbers that go in your Executive Summary

SELECT
    ROUND(AVG(CASE WHEN is_late = 0
              THEN is_detractor END) * 100, 1)          AS on_time_detractor_pct,
    ROUND(AVG(CASE WHEN is_late = 1
              THEN is_detractor END) * 100, 1)          AS late_detractor_pct,
    ROUND(SUM(CASE WHEN is_late = 1 AND is_detractor = 1
              THEN order_gmv ELSE 0 END), 0)            AS late_detractor_gmv,
    ROUND(SUM(CASE WHEN is_late = 1
              THEN order_gmv ELSE 0 END), 0)            AS total_late_gmv,
    ROUND(AVG(CASE WHEN is_late = 1
              THEN late_days END), 1)                   AS avg_days_late
FROM vw_order_analysis
WHERE review_score IS NOT NULL;