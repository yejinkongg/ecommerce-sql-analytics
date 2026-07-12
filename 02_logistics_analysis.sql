-- =====================================================================
-- 02_logistics_analysis.sql
-- E-Commerce Sales & Logistics Analytics — Part 2: Logistics Analysis
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 2.1 Average Delivery Time
-- Question: How long does delivery take on average, purchase -> customer receipt?
-- ---------------------------------------------------------------------
SELECT
  AVG(DATE_DIFF(order_delivered_customer_date, order_purchase_timestamp, DAY)) AS avg_delivery_days
FROM `e-commerce-public-dataanalysis.olist.orders`
WHERE order_delivered_customer_date IS NOT NULL;

-- Result: avg_delivery_days = 12.09


-- ---------------------------------------------------------------------
-- 2.2 Delivery Time Distribution (Bucketed)
-- Question: Where is delivery time actually concentrated?
-- ---------------------------------------------------------------------
SELECT
  CASE
    WHEN DATE_DIFF(order_delivered_customer_date, order_purchase_timestamp, DAY) <= 7 THEN '0-7'
    WHEN DATE_DIFF(order_delivered_customer_date, order_purchase_timestamp, DAY) BETWEEN 8 AND 14 THEN '8-14'
    WHEN DATE_DIFF(order_delivered_customer_date, order_purchase_timestamp, DAY) BETWEEN 15 AND 30 THEN '15-30'
    WHEN DATE_DIFF(order_delivered_customer_date, order_purchase_timestamp, DAY) BETWEEN 31 AND 70 THEN '31-70'
    ELSE '70+'
  END AS delivery_bucket,
  COUNT(*) AS order_count
FROM `e-commerce-public-dataanalysis.olist.orders`
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY delivery_bucket
ORDER BY
  CASE delivery_bucket
    WHEN '0-7' THEN 1
    WHEN '8-14' THEN 2
    WHEN '15-30' THEN 3
    WHEN '31-70' THEN 4
    ELSE 5
  END;

-- Result: 0-7 days: 33,698 | 8-14 days: 36,398 | 15-30 days: 22,262
--         31-70 days: 3,955 | 70+ days: 163
-- Most orders fall in the 0-14 day range; the long tail beyond 30 days
-- is a small fraction but pulls the mean upward.


-- ---------------------------------------------------------------------
-- 2.3 Most Common Delivery Times (Top 10)
-- Question: What is the single most frequent delivery duration?
-- ---------------------------------------------------------------------
SELECT
  DATE_DIFF(order_delivered_customer_date, order_purchase_timestamp, DAY) AS delivery_days,
  COUNT(*) AS order_count
FROM `e-commerce-public-dataanalysis.olist.orders`
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY delivery_days
ORDER BY order_count DESC
LIMIT 10;

-- Result: 7 days is the single most common delivery time (7,653 orders),
-- with 6-9 days forming the densest cluster overall — well below the
-- 12.09-day average, confirming the average is skewed by long-tail delays.


-- ---------------------------------------------------------------------
-- 2.4 On-Time Delivery Rate
-- Question: What share of orders arrive by the estimated delivery date?
-- ---------------------------------------------------------------------
SELECT
  COUNT(*) AS total_orders,
  COUNTIF(
    DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)
  ) AS delayed_orders,
  ROUND(
    COUNTIF(
      DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)
    ) * 100.0 / COUNT(*),
    2
  ) AS delayed_rate
FROM `e-commerce-public-dataanalysis.olist.orders`
WHERE order_delivered_customer_date IS NOT NULL;

-- Result: 96,476 total orders / 6,535 delayed (6.77%)
--         -> 93.23% on-time or early delivery rate


-- ---------------------------------------------------------------------
-- 2.5 Distribution of Days Early/Late vs. Estimated Delivery Date
-- Question: When orders are NOT late, how early do they tend to arrive?
--           (Signals whether ETA is set conservatively.)
-- ---------------------------------------------------------------------
SELECT
  DATE_DIFF(
    DATE(order_delivered_customer_date),
    DATE(order_estimated_delivery_date),
    DAY
  ) AS delayed_days,
  COUNT(*) AS order_count
FROM `e-commerce-public-dataanalysis.olist.orders`
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY delayed_days
ORDER BY order_count DESC;

-- Result: The most frequent values are -14, -13, -15 (i.e. arriving
-- 13-15 days *before* the estimated date) — suggesting the platform
-- applies a deliberately conservative ETA to manage customer expectations.


-- ---------------------------------------------------------------------
-- 2.6 Average Seller Hand-off Time
-- Question: How long does it take a seller to hand the order to the carrier
--           after payment approval?
-- ---------------------------------------------------------------------
SELECT
  AVG(
    DATE_DIFF(order_delivered_carrier_date, order_approved_at, DAY)
  ) AS avg_handoff_days
FROM `e-commerce-public-dataanalysis.olist.orders`
WHERE order_approved_at IS NOT NULL
  AND order_delivered_carrier_date IS NOT NULL;

-- Result: avg_handoff_days = 2.32


-- ---------------------------------------------------------------------
-- 2.7 Hand-off Time Distribution
-- Question: How concentrated is hand-off time, and are there anomalies?
-- ---------------------------------------------------------------------
SELECT
  DATE_DIFF(
    DATE(order_delivered_carrier_date), DATE(order_approved_at), DAY
  ) AS handoff_days,
  COUNT(*) AS order_count
FROM `e-commerce-public-dataanalysis.olist.orders`
WHERE order_approved_at IS NOT NULL
  AND order_delivered_carrier_date IS NOT NULL
GROUP BY handoff_days
ORDER BY order_count DESC
LIMIT 10;

-- Data quality note: a small number of rows return negative handoff_days
-- (e.g. -171, -9, -8), meaning the carrier pickup timestamp precedes the
-- payment approval timestamp — logically impossible in a normal process.
-- Flagged as a data quality issue requiring timestamp validation upstream
-- (see docs/schema_notes.md).
