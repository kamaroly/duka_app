# Chapter 34: Deploying the Server

> **Status:** plan. Putting Risiti on a server people depend on.

<!-- Section plan: each heading below gets written in full. -->

## The machine

*Ubuntu, system packages, Postgres.*

## Building elsewhere

*GitHub Actions builds the release; the server only runs it.*

## Zero-downtime restarts

*Three ports, one at a time, behind nginx.*

## Migrations and tenants

*Running them on deploy.*

## Secrets and config

*Environment variables, Google and SMS credentials.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `../risiti/docs/installation.md`
- `../risiti/lib/risiti/release.ex`

## By the end

The server live at your own domain.
