/*
Analysis:
City-zone marketplace health score.

Business question:
Which geographic zones are healthy marketplaces, and which zones need intervention?

Grain:
city + zone

Marketplace health dimensions:
1. Demand strength
2. Supply depth
3. Funnel conversion
4. Delivery reliability
5. Customer experience
6. Commercial efficiency

Key metrics:
- total_sessions
- active_users
- delivered_orders
- session_to_delivery_conversion_pct
- total_restaurants
- active_restaurants
- avg_delivery_time_min
- p90_delivery_time_min
- sla_breach_pct
- cancellation_rate_pct
- refund_rate_pct
- complaint_rate_pct
- marketplace_health_score
- marketplace_health_tier
- recommended_action

Caveats:
1. This is an interpretable scorecard, not a production ML marketplace model.
2. Zone score combines demand, supply, ops, and customer-experience signals.
3. Scores are meant for prioritization and diagnosis, not automated decisions.
*/

WITH zone_base AS (
    SELECT DISTINCT
        city,
        zone
    FROM fact_sessions

    UNION

    SELECT DISTINCT
        city,
        zone
    FROM dim_restaurants
),

session_metrics AS (
    SELECT
        city,
        zone,

        COUNT(DISTINCT session_id) AS total_sessions,
        COUNT(DISTINCT user_id) AS active_users

    FROM fact_sessions
    GROUP BY
        city,
        zone
),

search_metrics AS (
    SELECT
        s.city,
        s.zone,

        COUNT(DISTINCT se.search_id) AS search_events,

        COUNT(DISTINCT CASE WHEN se.clicked_restaurant_id IS NOT NULL THEN se.search_id END)
            AS clicked_search_events,

        COUNT(DISTINCT CASE WHEN se.zero_result_flag = TRUE THEN se.search_id END)
            AS zero_result_searches,

        COUNT(DISTINCT CASE WHEN se.low_result_flag = TRUE THEN se.search_id END)
            AS low_result_searches

    FROM fact_search_events se
    INNER JOIN fact_sessions s
        ON se.session_id = s.session_id
    GROUP BY
        s.city,
        s.zone
),

cart_metrics AS (
    SELECT
        s.city,
        s.zone,

        COUNT(DISTINCT c.cart_id) AS cart_events

    FROM fact_cart_events c
    INNER JOIN fact_sessions s
        ON c.session_id = s.session_id
    GROUP BY
        s.city,
        s.zone
),

order_base AS (
    SELECT
        r.city,
        r.zone,

        o.order_id,
        o.user_id,
        o.restaurant_id,
        o.order_value,
        o.discount_amount,
        o.platform_fee,
        o.delivery_fee,
        o.order_status

    FROM fact_orders o
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
),

order_metrics AS (
    SELECT
        city,
        zone,

        COUNT(DISTINCT order_id) AS total_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END) AS delivered_orders,

        COUNT(DISTINCT CASE WHEN order_status = 'cancelled' THEN order_id END) AS cancelled_orders,

        COUNT(DISTINCT user_id) AS ordering_users,

        COUNT(DISTINCT restaurant_id) AS active_restaurants,

        ROUND(SUM(order_value), 2) AS gross_order_value,
        ROUND(SUM(discount_amount), 2) AS total_discount,
        ROUND(SUM(platform_fee), 2) AS platform_fee_total,
        ROUND(SUM(delivery_fee), 2) AS delivery_fee_total,

        ROUND(AVG(order_value), 2) AS avg_order_value

    FROM order_base
    GROUP BY
        city,
        zone
),

repeat_metrics AS (
    SELECT
        city,
        zone,

        COUNT(DISTINCT user_id) AS delivered_ordering_users,

        COUNT(DISTINCT CASE WHEN delivered_orders_by_user >= 2 THEN user_id END) AS repeat_users

    FROM (
        SELECT
            city,
            zone,
            user_id,
            COUNT(DISTINCT order_id) AS delivered_orders_by_user
        FROM order_base
        WHERE order_status = 'delivered'
        GROUP BY
            city,
            zone,
            user_id
    ) user_zone_orders
    GROUP BY
        city,
        zone
),

delivery_metrics AS (
    SELECT
        r.city,
        r.zone,

        ROUND(AVG(d.total_delivery_time_min), 2) AS avg_delivery_time_min,

        ROUND(QUANTILE_CONT(d.total_delivery_time_min, 0.90), 2) AS p90_delivery_time_min,

        SUM(
            CASE
                WHEN d.sla_breach_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS sla_breach_orders,

        ROUND(AVG(d.prep_time_min), 2) AS avg_prep_time_min,
        ROUND(AVG(d.rider_wait_time_min), 2) AS avg_rider_wait_time_min,
        ROUND(AVG(d.drop_time_min), 2) AS avg_drop_time_min,
        ROUND(AVG(d.distance_km), 2) AS avg_distance_km

    FROM fact_delivery_ops d
    INNER JOIN dim_restaurants r
        ON d.restaurant_id = r.restaurant_id
    GROUP BY
        r.city,
        r.zone
),

refund_metrics AS (
    SELECT
        r.city,
        r.zone,

        COUNT(DISTINCT rf.order_id) AS refund_orders,
        ROUND(SUM(rf.refund_amount), 2) AS total_refund_amount

    FROM fact_refunds rf
    INNER JOIN fact_orders o
        ON rf.order_id = o.order_id
    INNER JOIN dim_restaurants r
        ON o.restaurant_id = r.restaurant_id
    GROUP BY
        r.city,
        r.zone
),

rating_metrics AS (
    SELECT
        r.city,
        r.zone,

        COUNT(DISTINCT rt.order_id) AS rated_orders,

        ROUND(AVG(rt.food_rating), 2) AS avg_food_rating,
        ROUND(AVG(rt.delivery_rating), 2) AS avg_delivery_rating,

        SUM(
            CASE
                WHEN rt.complaint_flag = TRUE THEN 1
                ELSE 0
            END
        ) AS complaint_orders

    FROM fact_ratings rt
    INNER JOIN dim_restaurants r
        ON rt.restaurant_id = r.restaurant_id
    GROUP BY
        r.city,
        r.zone
),

supply_metrics AS (
    SELECT
        city,
        zone,

        COUNT(DISTINCT restaurant_id) AS total_restaurants,

        COUNT(DISTINCT primary_cuisine) AS cuisine_depth,

        ROUND(AVG(COALESCE(rating, 0)), 2) AS avg_public_rating,

        ROUND(AVG(COALESCE(restaurant_quality_prior, 0)), 3) AS avg_restaurant_quality_prior,

        ROUND(
            100.0 * SUM(CASE WHEN online_order_flag = TRUE THEN 1 ELSE 0 END)
            / COUNT(*),
            2
        ) AS online_enabled_restaurant_pct,

        ROUND(
            100.0 * SUM(CASE WHEN price_band = 'low' THEN 1 ELSE 0 END)
            / COUNT(*),
            2
        ) AS low_price_supply_pct,

        ROUND(
            100.0 * SUM(CASE WHEN price_band = 'mid' THEN 1 ELSE 0 END)
            / COUNT(*),
            2
        ) AS mid_price_supply_pct,

        ROUND(
            100.0 * SUM(CASE WHEN price_band = 'premium' THEN 1 ELSE 0 END)
            / COUNT(*),
            2
        ) AS premium_supply_pct

    FROM dim_restaurants
    GROUP BY
        city,
        zone
),

metrics AS (
    SELECT
        zb.city,
        zb.zone,

        COALESCE(sm.total_sessions, 0) AS total_sessions,
        COALESCE(sm.active_users, 0) AS active_users,

        COALESCE(search.search_events, 0) AS search_events,
        COALESCE(search.clicked_search_events, 0) AS clicked_search_events,
        COALESCE(search.zero_result_searches, 0) AS zero_result_searches,
        COALESCE(search.low_result_searches, 0) AS low_result_searches,

        COALESCE(cart.cart_events, 0) AS cart_events,

        COALESCE(om.total_orders, 0) AS total_orders,
        COALESCE(om.delivered_orders, 0) AS delivered_orders,
        COALESCE(om.cancelled_orders, 0) AS cancelled_orders,
        COALESCE(om.ordering_users, 0) AS ordering_users,
        COALESCE(om.active_restaurants, 0) AS active_restaurants,

        COALESCE(om.gross_order_value, 0) AS gross_order_value,
        COALESCE(om.total_discount, 0) AS total_discount,
        COALESCE(om.platform_fee_total, 0) AS platform_fee_total,
        COALESCE(om.delivery_fee_total, 0) AS delivery_fee_total,
        COALESCE(om.avg_order_value, 0) AS avg_order_value,

        COALESCE(rm.delivered_ordering_users, 0) AS delivered_ordering_users,
        COALESCE(rm.repeat_users, 0) AS repeat_users,

        COALESCE(dm.avg_delivery_time_min, 0) AS avg_delivery_time_min,
        COALESCE(dm.p90_delivery_time_min, 0) AS p90_delivery_time_min,
        COALESCE(dm.sla_breach_orders, 0) AS sla_breach_orders,
        COALESCE(dm.avg_prep_time_min, 0) AS avg_prep_time_min,
        COALESCE(dm.avg_rider_wait_time_min, 0) AS avg_rider_wait_time_min,
        COALESCE(dm.avg_drop_time_min, 0) AS avg_drop_time_min,
        COALESCE(dm.avg_distance_km, 0) AS avg_distance_km,

        COALESCE(refund.refund_orders, 0) AS refund_orders,
        COALESCE(refund.total_refund_amount, 0) AS total_refund_amount,

        COALESCE(rating.rated_orders, 0) AS rated_orders,
        COALESCE(rating.avg_food_rating, 0) AS avg_food_rating,
        COALESCE(rating.avg_delivery_rating, 0) AS avg_delivery_rating,
        COALESCE(rating.complaint_orders, 0) AS complaint_orders,

        COALESCE(supply.total_restaurants, 0) AS total_restaurants,
        COALESCE(supply.cuisine_depth, 0) AS cuisine_depth,
        COALESCE(supply.avg_public_rating, 0) AS avg_public_rating,
        COALESCE(supply.avg_restaurant_quality_prior, 0) AS avg_restaurant_quality_prior,
        COALESCE(supply.online_enabled_restaurant_pct, 0) AS online_enabled_restaurant_pct,
        COALESCE(supply.low_price_supply_pct, 0) AS low_price_supply_pct,
        COALESCE(supply.mid_price_supply_pct, 0) AS mid_price_supply_pct,
        COALESCE(supply.premium_supply_pct, 0) AS premium_supply_pct

    FROM zone_base zb
    LEFT JOIN session_metrics sm
        ON zb.city = sm.city
        AND zb.zone = sm.zone
    LEFT JOIN search_metrics search
        ON zb.city = search.city
        AND zb.zone = search.zone
    LEFT JOIN cart_metrics cart
        ON zb.city = cart.city
        AND zb.zone = cart.zone
    LEFT JOIN order_metrics om
        ON zb.city = om.city
        AND zb.zone = om.zone
    LEFT JOIN repeat_metrics rm
        ON zb.city = rm.city
        AND zb.zone = rm.zone
    LEFT JOIN delivery_metrics dm
        ON zb.city = dm.city
        AND zb.zone = dm.zone
    LEFT JOIN refund_metrics refund
        ON zb.city = refund.city
        AND zb.zone = refund.zone
    LEFT JOIN rating_metrics rating
        ON zb.city = rating.city
        AND zb.zone = rating.zone
    LEFT JOIN supply_metrics supply
        ON zb.city = supply.city
        AND zb.zone = supply.zone
),

rates AS (
    SELECT
        *,

        CASE
            WHEN total_sessions = 0 THEN 0
            ELSE ROUND(100.0 * search_events / total_sessions, 2)
        END AS search_rate_pct,

        CASE
            WHEN search_events = 0 THEN 0
            ELSE ROUND(100.0 * clicked_search_events / search_events, 2)
        END AS search_click_rate_pct,

        CASE
            WHEN search_events = 0 THEN 0
            ELSE ROUND(100.0 * zero_result_searches / search_events, 2)
        END AS zero_result_search_rate_pct,

        CASE
            WHEN search_events = 0 THEN 0
            ELSE ROUND(100.0 * low_result_searches / search_events, 2)
        END AS low_result_search_rate_pct,

        CASE
            WHEN total_sessions = 0 THEN 0
            ELSE ROUND(100.0 * cart_events / total_sessions, 2)
        END AS cart_rate_pct,

        CASE
            WHEN total_sessions = 0 THEN 0
            ELSE ROUND(100.0 * delivered_orders / total_sessions, 2)
        END AS session_to_delivery_conversion_pct,

        CASE
            WHEN total_orders = 0 THEN 0
            ELSE ROUND(100.0 * cancelled_orders / total_orders, 2)
        END AS cancellation_rate_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * sla_breach_orders / delivered_orders, 2)
        END AS sla_breach_pct,

        CASE
            WHEN delivered_orders = 0 THEN 0
            ELSE ROUND(100.0 * refund_orders / delivered_orders, 2)
        END AS refund_rate_pct,

        CASE
            WHEN rated_orders = 0 THEN 0
            ELSE ROUND(100.0 * complaint_orders / rated_orders, 2)
        END AS complaint_rate_pct,

        CASE
            WHEN delivered_ordering_users = 0 THEN 0
            ELSE ROUND(100.0 * repeat_users / delivered_ordering_users, 2)
        END AS repeat_user_rate_pct,

        CASE
            WHEN gross_order_value = 0 THEN 0
            ELSE ROUND(100.0 * total_discount / gross_order_value, 2)
        END AS discount_burn_pct,

        ROUND(platform_fee_total + delivery_fee_total - total_discount - total_refund_amount, 2)
            AS contribution_proxy

    FROM metrics
),

scored AS (
    SELECT
        *,

        ROUND(
            10 * LEAST(session_to_delivery_conversion_pct / 10.0, 1.0)
            + 8 * LEAST(delivered_orders / 300.0, 1.0)
            + 7 * LEAST(active_users / 2500.0, 1.0),
            2
        ) AS demand_score,

        ROUND(
            8 * LEAST(total_restaurants / 300.0, 1.0)
            + 6 * LEAST(cuisine_depth / 20.0, 1.0)
            + 6 * LEAST(online_enabled_restaurant_pct / 100.0, 1.0),
            2
        ) AS supply_score,

        ROUND(
            10 * (1 - LEAST(sla_breach_pct / 40.0, 1.0))
            + 8 * (1 - LEAST(cancellation_rate_pct / 15.0, 1.0))
            + 7 * (1 - LEAST(GREATEST(p90_delivery_time_min - 40, 0) / 30.0, 1.0)),
            2
        ) AS operations_score,

        ROUND(
            7 * LEAST(avg_food_rating / 5.0, 1.0)
            + 6 * LEAST(avg_delivery_rating / 5.0, 1.0)
            + 6 * (1 - LEAST(refund_rate_pct / 10.0, 1.0))
            + 6 * (1 - LEAST(complaint_rate_pct / 50.0, 1.0)),
            2
        ) AS customer_experience_score,

        ROUND(
            5 * (1 - LEAST(discount_burn_pct / 20.0, 1.0))
            + 5 * CASE WHEN contribution_proxy > 0 THEN 1 ELSE 0 END,
            2
        ) AS commercial_score

    FROM rates
),

final AS (
    SELECT
        *,

        ROUND(
            demand_score
            + supply_score
            + operations_score
            + customer_experience_score
            + commercial_score,
            2
        ) AS marketplace_health_score

    FROM scored
)

SELECT
    city,
    zone,

    total_sessions,
    active_users,
    search_events,
    clicked_search_events,
    cart_events,

    total_orders,
    delivered_orders,
    cancelled_orders,
    ordering_users,
    delivered_ordering_users,
    repeat_users,

    total_restaurants,
    active_restaurants,
    cuisine_depth,

    gross_order_value,
    total_discount,
    discount_burn_pct,
    contribution_proxy,

    avg_order_value,

    search_rate_pct,
    search_click_rate_pct,
    zero_result_search_rate_pct,
    low_result_search_rate_pct,
    cart_rate_pct,
    session_to_delivery_conversion_pct,

    repeat_user_rate_pct,

    avg_delivery_time_min,
    p90_delivery_time_min,
    sla_breach_pct,
    cancellation_rate_pct,

    refund_orders,
    refund_rate_pct,
    rated_orders,
    avg_food_rating,
    avg_delivery_rating,
    complaint_orders,
    complaint_rate_pct,

    avg_prep_time_min,
    avg_rider_wait_time_min,
    avg_drop_time_min,
    avg_distance_km,

    avg_public_rating,
    avg_restaurant_quality_prior,
    online_enabled_restaurant_pct,
    low_price_supply_pct,
    mid_price_supply_pct,
    premium_supply_pct,

    demand_score,
    supply_score,
    operations_score,
    customer_experience_score,
    commercial_score,
    marketplace_health_score,

    CASE
        WHEN marketplace_health_score >= 75 THEN 'strong_market'
        WHEN marketplace_health_score >= 60 THEN 'balanced_market'
        WHEN marketplace_health_score >= 45 THEN 'needs_attention'
        ELSE 'at_risk_market'
    END AS marketplace_health_tier,

    CASE
        WHEN sla_breach_pct >= 25
             OR p90_delivery_time_min >= 55
            THEN 'fix_delivery_reliability'
        WHEN low_result_search_rate_pct >= 35
             OR total_restaurants < 50
            THEN 'improve_supply_depth_and_discovery'
        WHEN session_to_delivery_conversion_pct < 5
            THEN 'fix_funnel_conversion'
        WHEN refund_rate_pct >= 8
             OR complaint_rate_pct >= 35
            THEN 'repair_customer_experience'
        WHEN discount_burn_pct >= 15
             AND contribution_proxy < 0
            THEN 'improve_discount_efficiency'
        ELSE 'scale_growth'
    END AS recommended_action

FROM final
WHERE total_sessions >= 100
   OR delivered_orders >= 10
ORDER BY
    marketplace_health_score ASC,
    delivered_orders DESC;