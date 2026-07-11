import re
from html import escape
from pathlib import Path

import pandas as pd
import plotly.express as px
import streamlit as st


BASE_DIR = Path(__file__).resolve().parents[1]
ANALYSIS_DIR = BASE_DIR / "data" / "analysis"


FILES = {
    "funnel": "01_funnel_conversion.csv",
    "cohort": "02_cohort_retention.csv",
    "delivery": "03_delivery_p90.csv",
    "restaurant_quality": "04_restaurant_quality_score.csv",
    "discount": "05_discount_efficiency.csv",
    "sla_root": "06_sla_root_cause.csv",
    "user_segments": "07_order_frequency_segments.csv",
    "cuisine": "08_repeat_rate_by_cuisine.csv",
    "restaurant_anomaly": "09_refund_anomaly_restaurants.csv",
    "first_order": "10_first_order_experience_retention.csv",
    "marketplace": "11_city_zone_marketplace_score.csv",
    "search_quality": "12_search_result_quality.csv",
    "visibility": "13_restaurant_visibility_opportunity.csv",
    "hourly_heatmap": "14_delivery_time_hourly_heatmap.csv",
    "city_forecast_input": "16_forecast_input_city_daily.csv",
    "forecast_summary": "forecast_model_summary_city_daily.csv",
    "forecast_backtest": "forecast_backtest_city_daily.csv",
    "forecast_future": "forecast_next_14_days_city_daily.csv",
}


TONE_COLORS = {
    "risk": "#ff5c5c",
    "opportunity": "#4da3ff",
    "growth": "#36c486",
    "neutral": "#9ca3af",
}


# Exact display overrides for column / axis / legend names.
LABELS = {
    "zone": "Zone",
    "city": "City",
    "marketplace_health_score": "Marketplace Health Score",
    "marketplace_health_tier": "Marketplace Health Tier",
    "search_quality_tier": "Search Quality Tier",
    "search_quality_tier_display": "Search Quality Tier",
    "user_count": "Users",
    "order_frequency_segment": "Order Frequency Segment",
    "order_frequency_segment_display": "Order Frequency Segment",
    "model_name": "Forecast Model",
    "model_name_display": "Forecast Model",
    "mae": "MAE",
    "mape_pct": "MAPE %",
    "stage": "Stage",
    "volume": "Volume",
    "d30_retention_pct": "D30 Retention %",
    "d30_retention": "D30 Retention %",
    "first_experience_tier": "First Experience Tier",
    "first_experience_tier_display": "First Experience Tier",
    "repeat_rate": "Repeat Rate %",
    "users": "Users",
    "new_ordering_users": "New Ordering Users",
    "d30_retained_users": "D30 Retained Users",
    "user_segment": "User Segment",
    "user_segment_display": "User Segment",
    "session_to_delivery_conversion_pct": "Session to Delivery %",
    "recommended_action": "Recommended Action",
    "recommended_action_display": "Recommended Action",
    "root_cause_driver": "Root Cause Driver",
    "root_cause_driver_display": "Root Cause Driver",
    "hourly_risk_tier": "Hourly Risk Tier",
    "hourly_risk_tier_display": "Hourly Risk Tier",
    "hourly_operational_risk_score": "Operational Risk Score",
    "low_result_search_rate_pct": "Low Result Search %",
    "search_click_rate_pct": "Search Click %",
    "refund_rate_pct": "Refund %",
    "complaint_rate_pct": "Complaint %",
    "visibility_score": "Visibility Score",
    "visibility_opportunity_tier": "Visibility Opportunity Tier",
    "visibility_opportunity_tier_display": "Visibility Opportunity Tier",
    "restaurant_quality_score": "Restaurant Quality Score",
    "repeat_customer_rate_pct": "Repeat Customer %",
    "cuisine_price_segment": "Cuisine / Price Segment",
    "cuisine_stickiness_tier": "Cuisine Stickiness Tier",
    "cuisine_stickiness_tier_display": "Cuisine Stickiness Tier",
    "delivered_orders": "Delivered Orders",
    "actual_delivered_orders": "Actual Delivered Orders",
    "forecast_rolling_28d": "Rolling 28-Day Baseline",
    "forecast_weighted_baseline": "Weighted Baseline",
    "forecast_delivered_orders": "Forecast Delivered Orders",
    "forecast_delivered_orders_lower_bound": "Lower Bound",
    "forecast_delivered_orders_upper_bound": "Upper Bound",
    "value": "Orders",
    "variable": "Series",
    "count": "Count",
    "total_searches": "Total Searches",
    "avg_result_count": "Avg Result Count",
    "delivered_after_search_rate_pct": "Delivered After Search %",
    "search_quality_score": "Search Quality Score",
    "search_query": "Search Query",
    "total_orders": "Total Orders",
    "p90_delivery_time_min": "P90 Delivery Time (min)",
    "sla_breach_pct": "SLA Breach %",
    "meal_period": "Meal Period",
    "day_of_week": "Day of Week",
    "order_hour": "Order Hour",
    "anomaly_score": "Anomaly Score",
    "anomaly_tier": "Anomaly Tier",
    "underexposure_opportunity_score": "Opportunity Score",
    "confidence_tier": "Confidence",
    "restaurant_name": "Restaurant",
    "primary_cuisine": "Cuisine",
    "price_band": "Price Band",
    "recency_tier": "Recency Tier",
    "acquisition_channel": "Acquisition Channel",
    "repeat_user_rate_pct": "Repeat User %",
    "avg_orders_per_ordering_user": "Avg Orders per User",
    "recommended_product_action": "Recommended Action",
    "metric_date": "Date",
    "forecast_date": "Date",
    "cohort_month": "Cohort Month",
    "forecast_model": "Forecast Model",
    "forecast_gross_order_value": "Forecast GMV",
    "rank_by_mae": "Rank",
    "rmse": "RMSE",
    "bias": "Bias",
}


# Short KPI-only labels for forecast model codes, used where a full label would
# truncate inside a metric-style tile.
SHORT_VALUE_LABELS = {
    "forecast_rolling_28d": "Rolling 28D",
    "forecast_rolling_14d": "Rolling 14D",
    "forecast_rolling_7d": "Rolling 7D",
    "forecast_weighted_baseline": "Weighted",
    "forecast_lag_7d": "7D Lag",
    "rolling_28d_baseline": "Rolling 28D",
}


# Display names for the forecast backtest legend, matching the shorter "28D" style
# used across KPI tiles rather than the full "28-Day" wording used in tables.
BACKTEST_DISPLAY_COLUMNS = {
    "metric_date": "Date",
    "actual_delivered_orders": "Actual Delivered Orders",
    "forecast_rolling_28d": "Rolling 28D Baseline",
    "forecast_weighted_baseline": "Weighted Baseline",
}

FUTURE_DISPLAY_COLUMNS = {
    "forecast_date": "Date",
    "forecast_delivered_orders": "Forecast Delivered Orders",
    "forecast_delivered_orders_lower_bound": "Lower Bound",
    "forecast_delivered_orders_upper_bound": "Upper Bound",
}


# Exact display overrides for categorical values that need special-cased wording
# (numbered tiers, forecast model codes) beyond generic underscore cleanup.
VALUE_LABELS = {
    "0_no_order_yet": "No Order Yet",
    "1_one_time_orderer": "One-Time Orderer",
    "2_occasional_2_orders": "Occasional: 2 Orders",
    "3_regular_3_4_orders": "Regular: 3–4 Orders",
    "4_loyal_5_plus_orders": "Loyal: 5+ Orders",
    "1_active_last_30_days": "Active: Last 30 Days",
    "2_cooling_31_60_days": "Cooling: 31–60 Days",
    "3_dormant_60_plus_days": "Dormant: 60+ Days",
    "1_strong_first_experience": "Strong First Experience",
    "2_neutral_first_experience": "Neutral First Experience",
    "3_poor_first_experience": "Poor First Experience",
    "high_quality_underexposed": "High-Quality Underexposed",
    "maintain_and_scale": "Maintain and Scale",
    "forecast_rolling_28d": "Rolling 28-Day Baseline",
    "forecast_rolling_14d": "Rolling 14-Day Baseline",
    "forecast_rolling_7d": "Rolling 7-Day Baseline",
    "forecast_weighted_baseline": "Weighted Baseline",
    "forecast_lag_7d": "7-Day Lag Baseline",
    "rolling_28d_baseline": "Rolling 28-Day Baseline",
    "low_confidence": "Low Confidence",
    "medium_confidence": "Medium Confidence",
    "high_confidence": "High Confidence",
    "add_peak_ops_capacity": "Add Peak Ops Capacity",
}


_ABBREVIATIONS = {"sla", "gmv", "eta", "mae", "rmse", "mape", "p90", "d30", "d7", "kpi"}
_CONNECTORS = {"and", "to", "of", "or", "in", "on", "at", "for", "vs", "the"}
_NUMERIC_PREFIX_RE = re.compile(r"^[0-9]+_")
_DAY_TOKEN_RE = re.compile(r"^([0-9]+)d$")
_IDENTIFIER_RE = re.compile(r"^[0-9]+_[a-z0-9]+(?:[ _][a-z0-9]+)*$|^[a-z0-9]+(?:[ _][a-z0-9]+)*$")


st.set_page_config(
    page_title="OrderIQ Marketplace Analytics",
    page_icon="📊",
    layout="wide",
)


@st.cache_data
def load_csv(filename: str) -> pd.DataFrame:
    path = ANALYSIS_DIR / filename

    if not path.exists():
        return pd.DataFrame()

    df = pd.read_csv(path)

    date_columns = [
        "metric_date",
        "forecast_date",
        "cohort_month",
        "first_order_month",
        "order_date",
        "search_date",
    ]

    for col in date_columns:
        if col in df.columns:
            try:
                df[col] = pd.to_datetime(df[col])
            except Exception:
                pass

    return df


def load_all_data() -> dict:
    return {name: load_csv(filename) for name, filename in FILES.items()}


def metric_card(label: str, value, help_text: str | None = None):
    st.metric(label, value, help=help_text)


def show_missing_files(data: dict):
    missing = []

    for name, filename in FILES.items():
        if data[name].empty:
            missing.append(filename)

    if missing:
        st.warning(
            "Some analysis files are missing. Run the SQL/scripts that create these files:\n\n"
            + "\n".join([f"- `{file}`" for file in missing])
        )


def safe_mean(df: pd.DataFrame, col: str) -> float:
    if df.empty or col not in df.columns:
        return 0.0

    numeric_series = pd.to_numeric(df[col], errors="coerce")

    if numeric_series.dropna().empty:
        return 0.0

    return round(float(numeric_series.mean()), 2)


def safe_sum(df: pd.DataFrame, col: str) -> float:
    if df.empty or col not in df.columns:
        return 0.0
    return round(float(df[col].sum()), 2)


def weighted_pct(numerator, denominator) -> float:
    if not denominator:
        return 0.0
    return round(100 * float(numerator) / float(denominator), 2)


def add_confidence_tier(df: pd.DataFrame, order_col: str = "delivered_orders") -> pd.DataFrame:
    if df.empty or order_col not in df.columns:
        return df

    df = df.copy()
    orders = pd.to_numeric(df[order_col], errors="coerce")

    def tier(value):
        if pd.isna(value) or value < 5:
            return "low_confidence"
        if value < 10:
            return "medium_confidence"
        return "high_confidence"

    df["confidence_tier"] = orders.apply(tier)
    return df


def _humanize_token(token: str, is_first: bool) -> str:
    lowered = token.lower()

    day_match = _DAY_TOKEN_RE.match(lowered)
    if day_match:
        return f"{day_match.group(1)}-Day"

    if lowered == "pct":
        return "%"

    if lowered == "plus":
        return "+"

    if lowered in _ABBREVIATIONS:
        return lowered.upper()

    if not is_first and lowered in _CONNECTORS:
        return lowered

    return token.capitalize()


def _humanize(text: str) -> str:
    stripped = _NUMERIC_PREFIX_RE.sub("", text)
    tokens = [tok for tok in re.split(r"[ _]+", stripped) if tok]

    if not tokens:
        return text

    words = [_humanize_token(tok, idx == 0) for idx, tok in enumerate(tokens)]
    result = " ".join(words)

    return result[0].upper() + result[1:] if result else result


def pretty_label(text) -> str:
    """Convert a snake_case column/axis name into a readable dashboard label."""
    if text is None:
        return ""

    key = str(text).strip()

    if not key:
        return key

    if key in LABELS:
        return LABELS[key]

    if key in VALUE_LABELS:
        return VALUE_LABELS[key]

    return _humanize(key)


def pretty_value(value):
    """Convert a snake_case categorical value into readable dashboard text."""
    if not isinstance(value, str):
        return value

    key = value.strip()

    if key in VALUE_LABELS:
        return VALUE_LABELS[key]

    if key in LABELS:
        return LABELS[key]

    if _IDENTIFIER_RE.fullmatch(key):
        return _humanize(key)

    return value


def pretty_value_short(value):
    """Like pretty_value, but uses a shortened form for KPI tiles that would truncate."""
    if not isinstance(value, str):
        return value

    key = value.strip()

    if key in SHORT_VALUE_LABELS:
        return SHORT_VALUE_LABELS[key]

    return pretty_value(value)


def pretty_df(df: pd.DataFrame) -> pd.DataFrame:
    """Return a display copy of df with human-readable columns/values. Never mutates df."""
    if df.empty:
        return df

    display_df = df.copy()

    for col in display_df.columns:
        if pd.api.types.is_datetime64_any_dtype(display_df[col]):
            display_df[col] = display_df[col].dt.strftime("%Y-%m-%d")
        elif display_df[col].dtype == object:
            display_df[col] = display_df[col].apply(pretty_value)

    display_df.columns = [pretty_label(col) for col in display_df.columns]

    return display_df


def format_display_df(df: pd.DataFrame) -> pd.DataFrame:
    """Format numeric values for presentation: 2 decimals for floats, plain
    integers for whole-number columns. Leaves already-formatted text (dates,
    categories) untouched. Never mutates df."""
    if df.empty:
        return df

    formatted_df = df.copy()

    for col in formatted_df.columns:
        series = formatted_df[col]

        if pd.api.types.is_bool_dtype(series):
            continue

        if pd.api.types.is_float_dtype(series):
            formatted_df[col] = series.apply(lambda v: f"{v:,.2f}" if pd.notna(v) else v)
        elif pd.api.types.is_integer_dtype(series):
            formatted_df[col] = series.apply(lambda v: f"{v:,}" if pd.notna(v) else v)

    return formatted_df


def apply_pretty_labels(fig):
    """Clean up axis/legend/colorbar titles on a Plotly figure as a safety net."""
    try:
        if fig.layout.xaxis and fig.layout.xaxis.title and fig.layout.xaxis.title.text:
            fig.update_xaxes(title_text=pretty_label(fig.layout.xaxis.title.text))
    except Exception:
        pass

    try:
        if fig.layout.yaxis and fig.layout.yaxis.title and fig.layout.yaxis.title.text:
            fig.update_yaxes(title_text=pretty_label(fig.layout.yaxis.title.text))
    except Exception:
        pass

    try:
        if fig.layout.legend and fig.layout.legend.title and fig.layout.legend.title.text:
            fig.update_layout(legend_title_text=pretty_label(fig.layout.legend.title.text))
    except Exception:
        pass

    try:
        colorbar = fig.layout.coloraxis.colorbar
        if colorbar and colorbar.title and colorbar.title.text:
            fig.update_coloraxes(colorbar_title_text=pretty_label(colorbar.title.text))
    except Exception:
        pass

    return fig


def insight_card(
    title: str,
    evidence: str,
    action: str,
    impact: str | None = None,
    tag: str | None = None,
    tone: str = "neutral",
):
    accent = TONE_COLORS.get(tone, TONE_COLORS["neutral"])

    parts = [
        f'<div style="background-color:rgba(255,255,255,0.035); '
        f'border:1px solid rgba(255,255,255,0.12); border-left:4px solid {accent}; '
        f'border-radius:8px; padding:14px 16px; min-height:150px; height:100%; '
        f'margin-bottom:10px; box-sizing:border-box; display:flex; '
        f'flex-direction:column; justify-content:flex-start; overflow-wrap:break-word; '
        f'word-break:break-word;">'
    ]

    if tag:
        parts.append(
            f'<div style="font-size:0.7rem; font-weight:700; letter-spacing:0.05em; '
            f'text-transform:uppercase; color:{accent}; margin-bottom:6px;">'
            f'{escape(str(tag))}</div>'
        )

    parts.append(
        f'<div style="font-weight:600; font-size:0.94rem; line-height:1.38; '
        f'margin-bottom:6px;">{escape(str(title))}</div>'
    )
    parts.append(
        f'<div style="font-size:0.82rem; line-height:1.38;">'
        f'<b>Evidence:</b> {escape(str(evidence))}</div>'
    )
    parts.append(
        f'<div style="font-size:0.82rem; line-height:1.38; margin-top:4px;">'
        f'<b>Action:</b> {escape(str(action))}</div>'
    )

    if impact:
        parts.append(
            f'<div style="font-size:0.82rem; line-height:1.38; margin-top:4px;">'
            f'<b>Impact:</b> {escape(str(impact))}</div>'
        )

    parts.append("</div>")

    card_html = "".join(parts)
    st.markdown(card_html, unsafe_allow_html=True)


def insight_row(cards: list[dict]):
    if not cards:
        return

    if len(cards) == 1:
        insight_card(**cards[0])
        return

    # Stretch each column to the row's tallest card so uneven text lengths
    # do not leave shorter cards looking clipped or misaligned.
    st.markdown(
        '<style>'
        'div[data-testid="stHorizontalBlock"] { align-items: stretch; }'
        'div[data-testid="column"] { display: flex; }'
        'div[data-testid="column"] > div { width: 100%; }'
        '</style>',
        unsafe_allow_html=True,
    )

    columns = st.columns(len(cards))

    for column, card in zip(columns, cards):
        with column:
            insight_card(**card)


def compact_table(
    title: str,
    df: pd.DataFrame,
    columns: list[str],
    max_rows: int = 5,
    sort_by: str | None = None,
    ascending: bool = True,
):
    st.write(title)

    if df.empty:
        st.info("No data available for this table.")
        return

    if sort_by and sort_by in df.columns:
        df = df.sort_values(sort_by, ascending=ascending)

    available_columns = [col for col in columns if col in df.columns]

    if not available_columns:
        st.info("Expected columns are not available in this dataset.")
        return

    display_df = format_display_df(pretty_df(df[available_columns].head(max_rows)))
    # A static table avoids the scroll/toolbar chrome of st.dataframe, which reads
    # better in screenshots and PDF export for a decision-summary table this small.
    display_df.index = [""] * len(display_df)
    st.table(display_df)


def executive_overview(data: dict):
    st.subheader("Executive Overview")

    marketplace = data["marketplace"]
    forecast_future = data["forecast_future"]
    forecast_summary = data["forecast_summary"]
    user_segments = data["user_segments"]
    search_quality = data["search_quality"]

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        metric_card(
            "Total Delivered Orders",
            f"{int(safe_sum(marketplace, 'delivered_orders')):,}",
        )

    with col2:
        metric_card(
            "Marketplace GMV",
            f"₹{safe_sum(marketplace, 'gross_order_value'):,.0f}",
        )

    with col3:
        metric_card(
            "Avg Zone Health Score",
            safe_mean(marketplace, "marketplace_health_score"),
        )

    with col4:
        metric_card(
            "14-Day Forecast Avg Orders",
            safe_mean(forecast_future, "forecast_delivered_orders"),
        )

    st.divider()

    cards = []

    if not marketplace.empty:
        avg_health = safe_mean(marketplace, "marketplace_health_score")
        weak_zones = int((marketplace["marketplace_health_score"] < 60).sum())

        cards.append(
            dict(
                title="Marketplace health is uneven across zones",
                evidence=f"Average zone health score is {avg_health}, with {weak_zones} "
                "zone(s) scoring below 60.",
                action="Prioritize needs-attention zones before scaling stronger zones.",
                impact="Improves conversion, reliability, and customer experience.",
                tag="Marketplace",
                tone="risk",
            )
        )

    if not search_quality.empty and "search_quality_tier" in search_quality.columns:
        weak_mask = search_quality["search_quality_tier"].isin(
            ["weak_search_experience", "broken_search_experience"]
        )
        weak_count = int(weak_mask.sum())
        weak_share = weighted_pct(weak_count, len(search_quality))
        depth_count = 0
        if "recommended_action" in search_quality.columns:
            depth_count = int(
                (search_quality["recommended_action"] == "improve_result_depth").sum()
            )

        cards.append(
            dict(
                title="Search quality is strong overall, but result-depth gaps remain",
                evidence=f"{weak_count} row(s) ({weak_share}% of rows) are weak or broken "
                f"search experiences, and {depth_count} are flagged "
                f"{pretty_value('improve_result_depth')}.",
                action="Focus on query-zone pairs where result depth is weak.",
                impact="Improves search-to-click and search-to-order conversion.",
                tag="Discovery",
                tone="opportunity",
            )
        )

    if not forecast_summary.empty:
        best_model_row = forecast_summary.sort_values("rank_by_mae").iloc[0]
        best_model_display = pretty_value(best_model_row["model_name"])

        cards.append(
            dict(
                title="Rolling baseline is the strongest planning model",
                evidence=f"{best_model_display} has the best backtest fit: MAE "
                f"{best_model_row['mae']}, MAPE {best_model_row['mape_pct']}%.",
                action="Use the city-day forecast for short-term demand planning.",
                impact="Supports rider planning and GMV expectation-setting.",
                tag="Planning",
                tone="growth",
            )
        )

    insight_row(cards)

    st.divider()

    col1, col2 = st.columns(2)

    with col1:
        if not marketplace.empty:
            bottom_zones = marketplace.sort_values("marketplace_health_score").head(10)

            fig = px.bar(
                bottom_zones,
                x="zone",
                y="marketplace_health_score",
                title="Bottom 10 Zones by Marketplace Health Score",
                hover_data=[
                    "delivered_orders",
                    "session_to_delivery_conversion_pct",
                    "sla_breach_pct",
                    "refund_rate_pct",
                    "complaint_rate_pct",
                    "recommended_action",
                ],
                labels=LABELS,
            )
            fig.update_layout(xaxis_tickangle=-45)
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        if not search_quality.empty:
            tier_counts = (
                search_quality["search_quality_tier"]
                .value_counts()
                .reset_index()
            )
            tier_counts.columns = ["search_quality_tier", "count"]
            tier_counts["search_quality_tier_display"] = tier_counts[
                "search_quality_tier"
            ].apply(pretty_value)

            fig = px.pie(
                tier_counts,
                names="search_quality_tier_display",
                values="count",
                title="Search Quality Tier Mix",
                labels=LABELS,
            )
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    col1, col2 = st.columns(2)

    with col1:
        if not user_segments.empty:
            segment_summary = (
                user_segments.groupby("order_frequency_segment", as_index=False)
                .agg(user_count=("user_count", "sum"))
                .sort_values("order_frequency_segment")
            )
            segment_summary["order_frequency_segment_display"] = segment_summary[
                "order_frequency_segment"
            ].apply(pretty_value)

            fig = px.bar(
                segment_summary,
                x="order_frequency_segment_display",
                y="user_count",
                title="User Order-Frequency Segments",
                labels=LABELS,
            )
            fig.update_layout(xaxis_tickangle=-30)
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        if not forecast_summary.empty:
            forecast_display = forecast_summary.copy()
            forecast_display["model_name_display"] = forecast_display["model_name"].apply(
                pretty_value
            )

            fig = px.bar(
                forecast_display.sort_values("rank_by_mae"),
                x="model_name_display",
                y="mae",
                title="Forecast Model Backtest MAE",
                labels=LABELS,
            )
            fig.update_layout(xaxis_tickangle=-30)
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)


def funnel_tab(data: dict):
    st.subheader("Funnel and Retention")

    funnel = data["funnel"]
    cohort = data["cohort"]
    first_order = data["first_order"]
    user_segments = data["user_segments"]

    funnel_summary = pd.DataFrame()

    if not funnel.empty:
        col1, col2, col3, col4 = st.columns(4)

        # Weighted totals so these KPIs match the funnel chart's volumes below,
        # instead of averaging per-zone/device conversion rates (which skews
        # toward low-volume rows and can disagree with the chart's totals).
        with col1:
            metric_card(
                "Overall Session → Delivery %",
                weighted_pct(safe_sum(funnel, "delivered_orders"), safe_sum(funnel, "app_opens")),
            )

        with col2:
            metric_card(
                "Overall Search → Click %",
                weighted_pct(safe_sum(funnel, "restaurant_clicks"), safe_sum(funnel, "searches")),
            )

        with col3:
            metric_card(
                "Overall Cart → Payment %",
                weighted_pct(safe_sum(funnel, "payments"), safe_sum(funnel, "carts")),
            )

        with col4:
            if "low_result_sessions" in funnel.columns and "searches" in funnel.columns:
                low_result_pct = weighted_pct(
                    safe_sum(funnel, "low_result_sessions"), safe_sum(funnel, "searches")
                )
            else:
                low_result_col = (
                    "low_result_search_session_pct"
                    if "low_result_search_session_pct" in funnel.columns
                    else "zero_result_search_session_pct"
                )
                low_result_pct = safe_mean(funnel, low_result_col)

            metric_card("Avg Low Result Search %", low_result_pct)

        funnel_summary = pd.DataFrame(
            {
                "stage": [
                    "App Opens",
                    "Searches",
                    "Restaurant Clicks",
                    "Carts",
                    "Payments",
                    "Delivered Sessions",
                ],
                "volume": [
                    safe_sum(funnel, "app_opens"),
                    safe_sum(funnel, "searches"),
                    safe_sum(funnel, "restaurant_clicks"),
                    safe_sum(funnel, "carts"),
                    safe_sum(funnel, "payments"),
                    safe_sum(funnel, "delivered_orders"),
                ],
            }
        )

    cohort_summary = pd.DataFrame()

    if not cohort.empty:
        cohort_summary = cohort.groupby(
            ["cohort_month", "user_segment"], as_index=False
        ).agg(
            new_ordering_users=("new_ordering_users", "sum"),
            d30_retained_users=("d30_retained_users", "sum"),
        )
        cohort_summary["d30_retention_pct"] = cohort_summary.apply(
            lambda row: weighted_pct(row["d30_retained_users"], row["new_ordering_users"]),
            axis=1,
        )
        cohort_summary["user_segment_display"] = cohort_summary["user_segment"].apply(
            pretty_value
        )

    first_order_summary = pd.DataFrame()

    if not first_order.empty:
        first_order_summary = first_order.groupby(
            "first_experience_tier", as_index=False
        ).agg(
            users=("new_ordering_users", "sum"),
            repeat_users=("repeat_users", "sum"),
            d30_users=("d30_retained_users", "sum"),
        )
        first_order_summary["repeat_rate"] = first_order_summary.apply(
            lambda row: weighted_pct(row["repeat_users"], row["users"]), axis=1
        )
        first_order_summary["d30_retention"] = first_order_summary.apply(
            lambda row: weighted_pct(row["d30_users"], row["users"]), axis=1
        )
        first_order_summary["first_experience_tier_display"] = first_order_summary[
            "first_experience_tier"
        ].apply(pretty_value)

    st.divider()

    cards = []

    if not funnel_summary.empty:
        diffs = funnel_summary["volume"].diff()
        drop_stage_idx = diffs.idxmin()
        drop_from = funnel_summary.loc[drop_stage_idx - 1, "stage"]
        drop_to = funnel_summary.loc[drop_stage_idx, "stage"]
        drop_volume = abs(diffs.min())

        cards.append(
            dict(
                title="Biggest funnel drop-off",
                evidence=f"The largest volume loss happens between {drop_from} and "
                f"{drop_to}, a drop of roughly {drop_volume:,.0f}.",
                action=f"Focus conversion work on the {drop_from} to {drop_to} transition first.",
                tone="risk",
            )
        )

    if not first_order_summary.empty:
        sorted_tiers = first_order_summary.sort_values("repeat_rate", ascending=False)
        best_tier = sorted_tiers.iloc[0]
        worst_tier = sorted_tiers.iloc[-1]
        gap = round(best_tier["repeat_rate"] - worst_tier["repeat_rate"], 2)
        lift_word = "directional lift" if gap < 10 else "major driver"

        cards.append(
            dict(
                title="First-order experience has directional retention lift",
                evidence=f"Users with {best_tier['first_experience_tier_display']} show a "
                f"{best_tier['repeat_rate']}% repeat rate, versus {worst_tier['repeat_rate']}% "
                f"for {worst_tier['first_experience_tier_display']} — a {gap} point "
                f"{lift_word}.",
                action="Protect first-order delivery and food experience quality.",
                tone="opportunity",
            )
        )

    if not user_segments.empty and "order_frequency_segment" in user_segments.columns:
        one_time_mask = user_segments["order_frequency_segment"].astype(str).str.contains(
            "one_time|single|new|no_order", case=False, regex=True
        )
        opportunity_users = int(user_segments.loc[one_time_mask, "user_count"].sum())

        cards.append(
            dict(
                title="Activation opportunity",
                evidence=f"Roughly {opportunity_users:,} users sit in no-order or "
                "one-time-order segments.",
                action="Target activation and second-order nudges for these segments.",
                tone="growth",
            )
        )

    insight_row(cards)

    st.divider()

    if not funnel_summary.empty:
        fig = px.funnel(
            funnel_summary,
            x="volume",
            y="stage",
            title="Marketplace Funnel",
            labels=LABELS,
        )
        fig = apply_pretty_labels(fig)
        st.plotly_chart(fig, use_container_width=True)
        st.caption(
            "Funnel volumes are session-based. Executive total delivered orders is "
            "order-based, so the numbers can differ slightly."
        )

    col1, col2 = st.columns(2)

    with col1:
        if not cohort_summary.empty:
            fig = px.bar(
                cohort_summary,
                x="cohort_month",
                y="d30_retention_pct",
                color="user_segment_display",
                title="D30 Retention by Cohort and Segment",
                hover_data=["new_ordering_users", "d30_retained_users"],
                labels=LABELS,
            )
            fig.update_layout(barmode="group")
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        if not first_order_summary.empty:
            fig = px.bar(
                first_order_summary,
                x="first_experience_tier_display",
                y="repeat_rate",
                title="Repeat Rate by First-Order Experience",
                hover_data=["users", "d30_retention"],
                labels=LABELS,
            )
            fig.update_layout(xaxis_tickangle=-30)
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    if not user_segments.empty:
        compact_table(
            "Largest User Activation Segments",
            user_segments,
            [
                "order_frequency_segment",
                "recency_tier",
                "user_segment",
                "acquisition_channel",
                "user_count",
                "recommended_product_action",
            ],
            max_rows=5,
            sort_by="user_count",
            ascending=False,
        )


def marketplace_tab(data: dict):
    st.subheader("City-Zone Marketplace Health")

    marketplace = data["marketplace"]

    if marketplace.empty:
        st.info("Marketplace score file is missing.")
        return

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        metric_card("Zones", marketplace["zone"].nunique())

    with col2:
        metric_card("Avg Health Score", safe_mean(marketplace, "marketplace_health_score"))

    with col3:
        metric_card("Avg SLA Breach %", safe_mean(marketplace, "sla_breach_pct"))

    with col4:
        metric_card("Avg Complaint %", safe_mean(marketplace, "complaint_rate_pct"))

    st.divider()

    needs_attention_count = 0
    if "marketplace_health_tier" in marketplace.columns:
        needs_attention_mask = marketplace["marketplace_health_tier"] == "needs_attention"
        needs_attention_count = int(
            (needs_attention_mask | (marketplace["marketplace_health_score"] < 60)).sum()
        )

    # Display copy: a needs-attention zone should never show "Scale Growth" as its
    # recommended action, since that contradicts the zone's own health tier. Override
    # only that combination; every other zone keeps its normal pretty_value() label.
    marketplace_display = marketplace.copy()

    def _resolve_zone_action(row) -> str:
        if (
            row.get("marketplace_health_tier") == "needs_attention"
            and row.get("recommended_action") == "scale_growth"
        ):
            return "Repair Experience Before Scaling"
        return pretty_value(row.get("recommended_action"))

    if "recommended_action" in marketplace_display.columns:
        marketplace_display["recommended_action_display"] = marketplace_display.apply(
            _resolve_zone_action, axis=1
        )
    else:
        marketplace_display["recommended_action_display"] = ""

    supply_count = 0
    scale_count = 0
    if "recommended_action" in marketplace.columns:
        supply_count = int(
            (marketplace["recommended_action"] == "improve_supply_depth_and_discovery").sum()
        )
        # Count directly off the display column so the card total always matches
        # the "Scale Growth" bar in the chart below, even after the override.
        scale_count = int((marketplace_display["recommended_action_display"] == "Scale Growth").sum())

    cards = [
        dict(
            title="Needs-attention zones",
            evidence=f"{needs_attention_count} zone(s) are tagged "
            f"{pretty_value('needs_attention')} or score below 60.",
            action="Fix reliability and customer experience gaps before demand scaling.",
            tag="Risk",
            tone="risk",
        ),
        dict(
            title="Supply-depth opportunity",
            evidence=f"{supply_count} zone(s) are flagged "
            f"{pretty_value('improve_supply_depth_and_discovery')}.",
            action="Improve restaurant and cuisine depth in these zones.",
            tag="Opportunity",
            tone="opportunity",
        ),
        dict(
            title="Scale-ready zones",
            evidence=f"{scale_count} zone(s) are ready for Scale Growth after excluding "
            "needs-attention zones.",
            action="Scale demand in healthy zones first.",
            tag="Growth",
            tone="growth",
        ),
    ]

    insight_row(cards)

    st.divider()

    col1, col2 = st.columns(2)

    with col1:
        fig = px.scatter(
            marketplace_display,
            x="session_to_delivery_conversion_pct",
            y="marketplace_health_score",
            size="delivered_orders",
            hover_name="zone",
            hover_data=[
                "recommended_action_display",
                "sla_breach_pct",
                "refund_rate_pct",
                "complaint_rate_pct",
            ],
            title="Conversion vs Marketplace Health",
            labels=LABELS,
        )
        fig = apply_pretty_labels(fig)
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        action_counts = (
            marketplace_display["recommended_action_display"].value_counts().reset_index()
        )
        action_counts.columns = ["recommended_action_display", "count"]
        max_action_count = int(action_counts["count"].max()) if not action_counts.empty else 1

        fig = px.bar(
            action_counts,
            y="recommended_action_display",
            x="count",
            orientation="h",
            title="Recommended Zone Actions",
            labels=LABELS,
            text_auto=True,
        )
        fig.update_traces(textposition="outside", cliponaxis=False)
        fig.update_yaxes(categoryorder="total ascending", title_text="")
        fig.update_xaxes(range=[0, max(max_action_count, 1) * 1.15], title_text="Count")
        fig.update_layout(margin=dict(l=180, r=30, t=50, b=40))
        fig = apply_pretty_labels(fig)
        st.plotly_chart(fig, use_container_width=True)

    compact_table(
        "Lowest-Scoring Zones to Prioritize",
        marketplace_display,
        [
            "zone",
            "marketplace_health_score",
            "delivered_orders",
            "session_to_delivery_conversion_pct",
            "sla_breach_pct",
            "recommended_action_display",
        ],
        max_rows=5,
        sort_by="marketplace_health_score",
        ascending=True,
    )


def operations_tab(data: dict):
    st.subheader("Delivery Operations")

    delivery = data["delivery"]
    sla_root = data["sla_root"]
    hourly = data["hourly_heatmap"]

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        metric_card("Avg Delivery Time", safe_mean(delivery, "avg_delivery_time_min"))

    with col2:
        metric_card("Avg Hourly P90 Delivery Time", safe_mean(delivery, "p90_delivery_time_min"))

    with col3:
        metric_card("Avg SLA Breach %", safe_mean(delivery, "sla_breach_pct"))

    with col4:
        metric_card("Avg Cancellation %", safe_mean(delivery, "cancellation_rate_pct"))

    st.divider()

    cards = []

    if not sla_root.empty:
        driver_counts = sla_root["root_cause_driver"].value_counts()
        top_driver = driver_counts.idxmax()
        top_driver_share = weighted_pct(driver_counts.max(), driver_counts.sum())

        cards.append(
            dict(
                title="Main SLA driver",
                evidence=f"'{pretty_value(top_driver)}' is the leading root cause, at "
                f"{top_driver_share}% of flagged rows.",
                action="Prioritize that operational lever first.",
                tone="risk",
            )
        )

    if not hourly.empty and "hourly_risk_tier" in hourly.columns:
        high_risk_count = int((hourly["hourly_risk_tier"] == "high_risk_hour").sum())

        cards.append(
            dict(
                title="Peak-hour risk",
                evidence=f"{high_risk_count} day-hour slot(s) are tagged "
                f"{pretty_value('high_risk_hour')}.",
                action="Pre-position riders and adjust batching for these windows.",
                tone="risk",
            )
        )

    cards.append(
        dict(
            title="Capacity action",
            evidence="Top risk slots combine high P90 delivery time with elevated SLA "
            "breach or complaint rates.",
            action="Add capacity to the specific day-hour windows below, not blanket "
            "city-wide.",
            tone="opportunity",
        )
    )

    insight_row(cards)

    st.divider()

    if not hourly.empty:
        heatmap_data = hourly.pivot_table(
            index="day_of_week",
            columns="order_hour",
            values="hourly_operational_risk_score",
            aggfunc="mean",
        )

        day_order = [
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday",
            "Sunday",
        ]

        heatmap_data = heatmap_data.reindex(day_order)

        fig = px.imshow(
            heatmap_data,
            aspect="auto",
            title="Hourly Operational Risk Heatmap",
            labels=dict(x="Order Hour", y="Day of Week", color="Risk Score"),
        )
        fig = apply_pretty_labels(fig)
        st.plotly_chart(fig, use_container_width=True)
        st.caption("Dark cells may indicate lower risk or low-volume filtered slots.")

    col1, col2 = st.columns(2)

    with col1:
        if not sla_root.empty:
            root_counts = sla_root["root_cause_driver"].value_counts().reset_index()
            root_counts.columns = ["root_cause_driver", "count"]
            root_counts["root_cause_driver_display"] = root_counts[
                "root_cause_driver"
            ].apply(pretty_value)

            fig = px.bar(
                root_counts,
                x="root_cause_driver_display",
                y="count",
                title="SLA Root Cause Driver Mix",
                labels=LABELS,
            )
            fig.update_layout(xaxis_tickangle=-30)
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        if not hourly.empty:
            risk_counts = hourly["hourly_risk_tier"].value_counts().reset_index()
            risk_counts.columns = ["hourly_risk_tier", "count"]
            risk_counts["hourly_risk_tier_display"] = risk_counts[
                "hourly_risk_tier"
            ].apply(pretty_value)

            fig = px.pie(
                risk_counts,
                names="hourly_risk_tier_display",
                values="count",
                title="Hourly Risk Tier Mix",
                labels=LABELS,
            )
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    compact_table(
        "Top Risk Day-Hour Slots",
        hourly,
        [
            "day_of_week",
            "order_hour",
            "meal_period",
            "total_orders",
            "p90_delivery_time_min",
            "sla_breach_pct",
            "complaint_rate_pct",
            "hourly_operational_risk_score",
        ],
        max_rows=5,
        sort_by="hourly_operational_risk_score",
        ascending=False,
    )


def search_tab(data: dict):
    st.subheader("Search Quality")

    search_quality = data["search_quality"]

    if search_quality.empty:
        st.info("Search quality file is missing.")
        return

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        metric_card("Search Query-Zone Rows", len(search_quality))

    with col2:
        metric_card("Avg Search Quality Score", safe_mean(search_quality, "search_quality_score"))

    with col3:
        metric_card("Avg Search Click %", safe_mean(search_quality, "search_click_rate_pct"))

    with col4:
        metric_card("Avg Delivered After Search %", safe_mean(search_quality, "delivered_after_search_rate_pct"))

    st.divider()

    total_rows = len(search_quality)
    depth_count = int((search_quality["recommended_action"] == "improve_result_depth").sum())
    ranking_count = int((search_quality["recommended_action"] == "improve_result_ranking").sum())
    conversion_count = int(
        (search_quality["recommended_action"] == "fix_search_to_order_conversion").sum()
    )

    cards = [
        dict(
            title="Result-depth problem",
            evidence=f"{depth_count} row(s) ({weighted_pct(depth_count, total_rows)}%) are "
            f"flagged {pretty_value('improve_result_depth')}.",
            action="Increase supply and discoverability for those query-zone pairs.",
            tone="opportunity",
        ),
        dict(
            title="Ranking problem",
            evidence=f"{ranking_count} row(s) are flagged "
            f"{pretty_value('improve_result_ranking')}.",
            action="Audit ranking and clicked restaurant quality.",
            tone="risk",
        ),
        dict(
            title="Conversion problem",
            evidence=f"{conversion_count} row(s) are flagged "
            f"{pretty_value('fix_search_to_order_conversion')}.",
            action="Inspect ETA, pricing, restaurant quality, and cart transition.",
            tone="risk",
        ),
    ]

    insight_row(cards)

    st.divider()

    col1, col2 = st.columns(2)

    with col1:
        search_chart = search_quality.copy()
        search_chart["recommended_action_display"] = search_chart["recommended_action"].apply(
            pretty_value
        )

        fig = px.scatter(
            search_chart,
            x="low_result_search_rate_pct",
            y="search_click_rate_pct",
            size="total_searches",
            hover_data=[
                "zone",
                "search_query",
                "search_quality_score",
                "recommended_action_display",
            ],
            title="Low Result Rate vs Search CTR",
            labels=LABELS,
        )
        fig = apply_pretty_labels(fig)
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        action_counts = search_quality["recommended_action"].value_counts().reset_index()
        action_counts.columns = ["recommended_action", "count"]
        action_counts["recommended_action_display"] = action_counts[
            "recommended_action"
        ].apply(pretty_value)
        max_action_count = int(action_counts["count"].max()) if not action_counts.empty else 1

        fig = px.bar(
            action_counts,
            y="recommended_action_display",
            x="count",
            orientation="h",
            title="Search Recommended Actions",
            labels=LABELS,
            text_auto=True,
        )
        fig.update_traces(textposition="outside", cliponaxis=False)
        fig.update_yaxes(categoryorder="total ascending", title_text="")
        fig.update_xaxes(range=[0, max(max_action_count, 1) * 1.15], title_text="Count")
        fig.update_layout(margin=dict(l=180, r=30, t=50, b=40))
        fig = apply_pretty_labels(fig)
        st.plotly_chart(fig, use_container_width=True)

    compact_table(
        "Worst Query-Zone Search Experiences",
        search_quality,
        [
            "zone",
            "search_query",
            "total_searches",
            "low_result_search_rate_pct",
            "search_click_rate_pct",
            "search_quality_score",
            "recommended_action",
        ],
        max_rows=5,
        sort_by="search_quality_score",
        ascending=True,
    )


def restaurant_tab(data: dict):
    st.subheader("Restaurant Quality, Risk, and Visibility")

    quality = data["restaurant_quality"]
    anomaly = add_confidence_tier(data["restaurant_anomaly"])
    visibility = add_confidence_tier(data["visibility"])
    cuisine = data["cuisine"]

    critical_mask = anomaly.get("anomaly_tier", pd.Series(dtype=object)) == "critical_anomaly"
    critical_count = int(critical_mask.sum())
    qualified_critical_count = 0
    if "delivered_orders" in anomaly.columns:
        qualified_critical_count = int(
            (critical_mask & (anomaly["delivered_orders"] >= 5)).sum()
        )

    underexposed_mask = (
        visibility.get("visibility_opportunity_tier", pd.Series(dtype=object))
        == "high_quality_underexposed"
    )
    qualified_visibility_count = 0
    if "delivered_orders" in visibility.columns:
        qualified_visibility_count = int(
            (underexposed_mask & (visibility["delivered_orders"] >= 5)).sum()
        )

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        metric_card("Restaurants in Quality Table", len(quality))

    with col2:
        metric_card("Avg Restaurant Quality", safe_mean(quality, "restaurant_quality_score"))

    with col3:
        metric_card("Critical Anomalies", critical_count)

    with col4:
        metric_card("Qualified Visibility Candidates", qualified_visibility_count)

    st.divider()

    cards = [
        dict(
            title="Investigation candidates require validation",
            evidence=f"{critical_count} restaurant(s) are tagged "
            f"{pretty_value('critical_anomaly')}; {qualified_critical_count} meet the "
            "5+ delivered-order confidence threshold.",
            action="Investigate refunds, complaints, SLA, and cancellation patterns before "
            "penalizing.",
            tone="risk",
        ),
        dict(
            title="Visibility candidates need confidence filtering",
            evidence=f"{int(underexposed_mask.sum())} restaurant(s) are tagged "
            f"{pretty_value('high_quality_underexposed')}; only {qualified_visibility_count} "
            "qualify with 5+ delivered orders.",
            action="Test visibility lifts only on qualified candidates first.",
            tone="opportunity",
        ),
        dict(
            title="Small-denominator caution",
            evidence="Top anomaly and visibility rows often have low delivered order counts.",
            action="Use the confidence tier before taking enforcement or promotion decisions.",
            impact="Prevents overreacting to one refund or complaint.",
            tone="neutral",
        ),
    ]

    insight_row(cards)

    st.divider()

    # Restrict the scatter charts to restaurants with enough volume to trust their
    # rates; fall back to the full table if the confidence filter empties it out.
    anomaly_chart = anomaly[anomaly["delivered_orders"] >= 5] if "delivered_orders" in anomaly.columns else anomaly
    if anomaly_chart.empty:
        anomaly_chart = anomaly

    visibility_chart = (
        visibility[visibility["delivered_orders"] >= 5]
        if "delivered_orders" in visibility.columns
        else visibility
    )
    if visibility_chart.empty:
        visibility_chart = visibility

    col1, col2 = st.columns(2)

    with col1:
        if not anomaly_chart.empty:
            anomaly_chart = anomaly_chart.copy()
            anomaly_chart["recommended_action_display"] = anomaly_chart[
                "recommended_action"
            ].apply(pretty_value)

            fig = px.scatter(
                anomaly_chart,
                x="refund_rate_pct",
                y="complaint_rate_pct",
                size="delivered_orders",
                hover_name="restaurant_name",
                hover_data=[
                    "zone",
                    "primary_cuisine",
                    "anomaly_score",
                    "recommended_action_display",
                ],
                title="Restaurant Refund vs Complaint Risk",
                labels=LABELS,
            )
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        if not visibility_chart.empty:
            visibility_chart = visibility_chart.copy()
            visibility_chart["recommended_action_display"] = visibility_chart[
                "recommended_action"
            ].apply(pretty_value)
            visibility_chart["visibility_opportunity_tier_display"] = visibility_chart[
                "visibility_opportunity_tier"
            ].apply(pretty_value)

            fig = px.scatter(
                visibility_chart,
                x="visibility_score",
                y="restaurant_quality_score",
                size="delivered_orders",
                hover_name="restaurant_name",
                hover_data=[
                    "zone",
                    "primary_cuisine",
                    "visibility_opportunity_tier_display",
                    "recommended_action_display",
                ],
                title="Restaurant Visibility vs Quality",
                labels=LABELS,
            )
            fig = apply_pretty_labels(fig)
            st.plotly_chart(fig, use_container_width=True)

    st.caption(
        "Restaurant-level rates are filtered to restaurants with at least 5 delivered "
        "orders where possible to reduce small-denominator noise."
    )

    if not cuisine.empty:
        cuisine_plot = cuisine.copy()
        cuisine_plot["price_band_display"] = cuisine_plot["price_band"].apply(pretty_value)
        cuisine_plot["cuisine_price_segment"] = (
            cuisine_plot["primary_cuisine"].astype(str)
            + " | "
            + cuisine_plot["price_band_display"].astype(str)
        )
        cuisine_plot = cuisine_plot.sort_values(
            "repeat_customer_rate_pct", ascending=False
        ).head(15)

        if "cuisine_stickiness_tier" in cuisine_plot.columns:
            cuisine_plot["cuisine_stickiness_tier_display"] = cuisine_plot[
                "cuisine_stickiness_tier"
            ].apply(pretty_value)
            color_col = "cuisine_stickiness_tier_display"
        else:
            color_col = None

        fig = px.bar(
            cuisine_plot.sort_values("repeat_customer_rate_pct"),
            x="repeat_customer_rate_pct",
            y="cuisine_price_segment",
            color=color_col,
            orientation="h",
            title="Top Cuisine-Price Segments by Repeat Rate",
            hover_data=["delivered_orders", "refund_rate_pct", "complaint_rate_pct"],
            labels=LABELS,
        )
        fig = apply_pretty_labels(fig)
        st.plotly_chart(fig, use_container_width=True)

    visibility_columns = [
        "restaurant_name",
        "zone",
        "primary_cuisine",
        "delivered_orders",
        "restaurant_quality_score",
        "visibility_score",
        "underexposure_opportunity_score",
    ]

    qualified_visibility = (
        visibility[underexposed_mask & (visibility.get("delivered_orders", 0) >= 5)]
        if not visibility.empty
        else visibility
    )

    if not qualified_visibility.empty:
        compact_table(
            "Qualified Visibility Lift Candidates",
            qualified_visibility,
            visibility_columns,
            max_rows=5,
            sort_by="underexposure_opportunity_score",
            ascending=False,
        )
    else:
        st.info(
            "No high-confidence visibility candidates yet; below are early validation "
            "candidates."
        )
        early_candidates = visibility[underexposed_mask] if not visibility.empty else visibility
        compact_table(
            "Early Visibility Validation Candidates",
            early_candidates,
            visibility_columns,
            max_rows=5,
            sort_by="underexposure_opportunity_score",
            ascending=False,
        )

    anomaly_columns = [
        "restaurant_name",
        "zone",
        "primary_cuisine",
        "delivered_orders",
        "refund_rate_pct",
        "complaint_rate_pct",
        "sla_breach_pct",
        "anomaly_score",
    ]

    # Qualified Investigation Candidates is scoped to critical_anomaly only (not
    # high/medium anomaly) with delivered_orders >= 5, so its row count always
    # matches the "meet the confidence threshold" figure in the insight card above.
    if not anomaly.empty and "anomaly_tier" in anomaly.columns:
        investigation_mask = anomaly["anomaly_tier"] == "critical_anomaly"
        if "delivered_orders" in anomaly.columns:
            investigation_mask = investigation_mask & (anomaly["delivered_orders"] >= 5)
        qualified_investigation = anomaly[investigation_mask]
    else:
        qualified_investigation = pd.DataFrame()

    if not qualified_investigation.empty:
        compact_table(
            "Qualified Investigation Candidates",
            qualified_investigation,
            anomaly_columns,
            max_rows=5,
            sort_by="anomaly_score",
            ascending=False,
        )
    else:
        st.write("Qualified Investigation Candidates")
        st.info(
            "No critical anomaly restaurants meet the 5+ delivered-order confidence "
            "threshold yet."
        )


def forecast_tab(data: dict):
    st.subheader("Lightweight Forecasting")

    forecast_input = data["city_forecast_input"]
    forecast_summary = data["forecast_summary"]
    forecast_backtest = data["forecast_backtest"]
    forecast_future = data["forecast_future"]

    if forecast_input.empty or forecast_summary.empty or forecast_future.empty:
        st.info("Forecast files are missing. Run `src/forecast_city_daily.py` first.")
        return

    best_model = forecast_summary.sort_values("rank_by_mae").iloc[0]
    best_model_display = pretty_value(best_model["model_name"])
    best_model_short = pretty_value_short(best_model["model_name"])

    col1, col2, col3, col4 = st.columns(4)

    with col1:
        metric_card("Best Model", best_model_short)

    with col2:
        metric_card("Best MAE", best_model["mae"])

    with col3:
        metric_card("Best MAPE %", best_model["mape_pct"])

    with col4:
        metric_card("14-Day Forecast Avg", safe_mean(forecast_future, "forecast_delivered_orders"))

    st.caption(
        "This module intentionally uses lightweight baseline forecasting, not a "
        "production ML model. The goal is demand planning and operational "
        "expectation-setting."
    )

    st.divider()

    forecast_avg = safe_mean(forecast_future, "forecast_delivered_orders")
    forecast_min = round(float(forecast_future["forecast_delivered_orders"].min()), 2)
    forecast_max = round(float(forecast_future["forecast_delivered_orders"].max()), 2)

    cards = [
        dict(
            title="Best baseline",
            evidence=f"{best_model_display} is the top-ranked model with MAE "
            f"{best_model['mae']} and MAPE {best_model['mape_pct']}%.",
            action=f"Use {best_model_display} as the current baseline.",
            tone="growth",
        ),
        dict(
            title="Forecast stability",
            evidence=f"Next 14 days forecast ranges from {forecast_min} to {forecast_max}, "
            f"averaging {forecast_avg} delivered orders/day.",
            action="Use the forecast as a short-term planning baseline.",
            tone="neutral",
        ),
        dict(
            title="Forecast limitation",
            evidence="City-day forecasting has reliable signal here; the zone-day table "
            "was too sparse for stable estimates.",
            action="Avoid sparse zone-day forecasts until volume increases.",
            tone="neutral",
        ),
    ]

    insight_row(cards)

    st.divider()

    fig = px.line(
        forecast_input,
        x="metric_date",
        y="delivered_orders",
        title="Historical Daily Delivered Orders",
        labels=LABELS,
    )
    fig = apply_pretty_labels(fig)
    st.plotly_chart(fig, use_container_width=True)

    if not forecast_backtest.empty:
        backtest_display = forecast_backtest.rename(columns=BACKTEST_DISPLAY_COLUMNS)

        fig = px.line(
            backtest_display,
            x="Date",
            y=["Actual Delivered Orders", "Rolling 28D Baseline", "Weighted Baseline"],
            title="Backtest: Actual vs Forecast",
            labels={"value": "Delivered Orders", "variable": "Series"},
        )
        fig = apply_pretty_labels(fig)
        st.plotly_chart(fig, use_container_width=True)

    future_display = forecast_future.rename(columns=FUTURE_DISPLAY_COLUMNS)

    fig = px.line(
        future_display,
        x="Date",
        y=["Forecast Delivered Orders", "Lower Bound", "Upper Bound"],
        title="Next 14 Days Forecast",
        labels={"value": "Delivered Orders", "variable": "Series"},
    )
    fig = apply_pretty_labels(fig)
    st.plotly_chart(fig, use_container_width=True)

    compact_table(
        "Forecast Model Summary",
        forecast_summary,
        [
            "model_name",
            "mae",
            "rmse",
            "mape_pct",
            "bias",
            "rank_by_mae",
        ],
        max_rows=5,
        sort_by="rank_by_mae",
        ascending=True,
    )

    compact_table(
        "Next 5 Forecasted Days",
        forecast_future,
        [
            "forecast_date",
            "forecast_delivered_orders",
            "forecast_delivered_orders_lower_bound",
            "forecast_delivered_orders_upper_bound",
            "forecast_gross_order_value",
        ],
        max_rows=5,
    )


def raw_tables_tab(data: dict):
    st.subheader("Raw Analysis Tables")

    st.caption(
        "Raw analysis tables are retained for auditability and drilldown. Main tabs "
        "show summarized decision insights."
    )

    table_name = st.selectbox(
        "Select table",
        list(FILES.keys()),
    )

    df = data[table_name]

    if df.empty:
        st.info("Selected file is missing or empty.")
        return

    st.write(f"Rows: {len(df):,} | Columns: {len(df.columns):,}")
    st.dataframe(df, use_container_width=True)


def main():
    st.title("OrderIQ: Food Delivery Marketplace Analytics System")

    st.caption(
        "Product analytics, marketplace health, search quality, restaurant risk, "
        "delivery operations, and lightweight forecasting."
    )

    data = load_all_data()
    show_missing_files(data)

    tabs = st.tabs(
        [
            "Executive Overview",
            "Funnel & Retention",
            "Marketplace Health",
            "Delivery Ops",
            "Search Quality",
            "Restaurants",
            "Forecasting",
            "Raw Tables",
        ]
    )

    with tabs[0]:
        executive_overview(data)

    with tabs[1]:
        funnel_tab(data)

    with tabs[2]:
        marketplace_tab(data)

    with tabs[3]:
        operations_tab(data)

    with tabs[4]:
        search_tab(data)

    with tabs[5]:
        restaurant_tab(data)

    with tabs[6]:
        forecast_tab(data)

    with tabs[7]:
        raw_tables_tab(data)


if __name__ == "__main__":
    main()
