/*
Analysis:
First-order experience and retention.

Business question:
How does a user's first delivered order experience affect repeat behavior?

Grain:
first_experience_tier + first_delivery_time_bucket + user_segment + acquisition_channel

Key metrics:
- new_ordering_users
- repeat_users
- repeat_order_rate_pct
- d7_retained_users
- d30_retained_users
- d30_retention_pct
- avg_orders_per_user
- avg_days_to_second_order
- first_order_sla_breach_pct
- first_order_refund_pct
- first_order_complaint_pct
- avg_first_delivery_time_min
- avg_first_food_rating
- avg_first_delivery_rating

Caveats:
1. Cohort is based on first delivered order, not signup.
2. Only delivered first orders are included.
3. Cancelled orders are excluded from retention count.
4. The analysis is diagnostic, not causal.
*/

WITH delivered_orders AS (
    SELECT
        o.order_id,
        o.user_id,
        o.restaurant_id,
        CAST(o.order_time AS TIMESTAMP) AS order_timestamp,
        CAST(o.order_time AS DATE) AS order_date,
        o.order_value,
        o.discount_amount,
        o.discount_pct,

        r.city,
        r.zone,
        COALESCE(r.primary_cuisine, 'unknown') AS primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS price_band

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
    WHERE o.order_status = 'delivered'
),

ordered_sequence AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY order_timestamp, order_id
        ) AS order_sequence_number
    FROM delivered_orders
),

first_order AS (
    SELECT
        *
    FROM ordered_sequence
    WHERE order_sequence_number = 1
),

second_order AS (
    SELECT
        user_id,
        order_date AS second_order_date
    FROM ordered_sequence
    WHERE order_sequence_number = 2
),

user_lifetime_orders AS (
    SELECT
        user_id,
        COUNT(DISTINCT order_id) AS lifetime_delivered_orders,
        MIN(order_date) AS first_order_date,
        MAX(order_date) AS last_order_date,
        ROUND(SUM(order_value), 2) AS lifetime_gross_order_value
    FROM delivered_orders
    GROUP BY user_id
),

first_delivery_ops AS (
    SELECT
        fo.user_id,
        fo.order_id,
        d.total_delivery_time_min,
        d.prep_time_min,
        d.rider_wait_time_min,
        d.drop_time_min,
        d.distance_km,
        d.sla_breach_flag
    FROM first_order fo
    INNER JOIN fact_delivery_ops d
        ON fo.order_id = d.order_id
),

first_rating AS (
    SELECT
        fo.user_id,
        fo.order_id,
        AVG(rt.food_rating) AS first_food_rating,
        AVG(rt.delivery_rating) AS first_delivery_rating,
        MAX(
            CASE
                WHEN rt.complaint_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS first_complaint_flag
    FROM first_order fo
    LEFT JOIN fact_ratings rt
        ON fo.order_id = rt.order_id
    GROUP BY
        fo.user_id,
        fo.order_id
),

first_refund AS (
    SELECT
        fo.user_id,
        fo.order_id,
        COUNT(DISTINCT rf.refund_id) AS first_refund_count,
        ROUND(COALESCE(SUM(rf.refund_amount), 0), 2) AS first_refund_amount
    FROM first_order fo
    LEFT JOIN fact_refunds rf
        ON fo.order_id = rf.order_id
    GROUP BY
        fo.user_id,
        fo.order_id
),

user_first_order_features AS (
    SELECT
        fo.user_id,
        fo.order_id AS first_order_id,
        fo.order_date AS first_order_date,
        DATE_TRUNC('month', fo.order_date) AS first_order_month,

        u.user_segment,
        u.acquisition_channel,
        u.income_proxy,
        u.gold_member_flag,

        fo.primary_cuisine AS first_primary_cuisine,
        fo.price_band AS first_price_band,
        fo.order_value AS first_order_value,
        fo.discount_amount AS first_discount_amount,
        fo.discount_pct AS first_discount_pct,

        lo.lifetime_delivered_orders,
        lo.lifetime_gross_order_value,

        CASE
            WHEN lo.lifetime_delivered_orders >= 2 THEN 1
            ELSE 0
        END AS repeat_user_flag,

        CASE
            WHEN so.second_order_date IS NULL THEN NULL
            ELSE DATE_DIFF('day', fo.order_date, so.second_order_date)
        END AS days_to_second_order,

        CASE
            WHEN so.second_order_date IS NOT NULL
                 AND DATE_DIFF('day', fo.order_date, so.second_order_date) BETWEEN 1 AND 7
                THEN 1
            ELSE 0
        END AS d7_retained_flag,

        CASE
            WHEN so.second_order_date IS NOT NULL
                 AND DATE_DIFF('day', fo.order_date, so.second_order_date) BETWEEN 1 AND 30
                THEN 1
            ELSE 0
        END AS d30_retained_flag,

        fdo.total_delivery_time_min AS first_delivery_time_min,
        fdo.prep_time_min AS first_prep_time_min,
        fdo.rider_wait_time_min AS first_rider_wait_time_min,
        fdo.drop_time_min AS first_drop_time_min,
        fdo.distance_km AS first_distance_km,

        CASE
            WHEN fdo.sla_breach_flag = TRUE THEN 1
            ELSE 0
        END AS first_sla_breach_flag,

        COALESCE(fr.first_food_rating, 0) AS first_food_rating,
        COALESCE(fr.first_delivery_rating, 0) AS first_delivery_rating,
        COALESCE(fr.first_complaint_flag, 0) AS first_complaint_flag,

        COALESCE(frf.first_refund_count, 0) AS first_refund_count,
        COALESCE(frf.first_refund_amount, 0) AS first_refund_amount

    FROM first_order fo
    INNER JOIN dim_users u
        ON fo.user_id = u.user_id
    INNER JOIN user_lifetime_orders lo
        ON fo.user_id = lo.user_id
    LEFT JOIN second_order so
        ON fo.user_id = so.user_id
    LEFT JOIN first_delivery_ops fdo
        ON fo.user_id = fdo.user_id
    LEFT JOIN first_rating fr
        ON fo.user_id = fr.user_id
    LEFT JOIN first_refund frf
        ON fo.user_id = frf.user_id
),

segmented AS (
    SELECT
        *,

        CASE
            WHEN first_delivery_time_min <= 30 THEN '1_fast_under_30'
            WHEN first_delivery_time_min <= 45 THEN '2_normal_30_45'
            WHEN first_delivery_time_min <= 60 THEN '3_slow_45_60'
            ELSE '4_very_slow_60_plus'
        END AS first_delivery_time_bucket,

        CASE
            WHEN first_discount_pct = 0 THEN '0_no_discount'
            WHEN first_discount_pct <= 0.10 THEN '1_low_discount'
            WHEN first_discount_pct <= 0.20 THEN '2_medium_discount'
            ELSE '3_high_discount'
        END AS first_discount_bucket,

        CASE
            WHEN first_refund_count > 0
                 OR first_complaint_flag = 1
                 OR first_sla_breach_flag = 1
                 OR first_food_rating < 3
                 OR first_delivery_rating < 3
                THEN '3_poor_first_experience'
            WHEN first_delivery_time_min <= 35
                 AND first_food_rating >= 4
                 AND first_delivery_rating >= 4
                 AND first_refund_count = 0
                 AND first_complaint_flag = 0
                THEN '1_strong_first_experience'
            ELSE '2_neutral_first_experience'
        END AS first_experience_tier

    FROM user_first_order_features
),

grouped AS (
    SELECT
        first_experience_tier,
        first_delivery_time_bucket,
        user_segment,
        acquisition_channel,

        COUNT(DISTINCT user_id) AS new_ordering_users,

        SUM(repeat_user_flag) AS repeat_users,
        SUM(d7_retained_flag) AS d7_retained_users,
        SUM(d30_retained_flag) AS d30_retained_users,

        SUM(lifetime_delivered_orders) AS total_lifetime_delivered_orders,

        ROUND(SUM(lifetime_gross_order_value), 2) AS lifetime_gross_order_value,

        ROUND(AVG(first_order_value), 2) AS avg_first_order_value,
        ROUND(AVG(first_discount_amount), 2) AS avg_first_discount_amount,

        ROUND(AVG(first_delivery_time_min), 2) AS avg_first_delivery_time_min,
        ROUND(AVG(first_prep_time_min), 2) AS avg_first_prep_time_min,
        ROUND(AVG(first_rider_wait_time_min), 2) AS avg_first_rider_wait_time_min,
        ROUND(AVG(first_drop_time_min), 2) AS avg_first_drop_time_min,
        ROUND(AVG(first_distance_km), 2) AS avg_first_distance_km,

        SUM(first_sla_breach_flag) AS first_sla_breach_users,
        SUM(CASE WHEN first_refund_count > 0 THEN 1 ELSE 0 END) AS first_refund_users,
        SUM(first_complaint_flag) AS first_complaint_users,

        ROUND(AVG(first_food_rating), 2) AS avg_first_food_rating,
        ROUND(AVG(first_delivery_rating), 2) AS avg_first_delivery_rating,

        ROUND(AVG(CASE WHEN days_to_second_order IS NOT NULL THEN days_to_second_order ELSE NULL END), 2)
            AS avg_days_to_second_order

    FROM segmented
    GROUP BY
        first_experience_tier,
        first_delivery_time_bucket,
        user_segment,
        acquisition_channel
)

SELECT
    first_experience_tier,
    first_delivery_time_bucket,
    user_segment,
    acquisition_channel,

    new_ordering_users,

    repeat_users,

    CASE
        WHEN new_ordering_users = 0 THEN 0
        ELSE ROUND(100.0 * repeat_users / new_ordering_users, 2)
    END AS repeat_order_rate_pct,

    d7_retained_users,

    CASE
        WHEN new_ordering_users = 0 THEN 0
        ELSE ROUND(100.0 * d7_retained_users / new_ordering_users, 2)
    END AS d7_retention_pct,

    d30_retained_users,

    CASE
        WHEN new_ordering_users = 0 THEN 0
        ELSE ROUND(100.0 * d30_retained_users / new_ordering_users, 2)
    END AS d30_retention_pct,

    total_lifetime_delivered_orders,

    CASE
        WHEN new_ordering_users = 0 THEN 0
        ELSE ROUND(1.0 * total_lifetime_delivered_orders / new_ordering_users, 2)
    END AS avg_lifetime_orders_per_user,

    lifetime_gross_order_value,

    avg_first_order_value,
    avg_first_discount_amount,

    avg_first_delivery_time_min,
    avg_first_prep_time_min,
    avg_first_rider_wait_time_min,
    avg_first_drop_time_min,
    avg_first_distance_km,

    first_sla_breach_users,

    CASE
        WHEN new_ordering_users = 0 THEN 0
        ELSE ROUND(100.0 * first_sla_breach_users / new_ordering_users, 2)
    END AS first_order_sla_breach_pct,

    first_refund_users,

    CASE
        WHEN new_ordering_users = 0 THEN 0
        ELSE ROUND(100.0 * first_refund_users / new_ordering_users, 2)
    END AS first_order_refund_pct,

    first_complaint_users,

    CASE
        WHEN new_ordering_users = 0 THEN 0
        ELSE ROUND(100.0 * first_complaint_users / new_ordering_users, 2)
    END AS first_order_complaint_pct,

    avg_first_food_rating,
    avg_first_delivery_rating,

    COALESCE(avg_days_to_second_order, 0) AS avg_days_to_second_order,

    CASE
        WHEN first_experience_tier = '3_poor_first_experience'
            THEN 'repair_first_order_experience'
        WHEN first_experience_tier = '1_strong_first_experience'
            THEN 'accelerate_second_order'
        ELSE 'nudge_second_order_with_context'
    END AS recommended_product_action

FROM grouped
WHERE new_ordering_users >= 10
ORDER BY
    first_experience_tier,
    repeat_order_rate_pct DESC,
    new_ordering_users DESC;