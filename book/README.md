# Building Risiti by Hand

*Working title.* A book on building a native mobile app in Elixir with Mob,
from a first screen to an offline-first expense app with a Phoenix and Ash
server: Risiti, the way it was built.

- **Reader:** an Elixir developer who has never shipped a mobile app. We
  skip Elixir basics and explain every mobile idea the first time it
  appears, tied to what the reader knows from Phoenix and LiveView.
- **One app:** the whole book builds **Risiti**. Part I builds its phone
  half from `mix mob.new`, with the real module names, schema and
  components, each piece starting simple and growing into the real one.
  Parts II to V add receipt reading, claims, the server, sync and shipping.
- **Code:** Part I's code is tested against Mob 0.9.12, chapter by chapter,
  in `code/NN/`. Later parts draw on the production code, cut down where
  the full version would hide the idea.
- **Voice:** see [STYLE.md](STYLE.md).
- **Screenshots:** see [images/SHOTS.md](images/SHOTS.md).

## Contents

- [Preface](00-preface.md) · *written*

### Part I: Risiti on the phone

Built from the Medium series (Introduction, Parts 02–05), extended to the
whole phone app.

| # | Chapter | Status |
|---|---|---|
| 1 | [Elixir on the Phone](01-elixir-on-the-phone.md): native apps, what Mob puts on the phone, what Risiti is | written |
| 2 | [Your Android Workbench](02-your-android-workbench.md): the toolchain on Ubuntu, `mix mob.new risiti_app`, the first deploy, the daily loop | written |
| 3 | [Your First Screen](03-your-first-screen.md): screens as processes, `~MOB`, the receipts screen as the start screen | written |
| 4 | [Moving Between Screens](04-moving-between-screens.md): taps as messages, push and pop to the form and Settings | written |
| 5 | [Passing Parameters](05-passing-parameters.md): a receipt's ID in the tap, params into `mount/3` | written |
| 6 | [Columns, Rows and Boxes](06-columns-rows-and-boxes.md): the home layout: header, spend card, list, dock | written |
| 7 | [Colours, Type and Themes](07-colours-and-themes.md): `RisitiApp.Theme`, the dark spend card, the appearance choice | written |
| 8 | [Lists That Scroll](08-lists-that-scroll.md): `RisitiApp.Transactions`, a lazy `<List>`, group pills, money in cents | written |
| 9 | [Components of Your Own](09-components-of-your-own.md): `Header`, `TransactionItem`, `ActionButton` | written |
| 10 | [Testing Without a Phone](10-testing-without-a-phone.md): the three tiers, `Mob.ScreenCase`, `Mob.Test` on the device | written |
| 11 | [Remembering Things](11-remembering-things.md): `Mob.State` and `RisitiApp.Appearance` | written |
| 12 | [A Database on the Phone](12-a-database-on-the-phone.md): the `transactions` table, migrations at boot, the SQL sandbox | written |
| 13 | [The Receipt Form](13-the-receipt-form.md): `FormField`, keyboards, the category sheet, two-step validation | written |
| 14 | [Taking the Photo](14-taking-the-photo.md): plugins, permissions, `RisitiApp.Native`, `Photos` | written |
| 15 | [The Photo and the Lock](15-the-photo-and-the-lock.md): the photo viewer, the gallery, the fingerprint lock | written |

### Part II: Reading receipts

| # | Chapter | Status |
|---|---|---|
| 16 | [The Whole Picture](16-the-whole-picture.md): the system, phone and server, and the one rule behind the design | written |
| 17 | [The Whole Transaction](17-the-whole-transaction.md): types, statuses, `client_id`, growing the table | written |
| 18 | [The Home Screen, Finished](18-the-home-screen-finished.md): search, the month picker, date ranges, the details sheet | written |
| 19 | [Reading a Receipt](19-reading-a-receipt.md): on-device OCR and a parser for messy receipt text | written |
| 20 | [KRA Receipts](20-kra-receipts.md): scanning eTIMS and TIMS QR codes and trusting KRA's record | plan |
| 21 | [Refunds, Payment Requests and Attachments](21-refunds-payments-and-attachments.md): one transaction, three types | plan |
| 22 | [Writing a Native Plugin](22-writing-a-native-plugin.md): `mob_google` from scratch, Elixir to Zig to Kotlin and back | plan |
| 23 | [A PDF on the Phone](23-a-pdf-on-the-phone.md): exporting what the list shows as a printable report | plan |

### Part III: The server

| # | Chapter | Status |
|---|---|---|
| 24 | [Starting the Server](24-starting-the-server.md): Phoenix 1.8 and Ash 3, with teams as tenants | plan |
| 25 | [Accounts](25-accounts.md): SMS codes, Google sign-in, sign-up, personal and business books | plan |
| 26 | [Transactions and Approvals](26-transactions-and-approvals.md): the server's resource, actions and policies | plan |
| 27 | [The Mobile API](27-the-mobile-api.md): a JSON contract the phone can rely on | plan |
| 28 | [Work in the Background](28-work-in-the-background.md): Oban for SMS, email and push | plan |
| 29 | [The Web Side](29-the-web-side.md): the dashboard, reading receipts on the server, exports | plan |

### Part IV: Joining them

| # | Chapter | Status |
|---|---|---|
| 30 | [Signing In from the Phone](30-signing-in-from-the-phone.md): the whole sign-in flow, phone to server and back | plan |
| 31 | [Two-Way Sync](31-two-way-sync.md): keeping the phone and the server in step, over a bad connection | plan |
| 32 | [Push Notifications](32-push-notifications.md): telling people when something needs them | plan |

### Part V: Shipping

| # | Chapter | Status |
|---|---|---|
| 33 | [The Release APK](33-the-release-apk.md): from a debug build to an APK testers install | plan |
| 34 | [Deploying the Server](34-deploying-the-server.md): putting Risiti on a server people depend on | plan |
| 35 | [What I'd Do Again, and What I Wouldn't](35-what-id-do-again.md): lessons from building Risiti | plan |

## Files

- `NN-short-name.md`: one chapter per file. Chapters marked *plan* are still
  a section plan with the sources they draw on.
- `code/NN/`: Risiti at the end of chapter NN (Part I). See
  [code/README.md](code/README.md).
- `images/`: screenshots, listed in [images/SHOTS.md](images/SHOTS.md).
- `<!-- KAMARO: ... -->` comments mark places where only the author can
  write the line: a personal story, a thank-you, a memory.
