# Risiti app documentation

The Risiti phone app (Android), built with Elixir and
[Mob](https://hexdocs.pm/mob). It keeps a person's expense book on the phone,
works offline, and syncs with their team on the Risiti server
([risiti](https://github.com/kamaroly/risiti)).

| Guide | What it covers |
|---|---|
| [Transactions](transactions.md) | Scanning receipts, expenses, refunds, payment requests, approvals |
| [Signing in and signing up](sign-in.md) | SMS codes, Google, personal and business books, Google setup |
| [The server and sync](server-and-sync.md) | Which server the app uses, what sync does and when, what sync errors mean |
| [Building for testers](building.md) | Versions, plugins, and building the sideload APK |

Release notes are in [`releases/`](releases/). For the server side
(permissions, super admins, exports, the API), see the
[server docs](https://github.com/kamaroly/risiti/tree/transactions/docs).
