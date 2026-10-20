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

## Tables not available in the BigQuery dataset used here

- `products`
- `sellers`
- `order_reviews`

**What happened:** query design initially assumed these three tables existed. They were not present in the BigQuery dataset used for this analysis. After queries against them failed, the actual table list in the BigQuery project was checked directly and the analysis scope was rebuilt around the tables that were available.

**Consequences:**
- Seller-level analysis (Part 3) is derived from `order_items.seller_id` joined to `orders`, since there is no standalone `sellers` table. An order containing items from more than one seller is counted for each of those sellers.
- Category-level analysis is not possible without `products`.
- Review-based satisfaction analysis is not possible without `order_reviews`. Repeat purchase rate (from `customers` + `orders`, query 1.8 in `01`) is computed as a retention metric. It is not a satisfaction measure, and its link to delivery delays has not been analyzed yet (planned).

**Takeaway:** verify the actual schema of the specific dataset instance before designing queries.

## Metric definitions as currently implemented

| Metric | Query | Computation |
|---|---|---|
| Average delivery time, delivery buckets, most common delivery time, average hand-off time | `02` 2.1, 2.2, 2.3, 2.6 | `DATE_DIFF` applied to the raw timestamp columns |
| On-time / late rate, days early or late, hand-off distribution | `02` 2.4, 2.5, 2.7 | Differences between `DATE()`-truncated values |
| Seller hand-off, delivery time and late rate | `03` 3.1 | Differences between `DATE()`-truncated values |

**Known inconsistency:** the two approaches in the table above are not the same definition, so average hand-off in `02` 2.6 and seller-level average hand-off in `03` 3.1 are not directly comparable. The definitions are to be unified across `01`-`03`.

**Known issue in `03` 3.1:** the late rate and the share of 3+ day hand-offs use `COUNT(*)` over `orders` x `order_items` rows, i.e. they are item-row based, while `total_orders` counts distinct orders. The query is to be rewritten at one row per seller-order.

## Fan-out risk (not yet implemented)

`order_items` and `payments` each have a one-to-many relationship with `orders`. A direct `JOIN` between `order_items` and `payments` on `order_id` multiplies rows for any order with more than one item and more than one payment record, which inflates `COUNT` / `SUM` aggregates.

**Planned mitigation:** aggregate each table to order level in separate CTEs before joining. No SQL in this repository joins `order_items` and `payments` yet, so this mitigation has not been implemented. It will be documented as used only after a query that applies it is added.

## Known data quality issue

A small number of orders have `order_delivered_carrier_date` earlier than `order_approved_at`, producing negative hand-off durations (the most extreme case is -171 days). This is not logically possible in a normal order flow and is treated as a data quality defect rather than a real operational signal. In production it would call for timestamp validation at the ETL layer.

**Current handling:** affected rows are not excluded from the hand-off calculations in `02` and `03`, so they are included in the averages. A handling rule and the number of affected rows will be added when `03` is rewritten.
