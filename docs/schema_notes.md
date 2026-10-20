# Schema Notes

## Tables used in the current SQL

| Table | Purpose in this analysis | Used in |
|---|---|---|
| `orders` | Order lifecycle: status, purchase / approval / carrier hand-off / delivery timestamps | `01`, `02`, `03` |
| `order_items` | Line-item level detail; links orders to sellers via `seller_id` | `03` |
| `customers` | `customer_id` to `customer_unique_id` mapping, used for repeat-purchase analysis | `01` |

## Tables not used yet (planned)

| Table | Planned use | Status |
|---|---|---|
| `payments` | Payment method and value per order (payment / AOV analysis) | Not implemented |
| `geolocation` | Zip-code-level lat/long (customer geography analysis) | Not implemented |
| `category_translation` | PT to EN category names. Needs a table that links `order_items` to a category name (see `products` below), so it cannot be joined through `order_items` alone | Not implemented |

## Tables not available in the BigQuery table set used for this analysis

- `products`
- `sellers`
- `order_reviews`

**What happened:** query design initially assumed these three tables existed. They were not present in the BigQuery dataset used for the original analysis. After queries against them failed, the available tables in the BigQuery project were rechecked and the analysis scope was adjusted accordingly.

**Consequences:**
- Seller-level analysis (Part 3) is derived from `order_items.seller_id` joined to `orders`, since no standalone `sellers` table was used in the original analysis. An order containing items from more than one seller is counted once for each seller represented in that order.
- Within each seller, Part 3 now uses one row per seller-order, preventing multiple items from the same seller from weighting a single order more than once.
- Category-level analysis is not implemented in the current SQL.
- Repeat purchase rate (from `customers` + `orders`, query 1.8 in `01`) is used as a retention metric. It is not treated as a satisfaction measure, and its relationship with delivery delays has not yet been analyzed.

**Takeaway:** verify the actual schema of the specific dataset instance before designing queries.

## Metric definitions as currently implemented

| Metric | Query | Computation |
|---|---|---|
| Average delivery time, delivery buckets, most common delivery time, average hand-off time | `02` 2.1, 2.2, 2.3, 2.6 | `DATE_DIFF` applied to the raw timestamp columns |
| On-time / late rate, days early or late, hand-off distribution | `02` 2.4, 2.5, 2.7 | Differences between `DATE()`-truncated values |
| Seller hand-off, delivery time and late rate | `03` 3.0-3.5 | Differences between `DATE()`-truncated values at one row per seller-order |

**Known inconsistency:** the overall hand-off metric in `02` 2.6 and the seller-level hand-off metric in `03` do not use exactly the same time definition, so their averages are not directly comparable. The definitions should be unified in a future cleanup pass.

## Seller-level analysis grain and data-quality handling

Part 3 now creates a distinct `seller_id` + `order_id` base table before calculating seller metrics. This makes late-delivery rates and hand-off rates seller-order based rather than item-row based.

Negative hand-off durations (`order_delivered_carrier_date` earlier than `order_approved_at`) are treated as data-quality defects. They are:

- retained in seller order counts and delivery metrics,
- excluded from hand-off averages and hand-off-rate denominators,
- counted separately for transparency.

Among the 425 sellers with at least 50 seller-orders, 495 seller-order records have negative hand-off durations.

## Fan-out risk (not yet implemented)

`order_items` and `payments` each have a one-to-many relationship with `orders`. A direct `JOIN` between `order_items` and `payments` on `order_id` can multiply rows for orders with multiple items and multiple payment records, inflating `COUNT` / `SUM` aggregates.

**Planned mitigation:** aggregate each table to order level in separate CTEs before joining. No SQL in this repository currently joins `order_items` and `payments`, so this mitigation is documented as planned rather than implemented.

## Validated seller-level results

For sellers with at least 50 seller-orders:

- **Qualifying sellers:** 425
- **Median average hand-off time:** 2.14 days
- **Median late-delivery rate:** 5.69%
- **Top 20 sellers by delivery reliability:** 0.00-0.93% late-delivery rate; 0.67-4.73 average hand-off days
- **Bottom 20 sellers by delivery reliability:** 15.32-30.14% late-delivery rate; 1.40-15.14 average hand-off days
- **Pearson correlation between average hand-off time and late-delivery rate:** `r = 0.408`

The correlation indicates a moderate positive association, but the overlap in hand-off times across high- and low-performing sellers shows that hand-off speed alone is not a sufficient predictor of delivery reliability.
