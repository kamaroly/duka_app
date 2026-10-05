# Chapter 17: The Whole Transaction

> **Status:** plan. Grows Part I's `transactions` table into the real one, migration by migration: types, statuses, claims, and the ids sync will need. Builds on Chapters 12 and 14.

<!-- Section plan: each heading below gets written in full. -->

## Where the data lives

*`RisitiApp.DataDir`: the app's private storage on the phone, a temp dir in tests.*

## The `Transaction` schema

*Type, status, method, categories and the changesets that guard them.*

## `client_id`

*An id the phone makes up, the key sync will hang everything on.*

## The `Transactions` context

*Listing, filtering and saving, with tests against a real SQLite file.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `lib/risiti_app/repo.ex`
- `lib/risiti_app/data_dir.ex`
- `priv/repo/migrations/`
- `lib/risiti_app/transactions/transaction.ex`
- `lib/risiti_app/transactions.ex`

## By the end

Transactions saved on the phone survive an app restart.
