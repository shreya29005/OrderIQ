
# Data Sources

## Overview

This project uses a hybrid data strategy:

1. Public datasets for restaurant supply and delivery-time structure
2. Synthetic telemetry for internal marketplace behaviour that is not publicly available

The public datasets provide realistic restaurant and operational characteristics. Synthetic data is used to simulate product analytics tables such as sessions, search events, cart events, orders, refunds, ratings, and retention behaviour.

## Why Hybrid Data Is Used

Public food delivery datasets usually provide restaurant metadata, ratings, delivery-time fields, or customer preference surveys. They generally do not provide internal company telemetry such as:

- app sessions
- search result impressions
- restaurant clicks
- cart additions
- payment attempts
- refund linkage
- user retention
- order-level discounting
- SLA breach classification
- restaurant ranking exposure

Since these internal datasets are not public, this project simulates them using documented assumptions.

## Raw Public Datasets

Raw files should be placed in:

```text
data/raw/