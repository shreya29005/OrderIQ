import pandas as pd
from pathlib import Path

files = [
    "data/raw/zomato_bangalore.csv",
    "data/raw/food_delivery_time.csv",
    "data/raw/online_food_delivery_preferences.csv",
]

for f in files:
    path = Path(f)
    print("\nFILE:", f)
    print("Exists:", path.exists())
    if path.exists():
        df = pd.read_csv(path)
        print("Shape:", df.shape)
        print("Columns:", list(df.columns)[:10])