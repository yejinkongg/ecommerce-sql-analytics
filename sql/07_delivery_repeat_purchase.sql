-- =====================================================================
-- 07_delivery_repeat_purchase.sql
-- E-Commerce Sales & Logistics Analytics — Part 7: Delivery & Repeat Purchase
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 7.1 First Delivery Experience vs. Post-Delivery Repeat Purchase
-- Question: Is a customer's first delivery experience associated with whether
--           they place another order after that first delivery is completed?
--
-- Customer grain:
-- Orders are sequenced within each customer_unique_id. The first observed
-- order is classified as late or on-time/early only when a delivery timestamp
-- exists. Repeat purchase is counted only when ANY later order is placed AFTER
-- the first order's delivery timestamp. A customer's second order may occur
-- before first delivery and a third/later order can still qualify as a
-- post-delivery repeat purchase.
--
-- Coverage:
-- 96,096 unique customers exist in the dataset. 93,254 have a delivered first
-- observed order and are eligible for this comparison; 2,842 customers whose
-- first observed order lacks a delivery timestamp are excluded.
--
-- Important interpretation rule:
-- This is an observational association, not a causal estimate. Customers who
-- receive late deliveries may differ in geography, product mix, seller mix,
-- tenure, or other ways that also affect repeat purchasing.
-- ---------------------------------------------------------------------
WITH customer_orders AS (
  SELECT
    c.customer_unique_id,
    o.order_id,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    ROW_NUMBER() OVER (
      PARTITION BY c.customer_unique_id
      ORDER BY o.order_purchase_timestamp, o.order_id
    ) AS order_rank
  FROM `e-commerce-public-dataanalysis.olist.orders` o
  JOIN `e-commerce-public-dataanalysis.olist.customers` c
    ON o.customer_id = c.customer_id
),
first_order AS (
  SELECT
    customer_unique_id,
    order_id AS first_order_id,
    order_delivered_customer_date AS first_delivery_timestamp,
    CASE
      WHEN order_delivered_customer_date IS NOT NULL
        AND DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)
        THEN 'First order late'
      WHEN order_delivered_customer_date IS NOT NULL
        THEN 'First order on time / early'
      ELSE NULL
    END AS first_delivery_status
  FROM customer_orders
  WHERE order_rank = 1
),
customer_repeat AS (
  SELECT
    f.customer_unique_id,
    f.first_delivery_status,
    MAX(
      CASE
        WHEN co.order_purchase_timestamp > f.first_delivery_timestamp THEN 1
        ELSE 0
      END
    ) AS repeated_after_first_delivery
  FROM first_order f
  LEFT JOIN customer_orders co
    ON f.customer_unique_id = co.customer_unique_id
   AND f.first_order_id != co.order_id
  WHERE f.first_delivery_status IS NOT NULL
  GROUP BY
    f.customer_unique_id,
    f.first_delivery_status
)
SELECT
  first_delivery_status,
  COUNT(*) AS customers,
  COUNTIF(repeated_after_first_delivery = 1) AS repeat_customers_after_delivery,
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(repeated_after_first_delivery = 1),
      COUNT(*)
    ) * 100,
    2
  ) AS repeat_customer_rate_after_delivery
FROM customer_repeat
GROUP BY first_delivery_status
ORDER BY first_delivery_status;

-- CSV-reproduced result summary for the SQL logic above:
--   First order late:
--     6,345 customers | 79 repeat after delivery | 1.25% repeat rate
--   First order on time / early:
--     86,909 customers | 1,759 repeat after delivery | 2.02% repeat rate
--
-- Observed difference:
--   Post-delivery repeat rate is 0.77 percentage points lower among customers
--   whose first observed delivery was late (1.25% vs. 2.02%).
--
-- Why this differs from the earlier 2.54% vs. 3.13% comparison:
--   The earlier version counted any customer with 2+ observed orders as a
--   repeat customer, including orders placed before the first delivery was
--   completed. The current logic scans all later orders and counts a customer
--   if at least one later purchase occurs after first delivery. Therefore a
--   customer whose second order was pre-delivery can still count if a third or
--   later order was placed after first delivery.
--
-- Business interpretation:
--   The direction remains consistent with worse first-delivery experiences
--   being associated with weaker retention, but the result remains
--   observational and should not be interpreted as evidence that late delivery
--   causes lower repeat purchase.
