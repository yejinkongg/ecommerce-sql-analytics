-- =====================================================================
-- 04_tableau_exports.sql
-- E-Commerce Sales & Logistics Analytics — Tableau-ready datasets
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
--
-- Each section is designed to be run independently in BigQuery and exported
-- as CSV, or used as the source query for a Tableau connection.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 4.1 tableau_monthly_orders
-- Purpose: monthly demand trend + cancellation rate
-- Recommended Tableau use: line chart for orders, secondary line for cancel rate
--
-- Dashboard analysis window: Jan 2017 - Aug 2018.
-- Sparse partial months outside this range are excluded before the LAG()
-- calculation so incomplete periods do not create misleading MoM growth rates.
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT
    DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS order_month,
    COUNT(*) AS total_orders,
    COUNTIF(order_status = 'canceled') AS cancelled_orders
  FROM `e-commerce-public-dataanalysis.olist.orders`
  WHERE DATE(order_purchase_timestamp) >= DATE '2017-01-01'
    AND DATE(order_purchase_timestamp) < DATE '2018-09-01'
  GROUP BY order_month
),
with_growth AS (
  SELECT
    order_month,
    total_orders,
    cancelled_orders,
    LAG(total_orders) OVER (ORDER BY order_month) AS prior_month_orders
  FROM monthly
)
SELECT
  order_month,
  total_orders,
  cancelled_orders,
  ROUND(SAFE_DIVIDE(cancelled_orders, total_orders) * 100, 2) AS cancellation_rate,
  ROUND(
    SAFE_DIVIDE(total_orders - prior_month_orders, prior_month_orders) * 100,
    2
  ) AS mom_order_growth_rate
FROM with_growth
ORDER BY order_month;


-- ---------------------------------------------------------------------
-- 4.2 tableau_delivery_distribution
-- Purpose: delivery-time distribution and long-tail visualization
-- Grain: one row per delivered order
-- Recommended Tableau use: histogram / distribution chart
-- ---------------------------------------------------------------------
SELECT
  order_id,
  DATE(order_purchase_timestamp) AS purchase_date,
  DATE(order_delivered_customer_date) AS delivered_date,
  DATE(order_estimated_delivery_date) AS estimated_delivery_date,
  DATE_DIFF(
    DATE(order_delivered_customer_date),
    DATE(order_purchase_timestamp),
    DAY
  ) AS delivery_days,
  DATE_DIFF(
    DATE(order_delivered_customer_date),
    DATE(order_estimated_delivery_date),
    DAY
  ) AS days_vs_estimate,
  CASE
    WHEN DATE(order_delivered_customer_date) <= DATE(order_estimated_delivery_date)
      THEN 'On time / early'
    ELSE 'Late'
  END AS delivery_status,
  CASE
    WHEN DATE_DIFF(DATE(order_delivered_customer_date), DATE(order_purchase_timestamp), DAY) <= 7 THEN '0-7 days'
    WHEN DATE_DIFF(DATE(order_delivered_customer_date), DATE(order_purchase_timestamp), DAY) BETWEEN 8 AND 14 THEN '8-14 days'
    WHEN DATE_DIFF(DATE(order_delivered_customer_date), DATE(order_purchase_timestamp), DAY) BETWEEN 15 AND 30 THEN '15-30 days'
    WHEN DATE_DIFF(DATE(order_delivered_customer_date), DATE(order_purchase_timestamp), DAY) BETWEEN 31 AND 70 THEN '31-70 days'
    ELSE '70+ days'
  END AS delivery_bucket
FROM `e-commerce-public-dataanalysis.olist.orders`
WHERE order_delivered_customer_date IS NOT NULL;


-- ---------------------------------------------------------------------
-- 4.3 tableau_seller_performance
-- Purpose: seller-risk scatter plot and top/bottom performer comparison
-- Grain: one row per qualifying seller (>= 50 seller-orders)
--
-- Negative hand-off values are excluded from hand-off metrics but retained
-- in total-order and delivery metrics, matching Part 3.
-- ---------------------------------------------------------------------
WITH seller_order AS (
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
    AND o.order_estimated_delivery_date IS NOT NULL
),
seller_performance AS (
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
    ROUND(SAFE_DIVIDE(COUNTIF(late_days > 0), COUNT(*)) * 100, 2) AS late_delivery_rate
  FROM seller_order
  GROUP BY seller_id
  HAVING COUNT(*) >= 50
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      ORDER BY late_delivery_rate ASC, total_orders DESC, seller_id
    ) AS reliability_rank,
    ROW_NUMBER() OVER (
      ORDER BY late_delivery_rate DESC, total_orders DESC, seller_id
    ) AS risk_rank
  FROM seller_performance
)
SELECT
  seller_id,
  total_orders,
  valid_handoff_orders,
  invalid_negative_handoff_orders,
  avg_handoff_days,
  handoff_3plus_rate,
  avg_delivery_days,
  late_delivery_rate,
  reliability_rank,
  risk_rank,
  CASE
    WHEN reliability_rank <= 20 THEN 'Top 20 reliability'
    WHEN risk_rank <= 20 THEN 'Bottom 20 reliability'
    ELSE 'Other qualifying sellers'
  END AS seller_group
FROM ranked
ORDER BY late_delivery_rate, total_orders DESC;


-- ---------------------------------------------------------------------
-- 4.4 tableau_kpi_summary
-- Purpose: KPI cards for the executive dashboard
-- Returns one row.
--
-- Average delivery time intentionally matches Part 2's validated definition:
-- DATE_DIFF on the original timestamps (12.09 days in the validated output).
-- Seller hand-off is not included as a dashboard KPI here because Part 2 and
-- Part 3 currently use different hand-off definitions. Use 4.3 for seller
-- hand-off analysis until those definitions are fully unified.
-- ---------------------------------------------------------------------
WITH customer_orders AS (
  SELECT
    c.customer_unique_id,
    COUNT(o.order_id) AS order_count
  FROM `e-commerce-public-dataanalysis.olist.orders` o
  JOIN `e-commerce-public-dataanalysis.olist.customers` c
    ON o.customer_id = c.customer_id
  GROUP BY c.customer_unique_id
),
order_kpis AS (
  SELECT
    COUNT(*) AS total_orders,
    COUNTIF(order_delivered_customer_date IS NOT NULL) AS delivered_orders,
    COUNTIF(
      order_delivered_customer_date IS NOT NULL
      AND DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)
    ) AS late_orders,
    AVG(
      IF(
        order_delivered_customer_date IS NOT NULL,
        DATE_DIFF(order_delivered_customer_date, order_purchase_timestamp, DAY),
        NULL
      )
    ) AS avg_delivery_days
  FROM `e-commerce-public-dataanalysis.olist.orders`
),
customer_kpis AS (
  SELECT
    COUNT(*) AS unique_customers,
    COUNTIF(order_count >= 2) AS repeat_customers
  FROM customer_orders
)
SELECT
  o.total_orders,
  o.delivered_orders,
  ROUND(SAFE_DIVIDE(o.delivered_orders - o.late_orders, o.delivered_orders) * 100, 2) AS on_time_rate,
  ROUND(SAFE_DIVIDE(o.late_orders, o.delivered_orders) * 100, 2) AS late_delivery_rate,
  ROUND(o.avg_delivery_days, 2) AS avg_delivery_days,
  c.unique_customers,
  c.repeat_customers,
  ROUND(SAFE_DIVIDE(c.repeat_customers, c.unique_customers) * 100, 2) AS repeat_customer_rate
FROM order_kpis o
CROSS JOIN customer_kpis c;
