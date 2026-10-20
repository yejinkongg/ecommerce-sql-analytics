# E-Commerce Sales & Logistics Analytics

A BigQuery SQL analysis of the Olist Brazilian E-Commerce public dataset, translating demand, logistics, cancellation, seller-level delivery patterns, and customer geography into business-relevant insights.

> **Status: Core analysis and Tableau dashboard complete; payment/AOV and repeat-purchase follow-up analyses remain.**

> Interactive dashboard: [Tableau Public](https://public.tableau.com/views/E-CommerceSalesLogisticsAnalytics/Dashboard1?:language=en-US&publish=yes&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)
>
> Full write-up (project journey, debugging process, and detailed findings): [Notion](https://app.notion.com/p/E-Commerce-Sales-Logistics-Analytics-Project-39b7c6f38f688127838ce00127e455d4)

---

## At a Glance

- **99,441 orders analyzed**
- **96,096 unique customers**
- **6.77% late-delivery rate**
- **12.09-day average delivery time**, while the most common delivery time was **7 days**
- **3.12% repeat customer rate**
- Among 425 sellers with at least 50 seller-orders, the **top 20 had 0.00-0.93% late-delivery rates**, while the **bottom 20 had 15.32-30.14%**
- Seller average hand-off time and late-delivery rate showed a **moderate positive association (Pearson r = 0.408)**
- In the Revenue x Delivery-Risk segmentation, **116 High Revenue / High Risk sellers accounted for 4.57M in seller revenue and averaged a 9.38% late-delivery rate**
- **SP accounted for 41.98% of orders** with a 4.49% late-delivery rate, while **RJ accounted for 12.92% of orders** with a much higher 12.10% late-delivery rate

The goal was not just to write correct SQL, but to **translate raw numbers into business decisions while documenting metric definitions, data-quality issues, and analytical limitations.**

## 1. Project Purpose

This project uses e-commerce operations data to answer:

- How is order demand trending, and how should that trend be interpreted?
- How reliable is delivery performance, and what metrics actually reflect it?
- Are delivery delays and cancellations systemic issues, or concentrated exceptions?
- How much does seller hand-off performance relate to delivery reliability?
- Which sellers combine high commercial value with elevated delivery risk?
- Which customer geographies combine high order exposure with elevated delivery risk?
- What operational or customer-growth actions do these findings support?

## 2. Dataset

- **Olist Brazilian E-Commerce Public Dataset** (Kaggle)
- Analysis period: Sep 2016 - Oct 2018 (some months have incomplete data; see Limitations)
- Tables used in the current SQL: `orders`, `order_items`, `customers`
- Additional tables reserved for follow-up analysis: `payments`, `geolocation`, `category_translation`

See [`docs/schema_notes.md`](docs/schema_notes.md) for schema assumptions, table availability, metric definitions, seller-order grain, and data-quality handling.

## 3. Tools & Techniques

- **BigQuery Standard SQL**
- **Tableau Public** for the executive dashboard
- CTEs and temporary tables
- Window functions (`AVG() OVER()`, `LAG() OVER()`, `SUM() OVER()`)
- `SAFE_DIVIDE`, `DATE_DIFF`, `DATE_TRUNC`, `FORMAT_DATE`
- `APPROX_QUANTILES` for seller-level distribution summaries and segmentation thresholds
- `CORR` for seller-level association analysis
- Seller-order deduplication to prevent multi-item orders from receiving extra weight
- Seller revenue aggregation from `order_items.price` without joining payments, avoiding order_items x payments fan-out
- State-level demand and delivery-risk comparison using dynamic order-share calculations
- Tableau KPI cards, dual-axis monthly trend visualization, seller-risk scatter plot, and linear trend line

## 4. Key Insights

### Demand

- Order volume grew steadily from early 2017, then **spiked 62.9% month over month in November 2017** (4,631 -> 7,544 orders), followed by a **24.8% pullback** in December.
- From Jan-Aug 2018, monthly order volume remained around **6,700-7,300 orders**.
- Average orders per customer were **1.03**, and only **3.12% of customers** placed two or more orders.

**Business interpretation:** growth appears heavily dependent on new-customer acquisition, supporting further investigation into retention and repeat-purchase opportunities.

### Logistics

- Of 96,476 completed deliveries, **93.23% arrived on or before the estimated delivery date** and **6.77% were late**.
- **Average delivery time was 12.09 days**, but the **mode was 7 days**, with most deliveries concentrated around 6-9 days.
- A small long tail of severely delayed orders pulls the mean upward, so average delivery time alone does not fully describe the typical customer experience.

**Business interpretation:** median, P90, on-time delivery rate, and long-tail exception rates would be useful complementary KPIs in future analysis.

### Root Cause - Seller-Level Delivery Risk

The seller analysis was rebuilt at **one row per seller-order** so that multiple items from the same seller do not overweight a single order.

Among **425 sellers with at least 50 seller-orders**:

- Median seller average hand-off time: **2.14 days**
- Median late-delivery rate: **5.69%**
- Top 20 sellers by delivery reliability: **0.00-0.93% late-delivery rate**, with average hand-off times of **0.67-4.73 days**
- Bottom 20 sellers by delivery reliability: **15.32-30.14% late-delivery rate**, with average hand-off times of **1.40-15.14 days**
- Average hand-off time and late-delivery rate showed a **moderate positive association (Pearson r = 0.408)**

**Business interpretation:** hand-off time is a useful operational risk signal, but not a sufficient standalone predictor. Some reliable sellers still have relatively long hand-off times, while some high-risk sellers have relatively short hand-off times, indicating that delivery reliability is multi-factor.

### Revenue x Delivery-Risk Segmentation

Using the same 425 qualifying sellers, seller revenue was calculated as the sum of `order_items.price` and split at the seller-population revenue median; delivery risk was split at the seller-population late-delivery-rate median.

| Segment | Sellers | Segment revenue | Avg late-delivery rate | Avg orders / seller |
|---|---:|---:|---:|---:|
| High Revenue / High Risk | 116 | 4,571,185.21 | 9.38% | 268.6 |
| High Revenue / Low Risk | 96 | 3,058,795.86 | 3.49% | 240.8 |
| Low Revenue / High Risk | 99 | 610,916.18 | 10.19% | 89.2 |
| Low Revenue / Low Risk | 114 | 755,739.07 | 2.97% | 95.3 |

**Business interpretation:** the **High Revenue / High Risk** segment is the primary intervention group because it combines the largest revenue exposure with materially elevated late-delivery risk. The Low Revenue / High Risk group has an even higher average late rate, but represents substantially less revenue exposure.

### Customer Geography

Customer demand and delivery reliability vary materially by state:

- **SP:** 41,746 orders, **41.98%** of all orders, **4.49%** late-delivery rate
- **RJ:** 12,852 orders, **12.92%** share, **12.10%** late-delivery rate
- **MG:** 11,635 orders, **11.70%** share, **4.58%** late-delivery rate
- **RS:** 5,466 orders, **5.50%** share, **6.08%** late-delivery rate
- **PR:** 5,045 orders, **5.07%** share, **4.04%** late-delivery rate

Smaller states such as **AL (21.41%)** and **MA (17.43%)** have much higher late-delivery rates, but account for only **0.42%** and **0.75%** of orders respectively.

**Business interpretation:** **RJ is the clearest geography for operational investigation** because it combines meaningful order exposure with a late-delivery rate well above the overall 6.77% benchmark. SP is the dominant demand market but performs comparatively well on delivery reliability. Very small high-late-rate states should be monitored as localized service risks rather than treated as platform-wide drivers.

### Cancellations

- Monthly cancellation rates generally stayed between **0.2% and 1.3%**.
- During the largest demand spike in Nov 2017, cancellation rate decreased from **0.56% to 0.49%** even as order volume increased 62.9% MoM.

**Limitation:** the available fields do not establish a causal relationship between delivery delays and cancellations.

## 5. Dashboard

The Tableau Public dashboard summarizes the core findings in one view:

- KPI cards for total orders, average delivery days, on-time delivery rate, late-delivery rate, and repeat customer rate
- Monthly order volume vs. cancellation rate, including the Nov 2017 peak of 7,544 orders
- Seller average hand-off time vs. late-delivery rate, with top/bottom reliability groups and an overall linear trend line

**Dashboard period note:** KPI cards use the full available dataset, while the monthly trend is intentionally restricted to **Jan 2017-Aug 2018** to exclude sparse partial months that would distort month-over-month interpretation.

[Open the interactive Tableau dashboard](https://public.tableau.com/views/E-CommerceSalesLogisticsAnalytics/Dashboard1?:language=en-US&publish=yes&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)

## 6. Business Recommendations

- Prioritize the **High Revenue / High Risk** seller segment for operational review because it combines elevated late-delivery risk with the greatest revenue exposure.
- Investigate **RJ delivery performance** because it combines high order exposure with a 12.10% late-delivery rate, well above the platform average.
- Monitor seller hand-off time as **one** delivery-risk signal rather than treating it as a standalone predictor.
- Prioritize investigation of sellers with persistently elevated late-delivery rates and long hand-off patterns.
- Complement average delivery time with **median, P90, on-time rate, and long-tail exception monitoring** in future KPI design.
- Investigate retention opportunities given the **3.12% repeat customer rate**.

## 7. Status & Roadmap

| Item | Status |
|---|---|
| Demand analysis | Done |
| Logistics analysis | Done |
| Seller-level delivery-risk analysis | Done |
| Seller-order grain correction & data-quality handling | Done |
| Revenue x delivery-risk 2x2 segmentation | Done |
| Customer geography analysis | Done |
| Tableau executive dashboard | Done |
| Payment / AOV analysis | Planned |
| Delayed delivery vs. repeat purchase | Planned |

## 8. Limitations & Retrospective

- **Schema assumptions:** the analysis scope was revised after checking the tables available in the BigQuery environment used for the project.
- **Metric consistency:** overall hand-off time in `02` and seller-level hand-off time in `03` do not yet use exactly the same time definition, so they should not be directly compared.
- **Negative hand-off records:** 495 seller-order records among the 425 qualifying sellers had logically impossible negative hand-off durations. They are retained in order/delivery counts but excluded from hand-off averages and hand-off-rate denominators.
- **Causality:** the seller analysis describes association, not causal effects. Pearson `r = 0.408` does not imply that slower seller hand-off causes late delivery.
- **Seasonality:** the Nov 2017 spike cannot be confirmed as recurring seasonality from the available time span.
- **Fan-out risk:** no current SQL joins `order_items` and `payments`; if added later, those tables should be aggregated to order grain before joining to prevent duplicated aggregates.
- **2x2 segmentation:** the four seller segments are prioritization buckets based on population medians, not causal classifications or externally validated risk thresholds.
- **Geography:** state-level late-delivery rates identify where reliability differs, but they do not isolate the underlying cause; distance, carrier mix, seller mix, or other factors may contribute.

## 9. Repository Structure

```text
├── sql/
│   ├── 01_demand_analysis.sql
│   ├── 02_logistics_analysis.sql
│   ├── 03_root_cause_analysis.sql
│   ├── 04_tableau_exports.sql
│   └── 05_customer_geography.sql
├── docs/
│   └── schema_notes.md
├── README.md
└── LICENSE
```
