-- =====================================================================
-- 08_customer_satisfaction.sql
-- E-Commerce Sales & Logistics Analytics — Part 8: Customer Satisfaction
-- Dataset: Olist Brazilian E-Commerce Public Dataset (BigQuery Standard SQL)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 8.1 Review Score vs. Delivery Time
-- Question: How does delivery time vary across review scores?
--
-- Grain: one row per order.
-- Some orders have multiple review rows, so the most recent review is selected
-- with ROW_NUMBER before joining to orders. This prevents duplicate review rows
-- from overweighting an order in averages and correlation calculations.
--
-- Delivery-time definition:
-- elapsed hours between purchase and customer delivery divided by 24.0.
-- This preserves fractional days for satisfaction analysis.
-- ---------------------------------------------------------------------
WITH ranked_reviews AS (
  SELECT
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY
        review_answer_timestamp DESC,
        review_creation_date DESC
    ) AS rn
  FROM `e-commerce-public-dataanalysis.olist.order_reviews`
  WHERE review_score IS NOT NULL
),
order_review_base AS (
  SELECT
    o.order_id,
    r.review_score,
    TIMESTAMP_DIFF(
      o.order_delivered_customer_date,
      o.order_purchase_timestamp,
      HOUR
    ) / 24.0 AS delivery_days
  FROM `e-commerce-public-dataanalysis.olist.orders` o
  JOIN ranked_reviews r
    ON o.order_id = r.order_id
   AND r.rn = 1
  WHERE o.order_delivered_customer_date IS NOT NULL
)
SELECT
  review_score,
  COUNT(*) AS orders,
  ROUND(AVG(delivery_days), 2) AS avg_delivery_days
FROM order_review_base
GROUP BY review_score
ORDER BY review_score;

-- BigQuery-validated result:
--   1 star:  9,355 orders | 21.30 avg delivery days
--   2 stars: 2,921 orders | 16.62 avg delivery days
--   3 stars: 7,917 orders | 14.24 avg delivery days
--   4 stars: 18,888 orders | 12.29 avg delivery days
--   5 stars: 56,749 orders | 10.66 avg delivery days
--
-- Interpretation:
-- Average delivery time falls steadily as review score rises. The 1-star vs.
-- 5-star gap is 10.64 days. This is an association, not a causal estimate.


-- ---------------------------------------------------------------------
-- 8.2 Order-Level Correlation Between Review Score and Delivery Time
-- Question: How strong is the linear association across delivered orders?
-- ---------------------------------------------------------------------
WITH ranked_reviews AS (
  SELECT
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY
        review_answer_timestamp DESC,
        review_creation_date DESC
    ) AS rn
  FROM `e-commerce-public-dataanalysis.olist.order_reviews`
  WHERE review_score IS NOT NULL
),
order_review_base AS (
  SELECT
    o.order_id,
    r.review_score,
    TIMESTAMP_DIFF(
      o.order_delivered_customer_date,
      o.order_purchase_timestamp,
      HOUR
    ) / 24.0 AS delivery_days
  FROM `e-commerce-public-dataanalysis.olist.orders` o
  JOIN ranked_reviews r
    ON o.order_id = r.order_id
   AND r.rn = 1
  WHERE o.order_delivered_customer_date IS NOT NULL
)
SELECT
  COUNT(*) AS orders,
  ROUND(CORR(review_score, delivery_days), 3) AS pearson_correlation
FROM order_review_base;

-- BigQuery-validated result:
--   95,830 delivered orders with a selected review
--   Pearson r = -0.334
--
-- Interpretation:
-- Review score and delivery time show a moderate negative linear association:
-- longer delivery times tend to be associated with lower review scores.
-- This does not establish that delivery time alone causes review outcomes.


-- ---------------------------------------------------------------------
-- 8.3 Category-Level Review Score and Delivery Time
-- Question: Which product categories combine weaker review scores with longer
--           delivery times?
--
-- Grain: one row per order-category.
-- order_items is reduced to DISTINCT order_id + category before joining review
-- and order data so multiple items from the same category do not overweight a
-- single order. An order containing multiple categories can intentionally
-- appear once in each category.
--
-- Data-quality note:
-- category_translation was loaded with generic column names string_field_0 and
-- string_field_1, with the original header row stored as data. The cleaning CTE
-- aliases those fields and removes the header row before the join.
--
-- Eligibility: categories with at least 100 delivered reviewed order-category
-- records.
-- ---------------------------------------------------------------------
WITH ranked_reviews AS (
  SELECT
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY
        review_answer_timestamp DESC,
        review_creation_date DESC
    ) AS rn
  FROM `e-commerce-public-dataanalysis.olist.order_reviews`
  WHERE review_score IS NOT NULL
),
category_translation_clean AS (
  SELECT
    string_field_0 AS product_category_name,
    string_field_1 AS product_category_name_english
  FROM `e-commerce-public-dataanalysis.olist.category_translation`
  WHERE string_field_0 != 'product_category_name'
),
order_category AS (
  SELECT DISTINCT
    oi.order_id,
    COALESCE(
      ct.product_category_name_english,
      p.product_category_name
    ) AS product_category
  FROM `e-commerce-public-dataanalysis.olist.order_items` oi
  JOIN `e-commerce-public-dataanalysis.olist.products` p
    ON oi.product_id = p.product_id
  LEFT JOIN category_translation_clean ct
    ON p.product_category_name = ct.product_category_name
  WHERE p.product_category_name IS NOT NULL
),
category_base AS (
  SELECT
    oc.order_id,
    oc.product_category,
    r.review_score,
    TIMESTAMP_DIFF(
      o.order_delivered_customer_date,
      o.order_purchase_timestamp,
      HOUR
    ) / 24.0 AS delivery_days
  FROM order_category oc
  JOIN `e-commerce-public-dataanalysis.olist.orders` o
    ON oc.order_id = o.order_id
  JOIN ranked_reviews r
    ON oc.order_id = r.order_id
   AND r.rn = 1
  WHERE o.order_delivered_customer_date IS NOT NULL
)
SELECT
  product_category,
  COUNT(*) AS orders,
  ROUND(AVG(review_score), 2) AS avg_review_score,
  ROUND(AVG(delivery_days), 2) AS avg_delivery_days
FROM category_base
GROUP BY product_category
HAVING COUNT(*) >= 100
ORDER BY avg_review_score ASC, avg_delivery_days DESC;

-- BigQuery-validated selected results among categories with 100+ records:
--   office_furniture:        1,244 orders | 3.64 avg review | 20.56 days
--   fashion_male_clothing:     105 orders | 3.82 avg review | 12.66 days
--   audio:                     345 orders | 3.84 avg review | 13.41 days
--   home_confort:              390 orders | 3.88 avg review | 13.71 days
--   bed_bath_table:          9,177 orders | 4.00 avg review | 12.92 days
--   furniture_decor:         6,260 orders | 4.06 avg review | 13.00 days
--
-- Business interpretation:
-- office_furniture is the clearest category-level operational signal because it
-- combines the lowest average review score in the qualifying set with an
-- unusually long average delivery time. Audio also has a relatively weak
-- review score, but with much lower order exposure and a delivery time closer
-- to the platform range. Category-level results remain descriptive and can be
-- influenced by product mix, seller mix, geography, product quality, listing
-- accuracy, and other factors not isolated here.
