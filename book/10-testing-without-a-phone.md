# Chapter 10: Testing Without a Phone

Previously, we built Risiti's `Header`, `TransactionItem` and `ActionButton`. We've written
tests since Chapter 3, a few lines at a time, without stopping to talk about
them. In this chapter we step back and look at testing a Mob app properly.

Testing a mobile app has a reputation for being painful: emulators that
take a minute to boot, tests that tap at screen coordinates and break when a
button moves. Mob changes that, for the same reason everything else in this
book works: a screen is a process, and its UI is data. You can test almost
all of it in plain ExUnit, in milliseconds.

By the end of this chapter, you will know:

- The three tiers of testing a Mob app, and how much of each you need.
- Every helper `Mob.ScreenCase` gives you, and when to use it.
- How to make sure every screen can be drawn, with one test file.
- How to poke at the real app on your phone from IEx.

## Three tiers

```
            ┌──────────────┐
            │   on device  │   Mob.Test over distribution: a few checks
            │              │   only real hardware can prove.
          ┌─┴──────────────┴─┐
          │     contract     │   assert_renderable/2: every node is
          │                  │   something Compose can draw.
        ┌─┴──────────────────┴─┐
        │      in the BEAM      │   Mob.ScreenCase: mount, send messages,
        │                       │   check assigns, navigation and text.
        └───────────────────────┘
```

**In the BEAM.** `Mob.ScreenCase` calls your screen's callbacks directly,
the same way the runtime does on the phone. You test logic, state,
navigation and the shape of the UI. This is where most of your tests live.

**Contract.** `assert_renderable/2` checks that every node in a tree is a
type the native side can actually render. It catches typos and composites
that expand to nonsense. It's one line, so it goes in many tests.

**On the device.** Some things only hardware can prove: that the camera
opens, that the layout looks right on a small screen, that the fingerprint
prompt appears. For those, you drive the real app over Erlang distribution.
Keep this tier thin.

If you've used `Phoenix.LiveViewTest`, the bottom tier will feel familiar.
`Mob.ScreenCase` is its mobile cousin.

## The ScreenCase toolbox

Here's everything we've used so far, in one place:

| Helper | What it does |
|---|---|
| `mount_screen(Screen)` | Calls `mount/3` and `render/1`. Returns a `view`. |
| `mount_screen(Screen, params)` | Same, with the params `push_screen/3` would pass. |
| `render_info(view, message)` | Sends a message to `handle_info/2` and re-renders. A tap is `{:tap, tag}`. |
| `render_event(view, event, params)` | The same for `handle_event/3`. |
| `assigns(view)` | The socket's assigns after the last callback. |
| `navigated_to(view)` | Where the last callback navigated: a screen module, `{:pop}`, or `nil`. |
| `tree(view)` | The tree `render/1` returned, before composites and lists are expanded. |
| `text(tree_or_view)` | Every piece of text in the tree, joined. |
| `find(tree_or_view, type, props)` | The first node of that type whose props match. |
| `find_all(tree_or_view, type, props)` | All of them. |
| `assert_renderable(tree_or_view)` | Fails if any node can't be drawn natively. |

And our own helper from the last chapter, in `test/test_helper.exs`:

| Helper | What it does |
|---|---|
| `rendered(view)` | Expands composites, then lists, exactly as Mob does on the phone. |

A pattern you'll see in every screen test: **mount, send, assert.**

```elixir
view =
  ReceiptsScreen
  |> mount_screen()
  |> render_info({:tap, :open_settings})

assert navigated_to(view) == SettingsScreen
```

We don't simulate a finger. We send the screen the exact message a finger
would cause. That's not a shortcut: on the phone, the native side does
nothing more than send that message. Testing at the message level tests
what your code actually receives.

## What to test on a screen

For each screen, I ask four questions:

1. **Does it show the right thing?** Mount it, check `text(rendered(view))`
   for the strings that matter. Don't assert every label; assert the ones
   that come from data, like a receipt's vendor or the month's total.
2. **Does each action do the right thing?** For every `handle_info/2`
   clause, send its message and check the result: an assign changed, or
   `navigated_to/1` points where it should.
3. **Does it carry the right params?** When a screen pushes another with
   params, check the params, as we did in Chapter 5 with
   `view.socket.__mob__.nav_action`.
4. **Can the phone draw it?** `assert_renderable(rendered(view))`.

Notice what's missing: colours, sizes, spacing. Those are design decisions,
not logic, and a test that says `background == :surface` mostly gets in your
way when you change your mind. I assert a prop only when it *means*
something, like the selected appearance button being `:primary` in
Chapter 7.

## One test for every screen

Questions 1 to 3 are different for each screen. Question 4 is the same for
all of them, and so is another one: "does this screen survive a message it
doesn't expect?". Rather than repeat those in every file, let's write them
once.

Create `test/risiti_app/screens/all_screens_test.exs`:

```elixir
# test/risiti_app/screens/all_screens_test.exs
defmodule RisitiApp.Screens.AllScreensTest do
  use Mob.ScreenCase, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen, SettingsScreen}

  # Every screen, with the params it needs to mount. Add new screens here.
  @screens [
    {ReceiptsScreen, %{}},
    {ReceiptFormScreen, %{}},
    {ReceiptFormScreen, %{id: 1}},
    {SettingsScreen, %{}}
  ]

  for {screen, params} <- @screens do
    test "#{inspect(screen)} #{inspect(params)} renders a tree the phone can draw" do
      view = mount_screen(unquote(screen), unquote(Macro.escape(params)))
      assert_renderable(rendered(view))
    end

    test "#{inspect(screen)} #{inspect(params)} ignores unexpected messages" do
      view = mount_screen(unquote(screen), unquote(Macro.escape(params)))
      view = render_info(view, {:something, :unexpected})
      assert_renderable(rendered(view))
    end
  end
end
```

The `for` runs at compile time and defines two tests per entry. The receipt
form is listed twice, because it has two ways of being opened, new and
edit, and both must render. The params go into the test names, which keeps
the names unique. That's
ordinary ExUnit metaprogramming: `unquote` puts each screen and its params
into the test body. `Macro.escape/1` is needed because the params are a map,
and a map isn't valid quoted code on its own.

The second test guards the rule from Chapter 4: every screen ends its
`handle_info/2` with a catch-all. Delete one, and this test fails with a
`FunctionClauseError` before a stray message crashes the screen on someone's
phone.

When you add a screen, add a line to `@screens`. That's the whole cost.

```
mix test
```

```
22 tests, 0 failures
```

## `async: true` or `async: false`?

ExUnit can run test modules in parallel. Screen tests can join in, as long
as they don't share state. Two things in our app are shared:

- **The theme.** `Mob.Theme.set/1` changes it for the whole app. The
  Settings tests switch it, so they're `async: false`.
- **`Mob.State`**, which we'll meet in the next chapter. It's one store for
  the whole app.

From Chapter 12 there's a third, the database, but there the SQL sandbox
gives every test its own transaction.

If a screen keeps everything in its assigns, make its tests `async: true`.

## The tier on the phone

Some things only a phone can tell you. For those, connect to the running app
from IEx:

```
mix mob.connect
```

This sets up the USB tunnel, restarts the app, and opens an IEx shell
connected to the BEAM on your phone. Now `Mob.Test` can drive it:

```elixir
iex> node = hd(Node.list())
:"risiti_app_android_rzctb0gknkh@127.0.0.1"

iex> Mob.Test.screen(node)
RisitiApp.Screens.ReceiptsScreen

iex> Mob.Test.select(node, :receipts, 0)
iex> Mob.Test.screen(node)
RisitiApp.Screens.ReceiptFormScreen

iex> Mob.Test.assigns(node).receipt.vendor
"Naivas Supermarket"

iex> Mob.Test.back(node)
iex> Mob.Test.tap(node, :open_settings)
```

The phone's node name includes your device's ID; `hd(Node.list())` saves
you typing it. `tap/2` sends the same `{:tap, tag}` message a real tap
produces.
`select/3` taps a row in a list. `back/1` performs the system back gesture.
`assigns/1` and `tree/1` show you the live state of whatever screen is on
top.

Two more that are handy for the book, or a bug report:

```elixir
iex> {:ok, png} = Mob.Test.screenshot(node)
iex> File.write!("receipts.png", png)
```

That captures exactly what's on the phone's screen, over distribution.

And `send_message/2` delivers any message to the current screen, which lets
you fake hardware answers on a real device: a photo from the camera, a
location fix, a notification. We'll lean on that in Chapter 14.

I use this tier by hand, in IEx, while I work on a screen, and for a short
checklist before a release. Writing it as automated tests is possible too
(`Mob.ScreenCase` has a `device_view/1` that runs the same assertions
against a phone), but it needs a phone plugged into whatever runs your
tests, so keep that suite small.

## What we have so far

- A clear picture of what to test where.
- `all_screens_test.exs`: every screen renderable, every screen safe from
  stray messages.
- A way to drive the real app from IEx with `Mob.Test`.

The code at the end of this chapter is in `code/10/`.

So far, everything our app knows is forgotten the moment it closes. Remember
the appearance choice from Chapter 7, which resets on every restart? In the
next chapter we'll give Risiti a memory.
