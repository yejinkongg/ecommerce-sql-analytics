# E-Commerce Sales & Logistics Analytics

A BigQuery SQL analysis of the Olist Brazilian E-Commerce public dataset, translating demand, logistics, and cancellation patterns into business-relevant insights.

> **Status: In Progress (May 2026 – Present)**
> Demand, Logistics, and Root Cause sections are complete. Customer geography and payment analysis are in progress (see Roadmap below).

---

## 1. Project Purpose

This project uses e-commerce operations data to answer:

- How is order demand trending, and how should that trend be interpreted?
- How reliable is delivery performance, and what metrics actually reflect it?
- Are delivery delays and cancellations systemic issues, or isolated exceptions?
- What operational or marketing actions do these findings support?

The goal was not just to write correct SQL, but to **translate raw numbers into business decisions.**

## 2. Dataset

- **Olist Brazilian E-Commerce Public Dataset** (Kaggle)
  https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
- Analysis period: Sep 2016 – Oct 2018 (some months have incomplete data — see Limitations)
- 6 tables actually used: `orders`, `order_items`, `category_translation`, `payments`, `geolocation`, `customers`
  (`products`, `sellers`, and `order_reviews` are not present in this dataset version — the analysis scope was adjusted accordingly; see Limitations)

## 3. Tools & Techniques

- **BigQuery Standard SQL**
- CTEs, Window Functions (`AVG() OVER()`, `LAG() OVER()`)
- `SAFE_DIVIDE`, `DATE_DIFF`, `DATE_TRUNC`, `FORMAT_DATE`, `APPROX_QUANTILES`
- Fan-out prevention logic applied when joining multi-row tables (e.g. `order_items` × `payments`)

## 4. Key Insights (Business Analyst Perspective)

### Demand
- Order volume grew steadily from early 2017, then **spiked +62.9% month-over-month in November 2017** (4,631 → 7,544 orders), followed by a -24.8% pullback in December. With only one year of data, this can't be confirmed as recurring seasonality, but it flags a need to plan for peak-season demand and promotions.
- From Jan–Aug 2018, order volume held steady in the 6,700–7,300 range (±10% MoM) — a shift from growth phase to a maturity/plateau phase.
- **Repeat purchase rate is only 3.12%** (avg. 1.03 orders per customer), meaning revenue growth is heavily dependent on new customer acquisition rather than retention. This suggests rising long-term CAC risk and supports prioritizing retention tactics (post-purchase coupons, membership programs).

### Logistics
- Of all completed deliveries (96,476), **93.23% arrived on or before the estimated delivery date** (6.77% delayed) — indicating high delivery reliability overall.
- **Average delivery time is 12.09 days, but the actual mode is 7 days**, with most orders concentrated in the 6–9 day range. The average is skewed upward by a long tail of severely delayed orders — suggesting the KPI should be **redefined using median or P90 instead of mean**.
- Deliveries delayed 30+ days account for only ~4.1% of all orders — reframing the logistics problem from "systemic failure" to "a small number of extreme cases." This implies improvement efforts should target long-tail delay elimination rather than reducing the average.

### Root Cause — Seller Segmentation
- Comparing seller performance revealed a clear split: **top-performing sellers had an average hand-off time of 0.6–2 days and a 0–1% late delivery rate**, while **problem sellers averaged 5–15 days hand-off time with a 15–32.1% late delivery rate**.
- Hand-off time (time from order approval to carrier pickup) can serve as a **leading indicator** for delivery risk — flagging slow-hand-off sellers early could allow proactive intervention before delivery delays occur.
- Exceptions exist (some sellers with slow hand-off still had 0% late deliveries), so delivery performance is treated as multi-factor (seller, carrier, estimated-delivery-date policy) rather than attributed to sellers alone.

### Cancellations
- Monthly cancellation rates stayed low overall, generally between 0.2% and 1.3%. Notably, **during the month of steepest demand growth (Nov 2017, +62.9% MoM), the cancellation rate actually dropped from 0.56% to 0.49%** — indicating that the demand surge did not come at the cost of operational quality.
- However, no cancellation-reason or cancellation-timestamp data exists, so a causal link between delivery delays and cancellations could not be tested (see Limitations).

## 5. Status & Roadmap

| Item | Status |
|---|---|
| Demand Analysis (order volume trend, repeat purchase rate) | Done |
| Logistics Analysis (delivery time, delay rate, hand-off time) | Done |
| Root Cause Analysis (seller segmentation) | Done |
| Customer geography analysis (`customer_state`) | Planned |
| Payment / AOV analysis | Planned |
| Delayed delivery vs. repeat purchase rate (proxy for missing `order_reviews`) | Planned |

## 6. Limitations & Retrospective

Documented honestly, as part of the analysis process:

- **Incorrect schema assumptions**: The analysis initially assumed `products`, `sellers`, and `order_reviews` tables existed. They don't exist in this dataset version, requiring the analysis scope to be rebuilt around the 6 tables that actually exist. Takeaway: **always verify schema directly before writing queries**, rather than assuming based on prior familiarity with similar datasets.
- **Causality not established**: The relationship between delivery delay and cancellation, or delivery delay and repeat purchase, could not be tested — even at a correlational level — due to the absence of cancellation-reason and cancellation-timestamp fields. These relationships are described as "possible" or "hypothesized" in the analysis, never stated as confirmed.
- **Data quality issue identified**: A small number of orders show `order_delivered_carrier_date` preceding `order_approved_at` (e.g., -171 days), which is logically impossible in a normal process. Flagged as a data quality issue that would require timestamp validation in a production ETL pipeline.
- **Single-year seasonality caveat**: The November 2017 spike is interpreted as a possible seasonal/promotional effect, but the dataset only spans part of 2016–2018, so this cannot be validated against a second cycle. Treated as an open hypothesis, not a conclusion.
- **Fan-out risk in joins**: Joining `order_items` and `payments` creates a many-to-many relationship that can duplicate rows during aggregation; pre-aggregating in separate CTEs was used to prevent this.

## 7. Repository Structure

```
├── sql/
│   ├── 01_demand_analysis.sql
│   ├── 02_logistics_analysis.sql
│   └── 03_root_cause_analysis.sql
├── docs/
│   └── schema_notes.md
└── report/
    └── ECommerce_Public_Data_Analysis.pdf
```
