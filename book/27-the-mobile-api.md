# Chapter 27: The Mobile API

> **Status:** plan. A JSON contract the phone can rely on.

<!-- Section plan: each heading below gets written in full. -->

## The shape of the API

*JSON, integer cents, ISO dates, Bearer tokens.*

## Errors the phone can act on

*401, 403, 404, 422, 429, 502, and what each means on the phone.*

## Transactions

*Idempotent upserts by `client_id`, multipart uploads with photos and attachments.*

## Approvals and `/api/me`

*Decisions, and telling the phone what it may do.*

## The phone's client

*`RisitiApp.Api` and `RisitiApp.Http`, turning every answer into a small set of results.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `../risiti/lib/risiti_web/controllers/api/`
- `../risiti/docs/mobile-api.md`
- `lib/risiti_app/api.ex`
- `lib/risiti_app/http.ex`

## By the end

The whole API exercised with `curl`, and from IEx on the phone.
