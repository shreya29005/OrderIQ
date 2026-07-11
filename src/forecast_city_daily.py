from pathlib import Path
import numpy as np
import pandas as pd


INPUT_PATH = Path("data/analysis/16_forecast_input_city_daily.csv")

OUTPUT_DIR = Path("data/analysis")
BACKTEST_OUTPUT_PATH = OUTPUT_DIR / "forecast_backtest_city_daily.csv"
FUTURE_FORECAST_OUTPUT_PATH = OUTPUT_DIR / "forecast_next_14_days_city_daily.csv"
SUMMARY_OUTPUT_PATH = OUTPUT_DIR / "forecast_model_summary_city_daily.csv"

TARGET_COL = "delivered_orders"
DATE_COL = "metric_date"
CITY_COL = "city"

FORECAST_HORIZON_DAYS = 14
BACKTEST_HOLDOUT_DAYS = 28


def ensure_output_dir() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def safe_rmse(actual: pd.Series, predicted: pd.Series) -> float:
    actual_arr = actual.astype(float).to_numpy()
    pred_arr = predicted.astype(float).to_numpy()
    return float(np.sqrt(np.mean((actual_arr - pred_arr) ** 2)))


def safe_mae(actual: pd.Series, predicted: pd.Series) -> float:
    actual_arr = actual.astype(float).to_numpy()
    pred_arr = predicted.astype(float).to_numpy()
    return float(np.mean(np.abs(actual_arr - pred_arr)))


def safe_mape(actual: pd.Series, predicted: pd.Series) -> float:
    valid = actual.astype(float) != 0

    if valid.sum() == 0:
        return 0.0

    actual_arr = actual[valid].astype(float).to_numpy()
    pred_arr = predicted[valid].astype(float).to_numpy()

    return float(np.mean(np.abs((actual_arr - pred_arr) / actual_arr)) * 100)


def safe_bias(actual: pd.Series, predicted: pd.Series) -> float:
    actual_arr = actual.astype(float).to_numpy()
    pred_arr = predicted.astype(float).to_numpy()
    return float(np.mean(pred_arr - actual_arr))


def add_baseline_forecasts(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()

    df["forecast_lag_7d"] = df["delivered_orders_lag_7d"].astype(float)
    df["forecast_rolling_7d"] = df["delivered_orders_rolling_7d_avg"].astype(float)
    df["forecast_rolling_14d"] = df["delivered_orders_rolling_14d_avg"].astype(float)
    df["forecast_rolling_28d"] = df["delivered_orders_rolling_28d_avg"].astype(float)

    df["forecast_weighted_baseline"] = (
        0.50 * df["forecast_lag_7d"]
        + 0.30 * df["forecast_rolling_7d"]
        + 0.20 * df["forecast_rolling_28d"]
    )

    forecast_cols = [
        "forecast_lag_7d",
        "forecast_rolling_7d",
        "forecast_rolling_14d",
        "forecast_rolling_28d",
        "forecast_weighted_baseline",
    ]

    for col in forecast_cols:
        df[col] = df[col].clip(lower=0).round(2)

    return df


def build_backtest(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df[DATE_COL] = pd.to_datetime(df[DATE_COL])
    df = df.sort_values([CITY_COL, DATE_COL]).reset_index(drop=True)

    df = add_baseline_forecasts(df)

    max_date = df[DATE_COL].max()
    eval_start_date = max_date - pd.Timedelta(days=BACKTEST_HOLDOUT_DAYS - 1)

    backtest_df = df[
        (df[DATE_COL] >= eval_start_date)
        & (df["delivered_orders_rolling_28d_avg"] > 0)
    ].copy()

    backtest_df["actual_delivered_orders"] = backtest_df[TARGET_COL]

    backtest_df["absolute_error_weighted_baseline"] = (
        backtest_df["actual_delivered_orders"]
        - backtest_df["forecast_weighted_baseline"]
    ).abs()

    backtest_df["percentage_error_weighted_baseline"] = np.where(
        backtest_df["actual_delivered_orders"] == 0,
        0,
        100
        * backtest_df["absolute_error_weighted_baseline"]
        / backtest_df["actual_delivered_orders"],
    ).round(2)

    selected_cols = [
        DATE_COL,
        CITY_COL,
        "day_of_week",
        "weekend_flag",
        "total_sessions",
        "search_events",
        "cart_events",
        "actual_delivered_orders",
        "gross_order_value",
        "avg_order_value",
        "sla_breach_pct",
        "refund_rate_pct",
        "complaint_rate_pct",
        "forecast_lag_7d",
        "forecast_rolling_7d",
        "forecast_rolling_14d",
        "forecast_rolling_28d",
        "forecast_weighted_baseline",
        "absolute_error_weighted_baseline",
        "percentage_error_weighted_baseline",
        "operational_shock_flag",
        "forecast_signal_tier",
    ]

    return backtest_df[selected_cols]


def build_summary(backtest_df: pd.DataFrame) -> pd.DataFrame:
    model_cols = [
        "forecast_lag_7d",
        "forecast_rolling_7d",
        "forecast_rolling_14d",
        "forecast_rolling_28d",
        "forecast_weighted_baseline",
    ]

    rows = []

    for model_col in model_cols:
        actual = backtest_df["actual_delivered_orders"]
        predicted = backtest_df[model_col]

        rows.append(
            {
                "model_name": model_col,
                "evaluation_rows": len(backtest_df),
                "actual_avg_delivered_orders": round(float(actual.mean()), 2),
                "forecast_avg_delivered_orders": round(float(predicted.mean()), 2),
                "mae": round(safe_mae(actual, predicted), 2),
                "rmse": round(safe_rmse(actual, predicted), 2),
                "mape_pct": round(safe_mape(actual, predicted), 2),
                "bias": round(safe_bias(actual, predicted), 2),
            }
        )

    summary_df = pd.DataFrame(rows)

    summary_df["rank_by_mae"] = summary_df["mae"].rank(method="dense").astype(int)

    summary_df = summary_df.sort_values(
        ["rank_by_mae", "mae", "rmse"],
        ascending=[True, True, True],
    ).reset_index(drop=True)

    return summary_df


def estimate_residual_std(backtest_df: pd.DataFrame, model_col: str) -> float:
    if backtest_df.empty:
        return 0.0

    residuals = (
        backtest_df["actual_delivered_orders"]
        - backtest_df[model_col]
    )

    return float(residuals.std(ddof=0))


def build_future_forecast(df: pd.DataFrame, backtest_df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df[DATE_COL] = pd.to_datetime(df[DATE_COL])
    df = df.sort_values([CITY_COL, DATE_COL]).reset_index(drop=True)

    selected_model_col = "forecast_rolling_28d"
    residual_std = estimate_residual_std(backtest_df, selected_model_col)

    future_rows = []

    for city, city_df in df.groupby(CITY_COL):
        city_df = city_df.sort_values(DATE_COL).copy()

        last_date = city_df[DATE_COL].max()

        delivered_history = city_df[TARGET_COL].astype(float).tolist()
        gmv_history = city_df["gross_order_value"].astype(float).tolist()

        day_of_week_means = (
            city_df.groupby("day_of_week_num")[TARGET_COL]
            .mean()
            .to_dict()
        )

        overall_avg = float(city_df[TARGET_COL].mean())

        for horizon_day in range(1, FORECAST_HORIZON_DAYS + 1):
            forecast_date = last_date + pd.Timedelta(days=horizon_day)
            day_of_week_num = int(forecast_date.strftime("%w"))

            day_of_week = forecast_date.day_name()
            weekend_flag = 1 if day_of_week_num in [0, 6] else 0

            lag_1d = delivered_history[-1] if len(delivered_history) >= 1 else overall_avg
            lag_7d = delivered_history[-7] if len(delivered_history) >= 7 else overall_avg

            rolling_7d = float(np.mean(delivered_history[-7:])) if len(delivered_history) >= 7 else overall_avg
            rolling_14d = float(np.mean(delivered_history[-14:])) if len(delivered_history) >= 14 else overall_avg
            rolling_28d = float(np.mean(delivered_history[-28:])) if len(delivered_history) >= 28 else overall_avg

            day_of_week_avg = float(day_of_week_means.get(day_of_week_num, overall_avg))

            base_forecast = rolling_28d

            seasonality_adjustment = 0.90 + 0.10 * (
                day_of_week_avg / overall_avg
            ) if overall_avg > 0 else 1.0

            forecast_delivered_orders = base_forecast * seasonality_adjustment
            forecast_delivered_orders = max(0, forecast_delivered_orders)

            rounded_forecast = round(forecast_delivered_orders, 2)

            lower_bound = max(0, rounded_forecast - 1.28 * residual_std)
            upper_bound = rounded_forecast + 1.28 * residual_std

            avg_gmv_per_order = (
                float(np.mean(gmv_history[-28:])) / rolling_28d
                if rolling_28d > 0 and len(gmv_history) >= 28
                else float(city_df["avg_order_value"].replace(0, np.nan).mean())
            )

            if np.isnan(avg_gmv_per_order):
                avg_gmv_per_order = 0.0

            forecast_gross_order_value = rounded_forecast * avg_gmv_per_order

            future_rows.append(
                {
                    "forecast_date": forecast_date.date(),
                    "city": city,
                    "horizon_day": horizon_day,
                    "day_of_week_num": day_of_week_num,
                    "day_of_week": day_of_week,
                    "weekend_flag": weekend_flag,
                    "delivered_orders_lag_1d": round(lag_1d, 2),
                    "delivered_orders_lag_7d": round(lag_7d, 2),
                    "delivered_orders_rolling_7d_avg": round(rolling_7d, 2),
                    "delivered_orders_rolling_14d_avg": round(rolling_14d, 2),
                    "delivered_orders_rolling_28d_avg": round(rolling_28d, 2),
                    "forecast_delivered_orders": rounded_forecast,
                    "forecast_delivered_orders_lower_bound": round(lower_bound, 2),
                    "forecast_delivered_orders_upper_bound": round(upper_bound, 2),
                    "forecast_gross_order_value": round(forecast_gross_order_value, 2),
                    "forecast_model": "rolling_28d_baseline",
                }
            )

            delivered_history.append(rounded_forecast)
            gmv_history.append(forecast_gross_order_value)

    return pd.DataFrame(future_rows)


def main() -> None:
    ensure_output_dir()

    if not INPUT_PATH.exists():
        raise FileNotFoundError(
            f"Input file not found: {INPUT_PATH}. "
            "Run sql/16_forecast_input_city_daily.sql first."
        )

    df = pd.read_csv(INPUT_PATH)

    required_cols = [
        DATE_COL,
        CITY_COL,
        TARGET_COL,
        "gross_order_value",
        "avg_order_value",
        "delivered_orders_lag_1d",
        "delivered_orders_lag_7d",
        "delivered_orders_rolling_7d_avg",
        "delivered_orders_rolling_14d_avg",
        "delivered_orders_rolling_28d_avg",
    ]

    missing_cols = [col for col in required_cols if col not in df.columns]

    if missing_cols:
        raise ValueError(f"Missing required columns: {missing_cols}")

    backtest_df = build_backtest(df)
    summary_df = build_summary(backtest_df)
    future_forecast_df = build_future_forecast(df, backtest_df)

    backtest_df.to_csv(BACKTEST_OUTPUT_PATH, index=False)
    summary_df.to_csv(SUMMARY_OUTPUT_PATH, index=False)
    future_forecast_df.to_csv(FUTURE_FORECAST_OUTPUT_PATH, index=False)

    print("City daily forecast completed.")
    print(f"Input rows: {len(df)}")
    print(f"Backtest rows: {len(backtest_df)}")
    print(f"Future forecast rows: {len(future_forecast_df)}")

    print()
    print("Saved files:")
    print(f"- {BACKTEST_OUTPUT_PATH}")
    print(f"- {SUMMARY_OUTPUT_PATH}")
    print(f"- {FUTURE_FORECAST_OUTPUT_PATH}")

    print()
    print("Model summary:")
    print(summary_df.to_string(index=False))

    print()
    print("Future forecast preview:")
    print(future_forecast_df.head(14).to_string(index=False))


if __name__ == "__main__":
    main()