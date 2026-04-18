-- ============================================================
-- 02_cx_kpi_views.sql
-- Purpose:  Master analysis view joining all core tables and
--           computing derived KPI columns used across all
--           downstream queries
-- Analyst:  Michael Edgington
-- Stakeholders: CX Analytics, Logistics Ops, Seller Quality
-- ============================================================


CREATE OR REPLACE VIEW vw_order_analysis AS

WITH order_primary_item AS (
    -- One row per order: the first item, its product, seller, category
    SELECT
        oi.order_id,
        oi.seller_id,
        oi.product_id,
        oi.price,
        oi.freight_value,
        p.category_id,
        p.weight_grams
    FROM order_items oi
    LEFT JOIN products p ON oi.product_id = p.product_id
    WHERE oi.order_item_id = 1
),

order_gmv AS (
    -- Total GMV per order across all items
    SELECT
        order_id,
        SUM(price)                      AS order_gmv,
        SUM(freight_value)              AS order_freight,
        SUM(price + freight_value)      AS order_total,
        COUNT(*)                        AS item_count
    FROM order_items
    GROUP BY order_id
),

order_payments AS (
    -- Max installments per order (used for complaint correlation)
    SELECT
        order_id,
        MAX(payment_installments)       AS max_installments,
        SUM(payment_value)              AS total_paid,
        COUNT(DISTINCT payment_type)    AS payment_methods
    FROM payments
    GROUP BY order_id
)

SELECT
    -- ── Order identifiers ──────────────────────────────────
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_state,

    -- ── Seller & product ───────────────────────────────────
    pi.seller_id,
    pi.product_id,
    pi.category_id,
    pc.category_name,
    pi.weight_grams,

    -- ── Financials ─────────────────────────────────────────
    pi.price                            AS item_price,
    pi.freight_value,
    g.order_gmv,
    g.order_freight,
    g.order_total,
    g.item_count,

    -- ── Timestamps ─────────────────────────────────────────
    o.purchase_ts,
    o.approved_ts,
    o.delivered_carrier_ts,
    o.delivered_customer_ts,
    o.estimated_delivery_ts,

    -- ── Time dimensions ────────────────────────────────────
    DATE_TRUNC('month', o.purchase_ts)  AS order_month,
    EXTRACT(YEAR  FROM o.purchase_ts)   AS order_year,
    EXTRACT(MONTH FROM o.purchase_ts)   AS order_month_num,
    EXTRACT(DOW   FROM o.purchase_ts)   AS order_dow,

    -- ── Order status ───────────────────────────────────────
    o.order_status,
    CASE WHEN o.order_status IN ('canceled','returned','unavailable')
         THEN 1 ELSE 0 END              AS is_canceled_or_returned,

    -- ── Delivery performance ───────────────────────────────
    CASE
        WHEN o.delivered_customer_ts IS NULL THEN NULL
        WHEN o.delivered_customer_ts > o.estimated_delivery_ts THEN 1
        ELSE 0
    END                                 AS is_late,

    CASE
        WHEN o.delivered_customer_ts IS NULL THEN NULL
        ELSE DATEDIFF('day',
            o.estimated_delivery_ts,
            o.delivered_customer_ts)
    END                                 AS late_days,

    DATEDIFF('day',
        o.purchase_ts,
        o.delivered_customer_ts)        AS actual_delivery_days,

    -- ── Delivery lateness bucket ───────────────────────────
    CASE
        WHEN o.delivered_customer_ts IS NULL        THEN 'not_delivered'
        WHEN o.delivered_customer_ts
             <= o.estimated_delivery_ts             THEN 'on_time'
        WHEN DATEDIFF('day',
             o.estimated_delivery_ts,
             o.delivered_customer_ts) <= 3          THEN 'late_1_3_days'
        WHEN DATEDIFF('day',
             o.estimated_delivery_ts,
             o.delivered_customer_ts) <= 7          THEN 'late_4_7_days'
        ELSE                                             'late_8_plus_days'
    END                                 AS delivery_bucket,

    -- ── Review metrics ─────────────────────────────────────
    r.review_id,
    r.review_score,
    r.review_message,
    r.review_title,
    r.review_created_ts,
    r.review_answered_ts,

    CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END     AS is_detractor,
    CASE WHEN r.review_score >= 4 THEN 1 ELSE 0 END     AS is_promoter,
    CASE WHEN r.review_score =  3 THEN 1 ELSE 0 END     AS is_passive,
    CASE WHEN r.review_answered_ts IS NOT NULL
         THEN 1 ELSE 0 END                              AS has_seller_response,

    -- ── Root cause taxonomy (keyword classification) ───────
    -- ── Root cause taxonomy (keyword classification) ───────
    CASE
        WHEN review_score <= 2 AND (
            LOWER(review_message) LIKE '%late%' OR
            LOWER(review_message) LIKE '%delay%' OR
            LOWER(review_message) LIKE '%days late%' OR
            LOWER(review_message) LIKE '%too long%' OR
            LOWER(review_message) LIKE '%took forever%'
        ) THEN 'late_delivery'

        WHEN review_score <= 2 AND (
            LOWER(review_message) LIKE '%broken%' OR
            LOWER(review_message) LIKE '%damaged%' OR
            LOWER(review_message) LIKE '%cracked%' OR
            LOWER(review_message) LIKE '%defective%' OR
            LOWER(review_message) LIKE '%not work%' OR
            LOWER(review_message) LIKE '%dented%'
        ) THEN 'damaged_defective'

        WHEN review_score <= 2 AND (
            LOWER(review_message) LIKE '%wrong item%' OR
            LOWER(review_message) LIKE '%wrong size%' OR
            LOWER(review_message) LIKE '%wrong color%' OR
            LOWER(review_message) LIKE '%not what i ordered%' OR
            LOWER(review_message) LIKE '%different product%' OR
            LOWER(review_message) LIKE '%incorrect%'
        ) THEN 'wrong_item'

        WHEN review_score <= 2 AND (
            LOWER(review_message) LIKE '%no response%' OR
            LOWER(review_message) LIKE '%never replied%' OR
            LOWER(review_message) LIKE '%unresponsive%' OR
            LOWER(review_message) LIKE '%ignored%' OR
            LOWER(review_message) LIKE '%customer service%'
        ) THEN 'seller_unresponsive'

        WHEN review_score <= 2 AND (
            LOWER(review_message) LIKE '%cheap%' OR
            LOWER(review_message) LIKE '%poor quality%' OR
            LOWER(review_message) LIKE '%flimsy%' OR
            LOWER(review_message) LIKE '%not as described%' OR
            LOWER(review_message) LIKE '%disappointing%' OR
            LOWER(review_message) LIKE '%poorly made%' OR
            LOWER(review_message) LIKE '%fell apart%'
        ) THEN 'quality_below_expectations'

        WHEN review_score <= 2
            THEN 'uncategorized_complaint'

        ELSE NULL
    END                                 AS root_cause,

    -- ── Payment behavior ───────────────────────────────────
    pay.max_installments,
    pay.total_paid,
    CASE
        WHEN pay.max_installments = 1           THEN '1_installment'
        WHEN pay.max_installments <= 3          THEN '2_3_installments'
        WHEN pay.max_installments <= 5          THEN '4_5_installments'
        ELSE                                         '6_plus_installments'
    END                                 AS installment_bucket

FROM orders o
LEFT JOIN customers          c   ON o.customer_id    = c.customer_id
LEFT JOIN order_primary_item pi  ON o.order_id       = pi.order_id
LEFT JOIN product_categories pc  ON pi.category_id   = pc.category_id
LEFT JOIN order_gmv          g   ON o.order_id       = g.order_id
LEFT JOIN reviews            r   ON o.order_id       = r.order_id
LEFT JOIN order_payments     pay ON o.order_id       = pay.order_id;