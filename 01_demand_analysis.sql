-- =====================================================================
-- 01_demand_analysis.sql
-- E-Commerce Sales & Logistics Analytics — Part 1: Demand Analysis
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1.1 Order Status Distribution
-- Question: What share of orders falls into each status?
-- ---------------------------------------------------------------------
SELECT
  order_status,
  COUNT(*) AS order_count,
  ROUND(COUNT(*) / 99441 * 100, 2) AS percentage
FROM `e-commerce-public-dataanalysis.olist.orders`
GROUP BY order_status
ORDER BY order_count DESC;

-- Result: 'delivered' accounts for 96,478 orders (97.02%) of all orders.


-- ---------------------------------------------------------------------
-- 1.2 Monthly Cancellation Rate
-- Question: How does the cancellation rate change month over month,
--           and does it move together with order volume?
-- ---------------------------------------------------------------------
SELECT
  DATE_TRUNC(order_purchase_timestamp, MONTH) AS order_month,
  COUNT(*) AS total_orders,
  COUNTIF(order_status = 'canceled') AS cancelled_orders,
  SAFE_DIVIDE(
    COUNTIF(order_status = 'canceled'),
    COUNT(*)
  ) * 100 AS cancel_rate
FROM `e-commerce-public-dataanalysis.olist.orders`
GROUP BY order_month
ORDER BY order_month;

-- Result: Monthly cancellation rate stays mostly between 0.2% and 1.3%.
-- Notably, Nov 2017 (the month of steepest demand growth, +62.9% MoM)
-- saw cancellation rate drop from 0.56% to 0.49% rather than rise.


-- ---------------------------------------------------------------------
-- 1.3 Monthly Order Volume
-- Question: How has order volume trended over time?
-- ---------------------------------------------------------------------
SELECT
  FORMAT_DATE('%Y/%m', DATE(order_purchase_timestamp)) AS order_month,
  COUNT(*) AS order_count
FROM `e-commerce-public-dataanalysis.olist.orders`
GROUP BY order_month
ORDER BY order_month ASC;

-- Note: Sep 2018 (16) and Oct 2018 (4) are almost certainly incomplete
-- data, not a genuine demand collapse. Excluded from trend interpretation.


-- ---------------------------------------------------------------------
-- 1.4 Month-over-Month Growth Rate
-- Question: What is the MoM growth rate, and where are the inflection points?
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT
    DATE_TRUNC(order_purchase_timestamp, MONTH) AS order_month,
    COUNT(*) AS order_count
  FROM `e-commerce-public-dataanalysis.olist.orders`
  GROUP BY order_month
),
base AS (
  SELECT
    order_month,
    order_count,
    LAG(order_count) OVER (ORDER BY order_month) AS prev_month
  FROM monthly
)
SELECT
  order_month,
  order_count,
  prev_month,
  SAFE_DIVIDE(order_count - prev_month, prev_month) * 100 AS mom_growth_rate
FROM base
ORDER BY order_month;

-- Result: Nov 2017 shows the largest single-month spike: +62.90% MoM
-- (4,631 -> 7,544 orders), followed by a -24.80% pullback in Dec 2017.


-- ---------------------------------------------------------------------
-- 1.5 Order Volume vs. Overall Average (Window Function)
-- Question: How does each month's volume compare to the full-period average?
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT
    DATE_TRUNC(order_purchase_timestamp, MONTH) AS order_month,
    COUNT(*) AS order_count
  FROM `e-commerce-public-dataanalysis.olist.orders`
  GROUP BY order_month
)
SELECT
  order_month,
  order_count,
  AVG(order_count) OVER () AS avg_order_count,
  SAFE_DIVIDE(
    order_count - AVG(order_count) OVER(),
    AVG(order_count) OVER()
  ) * 100 AS avg_order_growth
FROM monthly
ORDER BY order_month;


-- ---------------------------------------------------------------------
-- 1.6 Peak Order Hour
-- Question: What time of day do most orders occur?
-- ---------------------------------------------------------------------
SELECT
  EXTRACT(HOUR FROM order_purchase_timestamp) AS order_hour,
  COUNT(*) AS order_count
FROM `e-commerce-public-dataanalysis.olist.orders`
GROUP BY order_hour
ORDER BY order_hour ASC;


-- ---------------------------------------------------------------------
-- 1.7 Average Orders per Customer
-- Question: On average, how many times does a unique customer order?
-- ---------------------------------------------------------------------
SELECT
  COUNT(o.order_id) AS total_orders,
  COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
  SAFE_DIVIDE(
    COUNT(o.order_id),
    COUNT(DISTINCT c.customer_unique_id)
  ) AS avg_orders_per_customer
FROM `e-commerce-public-dataanalysis.olist.orders` o
JOIN `e-commerce-public-dataanalysis.olist.customers` c
  ON o.customer_id = c.customer_id;

-- Result: 99,441 total orders / 96,096 unique customers
--         = 1.0348 average orders per customer


-- ---------------------------------------------------------------------
-- 1.8 Repeat Customer Rate
-- Question: What share of customers ordered 2+ times?
-- ---------------------------------------------------------------------
WITH customer_orders AS (
  SELECT
    c.customer_unique_id,
    COUNT(o.order_id) AS order_count
  FROM `e-commerce-public-dataanalysis.olist.orders` o
  JOIN `e-commerce-public-dataanalysis.olist.customers` c
    ON o.customer_id = c.customer_id
  GROUP BY c.customer_unique_id
)
SELECT
  COUNT(*) AS total_customers,
  COUNTIF(order_count >= 2) AS repeat_customers,
  SAFE_DIVIDE(
    COUNTIF(order_count >= 2),
    COUNT(*)
  ) * 100 AS repeat_customer_rate
FROM customer_orders;

-- Result: 96,096 total customers / 2,997 repeat customers
--         = 3.12% repeat customer rate
