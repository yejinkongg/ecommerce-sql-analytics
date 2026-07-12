-- =====================================================================
-- 03_root_cause_analysis.sql
-- E-Commerce Sales & Logistics Analytics — Part 3: Root Cause Analysis
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 3.1 Seller Performance Master Query
-- Question: Which sellers drive delivery delays, and is there a link
--           between hand-off speed and delivery reliability?
--
-- Grain: one row per seller (min. 50 orders, to avoid small-sample noise)
-- ---------------------------------------------------------------------
SELECT
  oi.seller_id,

  -- Order volume
  COUNT(DISTINCT o.order_id) AS total_orders,

  -- Average hand-off time (order approval -> carrier pickup)
  ROUND(
    AVG(
      DATE_DIFF(
        DATE(o.order_delivered_carrier_date),
        DATE(o.order_approved_at),
        DAY
      )
    ),
    2
  ) AS avg_handoff_days,

  -- Share of orders with 3+ day hand-off time
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(
        DATE_DIFF(
          DATE(o.order_delivered_carrier_date),
          DATE(o.order_approved_at),
          DAY
        ) >= 3
      ),
      COUNT(*)
    ) * 100,
    2
  ) AS handoff_3plus_rate,

  -- Average delivery time (purchase -> customer receipt)
  ROUND(
    AVG(
      DATE_DIFF(
        DATE(o.order_delivered_customer_date),
        DATE(o.order_purchase_timestamp),
        DAY
      )
    ),
    2
  ) AS avg_delivery_days,

  -- Share of orders delivered after the estimated delivery date
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(
        DATE_DIFF(
          DATE(o.order_delivered_customer_date),
          DATE(o.order_estimated_delivery_date),
          DAY
        ) > 0
      ),
      COUNT(*)
    ) * 100,
    2
  ) AS late_delivery_rate

FROM `e-commerce-public-dataanalysis.olist.orders` o
JOIN `e-commerce-public-dataanalysis.olist.order_items` oi
  ON o.order_id = oi.order_id
WHERE
  o.order_approved_at IS NOT NULL
  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY oi.seller_id
HAVING COUNT(DISTINCT o.order_id) >= 50
ORDER BY late_delivery_rate ASC, total_orders DESC
LIMIT 20;

-- Run the same query with `ORDER BY late_delivery_rate DESC` to get the
-- "Problem Seller" side of the comparison.
--
-- Result summary:
--   Best Sellers    -> avg_handoff_days ~0.6-2,  late_delivery_rate 0-1%
--   Problem Sellers  -> avg_handoff_days ~5-15,   late_delivery_rate 15-32.1%
-- Hand-off time functions as a leading indicator for delivery risk.
-- Exceptions exist (slow hand-off + 0% late delivery), so delivery
-- performance is treated as multi-factor, not seller-attributable alone.


-- ---------------------------------------------------------------------
-- 3.2 Revenue x Delivery-Risk Seller Segmentation (2x2)
-- ---------------------------------------------------------------------
-- STATUS: Not yet finalized in this repository.
--
-- This segmentation (sellers grouped into High/Low Revenue x High/Low
-- Delivery Risk quadrants, using APPROX_QUANTILES-based percentile
-- thresholds rather than arbitrary cutoffs) was iteratively debugged
-- across several issues: a stray LIMIT clause that was silently
-- truncating the segmentation population, a revenue-median calculation
-- that was computed over a mismatched population, and a wrong column
-- reference (r.orders vs. d.delivered_orders).
--
-- The final corrected query is not yet captured verbatim in this
-- repository and will be added once re-verified in BigQuery, rather
-- than reconstructed from memory.
-- ---------------------------------------------------------------------
