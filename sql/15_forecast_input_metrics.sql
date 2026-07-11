/*
Analysis:
Forecast input metrics.

Business question:
What daily zone-level features can be used for light marketplace forecasting?

Grain:
metric_date + city + zone

Use cases:
1. Daily delivered-order forecasting.
2. GMV forecasting.
3. Operational risk forecasting.
4. Demand anomaly detection.
5. Dashboard trend analysis.

Key metrics:
- delivered_orders
- gross_order_value
- avg_order_value
- cancellation_rate_pct
- sla_breach_pct
- refund_rate_pct
- complaint_rate_pct
- lag features
- rolling 7-day, 14-day, and 28-day features
- demand anomaly flags
- operational shock flags

Caveats:
1. This is a feature table, not a forecasting model.
2. Rolling features use prior days only to avoid target leakage.
3. Missing date-zone combinations are filled with zero metrics.
4. Forecasting can later be done in Python using this table.
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

zones AS (
    SELECT DISTINCT
        city,
        zone
    FROM dim_restaurants
),

date_zone_grid AS (
    SELECT
        c.metric_date,
        z.city,
        z.zone
    FROM calendar c
    CROSS JOIN zones z
),

order_base AS (
    SELECT
        CAST(o.order_time AS DATE) AS metric_date,

        r.city,
        r.zone,

        o.order_id,
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
        zone,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN user_id END) AS ordering_users,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN restaurant_id END) AS active_restaurants,

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
        city,
        zone
),

delivery_by_order AS (
    SELECT
        order_id,

        MAX(total_delivery_time_min) AS total_delivery_time_min,
        MAX(prep_time_min) AS prep_time_min,
        MAX(rider_wait_time_min) AS rider_wait_time_min,
        MAX(drop_time_min) AS drop_time_min,
        MAX(distance_km) AS distance_km,

        MAX(
            CASE
                WHEN sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_flag

    FROM fact_delivery_ops
    GROUP BY
        order_id
),

delivery_metrics AS (
    SELECT
        ob.metric_date,
        ob.city,
        ob.zone,

        ROUND(AVG(d.total_delivery_time_min), 2) AS avg_delivery_time_min,
        ROUND(QUANTILE_CONT(d.total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        ROUND(AVG(d.prep_time_min), 2) AS avg_prep_time_min,
        ROUND(AVG(d.rider_wait_time_min), 2) AS avg_rider_wait_time_min,
        ROUND(AVG(d.drop_time_min), 2) AS avg_drop_time_min,
        ROUND(AVG(d.distance_km), 2) AS avg_distance_km,

        SUM(d.sla_breach_flag) AS sla_breach_orders

    FROM order_base ob
    INNER JOIN delivery_by_order d
        ON ob.order_id = d.order_id
    WHERE ob.order_status = 'delivered'
    GROUP BY
        ob.metric_date,
        ob.city,
        ob.zone
),

refund_by_order AS (
    SELECT
        order_id,

        COUNT(DISTINCT refund_id) AS refund_count,

        ROUND(SUM(refund_amount), 2) AS refund_amount

    FROM fact_refunds
    GROUP BY
        order_id
),

refund_metrics AS (
    SELECT
        ob.metric_date,
        ob.city,
        ob.zone,

        COUNT(DISTINCT rb.order_id) AS refund_orders,
        ROUND(SUM(rb.refund_amount), 2) AS total_refund_amount

    FROM order_base ob
    INNER JOIN refund_by_order rb
        ON ob.order_id = rb.order_id
    GROUP BY
        ob.metric_date,
        ob.city,
        ob.zone
),

rating_by_order AS (
    SELECT
        order_id,

        COUNT(DISTINCT rating_id) AS rating_count,

        AVG(food_rating) AS food_rating,
        AVG(delivery_rating) AS delivery_rating,

        MAX(
            CASE
                WHEN complaint_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS complaint_flag

    FROM fact_ratings
    GROUP BY
        order_id
),

rating_metrics AS (
    SELECT
        ob.metric_date,
        ob.city,
        ob.zone,

        COUNT(DISTINCT rb.order_id) AS rated_orders,

        ROUND(AVG(rb.food_rating), 2) AS avg_food_rating,
        ROUND(AVG(rb.delivery_rating), 2) AS avg_delivery_rating,

        SUM(rb.complaint_flag) AS complaint_orders

    FROM order_base ob
    INNER JOIN rating_by_order rb
        ON ob.order_id = rb.order_id
    GROUP BY
        ob.metric_date,
        ob.city,
        ob.zone
),

combined AS (
    SELECT
        g.metric_date,
        g.city,
        g.zone,

        COALESCE(om.total_orders, 0) AS total_orders,
        COALESCE(om.delivered_orders, 0) AS delivered_orders,
        COALESCE(om.cancelled_orders, 0) AS cancelled_orders,
        COALESCE(om.ordering_users, 0) AS ordering_users,
        COALESCE(om.active_restaurants, 0) AS active_restaurants,

        COALESCE(om.gross_order_value, 0) AS gross_order_value,
        COALESCE(om.total_discount, 0) AS total_discount,
        COALESCE(om.platform_fee_total, 0) AS platform_fee_total,
        COALESCE(om.delivery_fee_total, 0) AS delivery_fee_total,
        COALESCE(om.avg_order_value, 0) AS avg_order_value,

        COALESCE(dm.avg_delivery_time_min, 0) AS avg_delivery_time_min,
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
        COALESCE(rtm.complaint_orders, 0) AS complaint_orders

    FROM date_zone_grid g
    LEFT JOIN order_metrics om
        ON g.metric_date = om.metric_date
        AND g.city = om.city
        AND g.zone = om.zone
    LEFT JOIN delivery_metrics dm
        ON g.metric_date = dm.metric_date
        AND g.city = dm.city
        AND g.zone = dm.zone
    LEFT JOIN refund_metrics rfm
        ON g.metric_date = rfm.metric_date
        AND g.city = rfm.city
        AND g.zone = rfm.zone
    LEFT JOIN rating_metrics rtm
        ON g.metric_date = rtm.metric_date
        AND g.city = rtm.city
        AND g.zone = rtm.zone
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
                PARTITION BY city, zone
                ORDER BY metric_date
            ),
            0
        ) AS delivered_orders_lag_1d,

        COALESCE(
            LAG(delivered_orders, 7) OVER (
                PARTITION BY city, zone
                ORDER BY metric_date
            ),
            0
        ) AS delivered_orders_lag_7d,

        COALESCE(
            LAG(gross_order_value, 1) OVER (
                PARTITION BY city, zone
                ORDER BY metric_date
            ),
            0
        ) AS gross_order_value_lag_1d,

        COALESCE(
            LAG(gross_order_value, 7) OVER (
                PARTITION BY city, zone
                ORDER BY metric_date
            ),
            0
        ) AS gross_order_value_lag_7d,

        COALESCE(
            ROUND(
                AVG(delivered_orders) OVER (
                    PARTITION BY city, zone
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
                    PARTITION BY city, zone
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
                    PARTITION BY city, zone
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
                    PARTITION BY city, zone
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
                    PARTITION BY city, zone
                    ORDER BY metric_date
                    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
                ),
                2
            ),
            0
        ) AS avg_order_value_rolling_7d_avg,

        COALESCE(
            ROUND(
                AVG(cancellation_rate_pct) OVER (
                    PARTITION BY city, zone
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
                    PARTITION BY city, zone
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
                    PARTITION BY city, zone
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
                    PARTITION BY city, zone
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
    zone,

    day_of_week_num,
    day_of_week,
    weekend_flag,
    day_of_month,
    month_num,
    week_of_year,

    total_orders,
    delivered_orders,
    cancelled_orders,
    ordering_users,
    active_restaurants,

    gross_order_value,
    total_discount,
    platform_fee_total,
    delivery_fee_total,
    total_refund_amount,
    contribution_proxy,

    avg_order_value,
    delivery_success_rate_pct,
    cancellation_rate_pct,

    avg_delivery_time_min,
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

    delivered_orders_lag_1d,
    delivered_orders_lag_7d,
    gross_order_value_lag_1d,
    gross_order_value_lag_7d,

    delivered_orders_rolling_7d_avg,
    delivered_orders_rolling_14d_avg,
    delivered_orders_rolling_28d_avg,

    gross_order_value_rolling_7d_avg,
    avg_order_value_rolling_7d_avg,

    cancellation_rate_rolling_7d_avg,
    sla_breach_rate_rolling_7d_avg,
    refund_rate_rolling_7d_avg,
    complaint_rate_rolling_7d_avg,

    CASE
        WHEN delivered_orders_rolling_28d_avg > 0
             AND delivered_orders >= 1.5 * delivered_orders_rolling_28d_avg
            THEN 1
        ELSE 0
    END AS positive_demand_spike_flag,

    CASE
        WHEN delivered_orders_rolling_28d_avg > 0
             AND delivered_orders <= 0.5 * delivered_orders_rolling_28d_avg
            THEN 1
        ELSE 0
    END AS negative_demand_drop_flag,

    CASE
        WHEN sla_breach_pct >= 25
             OR cancellation_rate_pct >= 10
             OR refund_rate_pct >= 8
             OR complaint_rate_pct >= 35
            THEN 1
        ELSE 0
    END AS operational_shock_flag,

    CASE
        WHEN delivered_orders >= 30 THEN 'high_signal_day'
        WHEN delivered_orders >= 10 THEN 'medium_signal_day'
        WHEN delivered_orders > 0 THEN 'low_signal_day'
        ELSE 'zero_order_day'
    END AS forecast_signal_tier

FROM features
ORDER BY
    metric_date,
    city,
    zone;