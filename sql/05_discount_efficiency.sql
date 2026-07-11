/*
Analysis:
Discount efficiency by user segment, acquisition channel, price band, and discount bucket.

Business question:
Which discount bands create efficient delivered order volume and marketplace value?

Grain:
user_segment + acquisition_channel + price_band + discount_bucket

Key metrics:
- total_orders
- delivered_orders
- cancelled_orders
- gross_order_value
- total_discount
- discount_burn_pct
- delivered_orders_per_1000_discount
- gross_value_per_1_discount
- cancellation_rate_pct
- refund_rate_pct
- complaint_rate_pct
- avg_food_rating
- avg_delivery_rating
- discount_efficiency_tier

Caveats:
1. Discount amount is treated as commercial burn proxy.
2. This is not causal incrementality. It is diagnostic efficiency analysis.
3. Groups with fewer than 20 orders are excluded to reduce noise.
*/

WITH order_base AS (
    SELECT
        o.order_id,
        o.user_id,
        o.restaurant_id,
        o.order_value,
        o.discount_amount,
        o.discount_pct,
        o.platform_fee,
        o.delivery_fee,
        o.order_status,
        o.payment_status,

        u.user_segment,
        u.acquisition_channel,
        u.income_proxy,
        u.gold_member_flag,

        r.city,
        r.zone,
        r.primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS price_band,

        CASE
            WHEN o.discount_pct = 0 THEN '0_no_discount'
            WHEN o.discount_pct > 0 AND o.discount_pct <= 0.10 THEN '1_low_discount_0_10'
            WHEN o.discount_pct > 0.10 AND o.discount_pct <= 0.20 THEN '2_medium_discount_10_20'
            WHEN o.discount_pct > 0.20 AND o.discount_pct <= 0.30 THEN '3_high_discount_20_30'
            ELSE '4_very_high_discount_30_plus'
        END AS discount_bucket

    FROM fact_orders o
    INNER JOIN dim_users u
        ON o.user_id = u.user_id
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
),

refund_base AS (
    SELECT
        o.order_id,
        SUM(rf.refund_amount) AS refund_amount
    FROM fact_orders o
    INNER JOIN fact_refunds rf
        ON o.order_id = rf.order_id
    GROUP BY
        o.order_id
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

discount_grouped AS (
    SELECT
        ob.user_segment,
        ob.acquisition_channel,
        ob.price_band,
        ob.discount_bucket,

        COUNT(DISTINCT ob.order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN ob.order_status = 'delivered' THEN ob.order_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN ob.order_status = 'cancelled' THEN ob.order_id END) AS cancelled_orders,

        COUNT(DISTINCT ob.user_id) AS unique_customers,

        ROUND(SUM(ob.order_value), 2) AS gross_order_value,

        ROUND(SUM(ob.discount_amount), 2) AS total_discount,

        ROUND(SUM(ob.platform_fee), 2) AS platform_fee_total,

        ROUND(SUM(ob.delivery_fee), 2) AS delivery_fee_total,

        COUNT(DISTINCT rb.order_id) AS refund_orders,

        ROUND(COALESCE(SUM(rb.refund_amount), 0), 2) AS total_refund_amount,

        COUNT(DISTINCT rating.order_id) AS rated_orders,

        ROUND(AVG(rating.food_rating), 2) AS avg_food_rating,

        ROUND(AVG(rating.delivery_rating), 2) AS avg_delivery_rating,

        SUM(
            CASE
                WHEN rating.complaint_flag = 1 THEN 1
                ELSE 0
            END
        ) AS complaint_orders

    FROM order_base ob
    LEFT JOIN refund_base rb
        ON ob.order_id = rb.order_id
    LEFT JOIN rating_base rating
        ON ob.order_id = rating.order_id

    GROUP BY
        ob.user_segment,
        ob.acquisition_channel,
        ob.price_band,
        ob.discount_bucket
),

final AS (
    SELECT
        user_segment,
        acquisition_channel,
        price_band,
        discount_bucket,

        total_orders,
        delivered_orders,
        cancelled_orders,
        unique_customers,

        gross_order_value,
        total_discount,
        platform_fee_total,
        delivery_fee_total,

        ROUND(platform_fee_total + delivery_fee_total - total_discount - total_refund_amount, 2)
            AS contribution_proxy,

        CASE
            WHEN gross_order_value = 0 THEN 0
            ELSE ROUND(100.0 * total_discount / gross_order_value, 2)
        END AS discount_burn_pct,

        CASE
            WHEN total_discount = 0 THEN 0
            ELSE ROUND(delivered_orders * 1000.0 / total_discount, 2)
        END AS delivered_orders_per_1000_discount,

        CASE
            WHEN total_discount = 0 THEN 0
            ELSE ROUND(gross_order_value / total_discount, 2)
        END AS gross_value_per_1_discount,

        CASE
            WHEN total_orders = 0 THEN 0
            ELSE ROUND(100.0 * delivered_orders / total_orders, 2)
        END AS delivery_success_rate_pct,

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
        COALESCE(avg_food_rating, 0) AS avg_food_rating,
        COALESCE(avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(complaint_orders, 0) AS complaint_orders,

        CASE
            WHEN rated_orders = 0 THEN 0
            ELSE ROUND(100.0 * COALESCE(complaint_orders, 0) / rated_orders, 2)
        END AS complaint_rate_pct

    FROM discount_grouped
)

SELECT
    user_segment,
    acquisition_channel,
    price_band,
    discount_bucket,

    total_orders,
    delivered_orders,
    cancelled_orders,
    unique_customers,

    gross_order_value,
    total_discount,
    platform_fee_total,
    delivery_fee_total,
    contribution_proxy,

    discount_burn_pct,
    delivered_orders_per_1000_discount,
    gross_value_per_1_discount,

    delivery_success_rate_pct,
    cancellation_rate_pct,
    refund_orders,
    refund_rate_pct,

    rated_orders,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,
    complaint_rate_pct,

    CASE
        WHEN total_discount = 0 THEN 'no_discount_baseline'
        WHEN delivered_orders_per_1000_discount >= 12
             AND refund_rate_pct <= 5
             AND complaint_rate_pct <= 25
            THEN 'efficient_discount'
        WHEN delivered_orders_per_1000_discount >= 8
             AND refund_rate_pct <= 8
            THEN 'acceptable_discount'
        WHEN delivered_orders_per_1000_discount >= 4
            THEN 'weak_discount'
        ELSE 'inefficient_discount'
    END AS discount_efficiency_tier

FROM final
WHERE total_orders >= 20
ORDER BY
    discount_efficiency_tier,
    delivered_orders_per_1000_discount DESC,
    total_orders DESC;