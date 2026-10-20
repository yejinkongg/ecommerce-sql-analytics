# Schema Notes

## Tables used in the current SQL

| Table | Purpose in this analysis | Used in |
|---|---|---|
| `orders` | Order lifecycle: status, purchase / approval / carrier hand-off / delivery timestamps | `01`, `02`, `03`, `04`, `05`, `07` |
| `order_items` | Line-item detail; links orders to sellers and supports seller revenue aggregation | `03` |
| `customers` | `customer_id` to `customer_unique_id` mapping; repeat purchase and state-level geography | `01`, `04`, `05`, `07` |
| `payments` | Order-level payment value and payment type after aggregation to order grain | `06` |

## Additional available tables not required by the completed core workflow

- `geolocation`
- `category_translation`
- `products`
- `sellers`
- `order_reviews`

These tables are available in the BigQuery dataset but are not required by the completed core SQL workflow. Customer geography in `05` uses `customers.customer_state`, so a geolocation join is unnecessary for the current state-level analysis.

## Schema re-verification

Early query design was revised after rechecking the actual BigQuery dataset and the grain of each table. The final workflow is based on the tables and fields verified for each analysis rather than assuming joins from documentation alone.

**Takeaway:** verify the schema and grain of the specific dataset instance before designing queries.

## Metric definitions as currently implemented

| Metric | Query | Computation |
|---|---|---|
| Average delivery time, delivery buckets, most common delivery time | `02` 2.1-2.3 | Full-day difference between purchase and customer delivery |
| On-time / late rate and days early/late | `02` 2.4-2.5 | Calendar-date comparison against estimated delivery date |
| Average seller hand-off time | `02` 2.6 | Calendar-day difference between approval and carrier hand-off; negative durations excluded |
| Hand-off distribution | `02` 2.7 | Calendar-day difference, with anomalies retained for visibility |
| Seller hand-off, delivery time and late rate | `03` | Calendar-day differences at one row per seller-order; negative hand-off excluded from hand-off averages/rates |
| Payment AOV | `06` | `payments` aggregated to one row per order before payment-method analysis |
| First-delivery repeat comparison | `07` | First observed delivery classified late vs. on-time/early; repeat defined as 2+ observed orders |

The seller hand-off definition in `02` is now aligned with the rule used in `03`: calendar-day differences with negative hand-off durations excluded from the average.

## Seller-level analysis grain and data-quality handling

Part 3 creates a distinct `seller_id` + `order_id` base table before calculating seller metrics. This makes late-delivery rates and hand-off rates seller-order based rather than item-row based.

Negative hand-off durations (`order_delivered_carrier_date` earlier than `order_approved_at`) are treated as data-quality defects. They are:

- retained in seller order counts and delivery metrics,
- excluded from hand-off averages and hand-off-rate denominators,
- counted separately for transparency.

Among the 425 sellers with at least 50 seller-orders, 495 seller-order records have negative hand-off durations.

## Fan-out prevention

`order_items` and `payments` each have a one-to-many relationship with `orders`. A direct `JOIN` between them on `order_id` can multiply rows for orders with multiple items and multiple payment records, inflating `COUNT` / `SUM` aggregates.

The completed workflow avoids this risk in two ways:

- seller revenue in `03` is aggregated from `order_items.price` without joining `payments`;
- payment analysis in `06` aggregates `payments` to one row per order before calculating payment mix and AOV.

No current SQL directly joins raw `order_items` rows to raw `payments` rows.

## Validated seller-level results

For sellers with at least 50 seller-orders:

- **Qualifying sellers:** 425
- **Median average hand-off time:** 2.14 days
- **Median late-delivery rate:** 5.69%
- **Top 20 sellers by delivery reliability:** 0.00-0.93% late-delivery rate; 0.67-4.73 average hand-off days
- **Bottom 20 sellers by delivery reliability:** 15.32-30.14% late-delivery rate; 1.40-15.14 average hand-off days
- **Pearson correlation between average hand-off time and late-delivery rate:** `r = 0.408`

The correlation indicates a moderate positive association, but the overlap in hand-off times across high- and low-performing sellers shows that hand-off speed alone is not a sufficient predictor of delivery reliability.

## Completed follow-up analyses

- **Revenue x Delivery Risk:** 116 High Revenue / High Risk sellers; 4.57M seller revenue; 9.38% average late-delivery rate.
- **Customer geography:** SP represents 41.98% of orders at 4.49% late-delivery rate; RJ represents 12.92% of orders at 12.10% late-delivery rate.
- **Payment / AOV:** credit cards represent 75.40% of payment orders with 167.29 AOV; boleto represents 19.90% with 145.03 AOV.
- **First delivery vs. repeat purchase:** repeat rate is 2.54% after a late first delivery vs. 3.13% after an on-time/early first delivery; this is observational, not causal.
