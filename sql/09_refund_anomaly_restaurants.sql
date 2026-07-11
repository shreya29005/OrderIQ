/*
Analysis:
Restaurant refund and complaint anomaly detection.

Business question:
Which restaurants are operational or customer-experience outliers?

Grain:
restaurant_id

Key metrics:
- total_orders
- delivered_orders
- refund_rate_pct
- complaint_rate_pct
- sla_breach_pct
- cancellation_rate_pct
- avg_food_rating
- avg_delivery_rating
- anomaly_score
- anomaly_tier

Caveats:
1. This is rule-based anomaly detection, not a statistical fraud model.
2. Restaurants with fewer than 3 delivered orders are excluded to reduce noise.
3. Refund, complaint, SLA, and cancellation signals are combined into a transparent anomaly score.
4. The score should be used for investigation prioritization, not automated enforcement.
*/

WITH restaurant_order_base AS (
    SELECT
        r.restaurant_id,
        r.restaurant_name,
        r.city,
        r.zone,
        COALESCE(r.primary_cuisine, 'unknown') AS primary_cuisine,
        COALESCE(r.price_band, 'unknown') AS price_band,
        COALESCE(r.rating, 0) AS public_rating,
        COALESCE(r.votes, 0) AS public_votes,

        o.order_id,
        o.user_id,
        o.order_status,
        o.order_value,
        CAST(o.order_time AS DATE) AS order_date

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
),

order_metrics AS (
    SELECT
        restaurant_id,
        restaurant_name,
        city,
        zone,
        primary_cuisine,
        price_band,
        public_rating,
        public_votes,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders,

        COUNT(DISTINCT user_id) AS unique_customers,

        ROUND(SUM(order_value), 2) AS gross_order_value,

        ROUND(AVG(order_value), 2) AS avg_order_value

    FROM restaurant_order_base
    GROUP BY
        restaurant_id,
        restaurant_name,
        city,
        zone,
        primary_cuisine,
        price_band,
        public_rating,
        public_votes
),

refund_metrics AS (
    SELECT
        o.restaurant_id,

        COUNT(DISTINCT rf.order_id) AS refund_orders,

        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount,

        COUNT(DISTINCT CASE WHEN rf.refund_reason = 'late_delivery' THEN rf.order_id END) AS late_delivery_refunds,

        COUNT(DISTINCT CASE WHEN rf.refund_reason = 'wrong_item' THEN rf.order_id END) AS wrong_item_refunds,

        COUNT(DISTINCT CASE WHEN rf.refund_reason = 'damaged_packaging' THEN rf.order_id END) AS damaged_packaging_refunds,

        COUNT(DISTINCT CASE WHEN rf.refund_reason = 'quality_issue' THEN rf.order_id END) AS quality_issue_refunds

    FROM fact_refunds rf
    INNER JOIN fact_orders o
        ON rf.order_id = o.order_id
    GROUP BY
        o.restaurant_id
),

rating_metrics AS (
    SELECT
        restaurant_id,

        COUNT(DISTINCT order_id) AS rated_orders,

        ROUND(AVG(food_rating), 2) AS avg_food_rating,

        ROUND(AVG(delivery_rating), 2) AS avg_delivery_rating,

        SUM(
            CASE
                WHEN complaint_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS complaint_orders

    FROM fact_ratings
    GROUP BY
        restaurant_id
),

delivery_metrics AS (
    SELECT
        restaurant_id,

        ROUND(AVG(total_delivery_time_min), 2) AS avg_delivery_time_min,

        ROUND(QUANTILE_CONT(total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        SUM(
            CASE
                WHEN sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_orders,

        ROUND(AVG(prep_time_min), 2) AS avg_prep_time_min,

        ROUND(AVG(rider_wait_time_min), 2) AS avg_rider_wait_time_min,

        ROUND(AVG(drop_time_min), 2) AS avg_drop_time_min

    FROM fact_delivery_ops
    GROUP BY
        restaurant_id
),

restaurant_features AS (
    SELECT
        om.restaurant_id,
        om.restaurant_name,
        om.city,
        om.zone,
        om.primary_cuisine,
        om.price_band,
        om.public_rating,
        om.public_votes,

        om.total_orders,
        om.delivered_orders,
        om.cancelled_orders,
        om.unique_customers,
        om.gross_order_value,
        om.avg_order_value,

        COALESCE(rf.refund_orders, 0) AS refund_orders,
        COALESCE(rf.total_refund_amount, 0) AS total_refund_amount,
        COALESCE(rf.late_delivery_refunds, 0) AS late_delivery_refunds,
        COALESCE(rf.wrong_item_refunds, 0) AS wrong_item_refunds,
        COALESCE(rf.damaged_packaging_refunds, 0) AS damaged_packaging_refunds,
        COALESCE(rf.quality_issue_refunds, 0) AS quality_issue_refunds,

        COALESCE(rt.rated_orders, 0) AS rated_orders,
        COALESCE(rt.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rt.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rt.complaint_orders, 0) AS complaint_orders,

        COALESCE(dm.avg_delivery_time_min, 0) AS avg_delivery_time_min,
        COALESCE(dm.p90_delivery_time_min, 0) AS p90_delivery_time_min,
        COALESCE(dm.sla_breach_orders, 0) AS sla_breach_orders,
        COALESCE(dm.avg_prep_time_min, 0) AS avg_prep_time_min,
        COALESCE(dm.avg_rider_wait_time_min, 0) AS avg_rider_wait_time_min,
        COALESCE(dm.avg_drop_time_min, 0) AS avg_drop_time_min

    FROM order_metrics om
    LEFT JOIN refund_metrics rf
        ON om.restaurant_id = rf.restaurant_id
    LEFT JOIN rating_metrics rt
        ON om.restaurant_id = rt.restaurant_id
    LEFT JOIN delivery_metrics dm
        ON om.restaurant_id = dm.restaurant_id
),

restaurant_rates AS (
    SELECT
        *,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * refund_orders / delivered_orders, 2)
        END AS refund_rate_pct,

        CASE
            WHEN rated_orders = 0 THEN 0
            ELSE ROUND(100.0 * complaint_orders / rated_orders, 2)
        END AS complaint_rate_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * sla_breach_orders / delivered_orders, 2)
        END AS sla_breach_pct,

        CASE
            WHEN total_orders = 0 THEN 0
            ELSE ROUND(100.0 * cancelled_orders / total_orders, 2)
        END AS cancellation_rate_pct,

        CASE
            WHEN gross_order_value = 0 THEN 0
            ELSE ROUND(100.0 * total_refund_amount / gross_order_value, 2)
        END AS refund_value_rate_pct

    FROM restaurant_features
),

scored AS (
    SELECT
        *,

        ROUND(
            30 * LEAST(refund_rate_pct / 20.0, 1.0)
            + 25 * LEAST(complaint_rate_pct / 50.0, 1.0)
            + 20 * LEAST(sla_breach_pct / 50.0, 1.0)
            + 15 * LEAST(cancellation_rate_pct / 25.0, 1.0)
            + 10 * LEAST(refund_value_rate_pct / 20.0, 1.0),
            2
        ) AS anomaly_score

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

    gross_order_value,
    avg_order_value,

    refund_orders,
    refund_rate_pct,
    total_refund_amount,
    refund_value_rate_pct,

    late_delivery_refunds,
    wrong_item_refunds,
    damaged_packaging_refunds,
    quality_issue_refunds,

    rated_orders,
    complaint_orders,
    complaint_rate_pct,

    avg_food_rating,
    avg_delivery_rating,

    avg_delivery_time_min,
    p90_delivery_time_min,
    sla_breach_orders,
    sla_breach_pct,

    cancellation_rate_pct,

    avg_prep_time_min,
    avg_rider_wait_time_min,
    avg_drop_time_min,

    public_rating,
    public_votes,

    anomaly_score,

    CASE
        WHEN anomaly_score >= 60 THEN 'critical_anomaly'
        WHEN anomaly_score >= 40 THEN 'high_anomaly'
        WHEN anomaly_score >= 25 THEN 'medium_anomaly'
        ELSE 'low_anomaly'
    END AS anomaly_tier,

    CASE
        WHEN refund_rate_pct >= 15
             OR refund_value_rate_pct >= 15
            THEN 'refund_investigation'
        WHEN complaint_rate_pct >= 45
            THEN 'customer_experience_investigation'
        WHEN sla_breach_pct >= 40
            THEN 'delivery_sla_investigation'
        WHEN cancellation_rate_pct >= 20
            THEN 'cancellation_investigation'
        ELSE 'monitor'
    END AS recommended_action

FROM scored
WHERE delivered_orders >= 3
ORDER BY
    anomaly_score DESC,
    delivered_orders DESC;