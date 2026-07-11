/*
Analysis:
Delivery reliability diagnostics by city, zone, and order hour.

Business question:
Where is delivery experience breaking down, and during which hours?

Grain:
city + zone + order_hour

Key metrics:
- delivered_orders
- cancelled_orders
- total_orders
- avg_delivery_time_min
- p50_delivery_time_min
- p90_delivery_time_min
- sla_breach_pct
- avg_prep_time_min
- avg_rider_wait_time_min
- avg_drop_time_min
- cancellation_rate_pct
- refund_rate_pct
- avg_food_rating
- avg_delivery_rating

Caveats:
1. Delivery-time metrics are calculated only for delivered orders.
2. Cancellation rate is calculated using delivered + cancelled orders for the same city-zone-hour.
3. P90 delivery time is used to capture bad-tail customer experience.
4. Groups with fewer than 10 delivered orders are removed to avoid noisy P90 values.
*/

WITH delivered_order_base AS (
    SELECT
        o.order_id,
        o.user_id,
        o.restaurant_id,
        r.city,
        r.zone,
        r.primary_cuisine,
        EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP)) AS order_hour,
        CAST(o.order_time AS DATE) AS order_date,

        d.prep_time_min,
        d.rider_wait_time_min,
        d.drop_time_min,
        d.total_delivery_time_min,
        d.distance_km,
        d.sla_breach_flag

    FROM fact_orders o
    INNER JOIN fact_delivery_ops d
        ON o.order_id = d.order_id
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
    WHERE o.order_status = 'delivered'
),

delivery_metrics AS (
    SELECT
        city,
        zone,
        order_hour,

        COUNT(DISTINCT order_id) AS delivered_orders,

        ROUND(AVG(total_delivery_time_min), 2) AS avg_delivery_time_min,

        ROUND(QUANTILE_CONT(total_delivery_time_min, 0.50), 2) AS p50_delivery_time_min,

        ROUND(QUANTILE_CONT(total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        SUM(
            CASE
                WHEN sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_orders,

        ROUND(AVG(prep_time_min), 2) AS avg_prep_time_min,

        ROUND(AVG(rider_wait_time_min), 2) AS avg_rider_wait_time_min,

        ROUND(AVG(drop_time_min), 2) AS avg_drop_time_min,

        ROUND(AVG(distance_km), 2) AS avg_distance_km

    FROM delivered_order_base
    GROUP BY
        city,
        zone,
        order_hour
),

cancelled_metrics AS (
    SELECT
        r.city,
        r.zone,
        EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP)) AS order_hour,

        COUNT(DISTINCT o.order_id) AS cancelled_orders

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
    WHERE o.order_status = 'cancelled'
    GROUP BY
        r.city,
        r.zone,
        EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP))
),

refund_metrics AS (
    SELECT
        b.city,
        b.zone,
        b.order_hour,

        COUNT(DISTINCT rf.order_id) AS refund_orders,
        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount

    FROM delivered_order_base b
    INNER JOIN fact_refunds rf
        ON b.order_id = rf.order_id
    GROUP BY
        b.city,
        b.zone,
        b.order_hour
),

rating_metrics AS (
    SELECT
        b.city,
        b.zone,
        b.order_hour,

        COUNT(DISTINCT rt.order_id) AS rated_orders,
        ROUND(AVG(rt.food_rating), 2) AS avg_food_rating,
        ROUND(AVG(rt.delivery_rating), 2) AS avg_delivery_rating,

        SUM(
            CASE
                WHEN rt.complaint_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS complaint_orders

    FROM delivered_order_base b
    INNER JOIN fact_ratings rt
        ON b.order_id = rt.order_id
    GROUP BY
        b.city,
        b.zone,
        b.order_hour
),

final AS (
    SELECT
        dm.city,
        dm.zone,
        dm.order_hour,

        dm.delivered_orders,
        COALESCE(cm.cancelled_orders, 0) AS cancelled_orders,

        dm.delivered_orders + COALESCE(cm.cancelled_orders, 0) AS total_orders,

        dm.avg_delivery_time_min,
        dm.p50_delivery_time_min,
        dm.p90_delivery_time_min,

        dm.sla_breach_orders,

        CASE
            WHEN dm.delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * dm.sla_breach_orders / dm.delivered_orders, 2)
        END AS sla_breach_pct,

        dm.avg_prep_time_min,
        dm.avg_rider_wait_time_min,
        dm.avg_drop_time_min,
        dm.avg_distance_km,

        CASE
            WHEN dm.delivered_orders + COALESCE(cm.cancelled_orders, 0) = 0 THEN 0
            ELSE ROUND(
                100.0 * COALESCE(cm.cancelled_orders, 0)
                / (dm.delivered_orders + COALESCE(cm.cancelled_orders, 0)),
                2
            )
        END AS cancellation_rate_pct,

        COALESCE(rfm.refund_orders, 0) AS refund_orders,

        CASE
            WHEN dm.delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * COALESCE(rfm.refund_orders, 0) / dm.delivered_orders, 2)
        END AS refund_rate_pct,

        COALESCE(rm.rated_orders, 0) AS rated_orders,
        COALESCE(rm.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rm.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rm.complaint_orders, 0) AS complaint_orders,

        CASE
            WHEN COALESCE(rm.rated_orders, 0) = 0 THEN 0
            ELSE ROUND(100.0 * COALESCE(rm.complaint_orders, 0) / rm.rated_orders, 2)
        END AS complaint_rate_pct

    FROM delivery_metrics dm
    LEFT JOIN cancelled_metrics cm
        ON dm.city = cm.city
        AND dm.zone = cm.zone
        AND dm.order_hour = cm.order_hour
    LEFT JOIN refund_metrics rfm
        ON dm.city = rfm.city
        AND dm.zone = rfm.zone
        AND dm.order_hour = rfm.order_hour
    LEFT JOIN rating_metrics rm
        ON dm.city = rm.city
        AND dm.zone = rm.zone
        AND dm.order_hour = rm.order_hour
)

SELECT
    city,
    zone,
    order_hour,

    delivered_orders,
    cancelled_orders,
    total_orders,

    avg_delivery_time_min,
    p50_delivery_time_min,
    p90_delivery_time_min,

    sla_breach_orders,
    sla_breach_pct,

    avg_prep_time_min,
    avg_rider_wait_time_min,
    avg_drop_time_min,
    avg_distance_km,

    cancellation_rate_pct,
    refund_orders,
    refund_rate_pct,

    rated_orders,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,
    complaint_rate_pct

FROM final
WHERE delivered_orders >= 10
ORDER BY
    p90_delivery_time_min DESC,
    sla_breach_pct DESC,
    delivered_orders DESC;