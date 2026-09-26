# Transactions

Everything in the book is a **transaction** (`DukaApp.Transactions`), stored
in the phone's SQLite database, so the app works without a connection.
There are three types, the same as on the server:

| Type | What it is | Approved? | Paid out? |
|---|---|---|---|
| Expense | Money already spent, kept for the books | Yes | No |
| Refund | An expense the person wants paid back | Yes | Yes, by M-Pesa |
| Payment request | Money the person asks the team to pay | Yes | Yes |

## Adding an expense

From the home screen:

- **Scan receipt:** take a photo. The app reads the vendor, date and total
  off it, and any QR code on it.
- **Scan QR code:** scan a KRA (eTIMS or TIMS) receipt's QR code. The app
  fetches KRA's record of the receipt and fills in the vendor, date, total
  and items. A code already saved opens that transaction instead of making a
  copy.
- **Add → Add an expense by hand.**

Details read from KRA or a photo only fill fields you haven't typed in, and
a photo never overwrites what KRA said. A photo can be added, retaken or
removed later.

## Refunds

Open an expense and tap **Request refund**. The expense itself becomes a
refund, for its full amount, paid by M-Pesa to your own number unless you
change it. While it waits for a decision, **Take back refund request** turns
it back into an expense.

## Payment requests

**Add → Request a payment** asks the team to pay:

- the amount, who is paid and what for, and the category;
- how to pay: send money to a phone, a Buy Goods till, or a paybill and
  account number;
- whether it pays a **supplier** or is an **advance** to you;
- optionally, attachments such as an invoice or quotation (photos or PDFs).

A payment request can be edited after it's sent. Changing a decided one
sends it back for approval.

## Personal books

A personal book (see [Signing in](sign-in.md)) has nobody else to approve
or pay. So there are no refunds, payment requests or approvals, and expenses
are approved as they're saved.

## Status

Each transaction shows its status: pending, approved, rejected, or paid
(refunds and payment requests). It also shows whether the server has it
yet. The approver's note appears on it once it's decided.

## Filters

The home list shows this month's spend and every transaction. It can be
filtered by spending group, or to **Refunds & payments**, and searched.

## Approvals

People the server lets approve or mark paid see **Approvals**. It has two
lists:

- **To decide:** approve or reject. Rejecting needs a note, so the person
  knows what to fix.
- **To pay:** approved refunds and payment requests. Mark them paid once the
  money has gone.

Approvals come from the server, not the phone, so they need a connection.
Photos and attachments download when opened. When push notifications are on,
the lists refresh as things change.
