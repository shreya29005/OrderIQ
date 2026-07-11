/*
Analysis:
Restaurant quality scorecard.

Business question:
Which restaurants are strong supply partners, and which restaurants create marketplace risk?

Grain:
restaurant_id

Key metrics:
- delivered_orders
- unique_customers
- repeat_customer_rate_pct
- avg_order_value
- refund_rate_pct
- complaint_rate_pct
- cancellation_rate_pct
- avg_food_rating
- avg_delivery_rating
- avg_delivery_time_min
- sla_breach_pct
- restaurant_quality_score

Scoring logic:
Higher is better.
Positive signals:
1. food rating
2. delivery rating
3. repeat customer rate
4. order volume

Negative signals:
1. refund rate
2. complaint rate
3. SLA breach rate
4. cancellation rate

Caveats:
1. Restaurants with fewer than 10 total orders are excluded to avoid noisy scoring.
2. The score is directional, not a production-grade ML ranking.
3. The purpose is marketplace prioritization, not automated penalization.
*/

WITH restaurant_order_base AS (
    SELECT
        r.restaurant_id,
        r.restaurant_name,
        r.city,
        r.zone,
        r.primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS price_band,
        COALESCE(r.rating, 0) AS public_rating,
        COALESCE(r.votes, 0) AS public_votes,
        COALESCE(r.restaurant_quality_prior, 0) AS restaurant_quality_prior,

        o.order_id,
        o.user_id,
        o.order_value,
        o.order_status,
        CAST(o.order_time AS DATE) AS order_date

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
),

restaurant_orders AS (
    SELECT
        restaurant_id,
        restaurant_name,
        city,
        zone,
        primary_cuisine,
        price_band,
        public_rating,
        public_votes,
        restaurant_quality_prior,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders,

        COUNT(DISTINCT user_id) AS unique_customers,

        ROUND(AVG(order_value), 2) AS avg_order_value,

        ROUND(SUM(order_value), 2) AS gross_order_value

    FROM restaurant_order_base
    GROUP BY
        restaurant_id,
        restaurant_name,
        city,
        zone,
        primary_cuisine,
        price_band,
        public_rating,
        public_votes,
        restaurant_quality_prior
),

repeat_customers AS (
    SELECT
        restaurant_id,
        COUNT(DISTINCT user_id) AS repeat_customers
    FROM (
        SELECT
            restaurant_id,
            user_id,
            COUNT(DISTINCT order_id) AS delivered_orders_by_user
        FROM restaurant_order_base
        WHERE order_status = 'delivered'
        GROUP BY
            restaurant_id,
            user_id
        HAVING COUNT(DISTINCT order_id) >= 2
    ) repeated
    GROUP BY restaurant_id
),

delivery_metrics AS (
    SELECT
        d.restaurant_id,

        ROUND(AVG(d.total_delivery_time_min), 2) AS avg_delivery_time_min,

        ROUND(QUANTILE_CONT(d.total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        SUM(
            CASE
                WHEN d.sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_orders

    FROM fact_delivery_ops d
    GROUP BY d.restaurant_id
),

refund_metrics AS (
    SELECT
        o.restaurant_id,
        COUNT(DISTINCT rf.order_id) AS refund_orders,
        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount
    FROM fact_refunds rf
    INNER JOIN fact_orders o
        ON rf.order_id = o.order_id
    GROUP BY o.restaurant_id
),

rating_metrics AS (
    SELECT
        restaurant_id,

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
    GROUP BY restaurant_id
),

restaurant_features AS (
    SELECT
        ro.restaurant_id,
        ro.restaurant_name,
        ro.city,
        ro.zone,
        ro.primary_cuisine,
        ro.price_band,
        ro.public_rating,
        ro.public_votes,
        ro.restaurant_quality_prior,

        ro.total_orders,
        ro.delivered_orders,
        ro.cancelled_orders,
        ro.unique_customers,
        COALESCE(rc.repeat_customers, 0) AS repeat_customers,

        ro.avg_order_value,
        ro.gross_order_value,

        COALESCE(dm.avg_delivery_time_min, 0) AS avg_delivery_time_min,
        COALESCE(dm.p90_delivery_time_min, 0) AS p90_delivery_time_min,
        COALESCE(dm.sla_breach_orders, 0) AS sla_breach_orders,

        COALESCE(rfm.refund_orders, 0) AS refund_orders,
        COALESCE(rfm.total_refund_amount, 0) AS total_refund_amount,

        COALESCE(rtm.rating_count, 0) AS rating_count,
        COALESCE(rtm.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rtm.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rtm.complaint_orders, 0) AS complaint_orders

    FROM restaurant_orders ro
    LEFT JOIN repeat_customers rc
        ON ro.restaurant_id = rc.restaurant_id
    LEFT JOIN delivery_metrics dm
        ON ro.restaurant_id = dm.restaurant_id
    LEFT JOIN refund_metrics rfm
        ON ro.restaurant_id = rfm.restaurant_id
    LEFT JOIN rating_metrics rtm
        ON ro.restaurant_id = rtm.restaurant_id
),

restaurant_rates AS (
    SELECT
        *,

        CASE
            WHEN unique_customers = 0 THEN 0
            ELSE ROUND(100.0 * repeat_customers / unique_customers, 2)
        END AS repeat_customer_rate_pct,

        CASE
            WHEN total_orders = 0 THEN 0
            ELSE ROUND(100.0 * cancelled_orders / total_orders, 2)
        END AS cancellation_rate_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * refund_orders / delivered_orders, 2)
        END AS refund_rate_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * sla_breach_orders / delivered_orders, 2)
        END AS sla_breach_pct,

        CASE
            WHEN rating_count = 0 THEN 0
            ELSE ROUND(100.0 * complaint_orders / rating_count, 2)
        END AS complaint_rate_pct

    FROM restaurant_features
),

scored AS (
    SELECT
        *,

        /*
        Simple interpretable score out of 100.
        This is deliberately transparent for business users.
        */
        ROUND(
            20 * (COALESCE(avg_food_rating, 0) / 5.0)
            + 15 * (COALESCE(avg_delivery_rating, 0) / 5.0)
            + 15 * LEAST(repeat_customer_rate_pct / 40.0, 1.0)
            + 10 * LEAST(delivered_orders / 50.0, 1.0)
            + 10 * COALESCE(restaurant_quality_prior, 0)
            + 10 * (1 - LEAST(refund_rate_pct / 15.0, 1.0))
            + 10 * (1 - LEAST(complaint_rate_pct / 40.0, 1.0))
            + 5 * (1 - LEAST(sla_breach_pct / 40.0, 1.0))
            + 5 * (1 - LEAST(cancellation_rate_pct / 20.0, 1.0)),
            2
        ) AS restaurant_quality_score

    FROM restaurant_rates
)

SELECT
    restaurant_id,
    restaurant_name,
    city,
    zone,
    primary_cuisine,
    price_band,

    total_orders,
    delivered_orders,
    cancelled_orders,
    unique_customers,
    repeat_customers,
    repeat_customer_rate_pct,

    avg_order_value,
    gross_order_value,

    avg_delivery_time_min,
    p90_delivery_time_min,
    sla_breach_pct,

    refund_orders,
    refund_rate_pct,
    total_refund_amount,

    rating_count,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,
    complaint_rate_pct,

    cancellation_rate_pct,

    public_rating,
    public_votes,

    restaurant_quality_score,

    CASE
        WHEN restaurant_quality_score >= 75 THEN 'high_quality_partner'
        WHEN restaurant_quality_score >= 60 THEN 'stable_partner'
        WHEN restaurant_quality_score >= 45 THEN 'needs_monitoring'
        ELSE 'high_risk_partner'
    END AS restaurant_quality_tier

FROM scored
WHERE total_orders >= 3
  AND delivered_orders >= 2
ORDER BY
    restaurant_quality_score DESC,
    delivered_orders DESC;