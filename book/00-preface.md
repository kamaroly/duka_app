# Preface

I have spent most of my career building software for the web. I came to
Elixir after Laravel, CodeIgniter, Django and the .NET Framework, and once I
learned to think in Ash and Phoenix, I didn't want to leave the BEAM. The
problem was that my users did.

As of September 2026, mobile applications drive around 64% of global web
traffic, and people spend about 90% of their mobile time inside dedicated
apps rather than in a browser. My users were no different. They wanted an app
on their phone, not a bookmark.

For an Elixir developer that has always meant stepping out of the BEAM:
learning Kotlin for Android, Swift for iOS, or React Native and a whole
JavaScript toolchain, and then keeping two codebases in step. We tried to
close that gap before. LiveView Native let us describe native screens from a
Phoenix server, but every tap was a round trip to that server, and the
project has since been discontinued.

Then I found [Mob](https://mobframework.com). Mob puts the BEAM itself on the
phone and draws a real native UI from your Elixir code. No server round trip
for a tap, no JavaScript bridge. I built a sample app with it, from setup to
running on my own Android phone, and the experience gave me hope that we can
finally build native mobile apps without leaving the ecosystem we love.

This book is what I learned on the way from that sample app to Risiti, a
production app my team and our users depend on.

<!-- KAMARO: one or two sentences on the moment Risiti became real: the first
team that used it, or the first receipt you scanned in a shop. -->

## Who this book is for

You are an Elixir developer. You know pattern matching, GenServers, Ecto and
probably Phoenix LiveView. You have never shipped a mobile app, and words like
APK, NDK, ADB or "back stack" are new to you.

That's exactly who I wrote for. I will not explain Elixir to you, but I will
explain every piece of the mobile world the first time we meet it, and I will
tie each new idea to something you already know. If you have written a
LiveView, you are closer to writing a mobile screen than you think.

## What we will build

One app, from an empty screen to production: **Risiti**, the expense app I
built for teams in Kenya. Risiti photographs receipts, reads them on the
phone, checks them against the Kenya Revenue Authority, works offline, and
syncs with a Phoenix and Ash server where managers approve expenses, refunds
and payment requests.

**Part I, Risiti on the phone,** starts from `mix mob.new` and teaches Mob
by building Risiti's phone app one piece at a time: the first screen,
navigation, layout, the theme, the receipts list, a SQLite database, the
receipt form, the camera and a fingerprint lock. By the end of Part I you
have a working offline expense tracker on your own phone.

**Parts II to V** finish the job: reading receipts with on-device OCR and
KRA's QR codes, refunds and payment requests, a native plugin of our own, a
PDF report, then the server, accounts, two-way sync over a bad connection,
push notifications, and finally an APK in your testers' hands and a server
in production.

## What "by hand" means

Every line of code in this book is typed and explained. We use Mob's
generator to create the project, because nobody should write Gradle files by
hand, but after that we write each screen ourselves. When a framework does
something for us, I will open the box and show you what it did.

The code is real: the same modules, schema and components as the Risiti
running in production. Early chapters show a simpler version of each piece,
and it grows into the real one; where the production code does more than a
chapter needs, I cut it down and say so. Part I's code is tested against Mob
0.9.12, and every snippet you see has a matching test in `code/`.

## How to read this book

Read Part I in order. Each chapter starts where the previous one stopped and
ends with something you can run on your phone. If you already know Mob, skim
Part I and start at Part II.

At the end of every chapter, the state of the code is in `code/NN/`, so if
you get lost you can compare your project with mine.

When I say "think of X as Y in LiveView", I mean it as a bridge, not an exact
match. Mob is not LiveView. It just shares a lot of its shape, on purpose.

## What you need

- A Linux or macOS computer. I use Ubuntu, so the setup chapter is written
  for Ubuntu and Debian. macOS works too, and Mob's own installation guide
  covers it.
- An Android phone and a USB cable. An Android emulator works, but nothing
  beats holding your app in your hand.
- Elixir 1.18 or later, the minimum a new Mob project asks for.
- For Parts III to V, PostgreSQL.

iOS needs a Mac with Xcode. I don't use one for this book, so we target
Android throughout. Almost everything you write in Elixir runs unchanged on
iOS; where it doesn't, I will say so.

## Thank you

<!-- KAMARO: thanks to the Mob maintainers, early readers who signed up from
the Medium series, and anyone else you want to name. -->

Let's start by understanding what Mob actually puts on your phone.
