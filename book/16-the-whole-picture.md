# Chapter 16: The Whole Picture

> **Part II: Reading receipts.** Part I built Risiti's phone half. This
> part finishes it: the phone learns to read receipts, check them with the
> Kenya Revenue Authority, and turn expenses into claims for money back.

Previously, we finished Part I with an expense tracker that lives entirely
on the phone. It works with no signal, photographs receipts and locks behind
a fingerprint. But it's a tracker for one person. Risiti's real job is
bigger: a team spends money, a manager approves it, someone pays people
back, and an accountant needs it all in the books at the end of the month.

That needs a server, and a phone and a server that agree. Before we build
any more, let's step back and look at the whole system: what it's made of,
how the parts talk, and the one rule that keeps them from fighting.

By the end of this chapter, you will know:

- The three kinds of transaction Risiti handles, and how each moves from
  "pending" to "done".
- The rule that makes offline-first simple: who owns which data.
- The stack, on the phone and on the server, and why each piece is there.
- How the phone's code and the server's code line up.

You should be able to draw the whole system on a napkin by the end.

## Three types, one transaction

Everything money-related that someone records in Risiti is a
**transaction**. There are three types:

| Type | What it is | Approved? | Paid out? |
|---|---|---|---|
| **Expense** | Money already spent, kept for the books. | Yes | No |
| **Refund** | An expense the person paid themselves and wants back. | Yes | Yes, by M-Pesa |
| **Payment request** | Money the person asks the team to pay. | Yes | Yes |

They look different to the user, but they share almost every field: a date,
a vendor, an amount, a category, often a receipt photo. That's why Part I
called its table `transactions`, not `receipts`, and gave each row a `type`.
In Chapter 17 the other two types move in.

A refund and a payment request are *claims*: they ask for money. So they
carry two more things an expense doesn't:

- **Who is paid** (`pay_to`): `self`, the person who sent it, or a
  `supplier`. A refund always pays its sender. A payment request to `self`
  is an advance; to a `supplier`, the team pays the vendor directly.
- **How to pay** (`method`): cash, M-Pesa send money to a phone, an M-Pesa
  Buy Goods till, an M-Pesa paybill and account number, a card, a bank
  transfer. Each method needs its own details. A till needs a till number; a
  paybill needs a paybill number *and* an account number.

### Status

Every transaction moves through the same small set of states:

```
pending ──approve──▶ approved ──pay──▶ paid      (refunds, payment requests)
   └─────reject────▶ rejected
```

- Everything starts **pending**.
- An approver **approves** or **rejects** it, optionally with a note. A
  rejection should say what to fix.
- An expense stops at **approved**: the money was already spent.
- A refund or payment request goes on to **paid**, once someone has sent the
  money and marked it so.
- Changing the figures of a decided transaction sends it back to
  **pending**, so nobody can get one approved and then change the amount.
- A paid transaction can't be changed at all.

There's one more case. Some people use Risiti alone, to track their own
spending. Their book is **personal**: nobody else approves it, so there are
no refunds or payment requests, and everything they record is approved as
it's saved. Business books get the whole flow.

## The rule: the phone owns the figures, the server owns the decisions

Here's the problem every offline-first app has to solve. Two copies of the
same data, one on the phone and one on the server, can both change while
they can't talk to each other. When they reconnect, which one wins?

Most apps answer with timestamps ("last write wins") or merge logic, and
both get subtle fast. Risiti avoids the question by splitting the data in
two, and giving each half one owner:

| Data | Owner | Examples |
|---|---|---|
| **The figures** | The phone | Date, vendor, amount, category, description, photo, how to pay |
| **The decisions** | The server | Status, the approver's note, when it was decided, when it was paid |

The person who spent the money types the figures, on their phone, often
with no connection. The phone is the only place those change, so the phone's
version is always right. The approver decides on the server, through the web
dashboard or the Approvals screen, and that needs a connection anyway. The
server's version of the decision is always right.

So sync never has to *merge* anything. It has two simple directions:

1. **Phone to server:** "here are the figures for transaction X". The server
   stores them.
2. **Server to phone:** "here's the decision on transaction X". The phone
   stores it.

The one place the halves touch is the rule we saw in the status diagram:
when the figures of a decided transaction change, the server sends it back
to pending. The phone doesn't decide that; it just sends the new figures,
and the server applies its own rule.

### What goes wrong without it

Imagine the server could also edit the amount, say an accountant correcting
a typo on the web. Now the phone and the server can both change the same
field. The person corrects it on their phone at the same moment, offline.
When the phone reconnects, one correction silently overwrites the other.
Somebody gets paid the wrong amount, and nobody knows why.

With one owner per field, that can't happen. The cost is a little
inconvenience: if the accountant spots a typo, they reject the transaction
with a note, and the person fixes it on their phone. That's a process the
team already understands, and it leaves a record.

### Ids the phone can make up

There's one more piece that makes this work offline. When the phone creates
a transaction, the server doesn't know about it yet, so there's no server
id. The phone makes up its own: a random UUID, the `client_id`, generated with
`Ecto.UUID.generate/0` when the transaction is first saved, and never
changed.

Every sync is keyed by that id. "Here are the figures for `client_id`
X" either creates X on the server or updates it. So a sync that's cut short
by a dropped connection can simply run again: the transactions it already
sent are updated with the same figures, not duplicated. On a phone that
moves between good signal and none all day, that's what makes sync
trustworthy. We'll add `client_id` in the next chapter, and build sync
itself in Part IV.

## The stack

Here's everything, phone and server, on one page:

```
┌──────────────── Phone (Android) ────────────────┐        ┌────────────────── Server ──────────────────┐
│                                                 │        │                                            │
│  Mob screens (Elixir)                           │        │  Phoenix 1.8                               │
│   ReceiptsScreen, ReceiptFormScreen, ...        │        │   /api/...   JSON for the phone            │
│                                                 │  HTTPS │   LiveView   web dashboard, approvals      │
│  RisitiApp.Transactions ── Ecto ── SQLite       │◄──────►│                                            │
│  RisitiApp.Sync                                 │  JSON  │  Ash 3 resources                           │
│  RisitiApp.Native ── plugins:                   │        │   Expenses.Transaction, Accounts.User, ... │
│     camera, QR scanner, OCR, fingerprint,       │        │   AshPostgres: one schema per team         │
│     Google sign-in, push                        │        │                                            │
│                                                 │        │  Oban: SMS codes, email, push, receipts    │
└─────────────────────────────────────────────────┘        │  Postgres                                  │
                                                           └──────────────┬─────────────────────────────┘
                                                                          │ push (Firebase)
                                                                          ▼
                                                                    back to the phone
```

### On the phone

You know these from Part I:

- **Mob**, with screens as processes and native UI drawn from Elixir.
- **Ecto and SQLite**, with the phone's database as the source of truth for
  the figures.
- **Plugins** for the hardware: `mob_camera`, `mob_biometric`, and in this
  part `mob_scanner` for QR codes and a receipt reader of Risiti's own.
- **`RisitiApp.Native`**, the one module that every device call goes
  through, which keeps the screens testable.

New in the coming parts:

- **`RisitiApp.Sync`**, a process that runs one sync at a time in the
  background and reports back to the screen that asked.
- **`RisitiApp.Api`**, a small HTTP client for the server's JSON API.

### On the server

If you've read my *Ash Framework for Phoenix Developers*, this side will
feel familiar. If you haven't, Part III explains each piece as it comes:

- **Phoenix 1.8** serves two audiences. A JSON API under `/api` for the
  phone, and LiveView pages for the web: the dashboard, the approvals list,
  team settings, exports.
- **Ash 3** holds the business rules. A transaction is an Ash resource with
  actions (create, approve, reject, mark paid) and policies (who may do
  each). The phone's API and the web pages call the same actions, so a rule
  like "changing a decided transaction sends it back to pending" lives in
  exactly one place.
- **AshPostgres** with **one Postgres schema per team**. Every team's data
  lives in its own schema, so one team can never see another's, even through
  a bug in a query. Ash calls this multitenancy with the `:context`
  strategy, and the team is the tenant.
- **Oban** runs everything that shouldn't make a request wait: sending SMS
  sign-in codes, emails, push notifications, and reading uploaded receipts.
- **Postgres**, of course.

### Between them

- **HTTPS and JSON.** Amounts in integer cents, dates as ISO 8601, types and
  statuses as lowercase strings. Uploads that carry a photo are multipart.
- **A bearer token** from sign-in on every call.
- **Push notifications** through Firebase, from the server to the phone,
  when someone else acts: an approver hears about a new claim, a sender hears
  about a decision. A push carries a short message for the person and which
  screen to open, not the transaction itself; it also makes the phone sync,
  and the data comes through sync.

## The map of the code

Risiti is two repositories, one per side.

**The phone app** (`duka_app`, for historical reasons; the app inside it
is `risiti_app`):

```
lib/risiti_app/
├── app.ex                  on_start/0: repo, migrations, theme, first screen
├── screens/                one module per screen
├── components/             Header, TransactionItem, ActionButton, FormField, ...
├── transactions.ex         the expense book (Ecto, SQLite)
├── transactions/           Transaction schema, attachments, the PDF report
├── receipts/               photos, the OCR parser, the QR parser, KRA lookups
├── accounts.ex             the signed-in profile(s) on this phone
├── sync.ex  sync/          phone ⇄ server
├── api.ex  http.ex         the server's JSON API
├── native.ex               every device call
├── theme.ex  appearance.ex
└── ...
plugins/                    Risiti's own Mob plugins: mob_ocr, mob_google
```

**The server** (`risiti`):

```
lib/risiti/
├── expenses.ex             the Expenses domain
├── expenses/               Transaction, TransactionType, PaymentMethod,
│                           Category, Attachment, the receipt reader, exports
├── accounts.ex             the Accounts domain
├── accounts/               User, Team, Group, PhoneCode, PushDevice, sign-up
├── billing/                plans and payments
├── sms.ex  email.ex  push.ex  and their Oban workers
└── ...
lib/risiti_web/
├── controllers/api/        the phone's JSON API
├── live/                   the web dashboard and approvals
└── router.ex
```

Notice how the names line up. The phone has `RisitiApp.Transactions` and
`RisitiApp.Transactions.Transaction`; the server has `Risiti.Expenses` and
`Risiti.Expenses.Transaction`. Both have a receipt QR parser and an OCR
parser, because both read receipts: the phone reads the ones it
photographs, and the server reads the ones uploaded on the web. Keeping the
two parsers alike (and their tests) is a deliberate chore; we'll see why in
Chapter 19.

## Where we go from here

The rest of the book follows the arrows on the diagram.

**Part II** finishes the phone: the full transaction with its types and
statuses, the rest of the home screen, reading receipts with OCR, KRA's QR
codes, refunds and payment requests, a native plugin of our own, and a PDF
report.

**Part III** builds the server: Phoenix and Ash with teams as tenants,
sign-in by SMS code and Google, the transaction resource with its actions
and policies, the JSON API, background jobs, and the web side.

**Part IV** joins them: signing in from the phone, two-way sync, and push
notifications.

**Part V** ships it: a release APK testers can install, and a server people
can depend on.

## What we have so far

No new code in this chapter, but a map:

- Three transaction types, one table, and a short status diagram.
- The rule: **the phone owns the figures, the server owns the decisions.**
- `client_id`, so a repeated sync is harmless.
- The stack on each side, and how the folders line up.

In the next chapter, we grow Part I's `transactions` table into the real
one, migration by migration: refunds and payment requests, statuses, and
the ids sync will need.
