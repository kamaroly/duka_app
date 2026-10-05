# Chapter 26: Transactions and Approvals

> **Status:** plan. The server's transaction resource, its actions and its policies.

<!-- Section plan: each heading below gets written in full. -->

## The resource

*Attributes, relationships and types that match the phone.*

## Actions

*Create, update, request refund, approve, reject, mark paid.*

## Policies

*Who can see and decide what, written once.*

## An audit trail

*AshPaperTrail recording every change.*

## Moving old data

*Merging receipts and refund requests into transactions without losing ids.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `../risiti/lib/risiti/expenses/transaction.ex`
- `../risiti/lib/risiti/expenses/transaction/`
- `../risiti/docs/transactions.md`

## By the end

Approvals work on the server, guarded by policies.
