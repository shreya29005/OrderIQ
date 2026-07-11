from pathlib import Path
import re
import numpy as np
import pandas as pd


RAW_DIR = Path("data/raw")
INTERIM_DIR = Path("data/interim")
INTERIM_DIR.mkdir(parents=True, exist_ok=True)


def read_csv_safe(path: Path) -> pd.DataFrame:
    """Read CSV with fallback encoding."""
    try:
        return pd.read_csv(path)
    except UnicodeDecodeError:
        return pd.read_csv(path, encoding="latin-1")


def normalize_column_name(col: str) -> str:
    """Normalize column names into snake_case."""
    col = str(col).strip().lower()
    col = re.sub(r"[^a-z0-9]+", "_", col)
    col = col.strip("_")
    return col


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df.columns = [normalize_column_name(c) for c in df.columns]
    return df


def clean_text(series: pd.Series, default: str = "Unknown") -> pd.Series:
    """Clean text columns and replace missing/blank values."""
    s = series.astype(str).str.strip()
    s = s.replace(["", "nan", "NaN", "None", "null"], np.nan)
    return s.fillna(default)


def extract_numeric(series: pd.Series) -> pd.Series:
    """Extract first numeric value from messy strings."""
    s = series.astype(str)
    extracted = s.str.extract(r"(-?\d+\.?\d*)")[0]
    return pd.to_numeric(extracted, errors="coerce")


def parse_rating(series: pd.Series) -> pd.Series:
    """
    Convert ratings like '4.1/5', 'NEW', '-' into numeric ratings.
    """
    return extract_numeric(series)


def parse_money(series: pd.Series) -> pd.Series:
    """
    Convert cost strings like '1,200' into numeric.
    """
    s = series.astype(str).str.replace(",", "", regex=False)
    return extract_numeric(s)


def parse_yes_no(series: pd.Series) -> pd.Series:
    """Convert yes/no style columns into boolean."""
    s = series.astype(str).str.strip().str.lower()
    return s.isin(["yes", "y", "true", "1"])


def get_existing_column(df: pd.DataFrame, possible_names: list[str]) -> str | None:
    """Return the first matching column name from a list of possible names."""
    for name in possible_names:
        if name in df.columns:
            return name
    return None


def haversine_distance_km(lat1, lon1, lat2, lon2):
    """
    Calculate distance between two lat/lon points using the Haversine formula.
    """
    lat1 = np.radians(lat1)
    lon1 = np.radians(lon1)
    lat2 = np.radians(lat2)
    lon2 = np.radians(lon2)

    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = (
        np.sin(dlat / 2) ** 2
        + np.cos(lat1) * np.cos(lat2) * np.sin(dlon / 2) ** 2
    )

    c = 2 * np.arcsin(np.sqrt(a))
    earth_radius_km = 6371
    return earth_radius_km * c


def assign_price_band(cost_series: pd.Series) -> pd.Series:
    """
    Assign low/mid/premium price bands using quantiles.
    """
    cost = pd.to_numeric(cost_series, errors="coerce")
    output = pd.Series("unknown", index=cost.index, dtype="object")

    valid = cost.dropna()

    if len(valid) < 10:
        return output

    q33 = valid.quantile(0.33)
    q66 = valid.quantile(0.66)

    output[(cost.notna()) & (cost <= q33)] = "low"
    output[(cost.notna()) & (cost > q33) & (cost <= q66)] = "mid"
    output[(cost.notna()) & (cost > q66)] = "premium"

    return output


def assign_rating_band(rating_series: pd.Series) -> pd.Series:
    """
    Assign restaurant rating band.
    """
    rating = pd.to_numeric(rating_series, errors="coerce")
    output = pd.Series("unknown", index=rating.index, dtype="object")

    output[(rating.notna()) & (rating < 3.5)] = "low"
    output[(rating.notna()) & (rating >= 3.5) & (rating < 4.0)] = "mid"
    output[(rating.notna()) & (rating >= 4.0)] = "high"

    return output


def clean_zomato_restaurants() -> tuple[pd.DataFrame, list[dict]]:
    """
    Clean Zomato Bangalore restaurant dataset into dim_restaurants base.
    """
    report = []

    path = RAW_DIR / "zomato_bangalore.csv"
    raw = read_csv_safe(path)
    raw_rows = len(raw)

    df = normalize_columns(raw)

    required_cols = [
        "name",
        "location",
        "cuisines",
        "rate",
        "votes",
        "approx_cost_for_two_people",
    ]

    missing_required = [c for c in required_cols if c not in df.columns]

    if missing_required:
        raise ValueError(
            f"Missing required Zomato columns after normalization: {missing_required}\n"
            f"Available columns: {list(df.columns)}"
        )

    restaurants = pd.DataFrame()

    restaurants["restaurant_name"] = clean_text(df["name"])
    restaurants["city"] = "Bangalore"
    restaurants["zone"] = clean_text(df["location"])
    restaurants["address"] = clean_text(df.get("address", pd.Series(index=df.index)), default="")
    restaurants["rest_type"] = clean_text(df.get("rest_type", pd.Series(index=df.index)))
    restaurants["cuisines_raw"] = clean_text(df["cuisines"])

    restaurants["primary_cuisine"] = restaurants["cuisines_raw"].apply(
        lambda x: str(x).split(",")[0].strip() if pd.notna(x) and str(x).strip() else "Unknown"
    )

    restaurants["cuisine_count"] = restaurants["cuisines_raw"].apply(
        lambda x: len([c.strip() for c in str(x).split(",") if c.strip() and c.strip() != "Unknown"])
    )

    restaurants["rating"] = parse_rating(df["rate"])
    restaurants["votes"] = pd.to_numeric(df["votes"], errors="coerce").fillna(0).astype(int)
    restaurants["avg_cost_for_two"] = parse_money(df["approx_cost_for_two_people"])

    restaurants["online_order_flag"] = parse_yes_no(
        df.get("online_order", pd.Series(index=df.index))
    )

    restaurants["book_table_flag"] = parse_yes_no(
        df.get("book_table", pd.Series(index=df.index))
    )

    restaurants["listed_in_type"] = clean_text(
        df.get("listed_in_type", pd.Series(index=df.index))
    )

    restaurants["listed_in_city"] = clean_text(
        df.get("listed_in_city", pd.Series(index=df.index))
    )

    # Remove unusable rows
    restaurants = restaurants[
        (restaurants["restaurant_name"] != "Unknown")
        & (restaurants["zone"] != "Unknown")
        & (restaurants["primary_cuisine"] != "Unknown")
    ].copy()

    # Remove impossible ratings/costs but preserve missing values
    restaurants.loc[
        (restaurants["rating"] < 0) | (restaurants["rating"] > 5), "rating"
    ] = np.nan

    restaurants.loc[
        restaurants["avg_cost_for_two"] <= 0, "avg_cost_for_two"
    ] = np.nan

    # Deduplicate restaurants by name-zone-cuisine.
    restaurants = restaurants.sort_values(
        by=["votes", "rating"],
        ascending=[False, False],
        na_position="last",
    )

    restaurants = restaurants.drop_duplicates(
        subset=["restaurant_name", "zone", "primary_cuisine"],
        keep="first",
    ).reset_index(drop=True)

    restaurants["price_band"] = assign_price_band(restaurants["avg_cost_for_two"])
    restaurants["rating_band"] = assign_rating_band(restaurants["rating"])

    restaurants.insert(0, "restaurant_id", range(1, len(restaurants) + 1))

    final_cols = [
        "restaurant_id",
        "restaurant_name",
        "city",
        "zone",
        "address",
        "rest_type",
        "primary_cuisine",
        "cuisines_raw",
        "cuisine_count",
        "avg_cost_for_two",
        "price_band",
        "rating",
        "rating_band",
        "votes",
        "online_order_flag",
        "book_table_flag",
        "listed_in_type",
        "listed_in_city",
    ]

    restaurants = restaurants[final_cols]

    report.append({
        "dataset": "zomato_bangalore",
        "check": "raw_rows",
        "value": raw_rows,
    })

    report.append({
        "dataset": "zomato_bangalore",
        "check": "cleaned_rows",
        "value": len(restaurants),
    })

    report.append({
        "dataset": "zomato_bangalore",
        "check": "missing_rating_pct",
        "value": round(restaurants["rating"].isna().mean() * 100, 2),
    })

    report.append({
        "dataset": "zomato_bangalore",
        "check": "missing_cost_pct",
        "value": round(restaurants["avg_cost_for_two"].isna().mean() * 100, 2),
    })

    return restaurants, report


def clean_delivery_time_base() -> tuple[pd.DataFrame, list[dict]]:
    """
    Clean food delivery time dataset into a delivery operations base.
    """
    report = []

    path = RAW_DIR / "food_delivery_time.csv"
    raw = read_csv_safe(path)
    raw_rows = len(raw)

    df = normalize_columns(raw)

    required_cols = [
        "id",
        "delivery_person_id",
        "delivery_person_age",
        "delivery_person_ratings",
        "restaurant_latitude",
        "restaurant_longitude",
        "delivery_location_latitude",
        "delivery_location_longitude",
        "type_of_order",
        "type_of_vehicle",
    ]

    missing_required = [c for c in required_cols if c not in df.columns]

    if missing_required:
        raise ValueError(
            f"Missing required delivery columns after normalization: {missing_required}\n"
            f"Available columns: {list(df.columns)}"
        )

    time_col = None
    for c in df.columns:
        if "time_taken" in c or ("time" in c and "taken" in c):
            time_col = c
            break

    if time_col is None:
        raise ValueError(
            f"Could not find delivery time column. Available columns: {list(df.columns)}"
        )

    delivery = pd.DataFrame()

    delivery["source_delivery_id"] = clean_text(df["id"])
    delivery["delivery_person_id"] = clean_text(df["delivery_person_id"])
    delivery["delivery_person_age"] = extract_numeric(df["delivery_person_age"])
    delivery["delivery_person_rating"] = extract_numeric(df["delivery_person_ratings"])

    delivery["restaurant_latitude"] = pd.to_numeric(df["restaurant_latitude"], errors="coerce")
    delivery["restaurant_longitude"] = pd.to_numeric(df["restaurant_longitude"], errors="coerce")
    delivery["delivery_location_latitude"] = pd.to_numeric(df["delivery_location_latitude"], errors="coerce")
    delivery["delivery_location_longitude"] = pd.to_numeric(df["delivery_location_longitude"], errors="coerce")

    delivery["type_of_order"] = clean_text(df["type_of_order"])
    delivery["type_of_vehicle"] = clean_text(df["type_of_vehicle"])
    delivery["total_delivery_time_min"] = extract_numeric(df[time_col])

    # Optional fields if present
    delivery["weather_conditions"] = clean_text(
        df.get("weatherconditions", df.get("weather_conditions", pd.Series(index=df.index)))
    )

    delivery["road_traffic_density"] = clean_text(
        df.get("road_traffic_density", pd.Series(index=df.index))
    )

    delivery["festival"] = clean_text(
        df.get("festival", pd.Series(index=df.index))
    )

    delivery["city_type"] = clean_text(
        df.get("city", pd.Series(index=df.index))
    )

    # Remove rows with invalid coordinates/time
    coordinate_cols = [
        "restaurant_latitude",
        "restaurant_longitude",
        "delivery_location_latitude",
        "delivery_location_longitude",
    ]

    for col in coordinate_cols:
        delivery[col] = pd.to_numeric(delivery[col], errors="coerce")

    delivery = delivery.dropna(
        subset=[
            "restaurant_latitude",
            "restaurant_longitude",
            "delivery_location_latitude",
            "delivery_location_longitude",
            "total_delivery_time_min",
        ]
    ).copy()

    # Drop impossible zero coordinates
    delivery = delivery[
        (delivery["restaurant_latitude"] != 0)
        & (delivery["restaurant_longitude"] != 0)
        & (delivery["delivery_location_latitude"] != 0)
        & (delivery["delivery_location_longitude"] != 0)
    ].copy()

    delivery["distance_km"] = haversine_distance_km(
        delivery["restaurant_latitude"],
        delivery["restaurant_longitude"],
        delivery["delivery_location_latitude"],
        delivery["delivery_location_longitude"],
    )

    # Remove unrealistic records
    delivery = delivery[
        (delivery["total_delivery_time_min"] >= 5)
        & (delivery["total_delivery_time_min"] <= 120)
        & (delivery["distance_km"] > 0)
        & (delivery["distance_km"] <= 50)
    ].copy()

    # Age and rating sanity
    delivery.loc[
        (delivery["delivery_person_age"] < 18)
        | (delivery["delivery_person_age"] > 65),
        "delivery_person_age",
    ] = np.nan

    delivery.loc[
        (delivery["delivery_person_rating"] < 1)
        | (delivery["delivery_person_rating"] > 5),
        "delivery_person_rating",
    ] = np.nan

    delivery["delivery_time_bucket"] = pd.cut(
        delivery["total_delivery_time_min"],
        bins=[0, 25, 40, 55, np.inf],
        labels=["fast", "normal", "slow", "delayed"],
        include_lowest=True,
    ).astype(str)

    delivery["distance_bucket"] = pd.cut(
        delivery["distance_km"],
        bins=[0, 2, 5, 8, np.inf],
        labels=["0-2 km", "2-5 km", "5-8 km", "8+ km"],
        include_lowest=True,
    ).astype(str)

    delivery["delivery_quality_score"] = delivery["delivery_person_rating"] / 5

    delivery = delivery.reset_index(drop=True)
    delivery.insert(0, "delivery_record_id", range(1, len(delivery) + 1))

    final_cols = [
        "delivery_record_id",
        "source_delivery_id",
        "delivery_person_id",
        "delivery_person_age",
        "delivery_person_rating",
        "restaurant_latitude",
        "restaurant_longitude",
        "delivery_location_latitude",
        "delivery_location_longitude",
        "distance_km",
        "distance_bucket",
        "type_of_order",
        "type_of_vehicle",
        "weather_conditions",
        "road_traffic_density",
        "festival",
        "city_type",
        "total_delivery_time_min",
        "delivery_time_bucket",
        "delivery_quality_score",
    ]

    delivery = delivery[final_cols]

    report.append({
        "dataset": "food_delivery_time",
        "check": "raw_rows",
        "value": raw_rows,
    })

    report.append({
        "dataset": "food_delivery_time",
        "check": "cleaned_rows",
        "value": len(delivery),
    })

    report.append({
        "dataset": "food_delivery_time",
        "check": "avg_distance_km",
        "value": round(delivery["distance_km"].mean(), 2),
    })

    report.append({
        "dataset": "food_delivery_time",
        "check": "avg_delivery_time_min",
        "value": round(delivery["total_delivery_time_min"].mean(), 2),
    })

    return delivery, report


def clean_user_preferences() -> tuple[pd.DataFrame, list[dict]]:
    """
    Clean online food delivery preference dataset.
    This dataset is used only as a reference for user segment assumptions.
    """
    report = []

    path = RAW_DIR / "online_food_delivery_preferences.csv"
    raw = read_csv_safe(path)
    raw_rows = len(raw)

    prefs = normalize_columns(raw)

    prefs = prefs.copy()
    prefs.insert(0, "preference_record_id", range(1, len(prefs) + 1))

    if "age" in prefs.columns:
        prefs["age_numeric"] = extract_numeric(prefs["age"])

        prefs["age_band"] = pd.cut(
            prefs["age_numeric"],
            bins=[0, 24, 34, 44, 60, np.inf],
            labels=["18-24", "25-34", "35-44", "45-60", "60+"],
            include_lowest=True,
        ).astype(str)
    else:
        prefs["age_numeric"] = np.nan
        prefs["age_band"] = "unknown"

    if "monthly_income" in prefs.columns:
        income_text = prefs["monthly_income"].astype(str).str.lower()

        prefs["income_proxy"] = "mid"
        prefs.loc[
            income_text.str.contains("no income|below|10000", na=False),
            "income_proxy",
        ] = "low"

        prefs.loc[
            income_text.str.contains("25001|more|above|50000", na=False),
            "income_proxy",
        ] = "premium"
    else:
        prefs["income_proxy"] = "unknown"

    report.append({
        "dataset": "online_food_delivery_preferences",
        "check": "raw_rows",
        "value": raw_rows,
    })

    report.append({
        "dataset": "online_food_delivery_preferences",
        "check": "cleaned_rows",
        "value": len(prefs),
    })

    report.append({
        "dataset": "online_food_delivery_preferences",
        "check": "columns",
        "value": len(prefs.columns),
    })

    return prefs, report


def main():
    all_report_rows = []

    print("Cleaning Zomato Bangalore restaurant dataset...")
    restaurants, report = clean_zomato_restaurants()
    all_report_rows.extend(report)

    restaurants_path = INTERIM_DIR / "cleaned_restaurants.csv"
    restaurants.to_csv(restaurants_path, index=False)

    print(f"Saved: {restaurants_path}")
    print(f"Shape: {restaurants.shape}")
    print(f"Columns: {list(restaurants.columns)}")

    print("\nCleaning food delivery time dataset...")
    delivery, report = clean_delivery_time_base()
    all_report_rows.extend(report)

    delivery_path = INTERIM_DIR / "cleaned_delivery_base.csv"
    delivery.to_csv(delivery_path, index=False)

    print(f"Saved: {delivery_path}")
    print(f"Shape: {delivery.shape}")
    print(f"Columns: {list(delivery.columns)}")

    print("\nCleaning online food delivery preference dataset...")
    preferences, report = clean_user_preferences()
    all_report_rows.extend(report)

    preferences_path = INTERIM_DIR / "cleaned_user_preferences.csv"
    preferences.to_csv(preferences_path, index=False)

    print(f"Saved: {preferences_path}")
    print(f"Shape: {preferences.shape}")
    print(f"Columns: {list(preferences.columns)[:15]}")

    report_df = pd.DataFrame(all_report_rows)
    report_path = INTERIM_DIR / "public_data_cleaning_report.csv"
    report_df.to_csv(report_path, index=False)

    print("\nSaved cleaning report:")
    print(report_df)
    print(f"\nReport path: {report_path}")

    print("\nPublic dataset cleaning complete.")


if __name__ == "__main__":
    main()