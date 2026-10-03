# Chapter 4: A Database on the Phone

> **Status:** plan. Ecto and SQLite on the device, and the schema everything else stands on.

<!-- Section plan: each heading below gets written in full. -->

## Where the data lives

*`RisitiApp.DataDir`: the app's private storage on the phone, a temp dir in tests.*

## The repo and migrations on the device

*Starting `RisitiApp.Repo` with ecto_sqlite3 and migrating at boot.*

## The `Transaction` schema

*Type, status, method, categories and the changesets that guard them.*

## Money in cents

*Integer cents in the database, shillings on screen.*

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
