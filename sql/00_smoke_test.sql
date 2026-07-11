/*
Analysis:
Smoke test for OrderIQ processed data.

Business question:
Can all processed marketplace tables be queried correctly through DuckDB?

Grain:
One row per source table.

Purpose:
This query validates that the SQL execution layer can access every processed table.
*/

SELECT
    'dim_users' AS table_name,
    COUNT(*) AS row_count
FROM dim_users

UNION ALL

SELECT
    'dim_restaurants' AS table_name,
    COUNT(*) AS row_count
FROM dim_restaurants

UNION ALL

SELECT
    'fact_sessions' AS table_name,
    COUNT(*) AS row_count
FROM fact_sessions

UNION ALL

SELECT
    'fact_search_events' AS table_name,
    COUNT(*) AS row_count
FROM fact_search_events

UNION ALL

SELECT
    'fact_cart_events' AS table_name,
    COUNT(*) AS row_count
FROM fact_cart_events

UNION ALL

SELECT
    'fact_orders' AS table_name,
    COUNT(*) AS row_count
FROM fact_orders

UNION ALL

SELECT
    'fact_delivery_ops' AS table_name,
    COUNT(*) AS row_count
FROM fact_delivery_ops

UNION ALL

SELECT
    'fact_refunds' AS table_name,
    COUNT(*) AS row_count
FROM fact_refunds

UNION ALL

SELECT
    'fact_ratings' AS table_name,
    COUNT(*) AS row_count
FROM fact_ratings

UNION ALL

SELECT
    'daily_marketplace_metrics' AS table_name,
    COUNT(*) AS row_count
FROM daily_marketplace_metrics;