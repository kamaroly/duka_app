# Chapter 1: What We're Building

> **Status:** plan. The product, the architecture, and the one rule behind the design.

<!-- Section plan: each heading below gets written in full. -->

## A tour of Risiti

*Scan a receipt, scan a KRA QR code, claim a refund, request a payment, approve, mark paid, export.*

## Three types, one transaction

*Expense, refund, payment request, and the statuses each one moves through.*

## The rule: the phone owns the figures, the server owns the decisions

*Why this rule makes offline-first simple, and what goes wrong without it.*

## Why Elixir on the phone

*One language from the phone to the server; the BEAM's processes on a device that sleeps and loses signal.*

## The stack

*Mob, Ecto + SQLite on the phone. Phoenix 1.8, Ash 3, Postgres and Oban on the server.*

## The map of the code

*The two repos and how their folders line up.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `README.md`
- `docs/transactions.md`
- `../risiti/README.md`

## By the end

The reader can draw the system on a napkin.
