-- =====================================================================
-- 06_payment_aov.sql
-- E-Commerce Sales & Logistics Analytics — Part 6: Payment & AOV Analysis
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 6.1 Payment Method Mix and Average Order Value
-- Question: Which payment methods dominate order volume, and how does average
--           order value differ across payment types?
--
-- Fan-out prevention:
-- `payments` can contain multiple rows per order. Payments are first
-- aggregated to one row per order before any higher-level analysis.
--
-- Primary payment method:
-- For orders with multiple payment records, the payment type associated with
-- the largest payment_value is used as the order's primary payment type.
-- ---------------------------------------------------------------------
WITH payment_order AS (
  SELECT
    order_id,
    SUM(payment_value) AS order_payment_value,
    ARRAY_AGG(
      STRUCT(payment_type, payment_value)
      ORDER BY payment_value DESC
      LIMIT 1
    )[OFFSET(0)].payment_type AS primary_payment_type
  FROM `e-commerce-public-dataanalysis.olist.payments`
  GROUP BY order_id
)
SELECT
  primary_payment_type AS payment_type,
  COUNT(*) AS total_orders,
  ROUND(SUM(order_payment_value), 2) AS total_payment_value,
  ROUND(AVG(order_payment_value), 2) AS avg_order_value,
  ROUND(
    SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()) * 100,
    2
  ) AS order_share_pct
FROM payment_order
GROUP BY payment_type
ORDER BY total_orders DESC;

-- Validated result summary:
--   credit_card: 74,975 orders | 75.40% share | 167.29 AOV |
--                12,542,527.15 total payment value
--   boleto:      19,784 orders | 19.90% share | 145.03 AOV |
--                2,869,361.27 total payment value
--   voucher:      3,151 orders |  3.17% share | 120.29 AOV |
--                  379,043.91 total payment value
--   debit_card:   1,527 orders |  1.54% share | 142.72 AOV |
--                  217,939.79 total payment value
--   not_defined:      3 orders |  0.00% share |   0.00 AOV
--
-- Business interpretation:
--   Payment behavior is highly concentrated in credit cards, which account
--   for 75.4% of orders and also have the highest AOV among the major payment
--   methods (167.29). Boleto remains commercially meaningful at 19.9% of
--   orders, but with a lower AOV of 145.03.
--
--   Voucher and debit-card orders represent relatively small shares of volume,
--   so even though their AOVs differ, changes in those payment types would have
--   less impact on overall revenue mix than credit-card or boleto behavior.
--
-- Limitation:
--   This is descriptive payment-method segmentation. It does not establish
--   that payment method causes differences in order value; product mix,
--   customer mix, promotions, or order composition may contribute.
