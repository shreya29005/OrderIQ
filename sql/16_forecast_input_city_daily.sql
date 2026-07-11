/*
Analysis:
City-day forecast input metrics.

Business question:
What daily city-level features can be used for realistic lightweight forecasting?

Grain:
metric_date + city

Why this table exists:
The zone-day forecast table is too sparse because most date-zone combinations have zero orders.
This city-day table aggregates across zones and gives a cleaner forecasting signal.

Use cases:
1. Daily delivered-order forecasting.
2. Daily GMV forecasting.
3. Operational risk forecasting.
4. Marketplace demand trend dashboard.
5. Demand anomaly detection.

Target variables:
- delivered_orders
- gross_order_value
- operational_shock_flag

Caveats:
1. This is a feature table, not the forecasting model itself.
2. Rolling features use prior days only to avoid target leakage.
3. The table is city-day level, so it should have far fewer zero rows than zone-day.
*/

WITH calendar AS (
    SELECT
        CAST(calendar_date AS DATE) AS metric_date
    FROM generate_series(
        (SELECT MIN(CAST(order_time AS DATE)) FROM fact_orders),
        (SELECT MAX(CAST(order_time AS DATE)) FROM fact_orders),
        INTERVAL 1 DAY
    ) AS t(calendar_date)
),

cities AS (
    SELECT DISTINCT
        city
    FROM dim_restaurants
),

date_city_grid AS (
    SELECT
        c.metric_date,
        ct.city
    FROM calendar c
    CROSS JOIN cities ct
),

session_metrics AS (
    SELECT
        CAST(session_start_time AS DATE) AS metric_date,
        city,

        COUNT(DISTINCT session_id) AS total_sessions,
        COUNT(DISTINCT user_id) AS active_users,

        COUNT(DISTINCT CASE WHEN device_type = 'android' THEN session_id END) AS android_sessions,
        COUNT(DISTINCT CASE WHEN device_type = 'ios' THEN session_id END) AS ios_sessions,
        COUNT(DISTINCT CASE WHEN device_type = 'web' THEN session_id END) AS web_sessions

    FROM fact_sessions
    GROUP BY
        CAST(session_start_time AS DATE),
        city
),

search_metrics AS (
    SELECT
        CAST(se.search_time AS DATE) AS metric_date,
        s.city,

        COUNT(DISTINCT se.search_id) AS search_events,

        COUNT(DISTINCT CASE WHEN se.clicked_restaurant_id IS NOT NULL THEN se.search_id END)
            AS clicked_search_events,

        COUNT(DISTINCT CASE WHEN se.zero_result_flag = TRUE THEN se.search_id END)
            AS zero_result_searches,

        COUNT(DISTINCT CASE WHEN se.low_result_flag = TRUE THEN se.search_id END)
            AS low_result_searches,

        ROUND(AVG(se.result_count), 2) AS avg_result_count,
        ROUND(AVG(se.estimated_eta_min), 2) AS avg_estimated_eta_min

    FROM fact_search_events se
    INNER JOIN fact_sessions s
        ON se.session_id = s.session_id
    GROUP BY
        CAST(se.search_time AS DATE),
        s.city
),

cart_metrics AS (
    SELECT
        CAST(c.cart_created_time AS DATE) AS metric_date,
        s.city,

        COUNT(DISTINCT c.cart_id) AS cart_events,
        COUNT(DISTINCT c.user_id) AS cart_users,
        ROUND(SUM(c.cart_value), 2) AS cart_value

    FROM fact_cart_events c
    INNER JOIN fact_sessions s
        ON c.session_id = s.session_id
    GROUP BY
        CAST(c.cart_created_time AS DATE),
        s.city
),

order_base AS (
    SELECT
        CAST(o.order_time AS DATE) AS metric_date,

        r.city,
        r.zone,

        o.order_id,
        o.session_id,
        o.user_id,
        o.restaurant_id,
        o.order_status,

        COALESCE(o.order_value, 0) AS order_value,
        COALESCE(o.discount_amount, 0) AS discount_amount,
        COALESCE(o.platform_fee, 0) AS platform_fee,
        COALESCE(o.delivery_fee, 0) AS delivery_fee

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
),

order_metrics AS (
    SELECT
        metric_date,
        city,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN user_id END) AS ordering_users,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN restaurant_id END) AS active_restaurants,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN zone END) AS active_zones,

        ROUND(
            SUM(
                CASE
                    WHEN order_status = 'delivered' THEN order_value
                    ELSE 0
                END
            ),
            2
        ) AS gross_order_value,

        ROUND(
            SUM(
                CASE
                    WHEN order_status = 'delivered' THEN discount_amount
                    ELSE 0
                END
            ),
            2
        ) AS total_discount,

        ROUND(
            SUM(
                CASE
                    WHEN order_status = 'delivered' THEN platform_fee
                    ELSE 0
                END
            ),
            2
        ) AS platform_fee_total,

        ROUND(
            SUM(
                CASE
                    WHEN order_status = 'delivered' THEN delivery_fee
                    ELSE 0
                END
            ),
            2
        ) AS delivery_fee_total,

        ROUND(
            AVG(
                CASE
                    WHEN order_status = 'delivered' THEN order_value
                    ELSE NULL
                END
            ),
            2
        ) AS avg_order_value

    FROM order_base
    GROUP BY
        metric_date,
        city
),

delivery_metrics AS (
    SELECT
        ob.metric_date,
        ob.city,

        ROUND(AVG(d.total_delivery_time_min), 2) AS avg_delivery_time_min,
        ROUND(QUANTILE_CONT(d.total_delivery_time_min, 0.50), 2) AS p50_delivery_time_min,
        ROUND(QUANTILE_CONT(d.total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        ROUND(AVG(d.prep_time_min), 2) AS avg_prep_time_min,
        ROUND(AVG(d.rider_wait_time_min), 2) AS avg_rider_wait_time_min,
        ROUND(AVG(d.drop_time_min), 2) AS avg_drop_time_min,
        ROUND(AVG(d.distance_km), 2) AS avg_distance_km,

        SUM(
            CASE
                WHEN d.sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_orders

    FROM order_base ob
    INNER JOIN fact_delivery_ops d
        ON ob.order_id = d.order_id
    WHERE ob.order_status = 'delivered'
    GROUP BY
        ob.metric_date,
        ob.city
),

refund_metrics AS (
    SELECT
        ob.metric_date,
        ob.city,

        COUNT(DISTINCT rf.order_id) AS refund_orders,
        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount

    FROM order_base ob
    INNER JOIN fact_refunds rf
        ON ob.order_id = rf.order_id
    GROUP BY
        ob.metric_date,
        ob.city
),

rating_metrics AS (
    SELECT
        ob.metric_date,
        ob.city,

        COUNT(DISTINCT rt.order_id) AS rated_orders,

        ROUND(AVG(rt.food_rating), 2) AS avg_food_rating,
        ROUND(AVG(rt.delivery_rating), 2) AS avg_delivery_rating,

        SUM(
            CASE
                WHEN rt.complaint_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS complaint_orders

    FROM order_base ob
    INNER JOIN fact_ratings rt
        ON ob.order_id = rt.order_id
    GROUP BY
        ob.metric_date,
        ob.city
),

supply_snapshot AS (
    SELECT
        city,

        COUNT(DISTINCT restaurant_id) AS total_restaurants,
        COUNT(DISTINCT zone) AS total_zones,
        COUNT(DISTINCT primary_cuisine) AS cuisine_depth,

        ROUND(
            100.0 * SUM(CASE WHEN online_order_flag = TRUE THEN 1 ELSE 0 END)
            / COUNT(*),
            2
        ) AS online_enabled_restaurant_pct,

        ROUND(AVG(COALESCE(restaurant_quality_prior, 0)), 3) AS avg_restaurant_quality_prior

    FROM dim_restaurants
    GROUP BY
        city
),

combined AS (
    SELECT
        g.metric_date,
        g.city,

        COALESCE(sm.total_sessions, 0) AS total_sessions,
        COALESCE(sm.active_users, 0) AS active_users,
        COALESCE(sm.android_sessions, 0) AS android_sessions,
        COALESCE(sm.ios_sessions, 0) AS ios_sessions,
        COALESCE(sm.web_sessions, 0) AS web_sessions,

        COALESCE(search.search_events, 0) AS search_events,
        COALESCE(search.clicked_search_events, 0) AS clicked_search_events,
        COALESCE(search.zero_result_searches, 0) AS zero_result_searches,
        COALESCE(search.low_result_searches, 0) AS low_result_searches,
        COALESCE(search.avg_result_count, 0) AS avg_result_count,
        COALESCE(search.avg_estimated_eta_min, 0) AS avg_estimated_eta_min,

        COALESCE(cart.cart_events, 0) AS cart_events,
        COALESCE(cart.cart_users, 0) AS cart_users,
        COALESCE(cart.cart_value, 0) AS cart_value,

        COALESCE(om.total_orders, 0) AS total_orders,
        COALESCE(om.delivered_orders, 0) AS delivered_orders,
        COALESCE(om.cancelled_orders, 0) AS cancelled_orders,
        COALESCE(om.ordering_users, 0) AS ordering_users,
        COALESCE(om.active_restaurants, 0) AS active_restaurants,
        COALESCE(om.active_zones, 0) AS active_zones,

        COALESCE(om.gross_order_value, 0) AS gross_order_value,
        COALESCE(om.total_discount, 0) AS total_discount,
        COALESCE(om.platform_fee_total, 0) AS platform_fee_total,
        COALESCE(om.delivery_fee_total, 0) AS delivery_fee_total,
        COALESCE(om.avg_order_value, 0) AS avg_order_value,

        COALESCE(dm.avg_delivery_time_min, 0) AS avg_delivery_time_min,
        COALESCE(dm.p50_delivery_time_min, 0) AS p50_delivery_time_min,
        COALESCE(dm.p90_delivery_time_min, 0) AS p90_delivery_time_min,
        COALESCE(dm.avg_prep_time_min, 0) AS avg_prep_time_min,
        COALESCE(dm.avg_rider_wait_time_min, 0) AS avg_rider_wait_time_min,
        COALESCE(dm.avg_drop_time_min, 0) AS avg_drop_time_min,
        COALESCE(dm.avg_distance_km, 0) AS avg_distance_km,
        COALESCE(dm.sla_breach_orders, 0) AS sla_breach_orders,

        COALESCE(rfm.refund_orders, 0) AS refund_orders,
        COALESCE(rfm.total_refund_amount, 0) AS total_refund_amount,

        COALESCE(rtm.rated_orders, 0) AS rated_orders,
        COALESCE(rtm.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rtm.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rtm.complaint_orders, 0) AS complaint_orders,

        COALESCE(ss.total_restaurants, 0) AS total_restaurants,
        COALESCE(ss.total_zones, 0) AS total_zones,
        COALESCE(ss.cuisine_depth, 0) AS cuisine_depth,
        COALESCE(ss.online_enabled_restaurant_pct, 0) AS online_enabled_restaurant_pct,
        COALESCE(ss.avg_restaurant_quality_prior, 0) AS avg_restaurant_quality_prior

    FROM date_city_grid g
    LEFT JOIN session_metrics sm
        ON g.metric_date = sm.metric_date
        AND g.city = sm.city
    LEFT JOIN search_metrics search
        ON g.metric_date = search.metric_date
        AND g.city = search.city
    LEFT JOIN cart_metrics cart
        ON g.metric_date = cart.metric_date
        AND g.city = cart.city
    LEFT JOIN order_metrics om
        ON g.metric_date = om.metric_date
        AND g.city = om.city
    LEFT JOIN delivery_metrics dm
        ON g.metric_date = dm.metric_date
        AND g.city = dm.city
    LEFT JOIN refund_metrics rfm
        ON g.metric_date = rfm.metric_date
        AND g.city = rfm.city
    LEFT JOIN rating_metrics rtm
        ON g.metric_date = rtm.metric_date
        AND g.city = rtm.city
    LEFT JOIN supply_snapshot ss
        ON g.city = ss.city
),

rates AS (
    SELECT
        *,

        CAST(STRFTIME(metric_date, '%w') AS INTEGER) AS day_of_week_num,

        CASE CAST(STRFTIME(metric_date, '%w') AS INTEGER)
            WHEN 0 THEN 'Sunday'
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
            ELSE 'Unknown'
        END AS day_of_week,

        CASE
            WHEN CAST(STRFTIME(metric_date, '%w') AS INTEGER) IN (0, 6) THEN 1
            ELSE 0
        END AS weekend_flag,

        EXTRACT(DAY FROM metric_date) AS day_of_month,
        EXTRACT(MONTH FROM metric_date) AS month_num,
        CAST(STRFTIME(metric_date, '%W') AS INTEGER) AS week_of_year,

        CASE
            WHEN total_sessions = 0 THEN 0
            ELSE ROUND(100.0 * search_events / total_sessions, 2)
        END AS search_rate_pct,

        CASE
            WHEN search_events = 0 THEN 0
            ELSE ROUND(100.0 * clicked_search_events / search_events, 2)
        END AS search_click_rate_pct,

        CASE
            WHEN search_events = 0 THEN 0
            ELSE ROUND(100.0 * zero_result_searches / search_events, 2)
        END AS zero_result_search_rate_pct,

        CASE
            WHEN search_events = 0 THEN 0
            ELSE ROUND(100.0 * low_result_searches / search_events, 2)
        END AS low_result_search_rate_pct,

        CASE
            WHEN total_sessions = 0 THEN 0
            ELSE ROUND(100.0 * cart_events / total_sessions, 2)
        END AS cart_rate_pct,

        CASE
            WHEN total_sessions = 0 THEN 0
            ELSE ROUND(100.0 * delivered_orders / total_sessions, 2)
        END AS session_to_delivery_conversion_pct,

        CASE
            WHEN total_orders = 0 THEN 0
            ELSE ROUND(100.0 * delivered_orders / total_orders, 2)
        END AS delivery_success_rate_pct,

        CASE
            WHEN total_orders = 0 THEN 0
            ELSE ROUND(100.0 * cancelled_orders / total_orders, 2)
        END AS cancellation_rate_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * sla_breach_orders / delivered_orders, 2)
        END AS sla_breach_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * refund_orders / delivered_orders, 2)
        END AS refund_rate_pct,

        CASE
            WHEN rated_orders = 0 THEN 0
            ELSE ROUND(100.0 * complaint_orders / rated_orders, 2)
        END AS complaint_rate_pct,

        CASE
            WHEN gross_order_value = 0 THEN 0
            ELSE ROUND(100.0 * total_discount / gross_order_value, 2)
        END AS discount_burn_pct,

        ROUND(
            platform_fee_total + delivery_fee_total - total_discount - total_refund_amount,
            2
        ) AS contribution_proxy

    FROM combined
),

features AS (
    SELECT
        *,

        COALESCE(
            LAG(delivered_orders, 1) OVER (
                PARTITION BY city
                ORDER BY metric_date
            ),
            0
        ) AS delivered_orders_lag_1d,

        COALESCE(
            LAG(delivered_orders, 7) OVER (
                PARTITION BY city
                ORDER BY metric_date
            ),
            0
        ) AS delivered_orders_lag_7d,

        COALESCE(
            LAG(gross_order_value, 1) OVER (
                PARTITION BY city
                ORDER BY metric_date
            ),
            0
        ) AS gross_order_value_lag_1d,

        COALESCE(
            LAG(gross_order_value, 7) OVER (
                PARTITION BY city
                ORDER BY metric_date
            ),
            0
        ) AS gross_order_value_lag_7d,

        COALESCE(
            ROUND(
                AVG(delivered_orders) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS delivered_orders_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(delivered_orders) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS delivered_orders_rolling_14d_avg,

        COALESCE(
            ROUND(
                AVG(delivered_orders) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 28 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS delivered_orders_rolling_28d_avg,

        COALESCE(
            ROUND(
                AVG(gross_order_value) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS gross_order_value_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(avg_order_value) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS avg_order_value_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(total_sessions) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS total_sessions_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(search_events) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS search_events_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(cart_events) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS cart_events_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(cancellation_rate_pct) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS cancellation_rate_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(sla_breach_pct) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS sla_breach_rate_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(refund_rate_pct) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS refund_rate_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(complaint_rate_pct) OVER (
                    PARTITION BY city
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS complaint_rate_rolling_7d_avg

    FROM rates
)

SELECT
    metric_date,
    city,

    day_of_week_num,
    day_of_week,
    weekend_flag,
    day_of_month,
    month_num,
    week_of_year,

    total_sessions,
    active_users,
    android_sessions,
    ios_sessions,
    web_sessions,

    search_events,
    clicked_search_events,
    zero_result_searches,
    low_result_searches,
    avg_result_count,
    avg_estimated_eta_min,

    cart_events,
    cart_users,
    cart_value,

    total_orders,
    delivered_orders,
    cancelled_orders,
    ordering_users,
    active_restaurants,
    active_zones,

    gross_order_value,
    total_discount,
    platform_fee_total,
    delivery_fee_total,
    total_refund_amount,
    contribution_proxy,

    avg_order_value,

    search_rate_pct,
    search_click_rate_pct,
    zero_result_search_rate_pct,
    low_result_search_rate_pct,
    cart_rate_pct,
    session_to_delivery_conversion_pct,

    delivery_success_rate_pct,
    cancellation_rate_pct,

    avg_delivery_time_min,
    p50_delivery_time_min,
    p90_delivery_time_min,
    avg_prep_time_min,
    avg_rider_wait_time_min,
    avg_drop_time_min,
    avg_distance_km,
    sla_breach_orders,
    sla_breach_pct,

    refund_orders,
    refund_rate_pct,

    rated_orders,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,
    complaint_rate_pct,

    discount_burn_pct,

    total_restaurants,
    total_zones,
    cuisine_depth,
    online_enabled_restaurant_pct,
    avg_restaurant_quality_prior,

    delivered_orders_lag_1d,
    delivered_orders_lag_7d,
    gross_order_value_lag_1d,
    gross_order_value_lag_7d,

    delivered_orders_rolling_7d_avg,
    delivered_orders_rolling_14d_avg,
    delivered_orders_rolling_28d_avg,

    gross_order_value_rolling_7d_avg,
    avg_order_value_rolling_7d_avg,

    total_sessions_rolling_7d_avg,
    search_events_rolling_7d_avg,
    cart_events_rolling_7d_avg,

    cancellation_rate_rolling_7d_avg,
    sla_breach_rate_rolling_7d_avg,
    refund_rate_rolling_7d_avg,
    complaint_rate_rolling_7d_avg,

    CASE
        WHEN delivered_orders_rolling_28d_avg > 0
             AND delivered_orders >= 1.25 * delivered_orders_rolling_28d_avg
            THEN 1
        ELSE 0
    END AS positive_demand_spike_flag,

    CASE
        WHEN delivered_orders_rolling_28d_avg > 0
             AND delivered_orders <= 0.75 * delivered_orders_rolling_28d_avg
            THEN 1
        ELSE 0
    END AS negative_demand_drop_flag,

    CASE
        WHEN sla_breach_pct >= 20
             OR cancellation_rate_pct >= 8
             OR refund_rate_pct >= 6
             OR complaint_rate_pct >= 30
            THEN 1
        ELSE 0
    END AS operational_shock_flag,

    CASE
        WHEN delivered_orders >= 60 THEN 'high_signal_day'
        WHEN delivered_orders >= 30 THEN 'medium_signal_day'
        WHEN delivered_orders > 0 THEN 'low_signal_day'
        ELSE 'zero_order_day'
    END AS forecast_signal_tier

FROM features
ORDER BY
    metric_date,
    city;