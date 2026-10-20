-- =====================================================================
-- 05_customer_geography.sql
-- E-Commerce Sales & Logistics Analytics — Part 5: Customer Geography
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 5.1 Customer Geography by State
-- Question: Which states drive the most order volume, and how does delivery
--           reliability vary across those markets?
--
-- Grain: one row per customer_state.
-- Order share is calculated dynamically from the full state-level total.
-- Late-delivery rate is limited to delivered orders.
-- ---------------------------------------------------------------------
WITH state_metrics AS (
  SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    COUNTIF(
      o.order_delivered_customer_date IS NOT NULL
      AND DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date)
    ) AS late_orders,
    COUNTIF(o.order_delivered_customer_date IS NOT NULL) AS delivered_orders
  FROM `e-commerce-public-dataanalysis.olist.orders` o
  JOIN `e-commerce-public-dataanalysis.olist.customers` c
    ON o.customer_id = c.customer_id
  GROUP BY c.customer_state
)
SELECT
  customer_state,
  total_orders,
  unique_customers,
  ROUND(
    SAFE_DIVIDE(total_orders, SUM(total_orders) OVER ()) * 100,
    2
  ) AS order_share_pct,
  ROUND(
    SAFE_DIVIDE(late_orders, delivered_orders) * 100,
    2
  ) AS late_delivery_rate
FROM state_metrics
ORDER BY total_orders DESC;

-- Validated result highlights:
--   SP: 41,746 orders | 41.98% order share | 4.49% late-delivery rate
--   RJ: 12,852 orders | 12.92% share | 12.10% late-delivery rate
--   MG: 11,635 orders | 11.70% share | 4.58% late-delivery rate
--   RS: 5,466 orders | 5.50% share | 6.08% late-delivery rate
--   PR: 5,045 orders | 5.07% share | 4.04% late-delivery rate
--
-- Business interpretation:
--   Demand is highly concentrated in SP, which alone accounts for roughly
--   42% of orders while maintaining a below-platform late-delivery rate.
--   RJ combines high commercial importance (12.92% of orders) with a much
--   higher late-delivery rate (12.10%), making it a higher-priority geography
--   for operational investigation than very small states with even higher
--   rates but limited order exposure.
--
--   Smaller states such as AL and MA show very high late-delivery rates
--   (21.41% and 17.43%), but their order shares are only 0.42% and 0.75%.
--   These should be treated as localized service-risk signals rather than
--   platform-wide drivers.
