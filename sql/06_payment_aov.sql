-- =====================================================================
-- 06_payment_aov.sql
-- E-Commerce Sales & Logistics Analytics — Part 6: Payment Analysis
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 6.1 Payment Method Mix and Average Payment Value per Order
-- Question: Which payment methods dominate order volume, and how does average
--           payment value per order differ across payment types?
--
-- Fan-out prevention:
-- `payments` can contain multiple rows per order. Payments are first
-- aggregated to one row per order before any higher-level analysis.
--
-- Metric definition:
-- `order_payment_value` is the sum of `payments.payment_value` for an order.
-- It represents the amount paid, not merchandise-only item revenue. It can
-- include freight and financing/installment-related charges captured in the
-- payment value, so this metric is labeled average payment value per order
-- rather than merchandise AOV.
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
  ROUND(AVG(order_payment_value), 2) AS avg_payment_value_per_order,
  ROUND(
    SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()) * 100,
    2
  ) AS order_share_pct
FROM payment_order
GROUP BY payment_type
ORDER BY total_orders DESC;

-- Validated result summary:
--   credit_card: 74,975 orders | 75.40% share | 167.29 avg payment/order |
--                12,542,527.15 total payment value
--   boleto:      19,784 orders | 19.90% share | 145.03 avg payment/order |
--                2,869,361.27 total payment value
--   voucher:      3,151 orders |  3.17% share | 120.29 avg payment/order |
--                  379,043.91 total payment value
--   debit_card:   1,527 orders |  1.54% share | 142.72 avg payment/order |
--                  217,939.79 total payment value
--   not_defined:      3 orders |  0.00% share |   0.00 avg payment/order
--
-- Coverage note:
--   These payment-order counts sum to 99,440. The full orders table contains
--   99,441 orders, so one order has no payment record and is not represented
--   in this payment analysis. The README summary table focuses on the four
--   defined payment methods and omits the 3 `not_defined` orders.
--
-- Business interpretation:
--   Payment behavior is highly concentrated in credit cards, which account
--   for 75.4% of payment orders and also have the highest average payment value
--   per order among the major payment methods (167.29). Boleto remains
--   commercially meaningful at 19.9% of payment orders, with 145.03 average
--   payment value per order.
--
-- Limitation:
--   This is descriptive payment-method segmentation. It does not establish
--   that payment method causes differences in payment value; product mix,
--   customer mix, promotions, freight, financing, or order composition may
--   contribute.
