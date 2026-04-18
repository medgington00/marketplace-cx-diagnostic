-- ============================================================
-- 01_data_quality_audit.sql
-- Purpose:  Validate data integrity before analysis begins
-- Analyst:  Michael Edgington
-- Updated:  2024
-- Stakeholder: Internal — establishes trust in the dataset
-- ============================================================


-- ============================================================
-- SECTION 1: ROW COUNTS & TABLE OVERVIEW
-- Expected: customers=100000, orders=100000, items=129650,
--           products=15000, categories=42, sellers=2500,
--           payments=107804, reviews=78687, geo=5000
-- ============================================================

SELECT 'customers'          AS table_name, COUNT(*) AS row_count FROM customers          UNION ALL
SELECT 'orders',                           COUNT(*)               FROM orders              UNION ALL
SELECT 'order_items',                      COUNT(*)               FROM order_items         UNION ALL
SELECT 'products',                         COUNT(*)               FROM products            UNION ALL
SELECT 'product_categories',               COUNT(*)               FROM product_categories  UNION ALL
SELECT 'sellers',                          COUNT(*)               FROM sellers             UNION ALL
SELECT 'payments',                         COUNT(*)               FROM payments            UNION ALL
SELECT 'reviews',                          COUNT(*)               FROM reviews             UNION ALL
SELECT 'geolocation',                      COUNT(*)               FROM geolocation
ORDER BY row_count DESC;


-- ============================================================
-- SECTION 2: DATE RANGE & COVERAGE
-- Expected: 2023-01-01 through 2024-12-31
-- ============================================================

SELECT
    MIN(purchase_ts)::DATE                              AS earliest_order,
    MAX(purchase_ts)::DATE                              AS latest_order,
    COUNT(DISTINCT CAST(purchase_ts AS DATE))           AS active_days,
    COUNT(DISTINCT DATE_TRUNC('month', purchase_ts))    AS active_months
FROM orders;


-- ============================================================
-- SECTION 3: NULL CHECKS ON CRITICAL FIELDS
-- These fields drive the core analyses — nulls here break things
-- ============================================================

SELECT
    COUNT(*)                                                         AS total_orders,
    COUNT(*) FILTER (WHERE delivered_customer_ts IS NULL)            AS null_delivered_ts,
    COUNT(*) FILTER (WHERE estimated_delivery_ts IS NULL)            AS null_estimated_ts,
    COUNT(*) FILTER (WHERE approved_ts IS NULL)                      AS null_approved_ts,
    COUNT(*) FILTER (WHERE customer_id IS NULL)                      AS null_customer_id,
    COUNT(*) FILTER (WHERE order_status IS NULL)                     AS null_status,
    ROUND(
        COUNT(*) FILTER (WHERE delivered_customer_ts IS NULL)
        * 100.0 / COUNT(*), 1
    )                                                                AS pct_null_delivered
FROM orders;

SELECT
    COUNT(*)                                                         AS total_reviews,
    COUNT(*) FILTER (WHERE review_score IS NULL)                     AS null_score,
    COUNT(*) FILTER (WHERE review_message IS NULL)                   AS null_message,
    COUNT(*) FILTER (WHERE review_answered_ts IS NULL)               AS null_answered,
    ROUND(
        COUNT(*) FILTER (WHERE review_answered_ts IS NULL)
        * 100.0 / COUNT(*), 1
    )                                                                AS pct_unanswered
FROM reviews;

SELECT
    COUNT(*)                                                         AS total_items,
    COUNT(*) FILTER (WHERE seller_id IS NULL)                        AS null_seller,
    COUNT(*) FILTER (WHERE product_id IS NULL)                       AS null_product,
    COUNT(*) FILTER (WHERE price IS NULL OR price <= 0)              AS invalid_price,
    COUNT(*) FILTER (WHERE freight_value IS NULL OR freight_value < 0) AS invalid_freight
FROM order_items;


-- ============================================================
-- SECTION 4: ORDER STATUS DISTRIBUTION
-- Understand what share of orders are actually delivered
-- ============================================================

SELECT
    order_status,
    COUNT(*)                                    AS orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct_of_total
FROM orders
GROUP BY order_status
ORDER BY orders DESC;


-- ============================================================
-- SECTION 5: REVIEW SCORE DISTRIBUTION
-- Baseline CSAT picture before any segmentation
-- ============================================================

SELECT
    review_score,
    COUNT(*)                                            AS reviews,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)  AS pct_of_total,
    ROUND(SUM(COUNT(*)) OVER (ORDER BY review_score) * 100.0
          / SUM(COUNT(*)) OVER(), 1)                    AS cumulative_pct
FROM reviews
GROUP BY review_score
ORDER BY review_score;


-- ============================================================
-- SECTION 6: FOREIGN KEY INTEGRITY CHECKS
-- Every child record should resolve to a parent
-- Expected: all orphan counts = 0
-- ============================================================

SELECT 'order_items → orders'       AS relationship,
    COUNT(*) AS orphaned_records
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT 'reviews → orders',
    COUNT(*)
FROM reviews r
LEFT JOIN orders o ON r.order_id = o.order_id
WHERE o.order_id IS NULL

UNION ALL

SELECT 'order_items → products',
    COUNT(*)
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL

UNION ALL

SELECT 'order_items → sellers',
    COUNT(*)
FROM order_items oi
LEFT JOIN sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL

UNION ALL

SELECT 'payments → orders',
    COUNT(*)
FROM payments p
LEFT JOIN orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL;


-- ============================================================
-- SECTION 7: PRICE & GMV SANITY
-- ============================================================

SELECT
    ROUND(MIN(price), 2)            AS min_price,
    ROUND(MAX(price), 2)            AS max_price,
    ROUND(AVG(price), 2)            AS avg_price,
    ROUND(MEDIAN(price), 2)         AS median_price,
    ROUND(SUM(price), 2)            AS total_gmv,
    COUNT(*)                        AS total_items
FROM order_items;


-- ============================================================
-- SECTION 8: REVIEW COVERAGE RATE
-- What % of delivered orders received a review?
-- ============================================================

SELECT
    o.order_status,
    COUNT(DISTINCT o.order_id)              AS orders,
    COUNT(DISTINCT r.order_id)              AS reviewed,
    ROUND(
        COUNT(DISTINCT r.order_id) * 100.0
        / COUNT(DISTINCT o.order_id), 1
    )                                       AS review_rate_pct
FROM orders o
LEFT JOIN reviews r ON o.order_id = r.order_id
GROUP BY o.order_status
ORDER BY orders D