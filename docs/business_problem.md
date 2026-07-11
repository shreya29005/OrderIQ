# Business Problem

## Project Title

**OrderIQ: Food Delivery Marketplace Product & Business Analytics System**

## Context

Food delivery marketplaces operate as multi-sided platforms involving customers, restaurants, delivery partners, pricing incentives, search/discovery systems, and operational reliability. Growth problems in such marketplaces rarely come from a single cause.

A zone may have strong demand but poor conversion because users cannot find relevant restaurants. Another zone may have good conversion but high cancellations because delivery times are unreliable. Some restaurants may generate high order volume but damage customer trust through refunds, complaints, or poor ratings. Discounts may increase conversion in some user segments but create inefficient growth if they do not improve repeat behaviour.

This project builds an analytics system to diagnose these marketplace problems using public restaurant and delivery datasets, combined with simulated internal product telemetry.

## Core Business Problem

The marketplace is seeing uneven performance across city zones. Some zones show high user activity but weak delivered-order growth. The goal is to identify whether the issue is caused by:

1. Poor funnel conversion
2. Weak search and restaurant discovery
3. High delivery time or SLA breaches
4. Restaurant quality and refund issues
5. Inefficient discounting
6. Weak user retention
7. Zone-level marketplace imbalance

The project converts these issues into measurable analytics questions and recommends targeted product or business interventions.

## Primary Objective

Build a product and business analytics system that can answer:

> Where is marketplace performance breaking down, why is it happening, and what intervention should be prioritized?

## Core Questions

1. Where is the order funnel leaking?
2. Which city zones have weak conversion despite strong traffic?
3. Which zones have delivery reliability issues?
4. Are delays caused by restaurant prep, rider wait, or drop distance?
5. Which restaurants improve or damage customer trust?
6. Are discounts improving conversion efficiently?
7. Which user cohorts and cuisines drive repeat behaviour?
8. Does a bad first-order experience reduce future retention?
9. Which restaurants are hidden growth opportunities?
10. What short-term demand should the marketplace expect?

## Marketplace Funnel

The project models the food-ordering funnel as:

```text
App Open → Search → Restaurant Click → Cart → Payment → Delivered Order