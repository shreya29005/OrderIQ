from pathlib import Path
import pandas as pd
import numpy as np


PROCESSED_DIR = Path("data/processed")
REPORT_PATH = PROCESSED_DIR / "data_quality_report.csv"


REQUIRED_FILES = {
    "dim_users": "dim_users.csv",
    "dim_restaurants": "dim_restaurants.csv",
    "fact_sessions": "fact_sessions.csv",
    "fact_search_events": "fact_search_events.csv",
    "fact_cart_events": "fact_cart_events.csv",
    "fact_orders": "fact_orders.csv",
    "fact_delivery_ops": "fact_delivery_ops.csv",
    "fact_refunds": "fact_refunds.csv",
    "fact_ratings": "fact_ratings.csv",
    "daily_marketplace_metrics": "daily_marketplace_metrics.csv",
}


def read_table(filename: str) -> pd.DataFrame:
    path = PROCESSED_DIR / filename
    return pd.read_csv(path)


def add_check(report, check_name, status, failed_rows, severity, notes):
    report.append({
        "check_name": check_name,
        "status": status,
        "failed_rows": int(failed_rows) if pd.notna(failed_rows) else 0,
        "severity": severity,
        "notes": notes,
    })


def status_from_failed(failed_rows: int) -> str:
    return "PASS" if failed_rows == 0 else "FAIL"


def check_file_exists(report):
    for table_name, filename in REQUIRED_FILES.items():
        path = PROCESSED_DIR / filename
        exists = path.exists()
        add_check(
            report,
            f"{table_name}: file exists",
            "PASS" if exists else "FAIL",
            0 if exists else 1,
            "critical",
            str(path),
        )


def check_primary_key(report, df, table_name, pk_col):
    missing = df[pk_col].isna().sum()
    duplicate = df[pk_col].duplicated().sum()

    add_check(
        report,
        f"{table_name}: {pk_col} not null",
        status_from_failed(missing),
        missing,
        "critical",
        f"{pk_col} should never be null.",
    )

    add_check(
        report,
        f"{table_name}: {pk_col} unique",
        status_from_failed(duplicate),
        duplicate,
        "critical",
        f"{pk_col} should be unique.",
    )


def check_foreign_key(report, child_df, parent_df, child_table, parent_table, child_col, parent_col):
    invalid = ~child_df[child_col].isin(parent_df[parent_col])
    failed_rows = invalid.sum()

    add_check(
        report,
        f"{child_table}.{child_col} exists in {parent_table}.{parent_col}",
        status_from_failed(failed_rows),
        failed_rows,
        "critical",
        f"Foreign key validity check from {child_table} to {parent_table}.",
    )


def check_non_negative(report, df, table_name, col, allow_zero=True):
    if allow_zero:
        failed = (df[col] < 0).sum()
        note = f"{col} should be >= 0."
    else:
        failed = (df[col] <= 0).sum()
        note = f"{col} should be > 0."

    add_check(
        report,
        f"{table_name}: {col} valid range",
        status_from_failed(failed),
        failed,
        "high",
        note,
    )


def main():
    report = []

    print("Running data quality checks...")

    check_file_exists(report)

    tables = {}
    for table_name, filename in REQUIRED_FILES.items():
        path = PROCESSED_DIR / filename
        if path.exists():
            tables[table_name] = read_table(filename)
        else:
            tables[table_name] = pd.DataFrame()

    users = tables["dim_users"]
    restaurants = tables["dim_restaurants"]
    sessions = tables["fact_sessions"]
    searches = tables["fact_search_events"]
    carts = tables["fact_cart_events"]
    orders = tables["fact_orders"]
    delivery = tables["fact_delivery_ops"]
    refunds = tables["fact_refunds"]
    ratings = tables["fact_ratings"]
    daily = tables["daily_marketplace_metrics"]

    # Row count checks
    for table_name, df in tables.items():
        failed = 1 if len(df) == 0 else 0
        add_check(
            report,
            f"{table_name}: non-empty table",
            status_from_failed(failed),
            failed,
            "critical",
            f"Row count = {len(df)}",
        )

    # Primary key checks
    check_primary_key(report, users, "dim_users", "user_id")
    check_primary_key(report, restaurants, "dim_restaurants", "restaurant_id")
    check_primary_key(report, sessions, "fact_sessions", "session_id")
    check_primary_key(report, searches, "fact_search_events", "search_id")
    check_primary_key(report, carts, "fact_cart_events", "cart_id")
    check_primary_key(report, orders, "fact_orders", "order_id")

    if len(refunds) > 0:
        check_primary_key(report, refunds, "fact_refunds", "refund_id")

    if len(ratings) > 0:
        check_primary_key(report, ratings, "fact_ratings", "rating_id")

    # Foreign key checks
    check_foreign_key(report, sessions, users, "fact_sessions", "dim_users", "user_id", "user_id")
    check_foreign_key(report, searches, sessions, "fact_search_events", "fact_sessions", "session_id", "session_id")
    check_foreign_key(report, searches, users, "fact_search_events", "dim_users", "user_id", "user_id")
    check_foreign_key(report, carts, sessions, "fact_cart_events", "fact_sessions", "session_id", "session_id")
    check_foreign_key(report, carts, users, "fact_cart_events", "dim_users", "user_id", "user_id")
    check_foreign_key(report, carts, restaurants, "fact_cart_events", "dim_restaurants", "restaurant_id", "restaurant_id")
    check_foreign_key(report, orders, sessions, "fact_orders", "fact_sessions", "session_id", "session_id")
    check_foreign_key(report, orders, carts, "fact_orders", "fact_cart_events", "cart_id", "cart_id")
    check_foreign_key(report, orders, users, "fact_orders", "dim_users", "user_id", "user_id")
    check_foreign_key(report, orders, restaurants, "fact_orders", "dim_restaurants", "restaurant_id", "restaurant_id")
    check_foreign_key(report, delivery, orders, "fact_delivery_ops", "fact_orders", "order_id", "order_id")
    check_foreign_key(report, delivery, restaurants, "fact_delivery_ops", "dim_restaurants", "restaurant_id", "restaurant_id")

    if len(refunds) > 0:
        check_foreign_key(report, refunds, orders, "fact_refunds", "fact_orders", "order_id", "order_id")

    if len(ratings) > 0:
        check_foreign_key(report, ratings, orders, "fact_ratings", "fact_orders", "order_id", "order_id")
        check_foreign_key(report, ratings, users, "fact_ratings", "dim_users", "user_id", "user_id")
        check_foreign_key(report, ratings, restaurants, "fact_ratings", "dim_restaurants", "restaurant_id", "restaurant_id")

    # Order status validity
    valid_order_status = {"delivered", "cancelled"}
    invalid_status = (~orders["order_status"].isin(valid_order_status)).sum()

    add_check(
        report,
        "fact_orders: valid order_status",
        status_from_failed(invalid_status),
        invalid_status,
        "critical",
        "order_status should be either delivered or cancelled.",
    )

    # Delivered orders should have delivery ops
    delivered_orders = orders[orders["order_status"] == "delivered"]
    cancelled_orders = orders[orders["order_status"] == "cancelled"]

    delivered_without_ops = ~delivered_orders["order_id"].isin(delivery["order_id"])
    failed_delivered_without_ops = delivered_without_ops.sum()

    add_check(
        report,
        "delivered orders have delivery ops",
        status_from_failed(failed_delivered_without_ops),
        failed_delivered_without_ops,
        "critical",
        "Every delivered order should have one delivery record.",
    )

    delivery_for_cancelled = delivery["order_id"].isin(cancelled_orders["order_id"])
    failed_delivery_for_cancelled = delivery_for_cancelled.sum()

    add_check(
        report,
        "cancelled orders do not have delivery ops",
        status_from_failed(failed_delivery_for_cancelled),
        failed_delivery_for_cancelled,
        "critical",
        "Cancelled orders should not have completed delivery records.",
    )

    duplicate_delivery_order_id = delivery["order_id"].duplicated().sum()

    add_check(
        report,
        "fact_delivery_ops: one delivery row per delivered order",
        status_from_failed(duplicate_delivery_order_id),
        duplicate_delivery_order_id,
        "critical",
        "Each delivered order should have only one delivery row.",
    )

    # Refunds and ratings should only be linked to delivered orders
    if len(refunds) > 0:
        refund_not_delivered = ~refunds["order_id"].isin(delivered_orders["order_id"])
        failed_refund_not_delivered = refund_not_delivered.sum()

        add_check(
            report,
            "refunds linked only to delivered orders",
            status_from_failed(failed_refund_not_delivered),
            failed_refund_not_delivered,
            "high",
            "Refund records should be linked to delivered orders.",
        )

    if len(ratings) > 0:
        rating_not_delivered = ~ratings["order_id"].isin(delivered_orders["order_id"])
        failed_rating_not_delivered = rating_not_delivered.sum()

        add_check(
            report,
            "ratings linked only to delivered orders",
            status_from_failed(failed_rating_not_delivered),
            failed_rating_not_delivered,
            "high",
            "Ratings should be linked to delivered orders.",
        )

    # Numeric sanity checks
    check_non_negative(report, orders, "fact_orders", "order_value", allow_zero=False)
    check_non_negative(report, orders, "fact_orders", "discount_amount", allow_zero=True)
    check_non_negative(report, orders, "fact_orders", "platform_fee", allow_zero=True)
    check_non_negative(report, orders, "fact_orders", "delivery_fee", allow_zero=True)

    discount_gt_order = (orders["discount_amount"] > orders["order_value"]).sum()

    add_check(
        report,
        "fact_orders: discount_amount <= order_value",
        status_from_failed(discount_gt_order),
        discount_gt_order,
        "high",
        "Discount should not exceed order value.",
    )

    if len(refunds) > 0:
        refunds_with_order = refunds.merge(
            orders[["order_id", "order_value"]],
            on="order_id",
            how="left",
        )

        refund_invalid = (
            (refunds_with_order["refund_amount"] <= 0)
            | (refunds_with_order["refund_amount"] > refunds_with_order["order_value"])
        ).sum()

        add_check(
            report,
            "fact_refunds: refund amount valid",
            status_from_failed(refund_invalid),
            refund_invalid,
            "high",
            "Refund amount should be positive and less than or equal to order value.",
        )

    # Ratings range
    if len(ratings) > 0:
        invalid_food_rating = (~ratings["food_rating"].between(1, 5)).sum()
        invalid_delivery_rating = (~ratings["delivery_rating"].between(1, 5)).sum()

        add_check(
            report,
            "fact_ratings: food_rating between 1 and 5",
            status_from_failed(invalid_food_rating),
            invalid_food_rating,
            "high",
            "food_rating should be between 1 and 5.",
        )

        add_check(
            report,
            "fact_ratings: delivery_rating between 1 and 5",
            status_from_failed(invalid_delivery_rating),
            invalid_delivery_rating,
            "high",
            "delivery_rating should be between 1 and 5.",
        )

    # Delivery time checks
    delivery_time_cols = [
        "prep_time_min",
        "rider_wait_time_min",
        "drop_time_min",
        "total_delivery_time_min",
        "distance_km",
    ]

    for col in delivery_time_cols:
        check_non_negative(report, delivery, "fact_delivery_ops", col, allow_zero=False if col != "rider_wait_time_min" else True)

    component_sum = (
        delivery["prep_time_min"]
        + delivery["rider_wait_time_min"]
        + delivery["drop_time_min"]
    )

    component_mismatch = (np.abs(component_sum - delivery["total_delivery_time_min"]) > 0.05).sum()

    add_check(
        report,
        "fact_delivery_ops: total time equals component sum",
        status_from_failed(component_mismatch),
        component_mismatch,
        "medium",
        "total_delivery_time_min should equal prep + rider_wait + drop time.",
    )

    unrealistic_delivery_time = (
        (delivery["total_delivery_time_min"] < 10)
        | (delivery["total_delivery_time_min"] > 120)
    ).sum()

    add_check(
        report,
        "fact_delivery_ops: realistic delivery time",
        status_from_failed(unrealistic_delivery_time),
        unrealistic_delivery_time,
        "medium",
        "Delivery time should be between 10 and 120 minutes.",
    )

    # Timestamp sanity
    delivery_time_cols_raw = [
        "order_accepted_time",
        "food_ready_time",
        "rider_arrival_time",
        "pickup_time",
        "delivered_time",
    ]

    for col in delivery_time_cols_raw:
        delivery[col] = pd.to_datetime(delivery[col], errors="coerce")

    invalid_timestamp_rows = (
        delivery["order_accepted_time"].isna()
        | delivery["food_ready_time"].isna()
        | delivery["pickup_time"].isna()
        | delivery["delivered_time"].isna()
        | (delivery["food_ready_time"] < delivery["order_accepted_time"])
        | (delivery["pickup_time"] < delivery["order_accepted_time"])
        | (delivery["delivered_time"] < delivery["pickup_time"])
    ).sum()

    add_check(
        report,
        "fact_delivery_ops: timestamp sequence valid",
        status_from_failed(invalid_timestamp_rows),
        invalid_timestamp_rows,
        "high",
        "Delivery timestamps should follow a valid sequence.",
    )

    # Daily metrics checks
    daily["metric_date"] = pd.to_datetime(daily["metric_date"], errors="coerce")

    duplicate_daily_dates = daily["metric_date"].duplicated().sum()

    add_check(
        report,
        "daily_marketplace_metrics: unique metric_date",
        status_from_failed(duplicate_daily_dates),
        duplicate_daily_dates,
        "critical",
        "Daily metrics should have one row per date.",
    )

    invalid_daily_dates = daily["metric_date"].isna().sum()

    add_check(
        report,
        "daily_marketplace_metrics: valid metric_date",
        status_from_failed(invalid_daily_dates),
        invalid_daily_dates,
        "critical",
        "metric_date should be a valid date.",
    )

    # Final report
    report_df = pd.DataFrame(report)

    severity_order = {
        "critical": 1,
        "high": 2,
        "medium": 3,
        "low": 4,
    }

    report_df["severity_order"] = report_df["severity"].map(severity_order)
    report_df = report_df.sort_values(["status", "severity_order", "check_name"])
    report_df = report_df.drop(columns=["severity_order"])

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    report_df.to_csv(REPORT_PATH, index=False)

    print("\nData quality report:")
    print(report_df.to_string(index=False))

    total_checks = len(report_df)
    failed_checks = (report_df["status"] == "FAIL").sum()

    print("\nSummary:")
    print(f"Total checks: {total_checks}")
    print(f"Failed checks: {failed_checks}")
    print(f"Saved report: {REPORT_PATH}")

    if failed_checks > 0:
        print("\nSome checks failed. Review failed rows before moving to SQL.")
    else:
        print("\nAll data quality checks passed.")


if __name__ == "__main__":
    main()