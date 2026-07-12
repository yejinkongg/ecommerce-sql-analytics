# Schema Notes

## Actual tables used

The analysis relies on 6 tables from the Olist Brazilian E-Commerce Public Dataset:

| Table | Purpose in this analysis |
|---|---|
| `orders` | Core order lifecycle: status, purchase/approval/handoff/delivery timestamps |
| `order_items` | Line-item level detail, links orders to sellers |
| `category_translation` | Product category name mapping (PT -> EN) |
| `payments` | Payment method and value per order |
| `geolocation` | Zip-code-level lat/long, for future geography analysis |
| `customers` | Customer ID and unique customer ID (for repeat-purchase analysis) |

## Tables initially assumed to exist, but not present in this dataset version

- `products`
- `sellers`
- `order_reviews`

**What happened:** query design initially assumed these three tables existed (they exist in some public versions/forks of the Olist dataset), which would have supported product-category-level analysis, seller master data, and review-based repeat-purchase / satisfaction analysis. Once queries against these tables failed, the actual table list in this BigQuery project was verified directly, and the analysis scope was rebuilt around the 6 tables above.

**Adjustments made as a result:**
- Seller-level analysis (Part 3) is derived entirely from `order_items.seller_id` joined to `orders`, since no standalone `sellers` table exists.
- Category-level analysis relies on `category_translation` joined through `order_items`, since there's no separate `products` table with richer attributes.
- Because `order_reviews` doesn't exist, satisfaction/repeat-purchase analysis substitutes **repeat purchase rate** (derived from `customers` + `orders`) as a proxy signal — this is a proxy, not a review-based satisfaction metric, and is documented as such in the README.

**Takeaway:** verify the actual schema of the specific dataset instance before designing queries, rather than assuming based on documentation or prior familiarity with similarly-named public datasets.

## Fan-out risk

`order_items` and `payments` are both in a many-to-one (or many-to-many, for split payments) relationship with `orders`. A naive `JOIN` between `order_items` and `payments` on `order_id` multiplies rows for any order with more than one item and more than one payment record, inflating COUNT/SUM aggregates.

**Mitigation used:** aggregate each table to the required grain (e.g., total order value from `order_items`, total paid amount from `payments`) in separate CTEs before joining, so the join happens on already-deduplicated, order-level rows rather than raw line-item x payment-installment combinations.

## Known data quality issue

A small number of orders in `orders` have `order_delivered_carrier_date` earlier than `order_approved_at`, producing negative hand-off durations (e.g., -171, -9, -8 days). This is not logically possible in a normal order flow and is treated as a data quality defect rather than a real operational signal. In a production setting, this would warrant timestamp validation at the ETL layer. In this analysis, affected rows are not manually excluded, but the anomaly itself is called out as a limitation rather than silently ignored.
