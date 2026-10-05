# Style

How the book sounds, taken from Kamaro's own writing: the Mob series on
Medium (Introduction and Parts 02–05) and *Ash Framework for Phoenix
Developers, Part 1: Thinking in Ash*. Every chapter should read like the same
person wrote it.

## Who is talking

A working developer who builds real products and is showing a colleague how
he did it. First person, plain, warm, never showing off. He says where he
stands ("I am using Ubuntu… iOS requires a Mac which I don't have access to at
the moment") and where he came from ("I came to Ash Framework after using
Laravel, CodeIgniter, Django, and the .NET Framework").

## Who is listening

An Elixir developer who has never shipped a mobile app. They know GenServers,
pattern matching, Ecto and LiveView. They do not know what an APK, an NDK, ADB
or a back stack is. Explain every mobile word the first time it appears, then
use it freely.

## How a chapter moves

1. **Recap and promise.** Open with where we left off and what this chapter
   adds: "Previously, we created our first native screen… Now, we are going to
   see how to navigate between screens."
2. **Why it matters**, in a short paragraph grounded in a real situation
   ("you will hardly find a one-screen application").
3. **What you will know** at the end, as a short list when it helps.
4. **Build it.** "Let's create `lib/risiti_app/screens/…` and add the following
   content." Then the full code.
5. **Explain it.** "Let's break down what we just did." / "Here is what's
   going on." Walk the code top to bottom, quoting the lines that matter.
6. **Run it.** The exact command, then a screenshot of the phone.
7. **Hand over** to the next chapter in one or two sentences.

## Habits to keep

- **One app.** Every example is Risiti, using the real module names. Early
  chapters show a simpler version of a piece and say so; it grows into the
  real one.
- **The LiveView bridge.** Anchor every new idea to what the reader already
  knows: "think of `on_tap` as `phx-click` for the mobile device", "`mount/3`
  plays the same role as `mount/3` in a LiveView", "the start screen acts like
  the `/` route in a web application".
- **Analogies from outside Elixir** when they help: "Think of how you use a
  `.yaml` file to describe your GitHub workflows."
- **Lists for steps and requirements**, prose for reasons.
- **"Let's"** to start doing; **"Note that…" / "You will notice…"** to point
  at a detail.
- **Short paragraphs.** Two to four sentences.
- **Honest asides** about what's unfinished or what tripped him up.

## Habits to drop (from the blog drafts)

- Typos inside code (`d` for `do`, `norepy`, `ext_color`). Every snippet in
  the book compiles and has a test in `code/`.
- Medium turning `--flag` into `- flag`. Flags are always written with two
  hyphens inside code blocks.
- "Lunch" for "launch", "serie" for "series", "wich" for "which".
- Links to private pages (Medium stats).
- Inconsistent names. The app is always `risiti_app` / `RisitiApp`, the
  device ID is always written `YOUR_DEVICE_ID`.

## Conventions

- Markdown, one chapter per file.
- Code blocks name their file on the first line as a comment
  (`# lib/risiti_app/screens/receipts_screen.ex`) when the file is new or
  replaced whole. Partial snippets say which function they belong to.
- Money is always in cents in code and in shillings in prose, written the
  way Risiti shows it: Ksh 1,250.
- Commands are shown as they're typed, without a `$` prompt.
- Screenshots live in `images/`, named `NN-what-it-shows.png`. A screenshot
  we still have to take is written as
  `![What it shows](images/NN-name.png)` with an HTML comment above it
  saying exactly what to capture. See `images/SHOTS.md`.
- Mob version: the book targets Mob 0.9.12 and `mob_new` 0.6.6.
