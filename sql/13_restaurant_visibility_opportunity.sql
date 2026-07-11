/*
Analysis:
Restaurant visibility opportunity.

Business question:
Which restaurants are under-exposed despite strong quality signals, and which visible restaurants create customer-experience risk?

Grain:
restaurant_id

Key metrics:
- search_clicks
- cart_events
- delivered_orders
- gross_order_value
- restaurant_quality_score
- visibility_score
- opportunity_score
- visibility_opportunity_tier
- recommended_action

Caveats:
1. Search visibility is proxied by clicked searches because raw impression-level restaurant ranking data is not available.
2. This is a prioritization scorecard, not a production ranking algorithm.
3. Restaurants with at least 2 delivered orders are included to preserve enough signal in this synthetic dataset.
*/

WITH restaurant_base AS (
    SELECT
        restaurant_id,
        restaurant_name,
        city,
        zone,
        COALESCE(primary_cuisine, 'unknown') AS primary_cuisine,
        COALESCE(price_band, 'unknown') AS price_band,
        COALESCE(rating, 0) AS public_rating,
        COALESCE(votes, 0) AS public_votes,
        COALESCE(restaurant_quality_prior, 0) AS restaurant_quality_prior,
        COALESCE(online_order_flag, FALSE) AS online_order_flag,
        COALESCE(menu_depth, 0) AS menu_depth
    FROM dim_restaurants
),

search_click_metrics AS (
    SELECT
        clicked_restaurant_id AS restaurant_id,
        COUNT(DISTINCT search_id) AS search_clicks,
        COUNT(DISTINCT user_id) AS search_click_users,
        ROUND(AVG(estimated_eta_min), 2) AS avg_search_eta_min
    FROM fact_search_events
    WHERE clicked_restaurant_id IS NOT NULL
    GROUP BY
        clicked_restaurant_id
),

cart_metrics AS (
    SELECT
        restaurant_id,
        COUNT(DISTINCT cart_id) AS cart_events,
        COUNT(DISTINCT user_id) AS cart_users,
        ROUND(SUM(cart_value), 2) AS cart_value
    FROM fact_cart_events
    GROUP BY
        restaurant_id
),

order_metrics AS (
    SELECT
        restaurant_id,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders,

        COUNT(DISTINCT user_id) AS ordering_users,

        ROUND(SUM(order_value), 2) AS gross_order_value,
        ROUND(SUM(discount_amount), 2) AS total_discount,
        ROUND(AVG(order_value), 2) AS avg_order_value

    FROM fact_orders
    GROUP BY
        restaurant_id
),

repeat_metrics AS (
    SELECT
        restaurant_id,

        COUNT(DISTINCT user_id) AS delivered_ordering_users,

        COUNT(DISTINCT CASE WHEN delivered_orders_by_user >= 2 THEN user_id END) AS repeat_users

    FROM (
        SELECT
            restaurant_id,
            user_id,
            COUNT(DISTINCT order_id) AS delivered_orders_by_user
        FROM fact_orders
        WHERE order_status = 'delivered'
        GROUP BY
            restaurant_id,
            user_id
    ) user_restaurant_orders
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
        ) AS sla_breach_orders

    FROM fact_delivery_ops
    GROUP BY
        restaurant_id
),

refund_metrics AS (
    SELECT
        o.restaurant_id,

        COUNT(DISTINCT rf.order_id) AS refund_orders,

        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount

    FROM fact_refunds rf
    INNER JOIN fact_orders o
        ON rf.order_id = o.order_id
    GROUP BY
        o.restaurant_id
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
    GROUP BY
        restaurant_id
),

features AS (
    SELECT
        rb.restaurant_id,
        rb.restaurant_name,
        rb.city,
        rb.zone,
        rb.primary_cuisine,
        rb.price_band,
        rb.public_rating,
        rb.public_votes,
        rb.restaurant_quality_prior,
        rb.online_order_flag,
        rb.menu_depth,

        COALESCE(sc.search_clicks, 0) AS search_clicks,
        COALESCE(sc.search_click_users, 0) AS search_click_users,
        COALESCE(sc.avg_search_eta_min, 0) AS avg_search_eta_min,

        COALESCE(cm.cart_events, 0) AS cart_events,
        COALESCE(cm.cart_users, 0) AS cart_users,
        COALESCE(cm.cart_value, 0) AS cart_value,

        COALESCE(om.total_orders, 0) AS total_orders,
        COALESCE(om.delivered_orders, 0) AS delivered_orders,
        COALESCE(om.cancelled_orders, 0) AS cancelled_orders,
        COALESCE(om.ordering_users, 0) AS ordering_users,
        COALESCE(om.gross_order_value, 0) AS gross_order_value,
        COALESCE(om.total_discount, 0) AS total_discount,
        COALESCE(om.avg_order_value, 0) AS avg_order_value,

        COALESCE(rm.delivered_ordering_users, 0) AS delivered_ordering_users,
        COALESCE(rm.repeat_users, 0) AS repeat_users,

        COALESCE(dm.avg_delivery_time_min, 0) AS avg_delivery_time_min,
        COALESCE(dm.p90_delivery_time_min, 0) AS p90_delivery_time_min,
        COALESCE(dm.sla_breach_orders, 0) AS sla_breach_orders,

        COALESCE(ref.refund_orders, 0) AS refund_orders,
        COALESCE(ref.total_refund_amount, 0) AS total_refund_amount,

        COALESCE(rt.rating_count, 0) AS rating_count,
        COALESCE(rt.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rt.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rt.complaint_orders, 0) AS complaint_orders

    FROM restaurant_base rb
    LEFT JOIN search_click_metrics sc
        ON rb.restaurant_id = sc.restaurant_id
    LEFT JOIN cart_metrics cm
        ON rb.restaurant_id = cm.restaurant_id
    LEFT JOIN order_metrics om
        ON rb.restaurant_id = om.restaurant_id
    LEFT JOIN repeat_metrics rm
        ON rb.restaurant_id = rm.restaurant_id
    LEFT JOIN delivery_metrics dm
        ON rb.restaurant_id = dm.restaurant_id
    LEFT JOIN refund_metrics ref
        ON rb.restaurant_id = ref.restaurant_id
    LEFT JOIN rating_metrics rt
        ON rb.restaurant_id = rt.restaurant_id
),

rates AS (
    SELECT
        *,

        CASE
            WHEN search_clicks = 0 THEN 0
            ELSE ROUND(100.0 * cart_events / search_clicks, 2)
        END AS click_to_cart_rate_pct,

        CASE
            WHEN cart_events = 0 THEN 0
            ELSE ROUND(100.0 * total_orders / cart_events, 2)
        END AS cart_to_order_rate_pct,

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
            ELSE ROUND(100.0 * repeat_users / delivered_ordering_users, 2)
        END AS repeat_user_rate_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * sla_breach_orders / delivered_orders, 2)
        END AS sla_breach_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * refund_orders / delivered_orders, 2)
        END AS refund_rate_pct,

        CASE
            WHEN rating_count = 0 THEN 0
            ELSE ROUND(100.0 * complaint_orders / rating_count, 2)
        END AS complaint_rate_pct,

        CASE
            WHEN gross_order_value = 0 THEN 0
            ELSE ROUND(100.0 * total_discount / gross_order_value, 2)
        END AS discount_burn_pct

    FROM features
),

scored AS (
    SELECT
        *,

        ROUND(
            20 * LEAST(COALESCE(avg_food_rating, public_rating, 0) / 5.0, 1.0)
            + 15 * LEAST(COALESCE(avg_delivery_rating, 0) / 5.0, 1.0)
            + 15 * LEAST(restaurant_quality_prior, 1.0)
            + 10 * LEAST(repeat_user_rate_pct / 30.0, 1.0)
            + 10 * (1 - LEAST(refund_rate_pct / 15.0, 1.0))
            + 10 * (1 - LEAST(complaint_rate_pct / 50.0, 1.0))
            + 10 * (1 - LEAST(sla_breach_pct / 40.0, 1.0))
            + 10 * (1 - LEAST(cancellation_rate_pct / 20.0, 1.0)),
            2
        ) AS restaurant_quality_score,

        ROUND(
            30 * LEAST(search_clicks / 25.0, 1.0)
            + 25 * LEAST(cart_events / 12.0, 1.0)
            + 25 * LEAST(delivered_orders / 10.0, 1.0)
            + 10 * LEAST(search_click_users / 20.0, 1.0)
            + 10 * LEAST(gross_order_value / 3000.0, 1.0),
            2
        ) AS visibility_score

    FROM rates
),

opportunity AS (
    SELECT
        *,

        ROUND(
            restaurant_quality_score * (1 - LEAST(visibility_score / 100.0, 1.0)),
            2
        ) AS underexposure_opportunity_score,

        ROUND(
            visibility_score * (1 - LEAST(restaurant_quality_score / 100.0, 1.0)),
            2
        ) AS overexposure_risk_score

    FROM scored
)

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
    online_order_flag,
    menu_depth,

    search_clicks,
    search_click_users,
    avg_search_eta_min,

    cart_events,
    cart_users,
    cart_value,

    total_orders,
    delivered_orders,
    cancelled_orders,
    ordering_users,

    gross_order_value,
    avg_order_value,
    total_discount,
    discount_burn_pct,

    click_to_cart_rate_pct,
    cart_to_order_rate_pct,
    delivery_success_rate_pct,
    cancellation_rate_pct,
    repeat_user_rate_pct,

    avg_delivery_time_min,
    p90_delivery_time_min,
    sla_breach_pct,

    refund_orders,
    refund_rate_pct,

    rating_count,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,
    complaint_rate_pct,

    restaurant_quality_score,
    visibility_score,
    underexposure_opportunity_score,
    overexposure_risk_score,

    CASE
        WHEN restaurant_quality_score >= 70
             AND visibility_score < 45
            THEN 'high_quality_underexposed'
        WHEN restaurant_quality_score >= 60
             AND visibility_score < 60
            THEN 'moderate_visibility_opportunity'
        WHEN restaurant_quality_score < 50
             AND visibility_score >= 60
            THEN 'overexposed_quality_risk'
        WHEN restaurant_quality_score >= 70
             AND visibility_score >= 70
            THEN 'visible_quality_winner'
        ELSE 'monitor'
    END AS visibility_opportunity_tier,

    CASE
        WHEN restaurant_quality_score >= 70
             AND visibility_score < 45
            THEN 'increase_ranking_or_promo_visibility'
        WHEN restaurant_quality_score >= 60
             AND visibility_score < 60
            THEN 'test_visibility_lift'
        WHEN restaurant_quality_score < 50
             AND visibility_score >= 60
            THEN 'reduce_exposure_until_quality_improves'
        WHEN restaurant_quality_score >= 70
             AND visibility_score >= 70
            THEN 'protect_and_scale_winner'
        ELSE 'monitor'
    END AS recommended_action

FROM opportunity
WHERE delivered_orders >= 2
ORDER BY
    underexposure_opportunity_score DESC,
    overexposure_risk_score DESC,
    delivered_orders DESC;