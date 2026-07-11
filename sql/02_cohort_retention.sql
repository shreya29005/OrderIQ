/*
Analysis:
Cohort retention by first delivered order month.

Business question:
Are users coming back after their first successful delivered order?

Grain:
cohort_month + user_segment + acquisition_channel

Key metrics:
- new_ordering_users
- users_with_repeat_order
- repeat_order_rate_pct
- d7_retained_users
- d7_retention_pct
- d30_retained_users
- d30_retention_pct
- avg_orders_per_user
- avg_days_to_second_order

Caveats:
1. Cohorts are based on first delivered order date, not signup date.
2. Cancelled orders are excluded from retention.
3. Retention is calculated at user grain.
4. D7 retention means user placed another delivered order within 1–7 days after first order.
5. D30 retention means user placed another delivered order within 1–30 days after first order.
*/

WITH delivered_orders AS (
    SELECT
        order_id,
        user_id,
        CAST(order_time AS DATE) AS order_date
    FROM fact_orders
    WHERE order_status = 'delivered'
),

first_order AS (
    SELECT
        user_id,
        MIN(order_date) AS first_order_date
    FROM delivered_orders
    GROUP BY user_id
),

user_order_sequence AS (
    SELECT
        d.user_id,
        d.order_id,
        d.order_date,
        f.first_order_date,
        DATE_DIFF('day', f.first_order_date, d.order_date) AS days_since_first_order,

        ROW_NUMBER() OVER (
            PARTITION BY d.user_id
            ORDER BY d.order_date, d.order_id
        ) AS order_sequence_number

    FROM delivered_orders d
    INNER JOIN first_order f
        ON d.user_id = f.user_id
),

second_order AS (
    SELECT
        user_id,
        MIN(days_since_first_order) AS days_to_second_order
    FROM user_order_sequence
    WHERE order_sequence_number = 2
    GROUP BY user_id
),

user_retention_flags AS (
    SELECT
        f.user_id,
        CAST(DATE_TRUNC('month', f.first_order_date) AS DATE) AS cohort_month,
        f.first_order_date,

        u.user_segment,
        u.acquisition_channel,
        u.income_proxy,
        u.gold_member_flag,

        COUNT(DISTINCT s.order_id) AS delivered_orders,

        MAX(
            CASE
                WHEN s.days_since_first_order BETWEEN 1 AND 7 THEN 1
                ELSE 0
            END
        ) AS d7_retained_flag,

        MAX(
            CASE
                WHEN s.days_since_first_order BETWEEN 1 AND 30 THEN 1
                ELSE 0
            END
        ) AS d30_retained_flag,

        MAX(
            CASE
                WHEN s.days_since_first_order > 0 THEN 1
                ELSE 0
            END
        ) AS repeat_order_flag,

        so.days_to_second_order

    FROM first_order f
    INNER JOIN dim_users u
        ON f.user_id = u.user_id
    LEFT JOIN user_order_sequence s
        ON f.user_id = s.user_id
    LEFT JOIN second_order so
        ON f.user_id = so.user_id

    GROUP BY
        f.user_id,
        CAST(DATE_TRUNC('month', f.first_order_date) AS DATE),
        f.first_order_date,
        u.user_segment,
        u.acquisition_channel,
        u.income_proxy,
        u.gold_member_flag,
        so.days_to_second_order
),

cohort_aggregated AS (
    SELECT
        cohort_month,
        user_segment,
        acquisition_channel,

        COUNT(DISTINCT user_id) AS new_ordering_users,

        SUM(repeat_order_flag) AS users_with_repeat_order,
        SUM(d7_retained_flag) AS d7_retained_users,
        SUM(d30_retained_flag) AS d30_retained_users,

        SUM(delivered_orders) AS total_delivered_orders,

        AVG(delivered_orders) AS avg_orders_per_user,

        AVG(
            CASE
                WHEN days_to_second_order IS NOT NULL THEN days_to_second_order
                ELSE NULL
            END
        ) AS avg_days_to_second_order

    FROM user_retention_flags
    GROUP BY
        cohort_month,
        user_segment,
        acquisition_channel
)

SELECT
    cohort_month,
    user_segment,
    acquisition_channel,

    new_ordering_users,
    users_with_repeat_order,

    CASE
        WHEN new_ordering_users = 0 THEN 0
        ELSE ROUND(100.0 * users_with_repeat_order / new_ordering_users, 2)
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

    total_delivered_orders,

    ROUND(avg_orders_per_user, 2) AS avg_orders_per_user,

    COALESCE(ROUND(avg_days_to_second_order, 2), 0) AS avg_days_to_second_order

FROM cohort_aggregated
WHERE new_ordering_users >= 10
ORDER BY
    cohort_month,
    user_segment,
    acquisition_channel;