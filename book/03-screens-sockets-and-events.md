# Chapter 3: Screens, Sockets and Events

> **Status:** plan. How a Mob screen works, and the shell of Risiti's home screen.

<!-- Section plan: each heading below gets written in full. -->

## `Mob.Screen`

*`mount/3`, the socket, assigns, and `render`.*

## Events

*`handle_event` for taps and text, `handle_info` for messages from tasks and native code.*

## Navigation

*Pushing and popping screens; a home screen that stays alive under the others.*

## Components

*`Header`, `ActionButton` and friends: functions that return UI.*

## The theme

*Colours, sizes and light/dark appearance in one module.*

## Talking to the device

*Why every native call goes through `RisitiApp.Native`, and how that makes screens testable.*

## Sources

The code this chapter draws on (paths from `duka_app/`):

- `lib/risiti_app/screens/receipts_screen.ex`
- `lib/risiti_app/components.ex`
- `lib/risiti_app/components/`
- `lib/risiti_app/theme.ex`
- `lib/risiti_app/appearance.ex`
- `lib/risiti_app/native.ex`

## By the end

A home screen with a header, an empty list and buttons that log their taps.
