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
  COUNT(*) AS total_orders,
  COUNTIF(handoff_days >= 0) AS valid_handoff_orders,
  COUNTIF(handoff_days < 0) AS invalid_negative_handoff_orders,
  ROUND(AVG(IF(handoff_days >= 0, handoff_days, NULL)), 2) AS avg_handoff_days,
  ROUND(
    SAFE_DIVIDE(COUNTIF(handoff_days >= 3), COUNTIF(handoff_days >= 0)) * 100,
    2
  ) AS handoff_3plus_rate,
  ROUND(AVG(delivery_days), 2) AS avg_delivery_days,
  ROUND(
    SAFE_DIVIDE(COUNTIF(late_days > 0), COUNT(*)) * 100,
    2
  ) AS late_delivery_rate
FROM seller_order
GROUP BY seller_id
HAVING COUNT(*) >= 50;


-- ---------------------------------------------------------------------
-- 3.2 Full Distribution Across All Qualifying Sellers
-- Question: What does the seller population look like before selecting
--           top/bottom examples?
--
-- Validated result summary:
--   Qualifying sellers: 425
--   Avg hand-off days: min 0.63 | P25 1.50 | median 2.14 | P75 3.28 | max 15.14
--   Late-delivery rate: min 0.00% | P25 3.52% | median 5.69% | P75 8.72% | max 30.14%
--   Negative hand-off seller-order records among qualifying sellers: 495
--
-- Note: the percentile values below use APPROX_QUANTILES, so reported
-- quartiles/medians are approximate rather than exact order-statistic values.
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
--
-- Validated range among the 20 lowest late-delivery-rate sellers:
--   Late-delivery rate: 0.00% to 0.93%
--   Average hand-off time: 0.67 to 4.73 days
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
--
-- Validated range among the 20 highest late-delivery-rate sellers:
--   Late-delivery rate: 15.32% to 30.14%
--   Average hand-off time: 1.40 to 15.14 days
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
-- Validated result: Pearson r = 0.408 across 425 qualifying sellers.
-- This is a moderate positive association, not a causal relationship and not
-- evidence that hand-off time is a sufficient standalone predictor.
-- ---------------------------------------------------------------------
SELECT
  COUNT(*) AS qualifying_sellers,
  ROUND(CORR(avg_handoff_days, late_delivery_rate), 3) AS pearson_correlation
FROM seller_performance
WHERE avg_handoff_days IS NOT NULL;


-- ---------------------------------------------------------------------
-- 3.6 Revenue x Delivery-Risk Seller Segmentation (2x2)
-- Question: Which qualifying sellers combine high commercial value with
--           elevated delivery risk?
--
-- Revenue definition: sum of `order_items.price` at seller-order grain.
-- This avoids the order_items x payments fan-out risk because payments are
-- not joined here.
--
-- Population: same seller-order base and >=50 seller-order threshold used
-- above. Thresholds are APPROX_QUANTILES-based approximate medians for total
-- revenue and late-delivery rate. Because these are approximate quantiles,
-- sellers close to the boundary may differ from an exact-median split.
--
-- Validated segment summary using the approximate-median thresholds:
--   High Revenue / High Risk: 116 sellers | 4,571,185.21 revenue |
--     9.38% avg late-delivery rate | 268.6 avg orders/seller
--   High Revenue / Low Risk: 96 sellers | 3,058,795.86 revenue |
--     3.49% avg late-delivery rate | 240.8 avg orders/seller
--   Low Revenue / High Risk: 99 sellers | 610,916.18 revenue |
--     10.19% avg late-delivery rate | 89.2 avg orders/seller
--   Low Revenue / Low Risk: 114 sellers | 755,739.07 revenue |
--     2.97% avg late-delivery rate | 95.3 avg orders/seller
--
-- Business interpretation: High Revenue / High Risk is the primary
-- intervention segment because it combines the largest revenue exposure with
-- materially elevated late-delivery risk.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE seller_order_revenue AS
SELECT
  seller_id,
  order_id,
  SUM(price) AS order_revenue
FROM `e-commerce-public-dataanalysis.olist.order_items`
GROUP BY seller_id, order_id;

CREATE TEMP TABLE seller_value_risk AS
SELECT
  so.seller_id,
  COUNT(*) AS total_orders,
  ROUND(SUM(sor.order_revenue), 2) AS total_revenue,
  ROUND(
    SAFE_DIVIDE(COUNTIF(so.late_days > 0), COUNT(*)) * 100,
    2
  ) AS late_delivery_rate
FROM seller_order so
JOIN seller_order_revenue sor
  ON so.seller_id = sor.seller_id
 AND so.order_id = sor.order_id
GROUP BY so.seller_id
HAVING COUNT(*) >= 50;

CREATE TEMP TABLE seller_segments AS
WITH thresholds AS (
  SELECT
    APPROX_QUANTILES(total_revenue, 2)[OFFSET(1)] AS median_total_revenue,
    APPROX_QUANTILES(late_delivery_rate, 2)[OFFSET(1)] AS median_late_delivery_rate
  FROM seller_value_risk
)
SELECT
  svr.seller_id,
  svr.total_orders,
  svr.total_revenue,
  svr.late_delivery_rate,
  ROUND(t.median_total_revenue, 2) AS median_total_revenue,
  ROUND(t.median_late_delivery_rate, 2) AS median_late_delivery_rate,
  CASE
    WHEN svr.total_revenue >= t.median_total_revenue
      AND svr.late_delivery_rate >= t.median_late_delivery_rate
      THEN 'High Revenue / High Risk'
    WHEN svr.total_revenue >= t.median_total_revenue
      AND svr.late_delivery_rate < t.median_late_delivery_rate
      THEN 'High Revenue / Low Risk'
    WHEN svr.total_revenue < t.median_total_revenue
      AND svr.late_delivery_rate >= t.median_late_delivery_rate
      THEN 'Low Revenue / High Risk'
    ELSE 'Low Revenue / Low Risk'
  END AS seller_segment
FROM seller_value_risk svr
CROSS JOIN thresholds t;

SELECT
  seller_id,
  total_orders,
  total_revenue,
  late_delivery_rate,
  median_total_revenue,
  median_late_delivery_rate,
  seller_segment
FROM seller_segments
ORDER BY
  CASE seller_segment
    WHEN 'High Revenue / High Risk' THEN 1
    WHEN 'High Revenue / Low Risk' THEN 2
    WHEN 'Low Revenue / High Risk' THEN 3
    ELSE 4
  END,
  total_revenue DESC;

SELECT
  seller_segment,
  COUNT(*) AS sellers,
  ROUND(SUM(total_revenue), 2) AS segment_revenue,
  ROUND(AVG(late_delivery_rate), 2) AS avg_late_delivery_rate,
  ROUND(AVG(total_orders), 1) AS avg_orders_per_seller
FROM seller_segments
GROUP BY seller_segment
ORDER BY
  CASE seller_segment
    WHEN 'High Revenue / High Risk' THEN 1
    WHEN 'High Revenue / Low Risk' THEN 2
    WHEN 'Low Revenue / High Risk' THEN 3
    ELSE 4
  END;
