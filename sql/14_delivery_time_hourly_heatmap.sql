/*
Analysis:
Delivery-time hourly heatmap.

Business question:
Which day-hour slots create operational stress in the marketplace?

Grain:
day_of_week + order_hour

Key metrics:
- delivered_orders
- total_orders
- avg_delivery_time_min
- p50_delivery_time_min
- p90_delivery_time_min
- sla_breach_pct
- cancellation_rate_pct
- refund_rate_pct
- complaint_rate_pct
- avg_prep_time_min
- avg_rider_wait_time_min
- avg_drop_time_min
- hourly_operational_risk_score
- hourly_risk_tier

Caveats:
1. Delivery-time metrics are calculated only on delivered orders.
2. Cancellation rate uses total orders in the same day-hour slot.
3. This table is designed for heatmap visualization in Streamlit or Power BI.
*/

WITH order_base AS (
    SELECT
        o.order_id,
        o.user_id,
        o.restaurant_id,
        CAST(o.order_time AS TIMESTAMP) AS order_timestamp,
        CAST(o.order_time AS DATE) AS order_date,

        CAST(STRFTIME(CAST(o.order_time AS TIMESTAMP), '%w') AS INTEGER) AS day_of_week_num,

        CASE CAST(STRFTIME(CAST(o.order_time AS TIMESTAMP), '%w') AS INTEGER)
            WHEN 0 THEN 'Sunday'
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
            ELSE 'Unknown'
        END AS day_of_week,

        EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP)) AS order_hour,

        CASE
            WHEN EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP)) BETWEEN 6 AND 10 THEN 'breakfast'
            WHEN EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP)) BETWEEN 11 AND 15 THEN 'lunch'
            WHEN EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP)) BETWEEN 16 AND 18 THEN 'evening_snack'
            WHEN EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP)) BETWEEN 19 AND 23 THEN 'dinner'
            ELSE 'late_night'
        END AS meal_period,

        o.order_status,
        o.order_value,
        o.discount_amount,

        r.city,
        r.zone,
        COALESCE(r.primary_cuisine, 'unknown') AS primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS price_band

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
),

delivered_base AS (
    SELECT
        ob.order_id,
        ob.user_id,
        ob.restaurant_id,
        ob.order_timestamp,
        ob.order_date,
        ob.day_of_week_num,
        ob.day_of_week,
        ob.order_hour,
        ob.meal_period,
        ob.city,
        ob.zone,
        ob.primary_cuisine,
        ob.price_band,
        ob.order_value,
        ob.discount_amount,

        d.prep_time_min,
        d.rider_wait_time_min,
        d.drop_time_min,
        d.total_delivery_time_min,
        d.distance_km,
        d.sla_breach_flag

    FROM order_base ob
    INNER JOIN fact_delivery_ops d
        ON ob.order_id = d.order_id
    WHERE ob.order_status = 'delivered'
),

order_metrics AS (
    SELECT
        day_of_week_num,
        day_of_week,
        order_hour,
        meal_period,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders,

        COUNT(DISTINCT user_id) AS ordering_users,

        COUNT(DISTINCT restaurant_id) AS active_restaurants,

        ROUND(SUM(order_value), 2) AS gross_order_value,
        ROUND(SUM(discount_amount), 2) AS total_discount,
        ROUND(AVG(order_value), 2) AS avg_order_value

    FROM order_base
    GROUP BY
        day_of_week_num,
        day_of_week,
        order_hour,
        meal_period
),

delivery_metrics AS (
    SELECT
        day_of_week_num,
        day_of_week,
        order_hour,
        meal_period,

        COUNT(DISTINCT order_id) AS delivered_orders_with_ops,

        ROUND(AVG(total_delivery_time_min), 2) AS avg_delivery_time_min,

        ROUND(QUANTILE_CONT(total_delivery_time_min, 0.50), 2) AS p50_delivery_time_min,

        ROUND(QUANTILE_CONT(total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        ROUND(AVG(prep_time_min), 2) AS avg_prep_time_min,
        ROUND(AVG(rider_wait_time_min), 2) AS avg_rider_wait_time_min,
        ROUND(AVG(drop_time_min), 2) AS avg_drop_time_min,
        ROUND(AVG(distance_km), 2) AS avg_distance_km,

        ROUND(QUANTILE_CONT(prep_time_min, 0.90), 2) AS p90_prep_time_min,
        ROUND(QUANTILE_CONT(rider_wait_time_min, 0.90), 2) AS p90_rider_wait_time_min,
        ROUND(QUANTILE_CONT(drop_time_min, 0.90), 2) AS p90_drop_time_min,

        SUM(
            CASE
                WHEN sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_orders

    FROM delivered_base
    GROUP BY
        day_of_week_num,
        day_of_week,
        order_hour,
        meal_period
),

refund_metrics AS (
    SELECT
        db.day_of_week_num,
        db.day_of_week,
        db.order_hour,
        db.meal_period,

        COUNT(DISTINCT rf.order_id) AS refund_orders,
        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount

    FROM delivered_base db
    INNER JOIN fact_refunds rf
        ON db.order_id = rf.order_id
    GROUP BY
        db.day_of_week_num,
        db.day_of_week,
        db.order_hour,
        db.meal_period
),

rating_metrics AS (
    SELECT
        db.day_of_week_num,
        db.day_of_week,
        db.order_hour,
        db.meal_period,

        COUNT(DISTINCT rt.order_id) AS rated_orders,

        ROUND(AVG(rt.food_rating), 2) AS avg_food_rating,
        ROUND(AVG(rt.delivery_rating), 2) AS avg_delivery_rating,

        SUM(
            CASE
                WHEN rt.complaint_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS complaint_orders

    FROM delivered_base db
    INNER JOIN fact_ratings rt
        ON db.order_id = rt.order_id
    GROUP BY
        db.day_of_week_num,
        db.day_of_week,
        db.order_hour,
        db.meal_period
),

combined AS (
    SELECT
        om.day_of_week_num,
        om.day_of_week,
        om.order_hour,
        om.meal_period,

        om.total_orders,
        om.delivered_orders,
        om.cancelled_orders,
        om.ordering_users,
        om.active_restaurants,

        om.gross_order_value,
        om.total_discount,
        om.avg_order_value,

        COALESCE(dm.avg_delivery_time_min, 0) AS avg_delivery_time_min,
        COALESCE(dm.p50_delivery_time_min, 0) AS p50_delivery_time_min,
        COALESCE(dm.p90_delivery_time_min, 0) AS p90_delivery_time_min,

        COALESCE(dm.avg_prep_time_min, 0) AS avg_prep_time_min,
        COALESCE(dm.avg_rider_wait_time_min, 0) AS avg_rider_wait_time_min,
        COALESCE(dm.avg_drop_time_min, 0) AS avg_drop_time_min,
        COALESCE(dm.avg_distance_km, 0) AS avg_distance_km,

        COALESCE(dm.p90_prep_time_min, 0) AS p90_prep_time_min,
        COALESCE(dm.p90_rider_wait_time_min, 0) AS p90_rider_wait_time_min,
        COALESCE(dm.p90_drop_time_min, 0) AS p90_drop_time_min,

        COALESCE(dm.sla_breach_orders, 0) AS sla_breach_orders,

        COALESCE(rf.refund_orders, 0) AS refund_orders,
        COALESCE(rf.total_refund_amount, 0) AS total_refund_amount,

        COALESCE(rt.rated_orders, 0) AS rated_orders,
        COALESCE(rt.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rt.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rt.complaint_orders, 0) AS complaint_orders

    FROM order_metrics om
    LEFT JOIN delivery_metrics dm
        ON om.day_of_week_num = dm.day_of_week_num
        AND om.order_hour = dm.order_hour
    LEFT JOIN refund_metrics rf
        ON om.day_of_week_num = rf.day_of_week_num
        AND om.order_hour = rf.order_hour
    LEFT JOIN rating_metrics rt
        ON om.day_of_week_num = rt.day_of_week_num
        AND om.order_hour = rt.order_hour
),

rates AS (
    SELECT
        *,

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
        END AS discount_burn_pct

    FROM combined
),

scored AS (
    SELECT
        *,

        ROUND(
            35 * LEAST(sla_breach_pct / 40.0, 1.0)
            + 25 * LEAST(GREATEST(p90_delivery_time_min - 40, 0) / 25.0, 1.0)
            + 15 * LEAST(cancellation_rate_pct / 15.0, 1.0)
            + 15 * LEAST(complaint_rate_pct / 45.0, 1.0)
            + 10 * LEAST(refund_rate_pct / 10.0, 1.0),
            2
        ) AS hourly_operational_risk_score

    FROM rates
)

SELECT
    day_of_week_num,
    day_of_week,
    order_hour,
    meal_period,

    total_orders,
    delivered_orders,
    cancelled_orders,
    ordering_users,
    active_restaurants,

    gross_order_value,
    total_discount,
    discount_burn_pct,
    avg_order_value,

    delivery_success_rate_pct,
    cancellation_rate_pct,

    avg_delivery_time_min,
    p50_delivery_time_min,
    p90_delivery_time_min,

    avg_prep_time_min,
    avg_rider_wait_time_min,
    avg_drop_time_min,
    avg_distance_km,

    p90_prep_time_min,
    p90_rider_wait_time_min,
    p90_drop_time_min,

    sla_breach_orders,
    sla_breach_pct,

    refund_orders,
    refund_rate_pct,

    rated_orders,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,
    complaint_rate_pct,

    hourly_operational_risk_score,

    CASE
        WHEN hourly_operational_risk_score >= 70 THEN 'critical_hour'
        WHEN hourly_operational_risk_score >= 50 THEN 'high_risk_hour'
        WHEN hourly_operational_risk_score >= 30 THEN 'medium_risk_hour'
        ELSE 'low_risk_hour'
    END AS hourly_risk_tier,

    CASE
        WHEN sla_breach_pct >= 25
             OR p90_delivery_time_min >= 55
            THEN 'add_peak_ops_capacity'
        WHEN cancellation_rate_pct >= 10
            THEN 'reduce_cancellation_drivers'
        WHEN complaint_rate_pct >= 35
            THEN 'repair_customer_experience'
        WHEN refund_rate_pct >= 8
            THEN 'investigate_refund_causes'
        ELSE 'maintain_current_ops'
    END AS recommended_action

FROM scored
WHERE total_orders >= 10
ORDER BY
    day_of_week_num,
    order_hour;