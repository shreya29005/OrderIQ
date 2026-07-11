# OrderIQ: Food Delivery Marketplace Analytics System

OrderIQ is an end-to-end food delivery marketplace analytics project built to analyze funnel conversion, customer retention, delivery reliability, restaurant quality, search experience, marketplace health, and short-term demand forecasting.

The project combines public food-delivery datasets with synthetic marketplace telemetry to simulate the analytical environment of a food-delivery platform. The final output is a Streamlit dashboard supported by Python data pipelines, DuckDB SQL analysis, data quality checks, and a lightweight forecasting layer.

---

## 1. Business Problem

Food delivery marketplaces need to balance demand, restaurant supply, delivery reliability, customer experience, and commercial efficiency across different zones and user segments.

A marketplace can grow only when the core operating system is healthy:

- users must move smoothly from app open to delivered order
- restaurants must provide enough supply depth and reliable quality
- delivery operations must meet SLA expectations
- search results must help users discover relevant restaurants
- risky restaurants must be identified before they damage customer trust
- strong zones should be scaled only after weaker zones are repaired

This project studies those marketplace problems through a structured analytics system.

---

## 2. Key Business Questions

The project answers the following questions:

1. Where are users dropping off in the ordering funnel?
2. Which user segments need activation, retention, or win-back actions?
3. Which zones are healthy enough to scale?
4. Which zones need operational repair before demand scaling?
5. Which day-hour slots create the highest delivery risk?
6. Which search query-zone combinations suffer from poor result depth?
7. Which restaurants should be investigated for refund, complaint, or SLA risk?
8. Which high-quality restaurants are underexposed and deserve visibility tests?
9. Can short-term delivered-order volume be forecasted for planning?

---

## 3. Project Scope

This project covers the complete analytics workflow:

1. Public dataset cleaning and standardization
2. Synthetic marketplace telemetry generation
3. Data quality validation
4. SQL-based analytical modeling
5. Funnel, cohort, delivery, search, restaurant, and marketplace health analysis
6. Lightweight city-day delivered-order forecasting
7. Streamlit dashboard for product and business decision-making
8. Business insight cards and compact evidence tables

---

## 4. Data Sources

The project uses public food-delivery datasets as base inputs:

- Bangalore restaurant data
- Food delivery time data
- Online food delivery preference data

These public datasets are cleaned and standardized, then used to generate synthetic internal marketplace telemetry.

The synthetic telemetry includes:

- users
- app sessions
- search events
- cart events
- orders
- delivery operations
- refunds
- ratings
- daily marketplace metrics

Synthetic telemetry is used because real internal event-level data from food delivery platforms is not publicly available.

---

## 5. Data Pipeline

The project follows this pipeline:

```text
Raw public datasets
        ↓
Cleaning and standardization
        ↓
Synthetic marketplace telemetry generation
        ↓
Data quality validation
        ↓
SQL analytical models
        ↓
Forecasting outputs
        ↓
Streamlit dashboard
```

Key scripts:

```text
src/clean_public_datasets.py
src/generate_synthetic_telemetry.py
src/data_quality.py
src/sql_runner.py
src/forecast_city_daily.py
```

---

## 6. Repository Structure

```text
OrderIQ/
├── app/
│   └── dashboard.py
├── data/
│   ├── raw/
│   ├── interim/
│   ├── processed/
│   └── analysis/
├── docs/
│   ├── business_problem.md
│   ├── data_assumptions.md
│   ├── data_sources.md
│   ├── metric_dict.md
│   └── sql_catalog.md
├── sql/
│   ├── 00_smoke_test.sql
│   ├── 01_funnel_conversion.sql
│   ├── 02_cohort_retention.sql
│   ├── 03_delivery_p90.sql
│   ├── 04_restaurant_quality_score.sql
│   ├── 05_discount_efficiency.sql
│   ├── 06_sla_root_cause.sql
│   ├── 07_order_frequency_segments.sql
│   ├── 08_repeat_rate_by_cuisine.sql
│   ├── 09_refund_anomaly_restaurants.sql
│   ├── 10_first_order_experience_retention.sql
│   ├── 11_city_zone_marketplace_score.sql
│   ├── 12_search_result_quality.sql
│   ├── 13_restaurant_visibility_opportunity.sql
│   ├── 14_delivery_time_hourly_heatmap.sql
│   ├── 15_forecast_input_metrics.sql
│   └── 16_forecast_input_city_daily.sql
├── src/
│   ├── clean_public_datasets.py
│   ├── generate_synthetic_telemetry.py
│   ├── data_quality.py
│   ├── sql_runner.py
│   └── forecast_city_daily.py
├── check_raw_data.py
├── check_interim_data.py
├── check_processed_data.py
├── requirements.txt
└── README.md
```

---

## 7. Analytics Modules

The SQL layer contains dedicated analytical models for different marketplace questions.

| SQL File | Module | Business Question |
|---|---|---|
| `01_funnel_conversion.sql` | Funnel Conversion | Where do users drop off from app open to delivery? |
| `02_cohort_retention.sql` | Cohort Retention | Are new ordering users coming back? |
| `03_delivery_p90.sql` | Delivery P90 | Where is delivery reliability breaking down? |
| `04_restaurant_quality_score.sql` | Restaurant Quality | Which restaurants are strong or risky partners? |
| `05_discount_efficiency.sql` | Discount Efficiency | Are discounts creating efficient delivered order volume? |
| `06_sla_root_cause.sql` | SLA Root Cause | What operational driver explains late deliveries? |
| `07_order_frequency_segments.sql` | User Segments | Which users need activation, habit-building, or win-back? |
| `08_repeat_rate_by_cuisine.sql` | Cuisine Repeat Rate | Which cuisine-price segments drive repeat behavior? |
| `09_refund_anomaly_restaurants.sql` | Restaurant Anomaly | Which restaurants need refund or complaint investigation? |
| `10_first_order_experience_retention.sql` | First-Order Experience | Does first-order experience affect repeat behavior? |
| `11_city_zone_marketplace_score.sql` | Marketplace Health | Which zones should scale, repair, or improve supply depth? |
| `12_search_result_quality.sql` | Search Quality | Which query-zone pairs have weak discovery quality? |
| `13_restaurant_visibility_opportunity.sql` | Restaurant Visibility | Which restaurants deserve visibility lift tests? |
| `14_delivery_time_hourly_heatmap.sql` | Delivery Heatmap | Which day-hour slots create operational stress? |
| `15_forecast_input_metrics.sql` | Forecast Input Metrics | What daily metrics support forecasting? |
| `16_forecast_input_city_daily.sql` | City-Day Forecast Input | What city-day features support delivered-order forecasting? |

---

## Dashboard Preview

### Executive Overview

![Executive Overview 1](<assets/screenshots/executive overview 1.jpg>)

![Executive Overview 2](<assets/screenshots/executive overview 2.jpg>)

![Executive Overview 3](<assets/screenshots/executive overview 3.jpg>)

---

### Funnel and Retention

![Funnel and Retention 1](<assets/screenshots/funnel and retention 1.jpg>)

![Funnel and Retention 2](<assets/screenshots/funnel and retention 2.jpg>)

![Funnel and Retention 3](<assets/screenshots/funnel and retention 3.jpg>)

---

### Marketplace Health

![Marketplace Health 1](<assets/screenshots/Marketplace Health 1.jpg>)

![Marketplace Health 2](<assets/screenshots/Marketplace Health 2.jpg>)

---

### Delivery Operations

![Delivery Ops 1](<assets/screenshots/Delivery Ops 1.jpg>)

![Delivery Ops 2](<assets/screenshots/Delivery ops 2.jpg>)

![Delivery Ops 3](<assets/screenshots/Delivery Opps 3.jpg>)

---

### Search Quality

![Search Quality 1](<assets/screenshots/Search Quality 1.jpg>)

![Search Quality 2](<assets/screenshots/Search Quality 2.jpg>)

---

### Restaurant Quality, Risk, and Visibility

![Restaurants 1](<assets/screenshots/Restaurants 1.jpg>)

![Restaurants 2](<assets/screenshots/Restaurants 2.jpg>)

![Restaurants 3](<assets/screenshots/Restaurants 3.jpg>)

---

### Lightweight Forecasting

![Forecasting 1](<assets/screenshots/Forecasting 1.jpg>)

![Forecasting 2](<assets/screenshots/Forecasting 2.jpg>)

![Forecasting 3](<assets/screenshots/Forecasting 3.jpg>)

![Forecasting 4](<assets/screenshots/Forecasting 4.jpg>)

---

## 9. Key Metrics

Some important metrics used in the project are:

| Metric | Meaning |
|---|---|
| Delivered Orders | Orders successfully completed |
| Marketplace GMV | Total value of delivered orders |
| Session to Delivery % | Delivered sessions divided by app-open sessions |
| Search to Click % | Restaurant clicks divided by searches |
| Cart to Payment % | Payments divided by carts |
| SLA Breach % | Share of delivered orders breaching delivery SLA |
| Complaint % | Share of orders with complaint signals |
| Refund % | Share of delivered orders refunded |
| Marketplace Health Score | Composite score measuring zone health |
| Search Quality Score | Composite score measuring query-zone search experience |
| Restaurant Quality Score | Composite score measuring restaurant reliability and performance |
| Visibility Score | Proxy for restaurant exposure and discovery strength |
| Anomaly Score | Risk score based on refund, complaint, SLA, and cancellation behavior |
| Forecast MAE | Mean absolute forecast error |
| Forecast MAPE | Mean absolute percentage forecast error |

---

## 10. Key Business Insights

The dashboard surfaces the following business insights:

### 10.1 Funnel Activation

The largest funnel drop-off occurs between app opens and searches.

This suggests that the first priority should be improving early-session activation through better homepage discovery, cuisine shortcuts, personalized recommendations, and first-order incentives.

---

### 10.2 First-Order Experience

Users with a strong first-order experience show a higher repeat rate than users with a poor first-order experience.

This supports investment in first-order delivery reliability, restaurant quality, and complaint prevention.

The insight is directional, not causal, because this project does not run an experimental design.

---

### 10.3 Zone Health

Marketplace health is uneven across zones.

Some zones are ready for growth, while others require customer experience repair or supply-depth improvements before demand scaling.

This prevents the business from increasing demand in zones where reliability or supply quality is not yet strong enough.

---

### 10.4 Delivery Operations

Delivery risk is concentrated in specific day-hour slots.

The dashboard identifies high-risk windows where delivery P90, SLA breach, and complaint rates are elevated.

This supports targeted rider pre-positioning and operational capacity planning.

---

### 10.5 Search Quality

Search quality is strong overall, but a subset of query-zone pairs suffers from poor result depth.

These cases indicate that users may not be seeing enough relevant restaurant options for specific cuisines or zones.

The recommended action is to improve supply depth, ranking quality, or search-to-order conversion depending on the diagnostic signal.

---

### 10.6 Restaurant Risk

A small set of restaurants shows elevated refund, complaint, or SLA risk.

However, restaurant-level decisions require confidence filtering because small order counts can make rates volatile.

The dashboard therefore separates all flagged restaurants from qualified investigation candidates.

---

### 10.7 Restaurant Visibility

Some high-quality restaurants appear underexposed.

These restaurants may be good candidates for controlled visibility lift tests, provided they meet minimum order-count confidence thresholds.

---

### 10.8 Forecasting

The rolling 28-day baseline performs best among the lightweight forecasting methods tested.

This model is used for short-term delivered-order planning, not as a production-grade machine learning system.

---

## 11. Forecasting Method

The forecasting layer is intentionally lightweight.

It compares simple baseline models:

- 7-day lag baseline
- 7-day rolling average
- 14-day rolling average
- 28-day rolling average
- weighted weekly baseline

Models are compared using:

- MAE
- RMSE
- MAPE
- Bias

The selected model is used to forecast the next 14 days of delivered orders and forecast GMV.

This forecasting module is designed for operational planning and expectation-setting rather than advanced machine learning.

---

## 12. Data Quality Checks

The project includes a dedicated data quality validation script.

The checks include:

- required files exist
- tables are non-empty
- primary keys are unique
- foreign keys are valid
- delivered orders have delivery operation records
- cancelled orders do not have delivery operation records
- refunds are linked to delivered orders
- ratings are linked to delivered orders
- ratings are within valid range
- delivery component times are logically consistent
- timestamp sequences are valid
- daily metric dates are unique

This makes the analysis layer more reliable and easier to audit.

---

## 13. Tech Stack

The project uses:

- Python
- Pandas
- NumPy
- DuckDB SQL
- Streamlit
- Plotly
- CSV-based analytical warehouse
- Git and GitHub

---

## 14. How to Run Locally

### 14.1 Install dependencies

```bash
pip install -r requirements.txt
```

### 14.2 Clean public datasets

```bash
python src/clean_public_datasets.py
```

### 14.3 Generate synthetic marketplace telemetry

```bash
python src/generate_synthetic_telemetry.py
```

### 14.4 Run data quality checks

```bash
python src/data_quality.py
```

### 14.5 Run SQL analysis

Example:

```bash
python src/sql_runner.py sql/01_funnel_conversion.sql
```

Run the SQL files from `00` to `16` to regenerate all analysis outputs.

### 14.6 Run forecasting

```bash
python src/forecast_city_daily.py
```

### 14.7 Launch the dashboard

```bash
streamlit run app/dashboard.py
```

---

## 15. Important Assumptions

The project uses the following assumptions:

- Internal marketplace telemetry is synthetic because real platform event-level data is not publicly available.
- Synthetic data is generated to preserve realistic relationships across sessions, search events, orders, delivery operations, refunds, and ratings.
- Restaurant-level outputs use confidence filters because small-denominator rates can be volatile.
- The forecasting model is a lightweight planning baseline, not a production-grade machine learning model.
- Zone-level and restaurant-level recommendations are prioritization signals, not automated business rules.
- Search visibility is proxied using available click and result-depth signals because impression-level ranking data is unavailable.

---

## 16. Limitations

The project has the following limitations:

- Synthetic telemetry cannot fully represent real marketplace seasonality, competitor behavior, promotions, weather shocks, or operational disruptions.
- Restaurant visibility is proxied using search and click behavior rather than true impression-level ranking logs.
- Delivery operations are modeled using available and generated features rather than real rider dispatch, batching, and GPS data.
- Forecasting is limited to baseline models and does not include advanced time-series or machine learning methods.
- The dashboard recommendations are analytical signals and should be validated through experiments before real-world implementation.

---

## 17. Future Improvements

Potential extensions include:

- add true impression-level restaurant ranking data
- add promotion campaign and discount incrementality analysis
- add rider supply, batching, and distance-based delivery features
- add geospatial serviceability modeling
- add causal analysis for first-order experience and retention
- add A/B testing design for visibility lift candidates
- add advanced forecasting models such as Prophet, XGBoost, or LightGBM
- deploy the dashboard publicly
- add automated data refresh jobs

