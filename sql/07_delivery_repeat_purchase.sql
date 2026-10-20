-- =====================================================================
-- 07_delivery_repeat_purchase.sql
-- E-Commerce Sales & Logistics Analytics — Part 7: Delivery & Repeat Purchase
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 7.1 First Delivery Experience vs. Repeat Purchase
-- Question: Is a customer's first delivery experience associated with whether
--           they place another order later?
--
-- Customer grain:
-- Orders are sequenced within each customer_unique_id. The first observed
-- order is classified as late or on-time/early if a delivery timestamp exists.
-- Repeat purchase is defined as customer_order_count >= 2.
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
    ) AS order_rank,
    COUNT(*) OVER (
      PARTITION BY c.customer_unique_id
    ) AS customer_order_count
  FROM `e-commerce-public-dataanalysis.olist.orders` o
  JOIN `e-commerce-public-dataanalysis.olist.customers` c
    ON o.customer_id = c.customer_id
),
first_order AS (
  SELECT
    customer_unique_id,
    customer_order_count,
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
)
SELECT
  first_delivery_status,
  COUNT(*) AS customers,
  COUNTIF(customer_order_count >= 2) AS repeat_customers,
  ROUND(
    SAFE_DIVIDE(COUNTIF(customer_order_count >= 2), COUNT(*)) * 100,
    2
  ) AS repeat_customer_rate
FROM first_order
WHERE first_delivery_status IS NOT NULL
GROUP BY first_delivery_status
ORDER BY first_delivery_status;

-- Validated result summary:
--   First order late:
--     6,345 customers | 161 repeat customers | 2.54% repeat rate
--   First order on time / early:
--     86,909 customers | 2,716 repeat customers | 3.13% repeat rate
--
-- Observed difference:
--   Repeat rate is 0.59 percentage points lower among customers whose first
--   observed delivery was late (2.54% vs. 3.13%).
--
-- Business interpretation:
--   The pattern is directionally consistent with worse first-delivery
--   experiences being associated with weaker retention, but the difference is
--   modest and should not be interpreted as evidence that late delivery causes
--   lower repeat purchase. It is best used as a retention-risk signal that
--   motivates deeper controlled analysis.
