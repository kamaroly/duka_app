# Chapter 19: Two-Way Sync

> **Status:** plan. Keeping the phone and the server in step, over a bad connection.

<!-- Section plan: each heading below gets written in full. -->

## One run, four steps

*Delete, push, pull, refresh.*

## Idempotency

*Everything keyed by `client_id`, so a cut-short run is just repeated.*

## Never losing an edit

*Marking a transaction sent only if it wasn't edited mid-upload.*

## Photos and attachments

*Uploaded once, downloaded when first opened.*

## Deletions

*Tombstones, and the server keeping anything already decided.*

## One run at a time

*A registered process name as the lock.*

## When to sync

*On open, after sending, on resume, back online, on push.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `lib/risiti_app/sync.ex`
- `lib/risiti_app/sync/deletion.ex`
- `docs/server-and-sync.md`

## By the end

Two phones and the web see the same transactions.
