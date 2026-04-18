# CX Diagnostic Dataset — Data Dictionary

Synthetic marketplace dataset generated for a customer-experience root-cause analysis portfolio project. Nine relational CSVs, ~100K orders, 24 months (Jan 2023 – Dec 2024), US-based marketplace.

---

## Headline stats

| Metric | Value |
|---|---|
| Orders | 100,000 |
| Order items | 129,650 |
| Reviews | 78,687 |
| Payments | 107,804 |
| Unique customers | 72,000 |
| Sellers | 2,500 |
| Products | 15,000 |
| Categories | 42 |
| Date range | 2023-01-01 to 2024-12-31 |
| Total GMV | ~$8.2M |
| CSAT (4–5 stars) | 68.0% |
| Detractor rate (1–2 stars) | 22.6% |
| Late delivery rate | 15.2% |

---

## Tables

### `customers.csv` — one row per order (per-order customer reference)
| Column | Type | Notes |
|---|---|---|
| customer_id | string | PK — unique per order (Olist-style) |
| customer_unique_id | string | Identifies the real buyer across orders; join here for repeat-buyer analysis |
| customer_state | string | 2-letter US state code |
| customer_zip_prefix | string | 5-digit synthetic zip |
| customer_city_bucket | string | Synthetic city identifier |

**Grain:** one row per order placed. 100,000 rows.

---

### `orders.csv` — order lifecycle and delivery timestamps
| Column | Type | Notes |
|---|---|---|
| order_id | string | PK |
| customer_id | string | FK → customers |
| order_status | string | delivered / canceled / returned / shipped / invoiced / unavailable |
| purchase_ts | timestamp | When order was placed |
| approved_ts | timestamp | Payment approved |
| delivered_carrier_ts | timestamp | Handed to carrier (nullable) |
| delivered_customer_ts | timestamp | Delivered to customer (nullable) |
| estimated_delivery_ts | timestamp | Promised delivery date |

**Grain:** one row per order. 100,000 rows.

**Late flag:** compute as `delivered_customer_ts > estimated_delivery_ts`.

---

### `order_items.csv` — item-level detail
| Column | Type | Notes |
|---|---|---|
| order_id | string | FK → orders |
| order_item_id | int | Sequence within order (1, 2, 3…) |
| product_id | string | FK → products |
| seller_id | string | FK → sellers (denormalized for convenience) |
| price | decimal | Item price paid |
| freight_value | decimal | Shipping cost for this item |
| shipping_limit_date | timestamp | Seller's promised ship-by date |

**Grain:** one row per item per order. 129,650 rows. 80% of orders have 1 item; 20% have 2–5.

---

### `products.csv` — product catalog
| Column | Type | Notes |
|---|---|---|
| product_id | string | PK |
| category_id | string | FK → product_categories |
| seller_id | string | FK → sellers (primary seller) |
| price | decimal | List price |
| weight_grams | int | Product weight (heavy items = furniture/appliances/electronics) |
| length_cm | int | Dimension |
| photos_qty | int | Number of listing photos |

**Grain:** one row per product. 15,000 rows.

---

### `product_categories.csv` — category lookup
| Column | Type | Notes |
|---|---|---|
| category_id | string | PK |
| category_slug | string | Machine-readable category |
| category_name | string | Display name |

**Grain:** one row per category. 42 rows.

---

### `sellers.csv` — seller directory
| Column | Type | Notes |
|---|---|---|
| seller_id | string | PK |
| seller_state | string | 2-letter US state code |
| seller_zip_prefix | string | Synthetic zip |
| onboarded_date | date | When the seller joined |

**Grain:** one row per seller. 2,500 rows.

---

### `payments.csv` — payment records (can be multiple per order for split-tender)
| Column | Type | Notes |
|---|---|---|
| order_id | string | FK → orders |
| payment_sequential | int | 1 for single payment, 2+ for split |
| payment_type | string | credit_card / debit_card / voucher / boleto / paypal |
| payment_installments | int | 1 for single, 2–12 for installments (credit_card only) |
| payment_value | decimal | Amount paid on this payment |

**Grain:** one row per payment per order. 107,804 rows. ~8% of orders use split-tender.

---

### `reviews.csv` — customer review records
| Column | Type | Notes |
|---|---|---|
| review_id | string | PK |
| order_id | string | FK → orders |
| review_score | int | 1–5 stars |
| review_title | string | Short headline |
| review_message | string | Free-text review body (use this for taxonomy mining) |
| review_created_ts | timestamp | When customer submitted review |
| review_answered_ts | timestamp | When seller responded (nullable, ~35% of negatives get a response) |

**Grain:** one row per review. 78,687 rows. ~80% of delivered orders get a review; lower rates for canceled/returned orders.

**Text language:** English. Templated from a curated library with realistic variation. Keywords for negative reviews cluster around 5 root causes (see below).

---

### `geolocation.csv` — zip prefix → coordinates lookup
| Column | Type | Notes |
|---|---|---|
| zip_prefix | string | PK |
| state | string | 2-letter code |
| latitude | decimal | Approximate lat |
| longitude | decimal | Approximate lng |
| city_bucket | string | Synthetic city |

**Grain:** one row per zip prefix. 5,000 rows. Useful for Power BI map visuals.

---

## Key relationships

```
customers (1) ──────── (many) orders ──────── (many) order_items
                            │                          │
                            │                          ├── products ── product_categories
                            │                          │
                            │                          └── sellers
                            │
                            ├── reviews (0..1)
                            └── payments (1..many)
```

---

## Known patterns (the findings your project should uncover)

These are baked into the data generation — your SQL analysis should surface them:

### Primary findings
- **Late delivery is a top detractor driver.** On-time orders: ~20% detractor rate. Late orders: ~31% detractor rate (~1.5× lift).
- **Furniture, Large Appliances, and Electronics run 1.4–1.6× the baseline detractor rate.** Heavy, high-value, shipping-sensitive categories.
- **Regional logistics hotspots.** Rural South (KY, AR, AL, MS, LA, WV) and Pacific Northwest (OR, WA, ID, MT) show 35–42% late rates vs ~15% national.
- **A problem-seller cohort exists in the top decile.** ~24 sellers with 30+ orders show detractor rates of 50%+ vs 22% baseline. Small share of GMV but disproportionate share of detractors.
- **~23% of customers who complain file a repeat complaint.** Use `customer_unique_id` to detect.

### Secondary findings
- **Installment payments correlate with complaint rate.** Orders with 6+ installments show ~28% detractor rate vs 21% for 1-installment.
- **Seasonal volume pattern.** Nov/Dec see 1.6–1.8× order volume; Feb/Jul/Aug dip.
- **Day-of-week pattern.** Mon–Wed see slightly elevated order volume.
- **Seller response rate.** Only ~35% of negative reviews (≤3 stars) get a seller response, identifying a service-recovery gap.

---

## Root-cause taxonomy (for review text mining)

Negative review text contains keyword patterns that map to these categories. Use `CASE WHEN LOWER(review_message) LIKE '%…%'` in SQL:

| Root cause | Keywords to match | Approx. share of detractor reviews |
|---|---|---|
| Late delivery | `late`, `delay`, `slow`, `forever`, `days late`, `took too long` | ~13% |
| Damaged/defective | `broken`, `damaged`, `cracked`, `defective`, `dented`, `doesn't work` | ~20% |
| Wrong item | `wrong item`, `wrong size`, `wrong color`, `not what i ordered`, `incorrect`, `different product` | ~10% |
| Seller unresponsive | `no response`, `never replied`, `unresponsive`, `ignored`, `couldn't reach` | ~13% |
| Quality below expectations | `cheap`, `poor quality`, `flimsy`, `not as described`, `disappointing`, `poorly made` | ~17% |
| Generic/uncategorized | no keyword match | ~27% (realistic residual — many complainers don't specify) |

A CASE statement with these patterns forms the backbone of Query 03 in the companion `/sql` folder.

---

## Limitations to acknowledge in your README

These are intentionally not modeled — mention them in your "Assumptions & Limitations" section:

- No agent-level or ticket-system data (reviews are the only CX voice signal)
- No explicit refund/chargeback table (infer from `order_status = 'returned'` and 1-star reviews)
- No session, app/web, or product-page behavioral data
- Reviews are templated — real-world text would be messier and multilingual
- No seller SLA or fulfillment-channel distinction (1P vs 3P)
- No customer support contact history beyond the review record

---

## Getting started

**Postgres/SQLite import:** All tables are clean UTF-8 CSVs with standard `YYYY-MM-DD HH:MM:SS` timestamp formatting. Load with `COPY` or `.import`.

**Power BI import:** Use "Get Data → Folder" pointing at the unzipped directory, then set relationships in Model view matching the ERD. Mark `orders.purchase_ts` as the date key for your date dimension.

**Suggested first query:** Start with `01_data_quality_audit.sql` — row counts per table, nulls in critical fields, distribution of `order_status`, distribution of `review_score`. This is also the doc header your project needs: "Analyst confirmed data integrity before beginning analysis."
