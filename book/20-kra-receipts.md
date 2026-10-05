# Chapter 20: KRA Receipts

> **Status:** plan. Scanning eTIMS and TIMS QR codes and trusting KRA's record.

<!-- Section plan: each heading below gets written in full. -->

## What's in a KRA QR code

*eTIMS and TIMS URLs, and the details they point to.*

## Scanning

*`mob_scanner`, and opening a saved transaction instead of making a duplicate.*

## Fetching KRA's record

*Reading the receipt from KRA's page: vendor, date, total, items.*

## Verifying in the background

*Checking saved receipts with KRA without blocking the screen, and not retrying forever.*

## KRA wins

*A photo never overwrites what KRA said; the photo taken after a scan.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `lib/risiti_app/receipts/qr_parser.ex`
- `lib/risiti_app/receipts/kra_receipt.ex`
- `lib/risiti_app/screens/receipts_screen.ex`

## By the end

A scanned KRA receipt arrives filled in and tagged.
