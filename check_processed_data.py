import pandas as pd
from pathlib import Path

files = [
    "data/processed/dim_users.csv",
    "data/processed/dim_restaurants.csv",
    "data/processed/fact_sessions.csv",
    "data/processed/fact_search_events.csv",
    "data/processed/fact_cart_events.csv",
    "data/processed/fact_orders.csv",
    "data/processed/fact_delivery_ops.csv",
    "data/processed/fact_refunds.csv",
    "data/processed/fact_ratings.csv",
    "data/processed/daily_marketplace_metrics.csv",
    "data/processed/synthetic_generation_report.csv",
]

for f in files:
    path = Path(f)
    print("\nFILE:", f)
    print("Exists:", path.exists())

    if path.exists():
        df = pd.read_csv(path)
        print("Shape:", df.shape)
        print("Columns:", list(df.columns)[:12])
        print(df.head(2))