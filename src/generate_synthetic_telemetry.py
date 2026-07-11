from pathlib import Path
from datetime import datetime, timedelta
import numpy as np
import pandas as pd


SEED = 42
rng = np.random.default_rng(SEED)

INTERIM_DIR = Path("data/interim")
PROCESSED_DIR = Path("data/processed")
PROCESSED_DIR.mkdir(parents=True, exist_ok=True)

N_USERS = 6500
N_SESSIONS = 90000

START_DATE = pd.Timestamp("2025-01-01")
END_DATE = pd.Timestamp("2025-06-30")


def safe_read_csv(path: Path) -> pd.DataFrame:
    try:
        return pd.read_csv(path)
    except UnicodeDecodeError:
        return pd.read_csv(path, encoding="latin-1")


def sigmoid(x):
    return 1 / (1 + np.exp(-x))


def clamp(value, low, high):
    return max(low, min(high, value))


def weighted_choice(values, weights=None):
    values = np.array(values)

    if len(values) == 0:
        return None

    if weights is None:
        return rng.choice(values)

    weights = np.array(weights, dtype=float)

    if weights.sum() <= 0 or np.isnan(weights).any():
        return rng.choice(values)

    weights = weights / weights.sum()
    return rng.choice(values, p=weights)

def random_timestamp(start_date, end_date, n):
    """
    Generate timestamps between start and end.
    Higher probability during lunch and dinner hours.
    """
    total_days = (end_date - start_date).days + 1
    random_days = rng.integers(0, total_days, size=n)

    # Food delivery demand is heavier around lunch and dinner.
    hour_weights = np.array([
        0.010, 0.005, 0.003, 0.002, 0.002, 0.003,
        0.010, 0.020, 0.035, 0.040, 0.045, 0.070,
        0.085, 0.070, 0.045, 0.035, 0.040, 0.055,
        0.080, 0.105, 0.115, 0.075, 0.035, 0.020
    ])

    # Normalize to avoid numpy probability-sum precision errors.
    hour_weights = hour_weights / hour_weights.sum()

    hours = rng.choice(
        np.arange(0, 24),
        size=n,
        p=hour_weights
    )

    minutes = rng.integers(0, 60, size=n)
    seconds = rng.integers(0, 60, size=n)

    timestamps = [
        start_date + pd.Timedelta(days=int(d), hours=int(h), minutes=int(m), seconds=int(s))
        for d, h, m, s in zip(random_days, hours, minutes, seconds)
    ]

    return pd.to_datetime(timestamps)


def build_dim_restaurants(restaurants_raw: pd.DataFrame) -> pd.DataFrame:
    """
    Build restaurant dimension from cleaned public restaurant data.
    Adds a few synthetic operational fields required for marketplace analysis.
    """
    restaurants = restaurants_raw.copy()

    restaurants["rating_filled"] = restaurants["rating"].fillna(restaurants["rating"].median())
    restaurants["cost_filled"] = restaurants["avg_cost_for_two"].fillna(restaurants["avg_cost_for_two"].median())

    # Menu depth is synthetic but linked to cuisine count, restaurant type, and cost.
    base_menu_depth = (
        18
        + restaurants["cuisine_count"].fillna(1) * 7
        + np.where(restaurants["price_band"] == "premium", 12, 0)
        + np.where(restaurants["price_band"] == "mid", 6, 0)
    )

    noise = rng.normal(0, 8, size=len(restaurants))
    restaurants["menu_depth"] = np.clip(base_menu_depth + noise, 8, 120).round().astype(int)

    # Operational reliability proxy.
    restaurants["restaurant_quality_prior"] = (
        0.55 * (restaurants["rating_filled"] / 5)
        + 0.25 * np.clip(np.log1p(restaurants["votes"]) / 10, 0, 1)
        + 0.10 * restaurants["online_order_flag"].astype(int)
        + 0.10 * np.where(restaurants["price_band"] == "premium", 1, 0.7)
    )

    restaurants["restaurant_quality_prior"] = restaurants["restaurant_quality_prior"].clip(0.25, 0.98)

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
        "menu_depth",
        "restaurant_quality_prior",
    ]

    return restaurants[final_cols].copy()


def build_dim_users(preferences: pd.DataFrame, restaurants: pd.DataFrame) -> pd.DataFrame:
    """
    Generate synthetic users using preference distribution and restaurant zone distribution.
    """
    users = pd.DataFrame()
    users["user_id"] = np.arange(1, N_USERS + 1)

    # Signup dates begin before analysis window.
    signup_offsets = rng.integers(-90, 150, size=N_USERS)
    users["signup_date"] = START_DATE + pd.to_timedelta(signup_offsets, unit="D")
    users["signup_date"] = users["signup_date"].dt.date

    # Use age distribution from preference dataset if available.
    age_bands = preferences["age_band"].dropna().astype(str)
    age_bands = age_bands[age_bands != "nan"]

    if len(age_bands) > 0:
        age_dist = age_bands.value_counts(normalize=True)
        users["age_band"] = rng.choice(age_dist.index, size=N_USERS, p=age_dist.values)
    else:
        users["age_band"] = rng.choice(
            ["18-24", "25-34", "35-44", "45-60"],
            size=N_USERS,
            p=[0.45, 0.35, 0.15, 0.05],
        )

    # Use income proxy from preference dataset if available.
    income_values = preferences["income_proxy"].dropna().astype(str)
    income_values = income_values[income_values != "unknown"]

    if len(income_values) > 0:
        income_dist = income_values.value_counts(normalize=True)
        users["income_proxy"] = rng.choice(income_dist.index, size=N_USERS, p=income_dist.values)
    else:
        users["income_proxy"] = rng.choice(
            ["low", "mid", "premium"],
            size=N_USERS,
            p=[0.35, 0.50, 0.15],
        )

    users["city"] = "Bangalore"

    # User zones weighted by restaurant supply density.
    zone_dist = restaurants["zone"].value_counts().head(40)
    users["zone"] = rng.choice(zone_dist.index, size=N_USERS, p=(zone_dist / zone_dist.sum()).values)

    users["acquisition_channel"] = rng.choice(
        ["organic", "paid", "referral", "partner_campaign"],
        size=N_USERS,
        p=[0.42, 0.28, 0.20, 0.10],
    )

    users["user_segment"] = users["income_proxy"].map({
        "low": "value_seeking",
        "mid": "convenience_focused",
        "premium": "premium",
    }).fillna("convenience_focused")

    # Some users are naturally regular.
    regular_boost = rng.random(N_USERS)
    users.loc[
        (users["income_proxy"] == "mid") & (regular_boost < 0.18),
        "user_segment",
    ] = "regular"

    users.loc[
        (users["income_proxy"] == "premium") & (regular_boost < 0.25),
        "user_segment",
    ] = "premium"

    users["gold_member_flag"] = (
        ((users["income_proxy"] == "premium") & (rng.random(N_USERS) < 0.40))
        | ((users["user_segment"] == "regular") & (rng.random(N_USERS) < 0.25))
    )

    # Base user preference strength.
    users["base_order_intent"] = users["user_segment"].map({
        "value_seeking": 0.48,
        "convenience_focused": 0.55,
        "premium": 0.62,
        "regular": 0.70,
    }).fillna(0.52)

    cuisine_dist = restaurants["primary_cuisine"].value_counts().head(18)
    users["preferred_cuisine"] = rng.choice(
        cuisine_dist.index,
        size=N_USERS,
        p=(cuisine_dist / cuisine_dist.sum()).values,
    )

    return users


def prepare_restaurant_lookup(restaurants: pd.DataFrame):
    """
    Precompute lookup structures for restaurant sampling.
    """
    rest = restaurants.copy()

    rest["rating_filled"] = rest["rating"].fillna(rest["rating"].median())
    rest["avg_cost_filled"] = rest["avg_cost_for_two"].fillna(rest["avg_cost_for_two"].median())

    rest["sampling_weight"] = (
        0.45 * rest["restaurant_quality_prior"]
        + 0.30 * np.clip(np.log1p(rest["votes"]) / 10, 0, 1)
        + 0.15 * rest["online_order_flag"].astype(int)
        + 0.10
    )

    by_zone = {}
    by_zone_cuisine = {}
    by_cuisine = {}

    for zone, group in rest.groupby("zone"):
        by_zone[zone] = group.index.to_numpy()

    for cuisine, group in rest.groupby("primary_cuisine"):
        by_cuisine[cuisine] = group.index.to_numpy()

    for (zone, cuisine), group in rest.groupby(["zone", "primary_cuisine"]):
        by_zone_cuisine[(zone, cuisine)] = group.index.to_numpy()

    return rest, by_zone, by_zone_cuisine, by_cuisine


def sample_restaurant_for_session(user_row, rest, by_zone, by_zone_cuisine, by_cuisine):
    """
    Pick a restaurant for a session based on user zone and preferred cuisine.
    """
    user_zone = user_row["zone"]
    preferred_cuisine = user_row["preferred_cuisine"]

    # Most searches are around preferred cuisine, but not all.
    if rng.random() < 0.72:
        query_cuisine = preferred_cuisine
    else:
        query_cuisine = weighted_choice(rest["primary_cuisine"].value_counts().head(20).index)

    candidate_indices = by_zone_cuisine.get((user_zone, query_cuisine))

    if candidate_indices is None or len(candidate_indices) == 0:
        candidate_indices = by_zone.get(user_zone)

    if candidate_indices is None or len(candidate_indices) == 0:
        candidate_indices = by_cuisine.get(query_cuisine)

    if candidate_indices is None or len(candidate_indices) == 0:
        candidate_indices = rest.index.to_numpy()

    candidates = rest.loc[candidate_indices]
    weights = candidates["sampling_weight"].to_numpy()

    chosen_idx = weighted_choice(candidates.index.to_numpy(), weights)
    chosen = rest.loc[chosen_idx]

    # Result count approximates how much supply exists for that query-zone.
    exact_supply = len(by_zone_cuisine.get((user_zone, query_cuisine), []))
    if exact_supply == 0:
        result_count = int(rng.integers(1, 8))
    else:
        result_count = int(clamp(rng.normal(exact_supply, max(2, exact_supply * 0.20)), 1, 80))

    return query_cuisine, result_count, chosen


def estimate_eta(delivery_base: pd.DataFrame, restaurant_quality: float, hour: int):
    """
    Estimate customer-facing delivery ETA using the public delivery-time dataset,
    but calibrate distances to a realistic local food-delivery marketplace range.
    """
    sample = delivery_base.sample(
        1,
        random_state=int(rng.integers(1, 1_000_000))
    ).iloc[0]

    base_time = float(sample["total_delivery_time_min"])
    raw_distance_km = float(sample["distance_km"])

    # Public coordinate-based distances can be too large for local marketplace simulation.
    # Compress them into a more realistic delivery catchment range.
    distance_km = raw_distance_km * rng.uniform(0.35, 0.75)
    distance_km = clamp(distance_km, 0.8, 8.0)

    peak_multiplier = 1.10 if hour in [12, 13, 19, 20, 21] else 1.0
    quality_adjustment = (1 - restaurant_quality) * 5

    eta = base_time * peak_multiplier + quality_adjustment + rng.normal(0, 3)
    eta = clamp(eta, 18, 60)

    return eta, distance_km


def compute_discount(user_segment, price_band):
    """
    Simulate shown discount amount percentage.
    """
    if user_segment == "value_seeking":
        discount_pct = rng.choice([0, 5, 10, 15, 20, 25], p=[0.10, 0.18, 0.25, 0.22, 0.18, 0.07])
    elif user_segment == "premium":
        discount_pct = rng.choice([0, 5, 10, 15, 20], p=[0.38, 0.28, 0.20, 0.10, 0.04])
    elif user_segment == "regular":
        discount_pct = rng.choice([0, 5, 10, 15, 20], p=[0.25, 0.25, 0.25, 0.18, 0.07])
    else:
        discount_pct = rng.choice([0, 5, 10, 15, 20], p=[0.22, 0.26, 0.25, 0.18, 0.09])

    # Premium restaurants have slightly lower discounting.
    if price_band == "premium" and rng.random() < 0.40:
        discount_pct = max(0, discount_pct - 5)

    return discount_pct


def build_sessions_and_events(users: pd.DataFrame, restaurants: pd.DataFrame, delivery_base: pd.DataFrame):
    """
    Generate sessions, search events, cart events, orders, delivery ops, refunds, and ratings.
    This is intentionally stateful so previous experience can influence repeat behaviour.
    """
    rest, by_zone, by_zone_cuisine, by_cuisine = prepare_restaurant_lookup(restaurants)

    user_lookup = users.set_index("user_id")

    # Session base.
    sessions = pd.DataFrame()
    sessions["session_id"] = np.arange(1, N_SESSIONS + 1)

    # More active users appear more often.
    user_weights = users["base_order_intent"].to_numpy()
    user_weights = user_weights / user_weights.sum()

    sessions["user_id"] = rng.choice(users["user_id"], size=N_SESSIONS, p=user_weights)
    sessions["session_start_time"] = random_timestamp(START_DATE, END_DATE, N_SESSIONS)
    sessions = sessions.sort_values("session_start_time").reset_index(drop=True)
    sessions["session_id"] = np.arange(1, N_SESSIONS + 1)

    sessions = sessions.merge(
        users[["user_id", "city", "zone"]],
        on="user_id",
        how="left",
    )

    sessions["device_type"] = rng.choice(
        ["Android", "iOS", "Web"],
        size=N_SESSIONS,
        p=[0.68, 0.27, 0.05],
    )

    sessions["traffic_source"] = rng.choice(
        ["organic", "paid", "referral", "push", "crm"],
        size=N_SESSIONS,
        p=[0.40, 0.22, 0.13, 0.15, 0.10],
    )

    sessions["app_open_flag"] = True

    # Containers.
    search_rows = []
    cart_rows = []
    order_rows = []
    delivery_rows = []
    refund_rows = []
    rating_rows = []

    # User state.
    user_state = {
        int(uid): {
            "delivered_orders": 0,
            "bad_experience_count": 0,
            "last_order_date": None,
            "first_order_bad": None,
        }
        for uid in users["user_id"]
    }

    order_id = 1
    search_id = 1
    cart_id = 1
    refund_id = 1
    rating_id = 1

    cuisine_complexity = {
        "Biryani": 1.18,
        "North Indian": 1.15,
        "Chinese": 1.06,
        "Fast Food": 0.92,
        "Cafe": 0.88,
        "Desserts": 0.80,
        "Bakery": 0.78,
        "South Indian": 0.98,
        "Pizza": 1.08,
        "Burger": 0.90,
        "Continental": 1.20,
        "Italian": 1.15,
        "Beverages": 0.72,
    }

    for _, session in sessions.iterrows():
        uid = int(session["user_id"])
        user = user_lookup.loc[uid]
        state = user_state[uid]

        session_time = pd.Timestamp(session["session_start_time"])
        hour = int(session_time.hour)
        is_peak = hour in [12, 13, 19, 20, 21]
        is_weekend = session_time.dayofweek >= 5

        intent = float(user["base_order_intent"])

        # Prior good behaviour increases session value. Bad experiences reduce it.
                # Prior successful ordering increases session value.
        # Food delivery is habit-driven, so repeat users should have materially higher intent.
        if state["delivered_orders"] > 0:
            intent += min(0.22, 0.10 + 0.035 * state["delivered_orders"])

        # Bad experiences reduce future ordering intent.
        if state["bad_experience_count"] > 0:
            intent -= min(0.22, 0.07 * state["bad_experience_count"])

        if is_peak:
            intent += 0.08

        if is_weekend:
            intent += 0.03

        if session["traffic_source"] == "push":
            intent -= 0.04

        search_probability = clamp(intent, 0.18, 0.88)

        if rng.random() > search_probability:
            continue

        query_cuisine, result_count, restaurant = sample_restaurant_for_session(
            user, rest, by_zone, by_zone_cuisine, by_cuisine
        )

        restaurant_quality = float(restaurant["restaurant_quality_prior"])
        eta_estimate, distance_km = estimate_eta(delivery_base, restaurant_quality, hour)

        low_result_flag = result_count <= 3
        zero_result_flag = result_count == 0

        search_to_click_probability = (
            0.22
            + 0.35 * restaurant_quality
            + 0.10 * np.log1p(result_count) / np.log(81)
            - 0.12 * (eta_estimate > 45)
            - 0.08 * low_result_flag
        )

        search_to_click_probability = clamp(search_to_click_probability, 0.08, 0.82)

        clicked_restaurant_id = None
        search_to_click_seconds = None

        if rng.random() < search_to_click_probability:
            clicked_restaurant_id = int(restaurant["restaurant_id"])
            search_to_click_seconds = int(clamp(rng.normal(22, 12), 3, 120))

        search_rows.append({
            "search_id": search_id,
            "session_id": int(session["session_id"]),
            "user_id": uid,
            "search_time": session_time + pd.Timedelta(seconds=int(rng.integers(5, 60))),
            "search_query": query_cuisine,
            "result_count": int(result_count),
            "clicked_restaurant_id": clicked_restaurant_id,
            "zero_result_flag": bool(zero_result_flag),
            "low_result_flag": bool(low_result_flag),
            "search_to_click_seconds": search_to_click_seconds,
            "estimated_eta_min": round(eta_estimate, 2),
        })

        search_id += 1

        if clicked_restaurant_id is None:
            continue

        discount_pct = compute_discount(user["user_segment"], restaurant["price_band"])

        price_base = float(restaurant["avg_cost_for_two"])
        if pd.isna(price_base) or price_base <= 0:
            price_base = float(rest["avg_cost_filled"].median())

        # Order value is per order, not cost for two.
        order_value_base = price_base * rng.uniform(0.35, 0.75)

        if user["income_proxy"] == "premium":
            order_value_base *= rng.uniform(1.10, 1.45)
        elif user["income_proxy"] == "low":
            order_value_base *= rng.uniform(0.75, 0.95)

        order_value_base = clamp(order_value_base, 120, 2500)

        delivery_fee_shown = 0 if bool(user["gold_member_flag"]) else clamp(20 + distance_km * 4 + rng.normal(0, 8), 0, 90)

        discount_shown = order_value_base * discount_pct / 100

        cart_probability = (
            0.18
            + 0.36 * restaurant_quality
            + 0.12 * (discount_pct / 20)
            - 0.14 * (eta_estimate > 45)
            - 0.08 * (delivery_fee_shown > 60)
        )

        if user["user_segment"] == "premium":
            cart_probability += 0.05

        if user["user_segment"] == "value_seeking" and discount_pct >= 10:
            cart_probability += 0.07

        cart_probability = clamp(cart_probability, 0.05, 0.82)

        if rng.random() > cart_probability:
            continue

        items_added = int(clamp(rng.poisson(2) + 1, 1, 8))

        cart_rows.append({
            "cart_id": cart_id,
            "session_id": int(session["session_id"]),
            "user_id": uid,
            "restaurant_id": int(restaurant["restaurant_id"]),
            "cart_created_time": session_time + pd.Timedelta(minutes=int(rng.integers(2, 10))),
            "items_added": items_added,
            "cart_value": round(order_value_base, 2),
            "delivery_fee_shown": round(delivery_fee_shown, 2),
            "discount_shown": round(discount_shown, 2),
            "estimated_eta_min": round(eta_estimate, 2),
        })

        current_cart_id = cart_id
        cart_id += 1

        payment_probability = (
            0.35
            + 0.20 * restaurant_quality
            + 0.12 * (discount_pct / 20)
            - 0.12 * (eta_estimate > 45)
            - 0.08 * (delivery_fee_shown > 65)
            - 0.05 * (order_value_base > 900 and user["income_proxy"] == "low")
        )

        if user["user_segment"] == "regular":
            payment_probability += 0.10

        if user["gold_member_flag"]:
            payment_probability += 0.06

        if state["delivered_orders"] > 0:
            payment_probability += min(0.12, 0.04 + 0.02 * state["delivered_orders"])

        payment_probability = clamp(payment_probability, 0.08, 0.90)

        if rng.random() > payment_probability:
            continue

        discount_amount = min(discount_shown, order_value_base * 0.40)
        platform_fee = rng.choice([5, 6, 7, 8, 9], p=[0.12, 0.25, 0.28, 0.22, 0.13])
        delivery_fee = delivery_fee_shown

        order_time = session_time + pd.Timedelta(minutes=int(rng.integers(5, 18)))

        # Cancellation risk before successful delivery.
        cancellation_probability = (
            0.025
            + 0.08 * (eta_estimate > 50)
            + 0.04 * (restaurant_quality < 0.55)
            + 0.03 * is_peak
        )

        cancellation_probability = clamp(cancellation_probability, 0.01, 0.25)

        order_status = "cancelled" if rng.random() < cancellation_probability else "delivered"

        cancellation_reason = None
        if order_status == "cancelled":
            cancellation_reason = rng.choice(
                ["late_delivery", "restaurant_unavailable", "customer_cancelled", "payment_issue", "out_of_stock"],
                p=[0.34, 0.24, 0.24, 0.08, 0.10],
            )

        order_rows.append({
            "order_id": order_id,
            "session_id": int(session["session_id"]),
            "cart_id": current_cart_id,
            "user_id": uid,
            "restaurant_id": int(restaurant["restaurant_id"]),
            "order_time": order_time,
            "order_value": round(order_value_base, 2),
            "discount_amount": round(discount_amount, 2),
            "discount_pct": round(100 * discount_amount / order_value_base, 2),
            "platform_fee": round(float(platform_fee), 2),
            "delivery_fee": round(float(delivery_fee), 2),
            "payment_status": "success",
            "order_status": order_status,
            "cancellation_reason": cancellation_reason,
        })

        if order_status == "cancelled":
            state["bad_experience_count"] += 1
            if state["delivered_orders"] == 0 and state["first_order_bad"] is None:
                state["first_order_bad"] = True
            order_id += 1
            continue

               # Delivery ops for delivered orders.
        cuisine = str(restaurant["primary_cuisine"])
        complexity = cuisine_complexity.get(cuisine, 1.00)

        peak_factor = 1.10 if is_peak else 1.00
        quality_factor = 1 + (1 - restaurant_quality) * 0.30

        # Restaurant preparation time.
        prep_time = rng.normal(12 * complexity * peak_factor * quality_factor, 3.5)
        prep_time = clamp(prep_time, 4, 38)

        # Rider wait should exist, but should not dominate every order.
        rider_wait = rng.normal(
            3.5 + max(0, prep_time - 18) * 0.12 + (1.8 if is_peak else 0),
            2.2
        )
        rider_wait = clamp(rider_wait, 0, 18)

        # Last-mile drop time based on calibrated local distance.
        drop_time = rng.normal(
            6 + distance_km * 2.7 + (2.5 if is_peak else 0),
            3.5
        )
        drop_time = clamp(drop_time, 5, 38)

        total_delivery_time = prep_time + rider_wait + drop_time

        # Use a distance-aware SLA threshold.
        # Longer-distance orders get a slightly higher acceptable threshold.
        sla_threshold = 40 + min(distance_km * 1.5, 10)
        sla_breach_flag = total_delivery_time > sla_threshold
        
        accepted_time = order_time + pd.Timedelta(minutes=1)
        food_ready_time = accepted_time + pd.Timedelta(minutes=float(prep_time))
        rider_arrival_time = accepted_time + pd.Timedelta(minutes=float(max(1, prep_time - rider_wait)))
        pickup_time = food_ready_time + pd.Timedelta(minutes=float(max(0, rider_wait * 0.25)))
        delivered_time = pickup_time + pd.Timedelta(minutes=float(drop_time))

        delivery_rows.append({
            "order_id": order_id,
            "restaurant_id": int(restaurant["restaurant_id"]),
            "rider_id": int(rng.integers(1, 3500)),
            "order_accepted_time": accepted_time,
            "food_ready_time": food_ready_time,
            "rider_arrival_time": rider_arrival_time,
            "pickup_time": pickup_time,
            "delivered_time": delivered_time,
            "prep_time_min": round(prep_time, 2),
            "rider_wait_time_min": round(rider_wait, 2),
            "drop_time_min": round(drop_time, 2),
            "total_delivery_time_min": round(total_delivery_time, 2),
            "distance_km": round(distance_km, 2),
            "sla_breach_flag": bool(sla_breach_flag),
        })

        # Ratings.
        rating_probability = 0.62
        if sla_breach_flag:
            rating_probability += 0.08

        generated_food_rating = None
        generated_delivery_rating = None
        complaint_flag = False

        if rng.random() < rating_probability:
            food_rating = rng.normal(float(restaurant["rating_filled"]), 0.55)
            delivery_rating = rng.normal(4.3, 0.45)

            if sla_breach_flag:
                delivery_rating -= rng.uniform(0.5, 1.2)

            if restaurant_quality < 0.55:
                food_rating -= rng.uniform(0.3, 0.8)

            food_rating = clamp(food_rating, 1, 5)
            delivery_rating = clamp(delivery_rating, 1, 5)

            complaint_flag = bool((food_rating < 3.0) or (delivery_rating < 3.0) or (sla_breach_flag and rng.random() < 0.22))

            review_text = None
            if complaint_flag:
                review_text = rng.choice([
                    "Food was cold",
                    "Delivery was late",
                    "Item quality was poor",
                    "Packaging issue",
                    "Not satisfied with the order",
                ])
            else:
                review_text = rng.choice([
                    "Good experience",
                    "Food was nice",
                    "Quick delivery",
                    "Satisfied",
                    "Good packaging",
                ])

            rating_rows.append({
                "rating_id": rating_id,
                "order_id": order_id,
                "user_id": uid,
                "restaurant_id": int(restaurant["restaurant_id"]),
                "rating_time": delivered_time + pd.Timedelta(minutes=int(rng.integers(10, 240))),
                "food_rating": round(food_rating, 1),
                "delivery_rating": round(delivery_rating, 1),
                "review_text": review_text,
                "complaint_flag": complaint_flag,
            })

            generated_food_rating = food_rating
            generated_delivery_rating = delivery_rating
            rating_id += 1

        # Refunds.
        refund_probability = (
            0.015
            + 0.05 * (restaurant_quality < 0.55)
            + 0.04 * sla_breach_flag
            + 0.05 * complaint_flag
        )

        refund_probability = clamp(refund_probability, 0.005, 0.22)

        refund_happened = rng.random() < refund_probability

        if refund_happened:
            refund_reason = rng.choice(
                ["missing_item", "wrong_item", "late_delivery", "poor_quality", "damaged_packaging"],
                p=[0.24, 0.14, 0.26, 0.26, 0.10],
            )

            refund_amount = order_value_base * rng.uniform(0.15, 0.75)

            refund_rows.append({
                "refund_id": refund_id,
                "order_id": order_id,
                "refund_amount": round(refund_amount, 2),
                "refund_reason": refund_reason,
                "refund_time": delivered_time + pd.Timedelta(minutes=int(rng.integers(30, 720))),
            })

            refund_id += 1

        # Update user state after delivered order.
        state["delivered_orders"] += 1
        state["last_order_date"] = delivered_time.date()

        bad_experience = bool(
            sla_breach_flag
            or refund_happened
            or (generated_food_rating is not None and generated_food_rating < 3.0)
            or (generated_delivery_rating is not None and generated_delivery_rating < 3.0)
        )

        if bad_experience:
            state["bad_experience_count"] += 1
        else:
            state["bad_experience_count"] = max(0, state["bad_experience_count"] - 1)

        if state["delivered_orders"] == 1 and state["first_order_bad"] is None:
            state["first_order_bad"] = bad_experience

        order_id += 1

    fact_search_events = pd.DataFrame(search_rows)
    fact_cart_events = pd.DataFrame(cart_rows)
    fact_orders = pd.DataFrame(order_rows)
    fact_delivery_ops = pd.DataFrame(delivery_rows)
    fact_refunds = pd.DataFrame(refund_rows)
    fact_ratings = pd.DataFrame(rating_rows)

    return (
        sessions,
        fact_search_events,
        fact_cart_events,
        fact_orders,
        fact_delivery_ops,
        fact_refunds,
        fact_ratings,
    )


def build_daily_metrics(fact_sessions, fact_orders, fact_delivery_ops, fact_refunds):
    """
    Build daily metrics for dashboard and forecasting.
    """
    sessions = fact_sessions.copy()
    orders = fact_orders.copy()
    delivery = fact_delivery_ops.copy()
    refunds = fact_refunds.copy()

    sessions["session_date"] = pd.to_datetime(sessions["session_start_time"]).dt.date

    if len(orders) > 0:
        orders["order_date"] = pd.to_datetime(orders["order_time"]).dt.date

    if len(delivery) > 0:
        delivery = delivery.merge(
            orders[["order_id", "order_date", "order_value", "discount_amount"]],
            on="order_id",
            how="left",
        )

    date_range = pd.date_range(START_DATE, END_DATE, freq="D").date
    daily = pd.DataFrame({"metric_date": date_range})

    sessions_daily = sessions.groupby("session_date").agg(
        total_sessions=("session_id", "nunique"),
        active_users=("user_id", "nunique"),
    ).reset_index().rename(columns={"session_date": "metric_date"})

    daily = daily.merge(sessions_daily, on="metric_date", how="left")

    if len(orders) > 0:
        orders_daily = orders.groupby("order_date").agg(
            total_orders=("order_id", "nunique"),
            delivered_orders=("order_id", lambda x: x[orders.loc[x.index, "order_status"].eq("delivered")].nunique()),
            cancelled_orders=("order_id", lambda x: x[orders.loc[x.index, "order_status"].eq("cancelled")].nunique()),
            gross_order_value=("order_value", "sum"),
            total_discount=("discount_amount", "sum"),
            platform_fee_total=("platform_fee", "sum"),
            delivery_fee_total=("delivery_fee", "sum"),
        ).reset_index().rename(columns={"order_date": "metric_date"})

        daily = daily.merge(orders_daily, on="metric_date", how="left")

    if len(delivery) > 0:
        delivery_daily = delivery.groupby("order_date").agg(
            avg_delivery_time_min=("total_delivery_time_min", "mean"),
            p90_delivery_time_min=("total_delivery_time_min", lambda x: np.percentile(x, 90)),
            sla_breach_orders=("sla_breach_flag", "sum"),
        ).reset_index().rename(columns={"order_date": "metric_date"})

        daily = daily.merge(delivery_daily, on="metric_date", how="left")

    if len(refunds) > 0 and len(orders) > 0:
        refunds = refunds.merge(
            orders[["order_id", "order_date"]],
            on="order_id",
            how="left",
        )

        refunds_daily = refunds.groupby("order_date").agg(
            refund_orders=("order_id", "nunique"),
            refund_amount=("refund_amount", "sum"),
        ).reset_index().rename(columns={"order_date": "metric_date"})

        daily = daily.merge(refunds_daily, on="metric_date", how="left")

    fill_zero_cols = [
        "total_sessions",
        "active_users",
        "total_orders",
        "delivered_orders",
        "cancelled_orders",
        "gross_order_value",
        "total_discount",
        "platform_fee_total",
        "delivery_fee_total",
        "sla_breach_orders",
        "refund_orders",
        "refund_amount",
    ]

    for col in fill_zero_cols:
        if col in daily.columns:
            daily[col] = daily[col].fillna(0)

    daily["aov"] = daily["gross_order_value"] / daily["delivered_orders"].replace(0, np.nan)
    daily["session_to_delivery_conversion"] = daily["delivered_orders"] / daily["total_sessions"].replace(0, np.nan)
    daily["cancellation_rate"] = daily["cancelled_orders"] / daily["total_orders"].replace(0, np.nan)
    daily["refund_rate"] = daily["refund_orders"] / daily["delivered_orders"].replace(0, np.nan)
    daily["discount_burn_pct"] = daily["total_discount"] / daily["gross_order_value"].replace(0, np.nan)
    daily["sla_breach_pct"] = daily["sla_breach_orders"] / daily["delivered_orders"].replace(0, np.nan)
    daily["delivered_orders_per_active_user"] = daily["delivered_orders"] / daily["active_users"].replace(0, np.nan)

    daily = daily.fillna(0)

    return daily


def validate_outputs(dim_users, dim_restaurants, fact_sessions, fact_search_events,
                     fact_cart_events, fact_orders, fact_delivery_ops, fact_refunds, fact_ratings):
    """
    Generate basic report.
    """
    report = []

    tables = {
        "dim_users": dim_users,
        "dim_restaurants": dim_restaurants,
        "fact_sessions": fact_sessions,
        "fact_search_events": fact_search_events,
        "fact_cart_events": fact_cart_events,
        "fact_orders": fact_orders,
        "fact_delivery_ops": fact_delivery_ops,
        "fact_refunds": fact_refunds,
        "fact_ratings": fact_ratings,
    }

    for table_name, df in tables.items():
        report.append({
            "table_name": table_name,
            "check": "row_count",
            "value": len(df),
        })

    if len(fact_orders) > 0:
        report.append({
            "table_name": "fact_orders",
            "check": "delivered_orders",
            "value": int((fact_orders["order_status"] == "delivered").sum()),
        })

        report.append({
            "table_name": "fact_orders",
            "check": "cancelled_orders",
            "value": int((fact_orders["order_status"] == "cancelled").sum()),
        })

        report.append({
            "table_name": "fact_orders",
            "check": "avg_order_value",
            "value": round(float(fact_orders["order_value"].mean()), 2),
        })

    if len(fact_delivery_ops) > 0:
        report.append({
            "table_name": "fact_delivery_ops",
            "check": "avg_delivery_time_min",
            "value": round(float(fact_delivery_ops["total_delivery_time_min"].mean()), 2),
        })

        report.append({
            "table_name": "fact_delivery_ops",
            "check": "p90_delivery_time_min",
            "value": round(float(np.percentile(fact_delivery_ops["total_delivery_time_min"], 90)), 2),
        })

        report.append({
            "table_name": "fact_delivery_ops",
            "check": "sla_breach_pct",
            "value": round(float(fact_delivery_ops["sla_breach_flag"].mean() * 100), 2),
        })

    if len(fact_refunds) > 0 and len(fact_orders) > 0:
        delivered_count = max(1, int((fact_orders["order_status"] == "delivered").sum()))
        report.append({
            "table_name": "fact_refunds",
            "check": "refund_rate_pct",
            "value": round(float(len(fact_refunds) / delivered_count * 100), 2),
        })

    return pd.DataFrame(report)


def main():
    print("Reading interim public datasets...")

    restaurants_raw = safe_read_csv(INTERIM_DIR / "cleaned_restaurants.csv")
    delivery_base = safe_read_csv(INTERIM_DIR / "cleaned_delivery_base.csv")
    preferences = safe_read_csv(INTERIM_DIR / "cleaned_user_preferences.csv")

    print(f"Restaurants base shape: {restaurants_raw.shape}")
    print(f"Delivery base shape: {delivery_base.shape}")
    print(f"User preference base shape: {preferences.shape}")

    print("\nBuilding dim_restaurants...")
    dim_restaurants = build_dim_restaurants(restaurants_raw)
    print(f"dim_restaurants shape: {dim_restaurants.shape}")

    print("\nBuilding dim_users...")
    dim_users = build_dim_users(preferences, dim_restaurants)
    print(f"dim_users shape: {dim_users.shape}")

    print("\nGenerating sessions, funnel events, orders, delivery ops, refunds, and ratings...")
    (
        fact_sessions,
        fact_search_events,
        fact_cart_events,
        fact_orders,
        fact_delivery_ops,
        fact_refunds,
        fact_ratings,
    ) = build_sessions_and_events(dim_users, dim_restaurants, delivery_base)

    print("\nBuilding daily marketplace metrics...")
    daily_marketplace_metrics = build_daily_metrics(
        fact_sessions,
        fact_orders,
        fact_delivery_ops,
        fact_refunds,
    )

    print("\nSaving processed tables...")

    outputs = {
        "dim_users.csv": dim_users,
        "dim_restaurants.csv": dim_restaurants,
        "fact_sessions.csv": fact_sessions,
        "fact_search_events.csv": fact_search_events,
        "fact_cart_events.csv": fact_cart_events,
        "fact_orders.csv": fact_orders,
        "fact_delivery_ops.csv": fact_delivery_ops,
        "fact_refunds.csv": fact_refunds,
        "fact_ratings.csv": fact_ratings,
        "daily_marketplace_metrics.csv": daily_marketplace_metrics,
    }

    for filename, df in outputs.items():
        path = PROCESSED_DIR / filename
        df.to_csv(path, index=False)
        print(f"Saved {path} | shape={df.shape}")

    report = validate_outputs(
        dim_users,
        dim_restaurants,
        fact_sessions,
        fact_search_events,
        fact_cart_events,
        fact_orders,
        fact_delivery_ops,
        fact_refunds,
        fact_ratings,
    )

    report_path = PROCESSED_DIR / "synthetic_generation_report.csv"
    report.to_csv(report_path, index=False)

    print("\nSynthetic generation report:")
    print(report)

    print(f"\nSaved report: {report_path}")
    print("\nSynthetic marketplace telemetry generation complete.")


if __name__ == "__main__":
    main()