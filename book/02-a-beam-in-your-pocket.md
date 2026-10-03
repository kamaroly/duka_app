# Chapter 2: A BEAM in Your Pocket

> **Status:** plan. Install the toolchain and put a first Elixir screen on a real phone.

<!-- Section plan: each heading below gets written in full. -->

## The toolchain

*Elixir/OTP, the Android SDK and NDK, Zig, and `mix mob.install` fetching the OTP runtimes.*

## A new Mob project

*What the generator gives you: `mob.exs`, `android/`, `ios/`, `lib/`.*

## `mob.exs` and plugins

*Paths for this machine, activated plugins, and acknowledging unsigned ones.*

## First run on the phone

*`mix mob.devices`, then `mix android.native` to build and install.*

## The dev loop

*`mix android` pushes new code without a native rebuild, and when you need the slow path.*

## When it doesn't start

*Reading logcat, a crashed BEAM, and missing NIFs.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `mob.exs`
- `mix.exs`
- `lib/risiti_app/application.ex`
- `lib/risiti_app/app.ex`

## By the end

"Hello from the BEAM" on the reader's own phone.
