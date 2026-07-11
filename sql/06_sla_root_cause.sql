/*
Analysis:
SLA root-cause diagnostics.

Business question:
What operational drivers explain late deliveries?

Corrected grain:
city + zone + order_hour

Why this grain:
The first version grouped by city + zone + hour + cuisine + price_band.
That was too sparse for this dataset and returned only 3 rows.
This version keeps the analysis operationally useful while preserving enough sample size.

Key metrics:
- delivered_orders
- sla_breach_pct
- avg_delivery_time_min
- p90_delivery_time_min
- prep_time_share_pct
- rider_wait_share_pct
- drop_time_share_pct
- prep_stress_index
- rider_wait_stress_index
- drop_time_stress_index
- root_cause_driver
- operational_risk_tier

Root-cause logic:
Instead of simply choosing the largest time component, this query compares each component
against a healthy operational benchmark.

Benchmarks:
- prep time baseline: 14 minutes
- rider wait baseline: 4.5 minutes
- drop time baseline: 18 minutes

The highest stress index becomes the directional root-cause driver.
*/

WITH delivered_base AS (
    SELECT
        o.order_id,
        o.user_id,
        o.restaurant_id,
        CAST(o.order_time AS TIMESTAMP) AS order_timestamp,
        EXTRACT(HOUR FROM CAST(o.order_time AS TIMESTAMP)) AS order_hour,

        r.city,
        r.zone,
        r.primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS price_band,
        COALESCE(r.restaurant_quality_prior, 0) AS restaurant_quality_prior,

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

rating_base AS (
    SELECT
        order_id,
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

refund_base AS (
    SELECT
        order_id,
        COUNT(*) AS refund_flag
    FROM fact_refunds
    GROUP BY
        order_id
),

grouped AS (
    SELECT
        b.city,
        b.zone,
        b.order_hour,

        COUNT(DISTINCT b.order_id) AS delivered_orders,
        COUNT(DISTINCT b.user_id) AS unique_customers,
        COUNT(DISTINCT b.restaurant_id) AS active_restaurants,
        COUNT(DISTINCT b.primary_cuisine) AS active_cuisines,

        ROUND(AVG(b.total_delivery_time_min), 2) AS avg_delivery_time_min,
        ROUND(QUANTILE_CONT(b.total_delivery_time_min, 0.50), 2) AS p50_delivery_time_min,
        ROUND(QUANTILE_CONT(b.total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        ROUND(AVG(b.prep_time_min), 2) AS avg_prep_time_min,
        ROUND(AVG(b.rider_wait_time_min), 2) AS avg_rider_wait_time_min,
        ROUND(AVG(b.drop_time_min), 2) AS avg_drop_time_min,
        ROUND(AVG(b.distance_km), 2) AS avg_distance_km,

        ROUND(QUANTILE_CONT(b.prep_time_min, 0.90), 2) AS p90_prep_time_min,
        ROUND(QUANTILE_CONT(b.rider_wait_time_min, 0.90), 2) AS p90_rider_wait_time_min,
        ROUND(QUANTILE_CONT(b.drop_time_min, 0.90), 2) AS p90_drop_time_min,

        SUM(
            CASE
                WHEN b.sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_orders,

        COUNT(DISTINCT rf.order_id) AS refund_orders,

        COUNT(DISTINCT rt.order_id) AS rated_orders,

        SUM(
            CASE
                WHEN rt.complaint_flag = 1 THEN 1
                ELSE 0
            END
        ) AS complaint_orders,

        ROUND(AVG(rt.food_rating), 2) AS avg_food_rating,
        ROUND(AVG(rt.delivery_rating), 2) AS avg_delivery_rating,

        ROUND(AVG(b.restaurant_quality_prior), 3) AS avg_restaurant_quality_prior,

        ROUND(
            100.0 * SUM(CASE WHEN b.price_band = 'low' THEN 1 ELSE 0 END) / COUNT(*),
            2
        ) AS low_price_order_share_pct,

        ROUND(
            100.0 * SUM(CASE WHEN b.price_band = 'mid' THEN 1 ELSE 0 END) / COUNT(*),
            2
        ) AS mid_price_order_share_pct,

        ROUND(
            100.0 * SUM(CASE WHEN b.price_band = 'premium' THEN 1 ELSE 0 END) / COUNT(*),
            2
        ) AS premium_order_share_pct

    FROM delivered_base b
    LEFT JOIN rating_base rt
        ON b.order_id = rt.order_id
    LEFT JOIN refund_base rf
        ON b.order_id = rf.order_id

    GROUP BY
        b.city,
        b.zone,
        b.order_hour
),

final AS (
    SELECT
        city,
        zone,
        order_hour,

        delivered_orders,
        unique_customers,
        active_restaurants,
        active_cuisines,

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

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * sla_breach_orders / delivered_orders, 2)
        END AS sla_breach_pct,

        CASE
            WHEN avg_delivery_time_min = 0 THEN 0
            ELSE ROUND(100.0 * avg_prep_time_min / avg_delivery_time_min, 2)
        END AS prep_time_share_pct,

        CASE
            WHEN avg_delivery_time_min = 0 THEN 0
            ELSE ROUND(100.0 * avg_rider_wait_time_min / avg_delivery_time_min, 2)
        END AS rider_wait_share_pct,

        CASE
            WHEN avg_delivery_time_min = 0 THEN 0
            ELSE ROUND(100.0 * avg_drop_time_min / avg_delivery_time_min, 2)
        END AS drop_time_share_pct,

        ROUND(avg_prep_time_min / 14.0, 2) AS prep_stress_index,
        ROUND(avg_rider_wait_time_min / 4.5, 2) AS rider_wait_stress_index,
        ROUND(avg_drop_time_min / 18.0, 2) AS drop_time_stress_index,

        refund_orders,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * refund_orders / delivered_orders, 2)
        END AS refund_rate_pct,

        rated_orders,
        COALESCE(avg_food_rating, 0) AS avg_food_rating,
        COALESCE(avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(complaint_orders, 0) AS complaint_orders,

        CASE
            WHEN rated_orders = 0 THEN 0
            ELSE ROUND(100.0 * COALESCE(complaint_orders, 0) / rated_orders, 2)
        END AS complaint_rate_pct,

        avg_restaurant_quality_prior,

        low_price_order_share_pct,
        mid_price_order_share_pct,
        premium_order_share_pct

    FROM grouped
)

SELECT
    city,
    zone,
    order_hour,

    delivered_orders,
    unique_customers,
    active_restaurants,
    active_cuisines,

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

    prep_time_share_pct,
    rider_wait_share_pct,
    drop_time_share_pct,

    prep_stress_index,
    rider_wait_stress_index,
    drop_time_stress_index,

    refund_orders,
    refund_rate_pct,

    rated_orders,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,
    complaint_rate_pct,

    avg_restaurant_quality_prior,

    low_price_order_share_pct,
    mid_price_order_share_pct,
    premium_order_share_pct,

    CASE
        WHEN prep_stress_index >= rider_wait_stress_index
             AND prep_stress_index >= drop_time_stress_index
            THEN 'restaurant_prep_time'
        WHEN rider_wait_stress_index >= prep_stress_index
             AND rider_wait_stress_index >= drop_time_stress_index
            THEN 'rider_wait_time'
        WHEN drop_time_stress_index >= prep_stress_index
             AND drop_time_stress_index >= rider_wait_stress_index
            THEN 'last_mile_drop_time'
        ELSE 'mixed_driver'
    END AS root_cause_driver,

    CASE
        WHEN sla_breach_pct >= 40
             OR p90_delivery_time_min >= 60
             OR complaint_rate_pct >= 45
            THEN 'high_operational_risk'
        WHEN sla_breach_pct >= 20
             OR p90_delivery_time_min >= 52
             OR complaint_rate_pct >= 30
            THEN 'medium_operational_risk'
        ELSE 'low_operational_risk'
    END AS operational_risk_tier

FROM final
WHERE delivered_orders >= 10
ORDER BY
    sla_breach_pct DESC,
    p90_delivery_time_min DESC,
    delivered_orders DESC;