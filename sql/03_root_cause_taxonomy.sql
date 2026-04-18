-- ============================================================
-- 03_root_cause_taxonomy.sql
-- Question:  What are the primary drivers of customer complaints,
--            and how has the mix shifted over time?
-- Stakeholder: VP Customer Experience, Support Operations
-- Output:    Root cause share of detractor reviews, monthly trend
-- ============================================================


-- ── 1. Overall root cause distribution ───────────────────────
-- What share of detractor reviews falls into each complaint category?

SELECT
    root_cause,
    COUNT(*)                                            AS detractor_reviews,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)  AS pct_of_detractors
FROM vw_order_analysis
WHERE is_detractor = 1
GROUP BY root_cause
ORDER BY detractor_reviews DESC;


-- ── 2. Root cause by category ────────────────────────────────
-- Which product categories drive which complaint types?
-- Reveals whether damaged = furniture/electronics, quality = apparel, etc.

SELECT
    category_name,
    root_cause,
    COUNT(*)                                            AS detractor_reviews,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER
          (PARTITION BY category_name), 1)              AS pct_within_category
FROM vw_order_analysis
WHERE is_detractor = 1
  AND category_name IS NOT NULL
GROUP BY category_name, root_cause
ORDER BY category_name, detractor_reviews DESC;


-- ── 3. Monthly trend of root cause mix ───────────────────────
-- Is any complaint type growing or shrinking over time?

SELECT
    order_month,
    root_cause,
    COUNT(*)                                            AS detractor_reviews,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER
          (PARTITION BY order_month), 1)                AS pct_of_month
FROM vw_order_analysis
WHERE is_detractor = 1
GROUP BY order_month, root_cause
ORDER BY order_month, detractor_reviews DESC;


-- ── 4. Seller response rate by root cause ────────────────────
-- Are sellers responding more to certain complaint types than others?

SELECT
    root_cause,
    COUNT(*)                                            AS detractor_reviews,
    SUM(has_seller_response)                            AS seller_responded,
    ROUND(SUM(has_seller_response) * 100.0
          / COUNT(*), 1)                                AS response_rate_pct
FROM vw_order_analysis
WHERE is_detractor = 1
GROUP BY root_cause
ORDER BY response_rate_pct DESC;


-- ── 5. GMV at risk by root cause ─────────────────────────────
-- Dollar value of orders tied to each complaint type

SELECT
    root_cause,
    COUNT(*)                                            AS detractor_reviews,
    ROUND(SUM(order_gmv), 0)                            AS gmv_at_risk,
    ROUND(AVG(order_gmv), 2)                            AS avg_order_value,
    ROUND(SUM(order_gmv) * 100.0 /
          SUM(SUM(order_gmv)) OVER(), 1)                AS pct_of_total_gmv_at_risk
FROM vw_order_analysis
WHERE is_detractor = 1
GROUP BY root_cause
ORDER BY gmv_at_risk DESC;