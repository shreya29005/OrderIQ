
# Data Assumptions

## Purpose

This document explains the assumptions used to generate synthetic marketplace telemetry for the OrderIQ project.

The project uses public datasets for restaurant and delivery structure. However, internal product analytics data such as sessions, search events, cart events, refunds, discounts, and retention is not publicly available. These layers are simulated using documented business assumptions.

## Core Principle

Synthetic data should not be random noise. It should reflect realistic marketplace relationships so that SQL analyses and dashboards produce meaningful business diagnostic outputs.

## What Is Public vs Synthetic

| Data Area | Source Type |
|---|---|
| Restaurant names, zones, cuisines, cost, ratings | Public dataset |
| Delivery distance/time distributions | Public dataset |
| User profiles | Synthetic |
| App sessions | Synthetic |
| Search events | Synthetic |
| Cart events | Synthetic |
| Orders | Synthetic |
| Refunds | Synthetic |
| Ratings linked to orders | Synthetic |
| Retention behaviour | Synthetic |
| Forecasting metrics | Derived from synthetic orders |

## User Assumptions

### User Segments

Users are assigned to broad behavioural segments:

| Segment | Behaviour |
|---|---|
| Value-seeking | More discount sensitive, lower AOV |
| Convenience-focused | More sensitive to ETA and reliability |
| Premium | Higher AOV, lower discount sensitivity |
| Regular | Higher repeat probability |
| Occasional | Lower order frequency |

### Income Proxy

Income proxy is simulated as:

```text
low
mid
premium