-- ============================================================
-- 08_installment_correlation.sql
-- Question:  Does payment installment behavior correlate with
--            complaint rate, and what does this signal about
--            purchase stress and buyer intent?
-- Stakeholder: Finance, VP Customer Experience, Product
-- ============================================================


-- ── 1. Detractor rate by installment bucket ──────────────────
-- Core correlation: does splitting payments predict complaints?

SELECT
    installment_bucket,
    COUNT(*)                                            AS orders,
    ROUND(AVG(is_detractor) * 100, 1)                  AS detractor_rate_pct,
    ROUND(AVG(is_promoter) * 100, 1)                   AS promoter_rate_pct,
    ROUND(AVG(review_score), 2)                        AS avg_review_score,
    ROUND(AVG(order_gmv), 2)                           AS avg_order_gmv,
    ROUND(SUM(CASE WHEN is_detractor = 1
              THEN order_gmv ELSE 0 END), 0)            AS detractor_gmv
FROM vw_order_analysis
WHERE review_score IS NOT NULL
  AND installment_bucket IS NOT NULL
GROUP BY installment_bucket
ORDER BY
    CASE installment_bucket
        WHEN '1_installment'      THEN 1
        WHEN '2_3_installments'   THEN 2
        WHEN '4_5_installments'   THEN 3
        WHEN '6_plus_installments' THEN 4
    END;


-- ── 2. Installment behavior by category ──────────────────────
-- Which categories see the most installment usage?
-- High installments + high detractor = financial stress signal

SELECT
    category_name,
    COUNT(*)                                            AS orders,
    ROUND(AVG(max_installments), 1)                    AS avg_installments,
    ROUND(AVG(CASE WHEN installment_bucket = '6_plus_installments'
              THEN 1.0 ELSE 0 END) * 100, 1)           AS pct_6plus_installments,
    ROUND(AVG(is_detractor) * 100, 1)                  AS detractor_rate_pct,
    ROUND(AVG(order_gmv), 2)                           AS avg_order_gmv
FROM vw_order_analysis
WHERE review_score IS NOT NULL
  AND category_name IS NOT NULL
GROUP BY category_name
HAVING COUNT(*) >= 200
ORDER BY pct_6plus_installments DESC;


-- ── 3. Installment + late delivery combined effect ───────────
-- Does being late AND on installments compound the complaint risk?

SELECT
    installment_bucket,
    CASE WHEN is_late = 1 THEN 'late' ELSE 'on_time' END    AS delivery_status,
    COUNT(*)                                                  AS orders,
    ROUND(AVG(is_detractor) * 100, 1)                       AS detractor_rate_pct,
    ROUND(AVG(review_score), 2)                             AS avg_review_score,
    ROUND(SUM(CASE WHEN is_detractor = 1
              THEN order_gmv ELSE 0 END), 0)                 AS detractor_gmv
FROM vw_order_analysis
WHERE review_score IS NOT NULL
  AND installment_bucket IS NOT NULL
  AND is_late IS NOT NULL
GROUP BY installment_bucket, delivery_status
ORDER BY
    CASE installment_bucket
        WHEN '1_installment'       THEN 1
        WHEN '2_3_installments'    THEN 2
        WHEN '4_5_installments'    THEN 3
        WHEN '6_plus_installments' THEN 4
    END,
    delivery_status;


-- ── 4. Monthly installment trend ─────────────────────────────
-- Is high-installment purchasing growing over time?

SELECT
    order_month,
    COUNT(*)                                            AS total_orders,
    ROUND(AVG(max_installments), 2)                    AS avg_installments,
    SUM(CASE WHEN installment_bucket = '6_plus_installments'
             THEN 1 ELSE 0 END)                        AS orders_6plus,
    ROUND(AVG(CASE WHEN installment_bucket = '6_plus_installments'
              THEN 1.0 ELSE 0 END) * 100, 1)           AS pct_6plus,
    ROUND(AVG(CASE WHEN installment_bucket = '6_plus_installments'
              THEN is_detractor END) * 100, 1)         AS detractor_rate_6plus
FROM vw_order_analysis
WHERE review_score IS NOT NULL
GROUP BY order_month
ORDER BY order_month;


-- ── 5. Installment summary headline numbers ──────────────────
-- Clean comparison for executive summary

SELECT
    ROUND(AVG(CASE WHEN installment_bucket = '1_installment'
              THEN is_detractor END) * 100, 1)         AS single_pay_detractor_pct,
    ROUND(AVG(CASE WHEN installment_bucket = '6_plus_installments'
              THEN is_detractor END) * 100, 1)         AS high_install_detractor_pct,
    ROUND(SUM(CASE WHEN installment_bucket = '6_plus_installments'
              AND is_detractor = 1
              THEN order_gmv ELSE 0 END), 0)           AS high_install_detractor_gmv,
    COUNT(CASE WHEN installment_bucket = '6_plus_installments'
               THEN 1 END)                             AS high_install_orders,
    ROUND(AVG(CASE WHEN installment_bucket = '6_plus_installments'
              THEN order_gmv END), 2)                  AS avg_high_install_order_value
FROM vw_order_analysis
WHERE review_score IS NOT NULL;