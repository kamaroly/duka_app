# Risiti app

The Risiti expense app for Android: scan receipts, record expenses, claim
refunds and request payments, and approve them. It works offline and syncs
with the team's Risiti server at https://expenses.zippiker.com
([risiti](https://github.com/kamaroly/risiti)).

Built with Elixir and [Mob](https://hexdocs.pm/mob), with SQLite on the
phone.

## Documentation

- [Transactions](docs/transactions.md): expenses, refunds, payment requests, approvals
- [Signing in and signing up](docs/sign-in.md): SMS, Google, personal and business books
- [The server and sync](docs/server-and-sync.md): what sync does, and what its errors mean
- [Building for testers](docs/building.md): versions, plugins, the release APK
- [Release notes](docs/releases/)

## Development

```sh
mix deps.get
mix test                 # creates and migrates the test database first
mix mob.devices          # connected phones
mix android.native       # build and install on a USB-connected phone
mix android              # push code changes to it
```
