/*
Analysis:
Repeat rate by cuisine and price band.

Business question:
Which cuisine categories create repeat behavior and customer stickiness?

Grain:
primary_cuisine + price_band

Key metrics:
- delivered_orders
- unique_customers
- repeat_customers
- repeat_customer_rate_pct
- avg_orders_per_customer
- avg_order_value
- gross_order_value
- discount_burn_pct
- refund_rate_pct
- complaint_rate_pct
- avg_food_rating
- avg_delivery_rating
- cuisine_stickiness_tier

Caveats:
1. Repeat behavior is measured within cuisine + price_band.
2. A repeat customer is a user with at least 2 delivered orders in that cuisine-price segment.
3. Cancelled orders are excluded from repeat behavior but included in cancellation-rate diagnostics.
4. This is a product/category diagnostic, not a causal preference model.
*/

WITH delivered_order_base AS (
    SELECT
        o.order_id,
        o.user_id,
        o.restaurant_id,
        CAST(o.order_time AS DATE) AS order_date,
        o.order_value,
        o.discount_amount,
        o.delivery_fee,
        o.platform_fee,

        r.city,
        r.zone,
        COALESCE(r.primary_cuisine, 'unknown') AS primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS price_band

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
    WHERE o.order_status = 'delivered'
),

all_order_base AS (
    SELECT
        o.order_id,
        o.user_id,
        o.restaurant_id,
        o.order_status,

        r.city,
        r.zone,
        COALESCE(r.primary_cuisine, 'unknown') AS primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS price_band

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
),

user_cuisine_stats AS (
    SELECT
        primary_cuisine,
        price_band,
        user_id,

        COUNT(DISTINCT order_id) AS delivered_orders_by_user,

        MIN(order_date) AS first_cuisine_order_date,
        MAX(order_date) AS last_cuisine_order_date,

        ROUND(SUM(order_value), 2) AS user_gross_order_value,
        ROUND(SUM(discount_amount), 2) AS user_total_discount

    FROM delivered_order_base
    GROUP BY
        primary_cuisine,
        price_band,
        user_id
),

repeat_customer_stats AS (
    SELECT
        primary_cuisine,
        price_band,

        COUNT(DISTINCT user_id) AS unique_customers,

        COUNT(DISTINCT CASE WHEN delivered_orders_by_user >= 2 THEN user_id END) AS repeat_customers,

        ROUND(AVG(delivered_orders_by_user), 2) AS avg_orders_per_customer

    FROM user_cuisine_stats
    GROUP BY
        primary_cuisine,
        price_band
),

order_metrics AS (
    SELECT
        primary_cuisine,
        price_band,

        COUNT(DISTINCT order_id) AS delivered_orders,

        ROUND(SUM(order_value), 2) AS gross_order_value,
        ROUND(SUM(discount_amount), 2) AS total_discount,
        ROUND(SUM(delivery_fee), 2) AS delivery_fee_total,
        ROUND(SUM(platform_fee), 2) AS platform_fee_total,

        ROUND(AVG(order_value), 2) AS avg_order_value

    FROM delivered_order_base
    GROUP BY
        primary_cuisine,
        price_band
),

cancellation_metrics AS (
    SELECT
        primary_cuisine,
        price_band,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders

    FROM all_order_base
    GROUP BY
        primary_cuisine,
        price_band
),

refund_metrics AS (
    SELECT
        b.primary_cuisine,
        b.price_band,

        COUNT(DISTINCT rf.order_id) AS refund_orders,
        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount

    FROM delivered_order_base b
    INNER JOIN fact_refunds rf
        ON b.order_id = rf.order_id
    GROUP BY
        b.primary_cuisine,
        b.price_band
),

rating_metrics AS (
    SELECT
        b.primary_cuisine,
        b.price_band,

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
        b.primary_cuisine,
        b.price_band
),

delivery_metrics AS (
    SELECT
        b.primary_cuisine,
        b.price_band,

        ROUND(AVG(d.total_delivery_time_min), 2) AS avg_delivery_time_min,
        ROUND(QUANTILE_CONT(d.total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        SUM(
            CASE
                WHEN d.sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_orders

    FROM delivered_order_base b
    INNER JOIN fact_delivery_ops d
        ON b.order_id = d.order_id
    GROUP BY
        b.primary_cuisine,
        b.price_band
),

final AS (
    SELECT
        om.primary_cuisine,
        om.price_band,

        om.delivered_orders,
        COALESCE(cm.total_orders, om.delivered_orders) AS total_orders,
        COALESCE(cm.cancelled_orders, 0) AS cancelled_orders,

        rcs.unique_customers,
        rcs.repeat_customers,
        rcs.avg_orders_per_customer,

        om.gross_order_value,
        om.total_discount,
        om.delivery_fee_total,
        om.platform_fee_total,
        om.avg_order_value,

        COALESCE(rfm.refund_orders, 0) AS refund_orders,
        COALESCE(rfm.total_refund_amount, 0) AS total_refund_amount,

        COALESCE(rtm.rated_orders, 0) AS rated_orders,
        COALESCE(rtm.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rtm.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rtm.complaint_orders, 0) AS complaint_orders,

        COALESCE(dm.avg_delivery_time_min, 0) AS avg_delivery_time_min,
        COALESCE(dm.p90_delivery_time_min, 0) AS p90_delivery_time_min,
        COALESCE(dm.sla_breach_orders, 0) AS sla_breach_orders

    FROM order_metrics om
    INNER JOIN repeat_customer_stats rcs
        ON om.primary_cuisine = rcs.primary_cuisine
        AND om.price_band = rcs.price_band
    LEFT JOIN cancellation_metrics cm
        ON om.primary_cuisine = cm.primary_cuisine
        AND om.price_band = cm.price_band
    LEFT JOIN refund_metrics rfm
        ON om.primary_cuisine = rfm.primary_cuisine
        AND om.price_band = rfm.price_band
    LEFT JOIN rating_metrics rtm
        ON om.primary_cuisine = rtm.primary_cuisine
        AND om.price_band = rtm.price_band
    LEFT JOIN delivery_metrics dm
        ON om.primary_cuisine = dm.primary_cuisine
        AND om.price_band = dm.price_band
)

SELECT
    primary_cuisine,
    price_band,

    delivered_orders,
    total_orders,
    cancelled_orders,

    unique_customers,
    repeat_customers,

    CASE
        WHEN unique_customers = 0 THEN 0
        ELSE ROUND(100.0 * repeat_customers / unique_customers, 2)
    END AS repeat_customer_rate_pct,

    avg_orders_per_customer,

    gross_order_value,
    total_discount,

    CASE
        WHEN gross_order_value = 0 THEN 0
        ELSE ROUND(100.0 * total_discount / gross_order_value, 2)
    END AS discount_burn_pct,

    avg_order_value,

    CASE
        WHEN total_orders = 0 THEN 0
        ELSE ROUND(100.0 * cancelled_orders / total_orders, 2)
    END AS cancellation_rate_pct,

    refund_orders,

    CASE
        WHEN delivered_orders = 0 THEN 0
        ELSE ROUND(100.0 * refund_orders / delivered_orders, 2)
    END AS refund_rate_pct,

    rated_orders,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,

    CASE
        WHEN rated_orders = 0 THEN 0
        ELSE ROUND(100.0 * complaint_orders / rated_orders, 2)
    END AS complaint_rate_pct,

    avg_delivery_time_min,
    p90_delivery_time_min,
    sla_breach_orders,

    CASE
        WHEN delivered_orders = 0 THEN 0
        ELSE ROUND(100.0 * sla_breach_orders / delivered_orders, 2)
    END AS sla_breach_pct,

    CASE
        WHEN unique_customers = 0 THEN 'insufficient_data'
        WHEN repeat_customers * 100.0 / unique_customers >= 20
             AND refund_orders * 100.0 / delivered_orders <= 5
             AND complaint_orders * 100.0 / NULLIF(rated_orders, 0) <= 30
            THEN 'high_stickiness_low_risk'
        WHEN repeat_customers * 100.0 / unique_customers >= 12
            THEN 'moderate_stickiness'
        WHEN repeat_customers * 100.0 / unique_customers >= 5
            THEN 'low_stickiness'
        ELSE 'trial_heavy_low_repeat'
    END AS cuisine_stickiness_tier

FROM final
WHERE delivered_orders >= 25
ORDER BY
    repeat_customer_rate_pct DESC,
    delivered_orders DESC,
    refund_rate_pct ASC;