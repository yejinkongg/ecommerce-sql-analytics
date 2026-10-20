# Schema Notes

## Tables used in the current SQL

| Table | Purpose in this analysis | Used in |
|---|---|---|
| `orders` | Order lifecycle: status, purchase / approval / carrier hand-off / delivery timestamps | `01`, `02`, `03`, `04`, `05`, `07`, `08` |
| `order_items` | Line-item detail; links orders to sellers and products; supports seller revenue and category analysis | `03`, `08` |
| `customers` | `customer_id` to `customer_unique_id` mapping; repeat purchase and state-level geography | `01`, `04`, `05`, `07` |
| `payments` | Order-level payment value and payment type after aggregation to order grain | `06` |
| `products` | Product-to-category mapping used for category-level satisfaction analysis | `08` |
| `order_reviews` | Review scores; deduplicated to one selected review per order before satisfaction analysis | `08` |
| `category_translation` | Portuguese-to-English category-name mapping after import cleanup | `08` |

## Additional available tables not required by the current workflow

- `geolocation`
- `sellers`

These tables are available in the current BigQuery dataset but are not required by the implemented SQL workflow. Customer geography in `05` uses `customers.customer_state`, so a geolocation join is unnecessary for the current state-level analysis.

## Schema re-verification

Early query design was revised after rechecking the actual BigQuery dataset and the grain of each table. The final workflow is based on the tables and fields verified for each analysis rather than assuming joins from documentation alone.

**Takeaway:** verify the schema and grain of the specific dataset instance before designing queries.

## Metric definitions as currently implemented

| Metric | Query | Computation |
|---|---|---|
| Average delivery time, delivery buckets, most common delivery time | `02` 2.1-2.3 | Full-day difference between purchase and customer delivery |
| On-time / late rate and days early/late | `02` 2.4-2.5 | Calendar-date comparison against estimated delivery date |
| Average seller hand-off time | `02` 2.6 | Calendar-day difference between approval and carrier hand-off; negative durations excluded; validated overall average = 2.74 days |
| Hand-off distribution | `02` 2.7 | Calendar-day difference, with anomalies retained for visibility |
| Seller hand-off, delivery time and late rate | `03` | Calendar-day differences at one row per seller-order; negative hand-off excluded from hand-off averages/rates |
| Seller 2x2 thresholds | `03` 3.6 | `APPROX_QUANTILES(..., 2)` approximate medians for seller revenue and late-delivery rate |
| Average payment value per order | `06` | `payments.payment_value` summed to one row per order, then averaged by primary payment type; this is payment value, not merchandise-only revenue |
| First-delivery repeat comparison | `07` | First observed delivery classified late vs. on-time/early; a customer repeats if any later order is placed after the first delivery timestamp |
| Review score vs. delivery time | `08` 8.1-8.2 | Most recent review selected per order; delivery time = elapsed hours from purchase to delivery / 24.0 |
| Category satisfaction summary | `08` 8.3 | Distinct order-category grain; average review score and elapsed delivery days for categories with at least 100 records |

The seller hand-off definition in `02` is aligned with the rule used in `03`: calendar-day differences with negative hand-off durations excluded from the average.

The customer-satisfaction delivery-time definition is intentionally different from the 12.09-day core logistics KPI. `08` preserves fractional days by dividing elapsed hours by 24.0, while `02` reports full-day differences.

## Seller-level analysis grain and data-quality handling

Part 3 creates a distinct `seller_id` + `order_id` base table before calculating seller metrics. This makes late-delivery rates and hand-off rates seller-order based rather than item-row based.

Negative hand-off durations (`order_delivered_carrier_date` earlier than `order_approved_at`) are treated as data-quality defects. They are:

- retained in seller order counts and delivery metrics,
- excluded from hand-off averages and hand-off-rate denominators,
- counted separately for transparency.

Among the 425 sellers with at least 50 seller-orders, 495 seller-order records have negative hand-off durations.

## Approximate quantiles in seller segmentation

Part 3 uses `APPROX_QUANTILES` for seller distribution summaries and the Revenue x Delivery Risk 2x2 thresholds. The validated 2x2 result is therefore tied to **approximate median thresholds**, not the exact 213th ordered seller value among 425 sellers.

This matters only for sellers very close to the boundary: an exact-median split can shift a small number of sellers between quadrants. The reported 116 / 96 / 99 / 114 segment counts and related revenue/risk summaries are the validated outputs from the SQL as written.

## Fan-out prevention

`order_items` and `payments` each have a one-to-many relationship with `orders`. A direct `JOIN` between them on `order_id` can multiply rows for orders with multiple items and multiple payment records, inflating `COUNT` / `SUM` aggregates.

The completed workflow avoids this risk in several ways:

- seller revenue in `03` is aggregated from `order_items.price` without joining `payments`;
- payment analysis in `06` aggregates `payments` to one row per order before calculating payment mix and average payment value per order;
- category satisfaction in `08` reduces `order_items` to distinct `order_id` + category pairs before joining reviews and orders.

No current SQL directly joins raw `order_items` rows to raw `payments` rows.

## Payment coverage and interpretation

`payments.payment_value` is the amount paid, not merchandise-only item revenue. The order-level sum can include freight and financing/installment-related charges captured in the payment value, so the analysis labels the metric **average payment value per order** rather than merchandise AOV.

The payment table covers 99,440 of the 99,441 orders. Three payment orders have `payment_type = 'not_defined'`; the README summary table focuses on the four defined payment methods and omits those three rows.

## Repeat-purchase temporal rule

The initial repeat-purchase comparison counted any customer with a second observed order, including customers who placed that order before the first delivery was completed. Because those purchases cannot have been influenced by the first delivery experience, `07` now counts a customer as a post-delivery repeat customer only when **at least one later order** has a purchase timestamp after the first delivery timestamp.

This distinction matters for customers with more than two orders: a second order may occur before first delivery, while a third or later order can still occur after first delivery and therefore qualify.

Of 96,096 unique customers, 93,254 have a delivered first observed order and enter the analysis. The remaining 2,842 customers are excluded because their first observed order has no delivery timestamp.

BigQuery-validated post-delivery repeat rates:

- **First order late:** 79 / 6,345 = **1.25%**
- **First order on time / early:** 1,759 / 86,909 = **2.02%**
- **Observed gap:** **0.77 percentage points**

The result remains observational and does not establish that late delivery causes lower retention.

## Review deduplication and customer-satisfaction grain

`order_reviews` can contain more than one review row for the same order. Part 8 therefore ranks reviews within each `order_id` and keeps the most recent row by `review_answer_timestamp`, then `review_creation_date`, before joining to orders.

This creates one selected review per delivered order for review-score averages and the order-level Pearson correlation. The validated population contains **95,830 delivered orders with a selected review**.

Category analysis uses a separate one-row-per-`order_id` + `product_category` grain. Multiple items from the same category in one order therefore count once for that category, while an order containing products from multiple categories can appear once in each relevant category.

## Category-translation import cleanup

In the current BigQuery dataset, `category_translation` was loaded with generic field names:

- `string_field_0`
- `string_field_1`

The original CSV header is also present as the first data row. Part 8 aliases these fields to `product_category_name` / `product_category_name_english` and removes the row where `string_field_0 = 'product_category_name'` before joining to `products`.

## Validated customer-satisfaction results

Review score vs. elapsed delivery time:

- **1 star:** 9,355 orders; **21.30 days** average delivery time
- **2 stars:** 2,921 orders; **16.62 days**
- **3 stars:** 7,917 orders; **14.24 days**
- **4 stars:** 18,888 orders; **12.29 days**
- **5 stars:** 56,749 orders; **10.66 days**
- **Pearson correlation:** `r = -0.334` across **95,830** delivered reviewed orders

The 1-star vs. 5-star average-delivery gap is **10.64 days**. This is a moderate negative association, not evidence that delivery time alone causes review outcomes.

Selected category-level results among categories with at least 100 delivered reviewed order-category records:

- **office_furniture:** 1,244 records; **3.64** average review score; **20.56 days** average delivery time
- **fashion_male_clothing:** 105; **3.82**; **12.66 days**
- **audio:** 345; **3.84**; **13.41 days**
- **home_confort:** 390; **3.88**; **13.71 days**
- **bed_bath_table:** 9,177; **4.00**; **12.92 days**
- **furniture_decor:** 6,260; **4.06**; **13.00 days**

`office_furniture` is the clearest category-level operational signal because it combines the lowest average review score in the qualifying set with the longest average delivery time. The result remains descriptive and can reflect product mix, seller mix, geography, product quality, listing accuracy, or other factors.

## Validated seller-level results

For sellers with at least 50 seller-orders:

- **Qualifying sellers:** 425
- **Approximate median average hand-off time:** 2.14 days
- **Approximate median late-delivery rate:** 5.69%
- **Top 20 sellers by delivery reliability:** 0.00-0.93% late-delivery rate; 0.67-4.73 average hand-off days
- **Bottom 20 sellers by delivery reliability:** 15.32-30.14% late-delivery rate; 1.40-15.14 average hand-off days
- **Pearson correlation between average hand-off time and late-delivery rate:** `r = 0.408`

The correlation indicates a moderate positive association, but the overlap in hand-off times across high- and low-performing sellers shows that hand-off speed alone is not a sufficient predictor of delivery reliability.

## Completed follow-up analyses

- **Revenue x Delivery Risk:** using `APPROX_QUANTILES` approximate medians, 116 High Revenue / High Risk sellers; 4.57M seller revenue; 9.38% average late-delivery rate.
- **Customer geography:** SP represents 41.98% of orders at 4.49% late-delivery rate; RJ represents 12.92% of orders at 12.10% late-delivery rate.
- **Payment method / payment value:** credit cards represent 75.40% of payment orders with 167.29 average payment value per order; boleto represents 19.90% with 145.03.
- **First delivery vs. post-delivery repeat purchase:** BigQuery-validated repeat rate is 1.25% after a late first delivery vs. 2.02% after an on-time/early first delivery; this is observational, not causal.
- **Customer satisfaction:** review score and delivery time have a BigQuery-validated Pearson correlation of **-0.334** at one selected review per delivered order; `office_furniture` is the lowest-rated and longest-delivery qualifying category at **3.64 stars** and **20.56 days**.
