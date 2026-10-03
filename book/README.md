# Building Risiti by Hand

*Working title.* A book on building an offline-first mobile expense app in
Elixir, phone and server, the way Risiti was built.

- **Reader:** experienced Elixir developers. No language basics; we go
  straight to Mob, SQLite on the phone, native plugins, Ash, sync and
  shipping.
- **Scope:** the Mob app on the phone *and* the Phoenix + Ash server it
  syncs with.
- **Approach:** each chapter adds one working piece and ends with something
  you can run on a real phone or hit with `curl`. The code is the real
  Risiti code, cut down where the full version would hide the idea.
- **Voice:** see [STYLE.md](STYLE.md).

## Contents

### Part I: The shape of the thing

- [Preface](00-preface.md): Why I built Risiti, who this book is for, and what building it "by hand" means.
- [Chapter 1: What We're Building](01-what-were-building.md): The product, the architecture, and the one rule behind the design.
- [Chapter 2: A BEAM in Your Pocket](02-a-beam-in-your-pocket.md): Install the toolchain and put a first Elixir screen on a real phone.

### Part II: The phone

- [Chapter 3: Screens, Sockets and Events](03-screens-sockets-and-events.md): How a Mob screen works, and the shell of Risiti's home screen.
- [Chapter 4: A Database on the Phone](04-a-database-on-the-phone.md): Ecto and SQLite on the device, and the schema everything else stands on.
- [Chapter 5: The Home Screen](05-the-home-screen.md): The list people open the app for.
- [Chapter 6: Taking the Photo](06-taking-the-photo.md): The camera, photos on disk, and the receipt form.
- [Chapter 7: Reading a Receipt](07-reading-a-receipt.md): On-device OCR and a parser for messy receipt text.
- [Chapter 8: KRA Receipts](08-kra-receipts.md): Scanning eTIMS and TIMS QR codes and trusting KRA's record.
- [Chapter 9: Refunds, Payment Requests and Attachments](09-refunds-payments-and-attachments.md): One transaction, three types.
- [Chapter 10: Writing a Native Plugin](10-writing-a-native-plugin.md): `mob_google` from scratch: Elixir to Zig to Kotlin and back.
- [Chapter 11: A PDF on the Phone](11-a-pdf-on-the-phone.md): Exporting what the list shows as a printable report.

### Part III: The server

- [Chapter 12: Starting the Server](12-starting-the-server.md): Phoenix 1.8 and Ash 3, with teams as tenants.
- [Chapter 13: Accounts](13-accounts.md): SMS codes, Google sign-in, sign-up, and personal and business books.
- [Chapter 14: Transactions and Approvals](14-transactions-and-approvals.md): The server's transaction resource, its actions and its policies.
- [Chapter 15: The Mobile API](15-the-mobile-api.md): A JSON contract the phone can rely on.
- [Chapter 16: Work in the Background](16-work-in-the-background.md): Oban for SMS, email and push.
- [Chapter 17: The Web Side](17-the-web-side.md): The dashboard, reading receipts on the server, and exports.

### Part IV: Joining them

- [Chapter 18: Signing In from the Phone](18-signing-in-from-the-phone.md): The whole sign-in flow, phone to server and back.
- [Chapter 19: Two-Way Sync](19-two-way-sync.md): Keeping the phone and the server in step, over a bad connection.
- [Chapter 20: Push Notifications](20-push-notifications.md): Telling people when something needs them.

### Part V: Shipping

- [Chapter 21: The Release APK](21-the-release-apk.md): From a debug build to an APK testers install.
- [Chapter 22: Deploying the Server](22-deploying-the-server.md): Putting Risiti on a server people depend on.
- [Chapter 23: What I'd Do Again, and What I Wouldn't](23-what-id-do-again.md): Lessons from building Risiti.

## Files

Each chapter is its own file, `NN-short-name.md`, starting as a section
plan with the sources it draws on. `code/NN/` will hold the state of the
code at the end of that chapter.
