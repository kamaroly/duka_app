# Chapter 7: Reading a Receipt

> **Status:** plan. On-device OCR and a parser for messy receipt text.

<!-- Section plan: each heading below gets written in full. -->

## Why on the phone

*Offline, free and private, and what it costs in accuracy.*

## The `mob_ocr` plugin

*ML Kit text recognition behind an Elixir function.*

## What OCR gives back

*Real receipt text, with all its noise.*

## Finding the total

*Keywords, the biggest believable number, and the traps.*

## Finding the date and vendor

*Date formats used in Kenya, and the first line that isn't an address.*

## Testing a parser

*A folder of real receipts as test fixtures.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `plugins/mob_ocr/`
- `lib/risiti_app/receipts/ocr_parser.ex`
- `test/`

## By the end

A photo fills in vendor, date and total by itself.
