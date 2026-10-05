# Chapter 28: Work in the Background

> **Status:** plan. Oban for SMS, email and push.

<!-- Section plan: each heading below gets written in full. -->

## Why a job queue

*Never make a request wait on an SMS gateway.*

## The SMS worker

*Queues, retries and attempts.*

## Email and reminders

*The mailer and billing reminders.*

## Push jobs

*Fanning a decision out to the right devices.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `../risiti/lib/risiti/sms_worker.ex`
- `../risiti/lib/risiti/mailer_worker.ex`
- `../risiti/lib/risiti/push_worker.ex`
- `../risiti/lib/risiti/billing/reminder_worker.ex`

## By the end

Sign-in codes and notifications go out through Oban.
