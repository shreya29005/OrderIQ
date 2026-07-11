/*
Analysis:
Search result quality diagnostics.

Business question:
Which search journeys are failing due to poor result quality, weak click-through,
low supply depth, high ETA, or weak downstream conversion?

Grain:
city + zone + search_query

Key metrics:
- total_searches
- unique_searching_users
- avg_result_count
- zero_result_search_rate_pct
- low_result_search_rate_pct
- search_click_rate_pct
- avg_search_to_click_seconds
- avg_estimated_eta_min
- cart_after_search_rate_pct
- order_after_search_rate_pct
- delivered_after_search_rate_pct
- search_quality_score
- search_quality_tier
- recommended_action

Caveats:
1. Search quality is measured at search event level.
2. Cart/order conversion is approximated at session grain after a search event.
3. This is a diagnostic product scorecard, not a ranking algorithm.
*/

WITH search_base AS (
    SELECT
        se.search_id,
        se.session_id,
        se.user_id,
        CAST(se.search_time AS TIMESTAMP) AS search_timestamp,
        CAST(se.search_time AS DATE) AS search_date,

        LOWER(TRIM(COALESCE(se.search_query, 'unknown'))) AS search_query,

        COALESCE(se.result_count, 0) AS result_count,
        se.clicked_restaurant_id,

        CASE
            WHEN se.zero_result_flag = TRUE THEN 1
            ELSE 0
        END AS zero_result_flag,

        CASE
            WHEN se.low_result_flag = TRUE THEN 1
            ELSE 0
        END AS low_result_flag,

        COALESCE(se.search_to_click_seconds, 0) AS search_to_click_seconds,
        COALESCE(se.estimated_eta_min, 0) AS estimated_eta_min,

        s.city,
        s.zone,
        s.device_type,
        s.traffic_source,

        u.user_segment,
        u.acquisition_channel,
        u.income_proxy,
        u.gold_member_flag

    FROM fact_search_events se
    INNER JOIN fact_sessions s
        ON se.session_id = s.session_id
    INNER JOIN dim_users u
        ON se.user_id = u.user_id
),

clicked_restaurant AS (
    SELECT
        sb.search_id,

        r.restaurant_id AS clicked_restaurant_id,
        r.restaurant_name AS clicked_restaurant_name,
        COALESCE(r.primary_cuisine, 'unknown') AS clicked_primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS clicked_price_band,
        COALESCE(r.rating, 0) AS clicked_public_rating,
        COALESCE(r.restaurant_quality_prior, 0) AS clicked_restaurant_quality_prior

    FROM search_base sb
    LEFT JOIN dim_restaurants r
        ON sb.clicked_restaurant_id = r.restaurant_id
),

session_cart AS (
    SELECT
        session_id,
        COUNT(DISTINCT cart_id) AS cart_events
    FROM fact_cart_events
    GROUP BY
        session_id
),

session_order AS (
    SELECT
        session_id,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END)
            AS delivered_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END)
            AS cancelled_orders,

        ROUND(SUM(order_value), 2) AS gross_order_value,
        ROUND(SUM(discount_amount), 2) AS total_discount

    FROM fact_orders
    GROUP BY
        session_id
),

search_enriched AS (
    SELECT
        sb.search_id,
        sb.session_id,
        sb.user_id,
        sb.search_query,
        sb.city,
        sb.zone,
        sb.device_type,
        sb.traffic_source,
        sb.user_segment,
        sb.acquisition_channel,

        sb.result_count,
        sb.clicked_restaurant_id,
        sb.zero_result_flag,
        sb.low_result_flag,
        sb.search_to_click_seconds,
        sb.estimated_eta_min,

        CASE
            WHEN sb.clicked_restaurant_id IS NOT NULL THEN 1
            ELSE 0
        END AS click_flag,

        COALESCE(cr.clicked_primary_cuisine, 'unknown') AS clicked_primary_cuisine,
        COALESCE(cr.clicked_price_band, 'unknown') AS clicked_price_band,
        COALESCE(cr.clicked_public_rating, 0) AS clicked_public_rating,
        COALESCE(cr.clicked_restaurant_quality_prior, 0) AS clicked_restaurant_quality_prior,

        CASE
            WHEN COALESCE(sc.cart_events, 0) > 0 THEN 1
            ELSE 0
        END AS cart_after_search_flag,

        CASE
            WHEN COALESCE(so.total_orders, 0) > 0 THEN 1
            ELSE 0
        END AS order_after_search_flag,

        CASE
            WHEN COALESCE(so.delivered_orders, 0) > 0 THEN 1
            ELSE 0
        END AS delivered_after_search_flag,

        COALESCE(so.total_orders, 0) AS session_total_orders,
        COALESCE(so.delivered_orders, 0) AS session_delivered_orders,
        COALESCE(so.cancelled_orders, 0) AS session_cancelled_orders,
        COALESCE(so.gross_order_value, 0) AS session_gross_order_value,
        COALESCE(so.total_discount, 0) AS session_total_discount

    FROM search_base sb
    LEFT JOIN clicked_restaurant cr
        ON sb.search_id = cr.search_id
    LEFT JOIN session_cart sc
        ON sb.session_id = sc.session_id
    LEFT JOIN session_order so
        ON sb.session_id = so.session_id
),

grouped AS (
    SELECT
        city,
        zone,
        search_query,

        COUNT(DISTINCT search_id) AS total_searches,
        COUNT(DISTINCT session_id) AS search_sessions,
        COUNT(DISTINCT user_id) AS unique_searching_users,

        ROUND(AVG(result_count), 2) AS avg_result_count,

        SUM(zero_result_flag) AS zero_result_searches,
        SUM(low_result_flag) AS low_result_searches,
        SUM(click_flag) AS clicked_searches,

        ROUND(
            AVG(
                CASE
                    WHEN click_flag = 1 THEN search_to_click_seconds
                    ELSE NULL
                END
            ),
            2
        ) AS avg_search_to_click_seconds,

        ROUND(AVG(estimated_eta_min), 2) AS avg_estimated_eta_min,

        COUNT(DISTINCT CASE WHEN cart_after_search_flag = 1 THEN session_id END)
            AS cart_after_search_sessions,

        COUNT(DISTINCT CASE WHEN order_after_search_flag = 1 THEN session_id END)
            AS order_after_search_sessions,

        COUNT(DISTINCT CASE WHEN delivered_after_search_flag = 1 THEN session_id END)
            AS delivered_after_search_sessions,

        SUM(session_total_orders) AS total_orders_from_search_sessions,
        SUM(session_delivered_orders) AS delivered_orders_from_search_sessions,
        SUM(session_cancelled_orders) AS cancelled_orders_from_search_sessions,

        ROUND(SUM(session_gross_order_value), 2) AS gross_order_value_from_search_sessions,
        ROUND(SUM(session_total_discount), 2) AS total_discount_from_search_sessions,

        COUNT(DISTINCT CASE WHEN clicked_restaurant_id IS NOT NULL THEN clicked_restaurant_id END)
            AS clicked_restaurant_count,

        COUNT(DISTINCT CASE WHEN clicked_primary_cuisine != 'unknown' THEN clicked_primary_cuisine END)
            AS clicked_cuisine_count,

        ROUND(AVG(CASE WHEN click_flag = 1 THEN clicked_public_rating ELSE NULL END), 2)
            AS avg_clicked_public_rating,

        ROUND(AVG(CASE WHEN click_flag = 1 THEN clicked_restaurant_quality_prior ELSE NULL END), 3)
            AS avg_clicked_restaurant_quality_prior

    FROM search_enriched
    GROUP BY
        city,
        zone,
        search_query
),

rates AS (
    SELECT
        *,

        CASE
            WHEN total_searches = 0 THEN 0
            ELSE ROUND(100.0 * zero_result_searches / total_searches, 2)
        END AS zero_result_search_rate_pct,

        CASE
            WHEN total_searches = 0 THEN 0
            ELSE ROUND(100.0 * low_result_searches / total_searches, 2)
        END AS low_result_search_rate_pct,

        CASE
            WHEN total_searches = 0 THEN 0
            ELSE ROUND(100.0 * clicked_searches / total_searches, 2)
        END AS search_click_rate_pct,

        CASE
            WHEN search_sessions = 0 THEN 0
            ELSE ROUND(100.0 * cart_after_search_sessions / search_sessions, 2)
        END AS cart_after_search_rate_pct,

        CASE
            WHEN search_sessions = 0 THEN 0
            ELSE ROUND(100.0 * order_after_search_sessions / search_sessions, 2)
        END AS order_after_search_rate_pct,

        CASE
            WHEN search_sessions = 0 THEN 0
            ELSE ROUND(100.0 * delivered_after_search_sessions / search_sessions, 2)
        END AS delivered_after_search_rate_pct,

        CASE
            WHEN total_orders_from_search_sessions = 0 THEN 0
            ELSE ROUND(
                100.0 * cancelled_orders_from_search_sessions
                / total_orders_from_search_sessions,
                2
            )
        END AS cancellation_rate_from_search_sessions_pct,

        CASE
            WHEN gross_order_value_from_search_sessions = 0 THEN 0
            ELSE ROUND(
                100.0 * total_discount_from_search_sessions
                / gross_order_value_from_search_sessions,
                2
            )
        END AS discount_burn_from_search_sessions_pct

    FROM grouped
),

scored AS (
    SELECT
        *,

        ROUND(
            20 * LEAST(search_click_rate_pct / 60.0, 1.0)
            + 15 * LEAST(delivered_after_search_rate_pct / 15.0, 1.0)
            + 15 * (1 - LEAST(zero_result_search_rate_pct / 20.0, 1.0))
            + 15 * (1 - LEAST(low_result_search_rate_pct / 50.0, 1.0))
            + 10 * (1 - LEAST(GREATEST(avg_estimated_eta_min - 25, 0) / 35.0, 1.0))
            + 10 * LEAST(clicked_restaurant_count / 25.0, 1.0)
            + 10 * LEAST(COALESCE(avg_clicked_restaurant_quality_prior, 0), 1.0)
            + 5 * (1 - LEAST(cancellation_rate_from_search_sessions_pct / 20.0, 1.0)),
            2
        ) AS search_quality_score

    FROM rates
)

SELECT
    city,
    zone,
    search_query,

    total_searches,
    search_sessions,
    unique_searching_users,

    avg_result_count,
    zero_result_searches,
    low_result_searches,
    clicked_searches,

    zero_result_search_rate_pct,
    low_result_search_rate_pct,
    search_click_rate_pct,

    COALESCE(avg_search_to_click_seconds, 0) AS avg_search_to_click_seconds,
    avg_estimated_eta_min,

    cart_after_search_sessions,
    order_after_search_sessions,
    delivered_after_search_sessions,

    cart_after_search_rate_pct,
    order_after_search_rate_pct,
    delivered_after_search_rate_pct,

    total_orders_from_search_sessions,
    delivered_orders_from_search_sessions,
    cancelled_orders_from_search_sessions,
    cancellation_rate_from_search_sessions_pct,

    gross_order_value_from_search_sessions,
    total_discount_from_search_sessions,
    discount_burn_from_search_sessions_pct,

    clicked_restaurant_count,
    clicked_cuisine_count,

    COALESCE(avg_clicked_public_rating, 0) AS avg_clicked_public_rating,
    COALESCE(avg_clicked_restaurant_quality_prior, 0) AS avg_clicked_restaurant_quality_prior,

    search_quality_score,

    CASE
        WHEN search_quality_score >= 75 THEN 'strong_search_experience'
        WHEN search_quality_score >= 60 THEN 'acceptable_search_experience'
        WHEN search_quality_score >= 45 THEN 'weak_search_experience'
        ELSE 'broken_search_experience'
    END AS search_quality_tier,

    CASE
        WHEN zero_result_search_rate_pct >= 10
            THEN 'fix_zero_results'
        WHEN low_result_search_rate_pct >= 35
            THEN 'improve_result_depth'
        WHEN search_click_rate_pct < 35
            THEN 'improve_result_ranking'
        WHEN avg_estimated_eta_min >= 45
            THEN 'improve_eta_or_supply_radius'
        WHEN delivered_after_search_rate_pct < 5
            THEN 'fix_search_to_order_conversion'
        ELSE 'maintain_and_scale'
    END AS recommended_action

FROM scored
WHERE total_searches >= 25
ORDER BY
    search_quality_score ASC,
    total_searches DESC;