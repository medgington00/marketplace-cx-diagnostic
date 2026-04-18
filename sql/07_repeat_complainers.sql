-- ============================================================
-- 07_repeat_complainers.sql
-- Question:  Which customers file repeat complaints, how
--            quickly do they return, and what is the retention
--            risk they represent?
-- Stakeholder: VP Customer Experience, Retention/Loyalty
-- ============================================================


-- ── 1. Complaint frequency distribution ──────────────────────
-- How many customers have filed 1, 2, 3+ complaints?

WITH customer_complaints AS (
    SELECT
        customer_unique_id,
        COUNT(*)                                        AS total_orders,
        SUM(is_detractor)                              AS complaint_count,
        SUM(is_promoter)                               AS promoter_count,
        ROUND(SUM(order_gmv), 2)                       AS lifetime_gmv
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    complaint_count,
    COUNT(*)                                            AS customers,
    ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER(), 1)                     AS pct_of_customers,
    ROUND(AVG(lifetime_gmv), 2)                        AS avg_lifetime_gmv,
    ROUND(SUM(lifetime_gmv), 0)                        AS total_gmv
FROM customer_complaints
GROUP BY complaint_count
ORDER BY complaint_count;


-- ── 2. Repeat complainer profile ─────────────────────────────
-- How do repeat complainers differ from one-time complainers?

WITH customer_complaints AS (
    SELECT
        customer_unique_id,
        COUNT(*)                                        AS total_orders,
        SUM(is_detractor)                              AS complaint_count,
        SUM(is_promoter)                               AS promoter_count,
        ROUND(SUM(order_gmv), 2)                       AS lifetime_gmv,
        MIN(purchase_ts)                               AS first_order,
        MAX(purchase_ts)                               AS last_order
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN complaint_count = 0  THEN '0_complaints'
        WHEN complaint_count = 1  THEN '1_complaint'
        WHEN complaint_count = 2  THEN '2_complaints'
        ELSE                           '3_plus_complaints'
    END                                                AS complaint_tier,
    COUNT(*)                                           AS customers,
    ROUND(AVG(total_orders), 2)                        AS avg_orders_per_customer,
    ROUND(AVG(lifetime_gmv), 2)                        AS avg_lifetime_gmv,
    ROUND(SUM(lifetime_gmv), 0)                        AS total_gmv,
    ROUND(AVG(
        DATEDIFF('day', first_order, last_order)
    ), 0)                                              AS avg_days_as_customer
FROM customer_complaints
GROUP BY complaint_tier
ORDER BY complaint_tier;


-- ── 3. Time between first complaint and next order ────────────
-- Do customers come back after a complaint, and how quickly?

WITH complaint_orders AS (
    SELECT
        customer_unique_id,
        purchase_ts,
        is_detractor,
        order_gmv,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY purchase_ts
        )                                              AS order_seq
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
),
first_complaints AS (
    SELECT
        c.customer_unique_id,
        c.purchase_ts                                  AS complaint_ts
    FROM complaint_orders c
    WHERE c.is_detractor = 1
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.customer_unique_id
        ORDER BY c.purchase_ts
    ) = 1
),
next_orders AS (
    SELECT
        fc.customer_unique_id,
        fc.complaint_ts,
        MIN(co.purchase_ts)                            AS next_order_ts
    FROM first_complaints fc
    LEFT JOIN complaint_orders co
        ON fc.customer_unique_id = co.customer_unique_id
        AND co.purchase_ts > fc.complaint_ts
    GROUP BY fc.customer_unique_id, fc.complaint_ts
)
SELECT
    COUNT(*)                                           AS customers_with_complaint,
    SUM(CASE WHEN next_order_ts IS NOT NULL
             THEN 1 ELSE 0 END)                        AS returned_after_complaint,
    ROUND(SUM(CASE WHEN next_order_ts IS NOT NULL
              THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 1)                               AS return_rate_pct,
    ROUND(AVG(CASE WHEN next_order_ts IS NOT NULL
              THEN DATEDIFF('day', complaint_ts, next_order_ts)
              END), 0)                                 AS avg_days_to_return
FROM next_orders;


-- ── 4. Repeat complainer root cause pattern ──────────────────
-- What are repeat complainers complaining about each time?

WITH complaint_sequence AS (
    SELECT
        customer_unique_id,
        purchase_ts,
        root_cause,
        order_gmv,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY purchase_ts
        )                                              AS complaint_seq
    FROM vw_order_analysis
    WHERE is_detractor = 1
)
SELECT
    complaint_seq,
    root_cause,
    COUNT(*)                                           AS occurrences,
    ROUND(COUNT(*) * 100.0 /
          SUM(COUNT(*)) OVER
          (PARTITION BY complaint_seq), 1)             AS pct_of_seq
FROM complaint_sequence
WHERE complaint_seq <= 3
GROUP BY complaint_seq, root_cause
ORDER BY complaint_seq, occurrences DESC;


-- ── 5. GMV at risk from repeat complainers ───────────────────
-- Total spend from customers with 2+ complaints

WITH customer_complaints AS (
    SELECT
        customer_unique_id,
        SUM(is_detractor)                              AS complaint_count,
        ROUND(SUM(order_gmv), 2)                       AS lifetime_gmv,
        COUNT(*)                                       AS total_orders
    FROM vw_order_analysis
    WHERE review_score IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    ROUND(SUM(CASE WHEN complaint_count >= 2
              THEN lifetime_gmv ELSE 0 END), 0)        AS repeat_complainer_gmv,
    ROUND(SUM(lifetime_gmv), 0)                        AS total_customer_gmv,
    ROUND(SUM(CASE WHEN complaint_count >= 2
              THEN lifetime_gmv ELSE 0 END) * 100.0
          / SUM(lifetime_gmv), 1)                      AS repeat_complainer_gmv_pct,
    COUNT(CASE WHEN complaint_count >= 2
               THEN 1 END)                             AS repeat_complainers,
    COUNT(*)                                           AS total_customers,
    ROUND(COUNT(CASE WHEN complaint_count >= 2
                     THEN 1 END) * 100.0
          / COUNT(*), 1)                               AS repeat_complainer_pct
FROM customer_complaints;