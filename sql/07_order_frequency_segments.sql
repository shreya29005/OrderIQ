/*
Analysis:
User order-frequency segmentation.

Business question:
How should users be segmented by ordering frequency, recency, and value?

Grain:
order_frequency_segment + recency_tier + user_segment + acquisition_channel

Key metrics:
- user_count
- ordering_users
- delivered_orders
- repeat_users
- repeat_user_rate_pct
- gross_order_value
- avg_orders_per_user
- avg_orders_per_ordering_user
- avg_days_since_last_order
- avg_sessions_per_user
- session_to_order_user_pct
- refund_user_rate_pct
- complaint_user_rate_pct
- recommended_product_action

Caveats:
1. Frequency is based only on delivered orders.
2. Cancelled orders do not count toward frequency.
3. Non-ordering users are included because they matter for funnel/product strategy.
4. This is a product segmentation layer, not a predictive churn model.
*/

WITH analysis_window AS (
    SELECT
        MAX(CAST(order_time AS DATE)) AS max_order_date
    FROM fact_orders
),

session_stats AS (
    SELECT
        user_id,
        COUNT(DISTINCT session_id) AS total_sessions
    FROM fact_sessions
    GROUP BY user_id
),

search_stats AS (
    SELECT
        user_id,
        COUNT(DISTINCT search_id) AS search_events,
        COUNT(DISTINCT CASE WHEN clicked_restaurant_id IS NOT NULL THEN search_id END) AS clicked_search_events
    FROM fact_search_events
    GROUP BY user_id
),

cart_stats AS (
    SELECT
        user_id,
        COUNT(DISTINCT cart_id) AS cart_events
    FROM fact_cart_events
    GROUP BY user_id
),

delivered_orders AS (
    SELECT
        order_id,
        user_id,
        restaurant_id,
        CAST(order_time AS DATE) AS order_date,
        order_value,
        discount_amount,
        delivery_fee,
        platform_fee
    FROM fact_orders
    WHERE order_status = 'delivered'
),

order_stats AS (
    SELECT
        user_id,

        COUNT(DISTINCT order_id) AS delivered_orders,

        MIN(order_date) AS first_order_date,
        MAX(order_date) AS last_order_date,

        COUNT(DISTINCT restaurant_id) AS restaurants_ordered_from,

        ROUND(SUM(order_value), 2) AS gross_order_value,
        ROUND(SUM(discount_amount), 2) AS total_discount,
        ROUND(SUM(delivery_fee), 2) AS total_delivery_fee,
        ROUND(SUM(platform_fee), 2) AS total_platform_fee,

        ROUND(AVG(order_value), 2) AS avg_order_value

    FROM delivered_orders
    GROUP BY user_id
),

refund_stats AS (
    SELECT
        o.user_id,
        COUNT(DISTINCT rf.order_id) AS refund_orders,
        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount
    FROM fact_refunds rf
    INNER JOIN fact_orders o
        ON rf.order_id = o.order_id
    GROUP BY o.user_id
),

rating_stats AS (
    SELECT
        user_id,
        COUNT(DISTINCT rating_id) AS rating_count,
        ROUND(AVG(food_rating), 2) AS avg_food_rating,
        ROUND(AVG(delivery_rating), 2) AS avg_delivery_rating,
        SUM(
            CASE
                WHEN complaint_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS complaint_orders
    FROM fact_ratings
    GROUP BY user_id
),

user_level AS (
    SELECT
        u.user_id,
        u.age_band,
        u.income_proxy,
        u.city,
        u.zone,
        u.acquisition_channel,
        u.user_segment,
        u.gold_member_flag,

        COALESCE(ss.total_sessions, 0) AS total_sessions,
        COALESCE(se.search_events, 0) AS search_events,
        COALESCE(se.clicked_search_events, 0) AS clicked_search_events,
        COALESCE(cs.cart_events, 0) AS cart_events,

        COALESCE(os.delivered_orders, 0) AS delivered_orders,
        os.first_order_date,
        os.last_order_date,

        COALESCE(os.restaurants_ordered_from, 0) AS restaurants_ordered_from,
        COALESCE(os.gross_order_value, 0) AS gross_order_value,
        COALESCE(os.total_discount, 0) AS total_discount,
        COALESCE(os.total_delivery_fee, 0) AS total_delivery_fee,
        COALESCE(os.total_platform_fee, 0) AS total_platform_fee,
        COALESCE(os.avg_order_value, 0) AS avg_order_value,

        COALESCE(rf.refund_orders, 0) AS refund_orders,
        COALESCE(rf.total_refund_amount, 0) AS total_refund_amount,

        COALESCE(rt.rating_count, 0) AS rating_count,
        COALESCE(rt.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rt.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rt.complaint_orders, 0) AS complaint_orders,

        CASE
            WHEN COALESCE(os.delivered_orders, 0) = 0 THEN 999
            ELSE DATE_DIFF('day', os.last_order_date, aw.max_order_date)
        END AS days_since_last_order,

        CASE
            WHEN COALESCE(os.delivered_orders, 0) = 0 THEN 0
            ELSE DATE_DIFF('day', os.first_order_date, aw.max_order_date) + 1
        END AS days_since_first_order

    FROM dim_users u
    CROSS JOIN analysis_window aw
    LEFT JOIN session_stats ss
        ON u.user_id = ss.user_id
    LEFT JOIN search_stats se
        ON u.user_id = se.user_id
    LEFT JOIN cart_stats cs
        ON u.user_id = cs.user_id
    LEFT JOIN order_stats os
        ON u.user_id = os.user_id
    LEFT JOIN refund_stats rf
        ON u.user_id = rf.user_id
    LEFT JOIN rating_stats rt
        ON u.user_id = rt.user_id
),

segmented_users AS (
    SELECT
        *,

        CASE
            WHEN delivered_orders = 0 THEN '0_no_order_yet'
            WHEN delivered_orders = 1 THEN '1_one_time_orderer'
            WHEN delivered_orders = 2 THEN '2_occasional_2_orders'
            WHEN delivered_orders BETWEEN 3 AND 4 THEN '3_regular_3_4_orders'
            ELSE '4_loyal_5_plus_orders'
        END AS order_frequency_segment,

        CASE
            WHEN delivered_orders = 0 THEN '0_no_order_yet'
            WHEN days_since_last_order <= 30 THEN '1_active_last_30_days'
            WHEN days_since_last_order BETWEEN 31 AND 60 THEN '2_cooling_31_60_days'
            ELSE '3_dormant_60_plus_days'
        END AS recency_tier,

        CASE
            WHEN delivered_orders >= 2 THEN 1
            ELSE 0
        END AS repeat_user_flag,

        CASE
            WHEN delivered_orders > 0 THEN 1
            ELSE 0
        END AS ordering_user_flag,

        CASE
            WHEN total_sessions > 0 AND delivered_orders > 0 THEN 1
            ELSE 0
        END AS session_to_order_user_flag,

        CASE
            WHEN refund_orders > 0 THEN 1
            ELSE 0
        END AS refund_user_flag,

        CASE
            WHEN complaint_orders > 0 THEN 1
            ELSE 0
        END AS complaint_user_flag

    FROM user_level
),

grouped AS (
    SELECT
        order_frequency_segment,
        recency_tier,
        user_segment,
        acquisition_channel,

        COUNT(DISTINCT user_id) AS user_count,

        SUM(ordering_user_flag) AS ordering_users,
        SUM(repeat_user_flag) AS repeat_users,

        SUM(delivered_orders) AS delivered_orders,
        SUM(restaurants_ordered_from) AS restaurants_ordered_from,

        ROUND(SUM(gross_order_value), 2) AS gross_order_value,
        ROUND(SUM(total_discount), 2) AS total_discount,
        ROUND(SUM(total_delivery_fee), 2) AS total_delivery_fee,
        ROUND(SUM(total_platform_fee), 2) AS total_platform_fee,
        ROUND(SUM(total_refund_amount), 2) AS total_refund_amount,

        SUM(total_sessions) AS total_sessions,
        SUM(search_events) AS search_events,
        SUM(clicked_search_events) AS clicked_search_events,
        SUM(cart_events) AS cart_events,

        SUM(refund_user_flag) AS refund_users,
        SUM(complaint_user_flag) AS complaint_users,

        SUM(rating_count) AS rating_count,

        ROUND(AVG(CASE WHEN delivered_orders > 0 THEN avg_order_value ELSE NULL END), 2) AS avg_order_value,

        ROUND(AVG(CASE WHEN delivered_orders > 0 THEN days_since_last_order ELSE NULL END), 2) AS avg_days_since_last_order,

        ROUND(AVG(CASE WHEN delivered_orders > 0 THEN days_since_first_order ELSE NULL END), 2) AS avg_days_since_first_order,

        ROUND(AVG(CASE WHEN rating_count > 0 THEN avg_food_rating ELSE NULL END), 2) AS avg_food_rating,

        ROUND(AVG(CASE WHEN rating_count > 0 THEN avg_delivery_rating ELSE NULL END), 2) AS avg_delivery_rating

    FROM segmented_users
    GROUP BY
        order_frequency_segment,
        recency_tier,
        user_segment,
        acquisition_channel
)

SELECT
    order_frequency_segment,
    recency_tier,
    user_segment,
    acquisition_channel,

    user_count,
    ordering_users,
    repeat_users,

    delivered_orders,
    restaurants_ordered_from,

    gross_order_value,
    total_discount,
    total_delivery_fee,
    total_platform_fee,
    total_refund_amount,

    CASE
        WHEN user_count = 0 THEN 0
        ELSE ROUND(100.0 * ordering_users / user_count, 2)
    END AS ordering_user_rate_pct,

    CASE
        WHEN user_count = 0 THEN 0
        ELSE ROUND(100.0 * repeat_users / user_count, 2)
    END AS repeat_user_rate_pct,

    CASE
        WHEN ordering_users = 0 THEN 0
        ELSE ROUND(1.0 * delivered_orders / ordering_users, 2)
    END AS avg_orders_per_ordering_user,

    CASE
        WHEN user_count = 0 THEN 0
        ELSE ROUND(1.0 * delivered_orders / user_count, 2)
    END AS avg_orders_per_user,

    CASE
        WHEN ordering_users = 0 THEN 0
        ELSE ROUND(gross_order_value / ordering_users, 2)
    END AS gross_value_per_ordering_user,

    COALESCE(avg_order_value, 0) AS avg_order_value,

    CASE
        WHEN gross_order_value = 0 THEN 0
        ELSE ROUND(100.0 * total_discount / gross_order_value, 2)
    END AS discount_burn_pct,

    CASE
        WHEN user_count = 0 THEN 0
        ELSE ROUND(1.0 * total_sessions / user_count, 2)
    END AS avg_sessions_per_user,

    CASE
        WHEN user_count = 0 THEN 0
        ELSE ROUND(100.0 * ordering_users / user_count, 2)
    END AS session_to_order_user_pct,

    CASE
        WHEN user_count = 0 THEN 0
        ELSE ROUND(100.0 * refund_users / user_count, 2)
    END AS refund_user_rate_pct,

    CASE
        WHEN user_count = 0 THEN 0
        ELSE ROUND(100.0 * complaint_users / user_count, 2)
    END AS complaint_user_rate_pct,

    COALESCE(avg_days_since_last_order, 0) AS avg_days_since_last_order,
    COALESCE(avg_days_since_first_order, 0) AS avg_days_since_first_order,

    rating_count,
    COALESCE(avg_food_rating, 0) AS avg_food_rating,
    COALESCE(avg_delivery_rating, 0) AS avg_delivery_rating,

    CASE
        WHEN order_frequency_segment = '0_no_order_yet'
            THEN 'activate_with_first_order_offer'
        WHEN order_frequency_segment = '1_one_time_orderer'
             AND recency_tier = '3_dormant_60_plus_days'
            THEN 'win_back_before_churn'
        WHEN order_frequency_segment = '1_one_time_orderer'
            THEN 'drive_second_order'
                WHEN order_frequency_segment = '2_occasional_2_orders'
            THEN 'increase_order_habit'
        WHEN order_frequency_segment = '3_regular_3_4_orders'
            THEN 'protect_and_cross_sell'
        ELSE 'loyalty_and_premium_retention'
    END AS recommended_product_action

FROM grouped
WHERE user_count >= 10
ORDER BY
    order_frequency_segment,
    recency_tier,
    user_segment,
    acquisition_channel;