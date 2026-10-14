# OrderIQ | Food Delivery Marketplace Analytics

OrderIQ is a portfolio analytics project that uses **DuckDB SQL, Python, and Streamlit** to study a simulated food-delivery marketplace. The core analysis covers **funnel conversion, customer retention, and delivery reliability** across approximately **6.5k users and 90k app sessions**.

The project combines cleaned public food-delivery datasets with **synthetic event-level telemetry**. The results demonstrate the analytical workflow and should not be interpreted as the performance of a real food-delivery company.

## Business questions

The analysis focuses on three main questions:

1. At which stage of the ordering journey do the most users drop off?
2. How does repeat activity vary across monthly customer cohorts?
3. Where do delivery-time and SLA metrics indicate possible reliability issues?

Additional exploratory SQL models examine search activity, restaurant-level metrics, refunds, complaints, discounts, and zone-level marketplace indicators.

## Data scope

Public food-delivery datasets were cleaned and used as base inputs. Because real platform event logs are not publicly available, the project generates linked synthetic tables for:

- users
- app sessions
- search events
- cart and payment events
- orders and deliveries
- refunds and ratings
- daily marketplace metrics

The synthetic data is intended to support SQL and dashboard analysis. It does not reproduce an actual company's customer or operational data.

## Analysis workflow

```text
Public datasets
      ↓
Cleaning and standardization
      ↓
Synthetic event generation
      ↓
Data-quality checks
      ↓
DuckDB SQL analysis
      ↓
Streamlit dashboard
```

## Core analyses

### 1. Funnel conversion

The funnel follows sessions through the main ordering stages:

```text
App open → Search → Restaurant click → Cart → Payment → Delivered order
```

Stage conversion and drop-off rates are calculated from distinct sessions. Within the generated data, the largest loss occurs between **app open and search**. This is an exploratory finding that can be used to frame questions around homepage discovery or early-session activation; it is not evidence that a specific product change would cause conversion to improve.

### 2. Cohort retention

Customers are assigned to a monthly cohort based on the month of their **first delivered order**. The analysis then checks whether each customer places another delivered order within the D7 and D30 windows.

| Metric | Definition used in the project |
|---|---|
| D7 retention | Share of first-time ordering users who place a repeat delivered order within 7 days |
| D30 retention | Share of first-time ordering users who place a repeat delivered order within 30 days |

These cohort comparisons describe repeat-order behavior in the synthetic dataset; they do not establish why retention differs.

### 3. Delivery reliability

Delivery analysis summarizes metrics such as delivery time, P90 delivery time, and SLA-breach rate by dimensions including city, zone, and time slot. These views help locate segments that may require further investigation, rather than automatically identifying a root cause.

## Dashboard preview

### Funnel and retention

![Funnel and Retention 1](<assets/screenshots/funnel and retention 1.jpg>)

![Funnel and Retention 2](<assets/screenshots/funnel and retention 2.jpg>)

### Search quality

![Search Quality 1](<assets/screenshots/Search Quality 1.jpg>)

![Search Quality 2](<assets/screenshots/Search Quality 2.jpg>)

### Restaurant metrics

![Restaurants 1](<assets/screenshots/Restaurants 1.jpg>)

![Restaurants 2](<assets/screenshots/Restaurants 2.jpg>)

![Restaurants 3](<assets/screenshots/Restaurants 3.jpg>)

## Supporting components

### Data-quality checks

The validation script checks items such as:

- required files and non-empty tables
- unique primary keys and valid foreign keys
- valid order-to-delivery, refund, and rating relationships
- logical timestamp sequences
- valid rating ranges
- consistent delivery component times

### Baseline forecasting

The repository also compares simple time-based baselines, including lag and rolling-average methods, for short-term delivered-order estimates. Forecasts are evaluated using MAE, RMSE, MAPE, and bias. This is a supporting experiment, not a production forecasting system.

## Repository structure

```text
OrderIQ/
├── app/
│   └── dashboard.py
├── assets/
│   └── screenshots/
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
│   └── 00_smoke_test.sql ... 16_forecast_input_city_daily.sql
├── src/
│   ├── clean_public_datasets.py
│   ├── generate_synthetic_telemetry.py
│   ├── data_quality.py
│   ├── sql_runner.py
│   └── forecast_city_daily.py
├── requirements.txt
└── README.md
```

## Tech stack

- DuckDB SQL
- Python
- Pandas and NumPy
- Streamlit
- Plotly

## Run locally

```bash
pip install -r requirements.txt
python src/clean_public_datasets.py
python src/generate_synthetic_telemetry.py
python src/data_quality.py
python src/sql_runner.py sql/01_funnel_conversion.sql
streamlit run app/dashboard.py
```

Run the relevant SQL file separately to regenerate another analysis output. The optional baseline forecasting script can be run with:

```bash
python src/forecast_city_daily.py
```

## Limitations

- The event-level marketplace data is synthetic, so the findings are illustrative rather than real business results.
- Generated behavior cannot fully represent seasonality, promotions, weather, competitor activity, or operational disruptions.
- Restaurant and zone metrics can be unstable at low order volumes and should be interpreted with sample-size checks.
- Observed relationships, including those involving first-order experience and retention, are correlational rather than causal.
- Search visibility is approximated from available search and click fields because impression-level ranking logs are unavailable.
- Recommendations suggested by the dashboard would need validation with real data and controlled experiments before implementation.
