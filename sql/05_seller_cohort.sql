-- ============================================================
-- 05_seller_cohort.sql
-- Question:  Which sellers are driving disproportionate
--            complaints, and what is their GMV footprint?
-- Stakeholder: Seller Quality Team, Marketplace Operations
-- ============================================================


-- ── 1. Seller performance overview ───────────────────────────
-- All sellers with 30+ reviewed orders ranked by detractor rate

SELECT
    seller_id,
    COUNT(*)                                            AS reviewed_orders,
    ROUND(AVG(is_detractor) * 100, 1)                  AS detractor_rate_pct,
    ROUND(AVG(is_promoter) * 100, 1)                   AS promoter_rate_pct,
    ROUND(AVG(review_score), 2)                        AS avg_review_score,
    ROUND(SUM(order_gmv), 0)                           AS total_gmv,
    ROUND(AVG(is_late) * 100, 1)                       AS late_rate_pct
FROM vw_order_analysis
WHERE review_score IS NOT NULL
GROUP BY seller_id
HAVING COUNT(*) >= 30
ORDER BY detractor_rate_pct DESC;


-- ── 2. Problem seller cohort (top decile) ────────────────────
-- Flag sellers whose detractor rate is in the top 10%

WITH seller_stats AS (
    SELECT
        seller_id,
        COUNT(*)                                        AS reviewed_orders,
        ROUND(AVG(is_detractor) * 100, 1)              AS detractor_rate_pct,
        ROUND(AVG(review_score), 2)                    AS avg_review_score,
        ROUND(SUM(order_gmv), 0)                       AS total_gmv,
        ROUND(SUM(is_detractor * order_gmv), 0)        AS detractor_gmv,
        ROUND(AVG(is_late) * 100, 1)                   AS late_rate_pct
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
    GROUP BY seller_id
    HAVING COUNT(*) >= 30
),
threshold AS (
    SELECT PERCENTILE_CONT(0.90) WITHIN GROUP
           (ORDER BY detractor_rate_pct)                AS p90_threshold
    FROM seller_stats
)
SELECT
    s.*,
    CASE WHEN s.detractor_rate_pct >= t.p90_threshold
         THEN 'problem_seller' ELSE 'standard' END      AS cohort_flag
FROM seller_stats s
CROSS JOIN threshold t
ORDER BY detractor_rate_pct DESC;


-- ── 3. Cohort summary — problem vs standard ──────────────────
-- Side-by-side comparison of the two cohorts

WITH seller_stats AS (
    SELECT
        seller_id,
        COUNT(*)                                        AS reviewed_orders,
        AVG(is_detractor)                              AS detractor_rate,
        SUM(order_gmv)                                 AS total_gmv,
        SUM(is_detractor * order_gmv)                  AS detractor_gmv
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
    GROUP BY seller_id
    HAVING COUNT(*) >= 30
),
threshold AS (
    SELECT PERCENTILE_CONT(0.90) WITHIN GROUP
           (ORDER BY detractor_rate)                    AS p90_threshold
    FROM seller_stats
),
flagged AS (
    SELECT
        s.*,
        CASE WHEN s.detractor_rate >= t.p90_threshold
             THEN 'problem_seller' ELSE 'standard' END  AS cohort_flag
    FROM seller_stats s
    CROSS JOIN threshold t
)
SELECT
    cohort_flag,
    COUNT(*)                                            AS seller_count,
    SUM(reviewed_orders)                               AS total_orders,
    ROUND(AVG(detractor_rate) * 100, 1)                AS avg_detractor_rate_pct,
    ROUND(SUM(total_gmv), 0)                           AS total_gmv,
    ROUND(SUM(detractor_gmv), 0)                       AS detractor_gmv,
    ROUND(SUM(detractor_gmv) /
          SUM(total_gmv) * 100, 1)                     AS detractor_gmv_pct
FROM flagged
GROUP BY cohort_flag
ORDER BY cohort_flag;


-- ── 4. Problem seller category concentration ─────────────────
-- What categories do problem sellers operate in?

WITH seller_stats AS (
    SELECT
        seller_id,
        AVG(is_detractor)                              AS detractor_rate
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
    GROUP BY seller_id
    HAVING COUNT(*) >= 30
),
threshold AS (
    SELECT PERCENTILE_CONT(0.90) WITHIN GROUP
           (ORDER BY detractor_rate)                    AS p90_threshold
    FROM seller_stats
),
problem_sellers AS (
    SELECT s.seller_id
    FROM seller_stats s
    CROSS JOIN threshold t
    WHERE s.detractor_rate >= t.p90_threshold
)
SELECT
    v.category_name,
    COUNT(DISTINCT v.seller_id)                        AS problem_sellers,
    COUNT(*)                                           AS orders,
    ROUND(AVG(v.is_detractor) * 100, 1)               AS detractor_rate_pct,
    ROUND(SUM(v.order_gmv), 0)                        AS gmv
FROM vw_order_analysis v
INNER JOIN problem_sellers ps ON v.seller_id = ps.seller_id
WHERE review_score IS NOT NULL
GROUP BY v.category_name
ORDER BY orders DESC;


-- ── 5. Problem seller complaint type breakdown ────────────────
-- What are problem sellers' customers complaining about?

WITH seller_stats AS (
    SELECT
        seller_id,
        AVG(is_detractor)                              AS detractor_rate
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
    GROUP BY seller_id
    HAVING COUNT(*) >= 30
),
threshold AS (
    SELECT PERCENTILE_CONT(0.90) WITHIN GROUP
           (ORDER BY detractor_rate)                    AS p90_threshold
    FROM seller_stats
),
problem_sellers AS (
    SELECT s.seller_id
    FROM seller_stats s
    CROSS JOIN threshold t
    WHERE s.detractor_rate >= t.p90_threshold
)
SELECT
    v.root_cause,
    COUNT(*)                                           AS detractor_reviews,
    ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER(), 1)                     AS pct_of_complaints
FROM vw_order_analysis v
INNER JOIN problem_sellers ps ON v.seller_id = ps.seller_id
WHERE v.is_detractor = 1
GROUP BY v.root_cause
ORDER BY detractor_reviews DESC;