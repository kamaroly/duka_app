# Screenshots

Every screenshot in Part I was taken on a Samsung Galaxy A53 (SM-A536E),
from the book's own checkpoints in `../code/NN/`, deployed as a separate app
(`com.example.risiti_book`) so the real Risiti on the phone was untouched.
They're scaled to 540 px wide.

`medium/` holds the screenshots from the original Medium articles (Mob 0.7,
`duka_app`). The book doesn't use them any more; they're kept for reference.

## Still to take

| File | Chapter | What it shows | How |
|---|---|---|---|
| `15-fingerprint.png` | 15 | Android's fingerprint prompt over the locked receipts screen. | By hand, with the phone's own screenshot buttons; see the comment in Chapter 15. |

## Notes on what's in the shots

- **The receipt photo** in `14-form-with-photo.png`, `14-list-with-photo.png`
  and `15-photo-viewer.png` is a generated image of a Naivas till receipt,
  handed to the app as the camera's answer (`{:camera, :photo, ...}`), the
  same way the tests do it. Retake those three with a real receipt photo if
  you'd like the book to show one.
- **`06-button-without-width.png`** is `code/06` with the two `width`
  props removed, on purpose, to show the bug Chapter 6 explains.
- **The permission dialog** in `14-camera-permission.png` is the real one;
  "Only this time" was chosen.
- **Sample receipts** for Chapters 13 to 15 were added on the phone over
  Erlang distribution with `RisitiApp.Transactions.create_transaction/1`, as
  Chapter 12 shows.

## How to retake one

1. Copy the checkpoint over a generated project and deploy it. Close the app
   first, so `mob.deploy` writes the new code instead of hot-loading it:

   ```
   adb shell am force-stop com.example.risiti_app
   mix mob.deploy --device YOUR_DEVICE_ID
   ```

   Use `--native` for `14` and `15`, which add plugins.
2. Put the app in the state the table describes. `mix mob.connect` and
   `Mob.Test` (`tap/2`, `select/3`, `send_message/2`) get you there without
   touching the phone.
3. Capture straight to the file, and only while the app is in front:

   ```
   adb exec-out screencap -p > book/images/NN-name.png
   ```

   or, over distribution, `{:ok, png} = Mob.Test.screenshot(node)`.
