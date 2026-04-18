-- Quick sanity checks before formal data quality audit
-- Run after load_database.py to confirm foreign keys resolve and dates look right

-- All 9 tables and their row counts in one shot
SELECT 'customers'          AS tbl, COUNT(*) AS rows FROM customers          UNION ALL
SELECT 'orders',                    COUNT(*)          FROM orders              UNION ALL
SELECT 'order_items',               COUNT(*)          FROM order_items         UNION ALL
SELECT 'products',                  COUNT(*)          FROM products            UNION ALL
SELECT 'product_categories',        COUNT(*)          FROM product_categories  UNION ALL
SELECT 'sellers',                   COUNT(*)          FROM sellers             UNION ALL
SELECT 'payments',                  COUNT(*)          FROM payments            UNION ALL
SELECT 'reviews',                   COUNT(*)          FROM reviews             UNION ALL
SELECT 'geolocation',               COUNT(*)          FROM geolocation;

-- Date range of orders (should be 2023-01-01 through 2024-12-31)
SELECT
    MIN(purchase_ts) AS earliest_order,
    MAX(purchase_ts) AS latest_order,
    COUNT(DISTINCT CAST(purchase_ts AS DATE)) AS active_days
FROM orders;

-- FK spot check: any order_items pointing to an order that doesn't exist?
SELECT COUNT(*) AS orphaned_items
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;