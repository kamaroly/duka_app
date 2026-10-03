# Chapter 10: Writing a Native Plugin

> **Status:** plan. `mob_google` from scratch: Elixir to Zig to Kotlin and back.

<!-- Section plan: each heading below gets written in full. -->

## Anatomy of a Mob plugin

*`mob_plugin.exs`, the Erlang stub, the NIF and the bridge.*

## The Elixir side

*A function that asks, and a message that answers.*

## The Zig NIF

*Crossing into JNI and calling Kotlin.*

## The Kotlin bridge

*Android's Credential Manager and the Google account chooser.*

## Back to Elixir

*Sending the ID token to the screen's process.*

## Wiring it into the build

*Gradle dependencies, the bootstrap, the NIF table, and why `mix mob.release` doesn't do it for you.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `plugins/mob_google/lib/mob_google.ex`
- `plugins/mob_google/src/mob_google_nif.erl`
- `plugins/mob_google/priv/native/jni/mob_google_nif.zig`
- `plugins/mob_google/priv/native/android/MobGoogleBridge.kt`
- `plugins/mob_google/priv/mob_plugin.exs`

## By the end

Continue with Google returns an ID token to Elixir.
