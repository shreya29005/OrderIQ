/*
Analysis:
Funnel conversion by city, zone, and device type.

Business question:
Where are users dropping in the app-to-delivered-order journey?

Funnel:
App Open → Search → Restaurant Click → Cart → Payment → Delivered

Grain:
city + zone + device_type

Key metrics:
- app_opens
- searches
- restaurant_clicks
- carts
- payments
- delivered_orders
- search_rate
- search_to_click_rate
- click_to_cart_rate
- cart_to_payment_rate
- payment_to_delivery_rate
- session_to_delivery_conversion

Caveats:
1. Funnel stages are counted at distinct session grain to avoid duplicate counting.
2. Payment stage is represented by successful paid orders in fact_orders.
3. Delivered stage excludes cancelled orders.
*/

WITH session_base AS (
    SELECT
        session_id,
        user_id,
        city,
        zone,
        device_type,
        traffic_source,
        CAST(session_start_time AS DATE) AS session_date
    FROM fact_sessions
),

search_stage AS (
    SELECT
        session_id,
        COUNT(DISTINCT search_id) AS search_events,
        MAX(CASE WHEN result_count = 0 THEN 1 ELSE 0 END) AS had_zero_result_search,
        MAX(CASE WHEN low_result_flag = TRUE THEN 1 ELSE 0 END) AS had_low_result_search
    FROM fact_search_events
    GROUP BY session_id
),

click_stage AS (
    SELECT
        session_id,
        MAX(CASE WHEN clicked_restaurant_id IS NOT NULL THEN 1 ELSE 0 END) AS had_restaurant_click
    FROM fact_search_events
    GROUP BY session_id
),

cart_stage AS (
    SELECT
        session_id,
        COUNT(DISTINCT cart_id) AS cart_events
    FROM fact_cart_events
    GROUP BY session_id
),

payment_stage AS (
    SELECT
        session_id,
        COUNT(DISTINCT order_id) AS paid_orders
    FROM fact_orders
    WHERE payment_status = 'success'
    GROUP BY session_id
),

delivery_stage AS (
    SELECT
        session_id,
        COUNT(DISTINCT order_id) AS delivered_orders
    FROM fact_orders
    WHERE order_status = 'delivered'
    GROUP BY session_id
),

funnel_session_flags AS (
    SELECT
        sb.session_id,
        sb.user_id,
        sb.city,
        sb.zone,
        sb.device_type,
        sb.traffic_source,
        sb.session_date,

        1 AS app_open_flag,

        CASE
            WHEN ss.search_events > 0 THEN 1
            ELSE 0
        END AS search_flag,

        CASE
            WHEN cs.had_restaurant_click = 1 THEN 1
            ELSE 0
        END AS restaurant_click_flag,

        CASE
            WHEN cart.cart_events > 0 THEN 1
            ELSE 0
        END AS cart_flag,

        CASE
            WHEN ps.paid_orders > 0 THEN 1
            ELSE 0
        END AS payment_flag,

        CASE
            WHEN ds.delivered_orders > 0 THEN 1
            ELSE 0
        END AS delivered_flag,

        COALESCE(ss.had_zero_result_search, 0) AS had_zero_result_search,
        COALESCE(ss.had_low_result_search, 0) AS had_low_result_search

    FROM session_base sb
    LEFT JOIN search_stage ss
        ON sb.session_id = ss.session_id
    LEFT JOIN click_stage cs
        ON sb.session_id = cs.session_id
    LEFT JOIN cart_stage cart
        ON sb.session_id = cart.session_id
    LEFT JOIN payment_stage ps
        ON sb.session_id = ps.session_id
    LEFT JOIN delivery_stage ds
        ON sb.session_id = ds.session_id
),

funnel_aggregated AS (
    SELECT
        city,
        zone,
        device_type,

        COUNT(DISTINCT session_id) AS app_opens,

        COUNT(DISTINCT CASE WHEN search_flag = 1 THEN session_id END) AS searches,

        COUNT(DISTINCT CASE WHEN restaurant_click_flag = 1 THEN session_id END) AS restaurant_clicks,

        COUNT(DISTINCT CASE WHEN cart_flag = 1 THEN session_id END) AS carts,

        COUNT(DISTINCT CASE WHEN payment_flag = 1 THEN session_id END) AS payments,

        COUNT(DISTINCT CASE WHEN delivered_flag = 1 THEN session_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN had_zero_result_search = 1 THEN session_id END) AS zero_result_sessions,

        COUNT(DISTINCT CASE WHEN had_low_result_search = 1 THEN session_id END) AS low_result_sessions

    FROM funnel_session_flags
    GROUP BY
        city,
        zone,
        device_type
)

SELECT
    city,
    zone,
    device_type,

    app_opens,
    searches,
    restaurant_clicks,
    carts,
    payments,
    delivered_orders,
    zero_result_sessions,
    low_result_sessions,

        CASE
        WHEN app_opens = 0 THEN 0
        ELSE ROUND(100.0 * searches / app_opens, 2)
    END AS search_rate_pct,

    CASE
        WHEN searches = 0 THEN 0
        ELSE ROUND(100.0 * restaurant_clicks / searches, 2)
    END AS search_to_click_rate_pct,

    CASE
        WHEN restaurant_clicks = 0 THEN 0
        ELSE ROUND(100.0 * carts / restaurant_clicks, 2)
    END AS click_to_cart_rate_pct,

    CASE
        WHEN carts = 0 THEN 0
        ELSE ROUND(100.0 * payments / carts, 2)
    END AS cart_to_payment_rate_pct,

    CASE
        WHEN payments = 0 THEN 0
        ELSE ROUND(100.0 * delivered_orders / payments, 2)
    END AS payment_to_delivery_rate_pct,

    CASE
        WHEN app_opens = 0 THEN 0
        ELSE ROUND(100.0 * delivered_orders / app_opens, 2)
    END AS session_to_delivery_conversion_pct,

    CASE
        WHEN searches = 0 THEN 0
        ELSE ROUND(100.0 * zero_result_sessions / searches, 2)
    END AS zero_result_search_session_pct,

    CASE
        WHEN searches = 0 THEN 0
        ELSE ROUND(100.0 * low_result_sessions / searches, 2)
    END AS low_result_search_session_pct
    
FROM funnel_aggregated
WHERE app_opens >= 50
ORDER BY
    session_to_delivery_conversion_pct ASC,
    app_opens DESC;