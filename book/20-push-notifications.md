# Chapter 20: Push Notifications

> **Status:** plan. Telling people when something needs them.

<!-- Section plan: each heading below gets written in full. -->

## Who hears what

*Approvers on new claims, claimants on decisions and payments.*

## Registering a device

*FCM tokens with `mob_notify`, and remembering them.*

## Sending from the server

*`mob_push` from an Oban job.*

## Arriving on the phone

*Refreshing the list, and opening Approvals from a tapped notification.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `lib/risiti_app/push.ex`
- `../risiti/lib/risiti/push.ex`
- `../risiti/lib/risiti/expenses/push_notifier.ex`
- `docs/push-notifications.md`

## By the end

Approve on the web, and the claimant's phone buzzes.
