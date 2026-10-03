# Chapter 6: Taking the Photo

> **Status:** plan. The camera, photos on disk, and the receipt form.

<!-- Section plan: each heading below gets written in full. -->

## Asking for the camera

*Permissions, and what to do when the user says no.*

## Taking and keeping the photo

*`mob_camera`, shrinking the image, and `Receipts.Photos`.*

## The receipt form

*Vendor, date, amount, category, description.*

## Filling only what the user hasn't touched

*Tracking touched fields so a slow reading never overwrites typing.*

## Retake, remove, add later

*The photo's whole life on a transaction.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `lib/risiti_app/screens/receipt_form_screen.ex`
- `lib/risiti_app/receipts/photos.ex`
- `lib/risiti_app/native.ex`

## By the end

Scan receipt opens the camera and saves an expense with its photo.
