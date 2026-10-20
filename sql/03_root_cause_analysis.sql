-- =====================================================================
-- 03_root_cause_analysis.sql
-- E-Commerce Sales & Logistics Analytics — Part 3: Root Cause Analysis
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 3.0 Build a seller-order base table
-- Grain: one row per seller-order
--
-- Why this matters:
-- `order_items` can contain multiple rows for the same seller-order.
-- Using DISTINCT here prevents multi-item orders from receiving extra weight
-- in seller-level rates. Orders containing multiple sellers still appear once
-- for each seller, which is intentional for seller performance analysis.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE seller_order AS
SELECT DISTINCT
  oi.seller_id,
  o.order_id,
  DATE_DIFF(
    DATE(o.order_delivered_carrier_date),
    DATE(o.order_approved_at),
    DAY
  ) AS handoff_days,
  DATE_DIFF(
    DATE(o.order_delivered_customer_date),
    DATE(o.order_purchase_timestamp),
    DAY
  ) AS delivery_days,
  DATE_DIFF(
    DATE(o.order_delivered_customer_date),
    DATE(o.order_estimated_delivery_date),
    DAY
  ) AS late_days
FROM `e-commerce-public-dataanalysis.olist.orders` o
JOIN `e-commerce-public-dataanalysis.olist.order_items` oi
  ON o.order_id = oi.order_id
WHERE
  o.order_approved_at IS NOT NULL
  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL;


-- ---------------------------------------------------------------------
-- 3.1 Seller Performance Master Table
-- Question: How do seller hand-off speed and delivery reliability vary?
--
-- Eligibility: at least 50 distinct seller-orders, to reduce small-sample
-- noise.
--
-- Negative hand-off rule:
-- handoff_days < 0 is logically impossible in a normal order flow and is
-- treated as a data-quality defect. These rows remain in total_orders and
-- delivery metrics, but are excluded from hand-off averages and hand-off-rate
-- denominators. Their count is reported separately for transparency.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE seller_performance AS
SELECT
  seller_id,

  -- One row in seller_order = one seller-order
  COUNT(*) AS total_orders,

  -- Data-quality visibility for hand-off metrics
  COUNTIF(handoff_days >= 0) AS valid_handoff_orders,
  COUNTIF(handoff_days < 0) AS invalid_negative_handoff_orders,

  -- Average valid hand-off time (approval -> carrier pickup)
  ROUND(
    AVG(IF(handoff_days >= 0, handoff_days, NULL)),
    2
  ) AS avg_handoff_days,

  -- Share of valid seller-orders with 3+ day hand-off time
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(handoff_days >= 3),
      COUNTIF(handoff_days >= 0)
    ) * 100,
    2
  ) AS handoff_3plus_rate,

  -- Average delivery time (purchase -> customer receipt)
  ROUND(AVG(delivery_days), 2) AS avg_delivery_days,

  -- Order-level late-delivery rate
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(late_days > 0),
      COUNT(*)
    ) * 100,
    2
  ) AS late_delivery_rate

FROM seller_order
GROUP BY seller_id
HAVING COUNT(*) >= 50;


-- ---------------------------------------------------------------------
-- 3.2 Full Distribution Across All Qualifying Sellers
-- Question: What does the seller population look like before selecting
--           top/bottom examples?
-- ---------------------------------------------------------------------
SELECT
  COUNT(*) AS qualifying_sellers,

  ROUND(MIN(avg_handoff_days), 2) AS min_avg_handoff_days,
  ROUND(APPROX_QUANTILES(avg_handoff_days, 4)[OFFSET(1)], 2) AS p25_avg_handoff_days,
  ROUND(APPROX_QUANTILES(avg_handoff_days, 4)[OFFSET(2)], 2) AS median_avg_handoff_days,
  ROUND(APPROX_QUANTILES(avg_handoff_days, 4)[OFFSET(3)], 2) AS p75_avg_handoff_days,
  ROUND(MAX(avg_handoff_days), 2) AS max_avg_handoff_days,

  ROUND(MIN(late_delivery_rate), 2) AS min_late_delivery_rate,
  ROUND(APPROX_QUANTILES(late_delivery_rate, 4)[OFFSET(1)], 2) AS p25_late_delivery_rate,
  ROUND(APPROX_QUANTILES(late_delivery_rate, 4)[OFFSET(2)], 2) AS median_late_delivery_rate,
  ROUND(APPROX_QUANTILES(late_delivery_rate, 4)[OFFSET(3)], 2) AS p75_late_delivery_rate,
  ROUND(MAX(late_delivery_rate), 2) AS max_late_delivery_rate,

  SUM(invalid_negative_handoff_orders) AS negative_handoff_rows
FROM seller_performance;


-- ---------------------------------------------------------------------
-- 3.3 Top 20 Sellers by Delivery Reliability
-- ---------------------------------------------------------------------
SELECT
  seller_id,
  total_orders,
  valid_handoff_orders,
  invalid_negative_handoff_orders,
  avg_handoff_days,
  handoff_3plus_rate,
  avg_delivery_days,
  late_delivery_rate
FROM seller_performance
ORDER BY late_delivery_rate ASC, total_orders DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- 3.4 Bottom 20 Sellers by Delivery Reliability
-- ---------------------------------------------------------------------
SELECT
  seller_id,
  total_orders,
  valid_handoff_orders,
  invalid_negative_handoff_orders,
  avg_handoff_days,
  handoff_3plus_rate,
  avg_delivery_days,
  late_delivery_rate
FROM seller_performance
ORDER BY late_delivery_rate DESC, total_orders DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- 3.5 Association Between Hand-off Time and Late-Delivery Rate
-- Question: Across qualifying sellers, how strongly are the two metrics
--           associated?
--
-- CORR reports Pearson correlation. This is descriptive association only;
-- it does not establish causality or prove that hand-off time is a reliable
-- standalone leading indicator.
-- ---------------------------------------------------------------------
SELECT
  COUNT(*) AS qualifying_sellers,
  ROUND(CORR(avg_handoff_days, late_delivery_rate), 3) AS pearson_correlation
FROM seller_performance
WHERE avg_handoff_days IS NOT NULL;


-- ---------------------------------------------------------------------
-- 3.6 Revenue x Delivery-Risk Seller Segmentation (2x2)
-- ---------------------------------------------------------------------
-- STATUS: Not yet finalized in this repository.
--
-- This segmentation will group sellers into High/Low Revenue x High/Low
-- Delivery Risk quadrants using verified population-level thresholds.
-- The final query will be added only after it is re-run and validated in
-- BigQuery; it is intentionally not reconstructed from memory here.
-- ---------------------------------------------------------------------
