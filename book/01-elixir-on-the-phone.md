# Chapter 1: Elixir on the Phone

> **Part I: Risiti on the phone.** In this part we build the phone half of
> Risiti, an expense app, from an empty screen to an app that photographs
> receipts, one piece per chapter.

Before we install anything, I want you to have a picture in your head of
what we are about to put on your phone. When you build a Phoenix app you
already have that picture: a browser, a socket, a server, a database. On a
phone the pieces have different names, and some of them will be new to you.

By the end of this chapter, you will know:

- What makes an app "native", and why your users care.
- What Mob is, and how it is different from what we tried before.
- What actually runs on the phone when you run a Mob app.
- How a tap on the screen reaches your Elixir code and comes back as pixels.

## Native, web and everything in between

There are three ways to put your software on someone's phone.

**A website.** Your Phoenix app, opened in the phone's browser. It is the
cheapest option: you already have it. But it lives inside the browser. It
can't work when there is no connection, it gets limited access to the
camera, files and notifications, and it never quite feels like the other apps
on the phone.

**A wrapped website.** The same website, packaged inside an app shell that
shows it in a built-in browser (a *WebView*). It gets an icon on the home
screen and a place in the app store, but under the icon it is still a
website, with the same limits.

**A native app.** An app built with the phone's own UI toolkit. On Android
that toolkit is Jetpack Compose; on iOS it is SwiftUI. The buttons are the
platform's real buttons, the scrolling feels like every other app, and the
app can use the camera, the file system, the fingerprint reader and push
notifications directly. It also works with no network at all, because
everything it needs is on the phone.

Users can't always tell you *why* a native app feels better, but they can
feel it. That's why most of their time on a phone is spent in apps, not in
the browser. And that's what we're going to build.

## The price we used to pay

The catch has always been the language. Android apps are written in Kotlin
or Java, iOS apps in Swift. Cross-platform tools such as React Native and
Flutter let you write one codebase, but in JavaScript or Dart.

For an Elixir developer, every one of those options means stepping out of
the BEAM, learning a new language and toolchain, and usually building a
separate API so the app can talk to your Elixir server.

LiveView Native tried to close the gap from the other side. You described
native screens in your Phoenix app, and a thin client on the phone drew them.
It was a clever idea, but the logic lived on the server, so every tap was a
round trip over the network, and the app was useless offline. The project has
since been discontinued.

## What Mob does differently

Mob takes the BEAM to the phone.

When you build a Mob app, the APK you install contains a full Erlang/OTP
runtime, compiled for the phone's processor, alongside your compiled `.beam`
files. When the user opens the app, the BEAM boots *on the phone*, your
application starts, and your Elixir code decides what the screen shows.

Nothing goes to a server unless you decide it should. A tap is handled on the
phone, in your process, in microseconds.

> **New word: APK.** An APK (Android Package) is the file you install on an
> Android phone. It's a zip file with your app's code, resources and a
> manifest that tells Android what the app is and which permissions it needs.
> Think of it as a release tarball for a phone.

## What runs on the phone

Here is the picture to keep in your head for the rest of the book:

```
┌─────────────────────────── Your Android phone ───────────────────────────┐
│                                                                          │
│   ┌─────────────── The BEAM (Erlang/OTP) ───────────────┐                │
│   │                                                     │                │
│   │   RisitiApp.App          your application           │                │
│   │   Mob.Router             which screen is showing    │                │
│   │   ReceiptsScreen ◄─┐     one process per screen     │                │
│   │   SettingsScreen   │                                │                │
│   │   RisitiApp.Repo ──┼──►  SQLite file on the phone   │                │
│   │                    │                                │                │
│   └───────┬────────────┼────────────────────────────────┘                │
│           │ view tree  │ {:tap, :open_settings}                          │
│           ▼            │                                                 │
│   ┌──────────────── mob_nif (a NIF written in Zig) ─────────────────┐    │
│   └───────┬────────────▲────────────────────────────────────────────┘    │
│           ▼            │                                                 │
│   ┌─────── Jetpack Compose: real Android buttons, text, lists ──────┐    │
│   └─────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

Let's walk through it.

**Your application.** `RisitiApp.App` is the entry point, much like the
`Application` module of a Phoenix app. When the BEAM starts, Mob calls its
`on_start/0`, where you start your database and say which screen to show
first.

**Screens are processes.** Every screen in a Mob app is a GenServer. It
holds its state in a socket with assigns, has a `mount/3` and a `render/1`,
and handles events in `handle_info/2`. If you've written a LiveView, you have
written something very close to a Mob screen.

**The view tree.** A screen's `render/1` doesn't return HTML. It returns
plain Elixir data: nested maps such as
`%{type: :button, props: %{text: "Settings"}, children: []}`. You'll write it
with the `~MOB` sigil, which looks like HEEx, but the result is just data.

**The NIF.** Mob hands that tree to `mob_nif`, a native library loaded into
the BEAM (a NIF, a Natively Implemented Function). It is written in Zig,
which is why the setup chapter asks you to install Zig.

**The native UI.** On Android, Jetpack Compose draws the tree with real
Android components. On iOS, SwiftUI does the same. Your Elixir code never
knows or cares which one is drawing.

**And back.** When the user taps a button, the native side sends a message
back to the screen process that owns the button: `{:tap, :open_settings} `.
Your `handle_info/2` pattern matches on it, changes the assigns, and Mob
renders again. The loop is the one you know from LiveView, without the
network in the middle.

## Why this is good news for us

Because it's the BEAM, everything you already know still works on the phone:

- **Processes and supervision.** A crash in one screen restarts that
  screen, not the app.
- **Ecto.** The phone has SQLite, and `ecto_sqlite3` talks to it with the
  same schemas, changesets and queries you write for Postgres.
- **Pattern matching on messages.** Taps, text changes, camera results and
  permission answers all arrive as messages.
- **Hot code loading.** During development, `mix mob.deploy` pushes only your
  changed `.beam` files to the phone and restarts the app in seconds, without
  rebuilding the APK.
- **Distribution.** You can open an IEx shell connected to the BEAM running
  on your phone and inspect it live.

## An honest word about maturity

Mob is young. When I wrote the Medium series that became this part of the
book, Mob was at version 0.7; this book targets 0.9.12. APIs have moved
between versions and will move again before 1.0. Live camera preview, for
example, works on iOS but is not yet wired up on Android.

I still think it is worth learning now. The ideas (screens as processes,
render trees as data, events as messages) are not going to change, and those
are what this book is really about. When an API changes, the fix is usually
a rename.

## What we will build

This whole book builds one app: **Risiti** ("receipt" in Swahili), the
expense app I built for teams in Kenya.

People in a team spend money for work every day: fuel, a client lunch,
airtime, office supplies. Each spend has a receipt, and most receipts end up
crumpled in a pocket until someone has to account for them. Risiti keeps
them on the phone instead. You photograph the receipt, Risiti files it under
a category, and the month's spending is always one glance away. Later in the
book, Risiti reads the receipt for you, checks it against the Kenya Revenue
Authority, lets people claim refunds, and syncs everything with a server
where managers approve it.

Part I builds the phone side from nothing. By the end of it, Risiti will:

- Open on the month's spending, split into food, fuel and everything else.
- List every receipt, filter it by group, and open any one of them.
- Add, edit and delete receipts through a form with validation.
- Keep everything in SQLite on the phone, so it works with no signal.
- Photograph receipts with the camera, and save a photo to the gallery.
- Remember the user's light, dark or system theme.
- Lock the receipts behind a fingerprint.
- Have tests for every screen that run in milliseconds, without a phone.

The code is the real Risiti code: the same module names, the same schema,
the same components. Early chapters show a simpler version of each piece,
and it grows into the real one as we go.

In the next chapter, we'll set up the Android development environment on
Ubuntu and run our first app on a real phone.
