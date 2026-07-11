import pandas as pd
from pathlib import Path

files = [
    "data/interim/cleaned_restaurants.csv",
    "data/interim/cleaned_delivery_base.csv",
    "data/interim/cleaned_user_preferences.csv",
    "data/interim/public_data_cleaning_report.csv",
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