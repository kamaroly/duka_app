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
| `19-search-ocr.png` | 19 | Home screen, search open, "kimbo" typed, the Quickmart receipt listed. | `code/19`, after saving the Quickmart receipt. |
| `20-form-kra.png` | 20 | The form after a scan, filled in from KRA: the "Verified with KRA" notice, the eTIMS box with PIN and receipt number, vendor, amount. | `code/20`. No real eTIMS link is in the repo (the saved page's signature is blanked), so send the form `{:kra, :result, details}` with the details from `test/fixtures/kra/etims_receipt.html`, as the tests do, and say so here. |
| `20-sheet-verified.png` | 20 | The sheet of a verified KRA receipt: "Verified with KRA · date", PIN, receipt number, View on KRA. | After saving the receipt above. |
| `21-request-form.png` | 21 | The request form: 12,500 to Kamau Hardware for cement, A supplier, Till 832909, one PDF attachment. | `code/21`. Push a small PDF into the app's cache with `run-as` and send `{:files, :picked, [%{path: ..., name: "Quotation.pdf", mime: "application/pdf", size: n}]}`. |
| `21-refund-form.png` | 21 | The refund form for the Java House expense, with a note and an M-Pesa number. | Open the expense's sheet, tap Request refund. |
| `23-report-on-phone.png` | 23 | The report open in the phone's PDF viewer (last month, September's data). | `code/23`: date pill → Last month, tap PDF. Also confirms `Native.open_file/2` opens a file path on the phone. |
| `15-fingerprint.png` | 15 | Android's fingerprint prompt over the locked receipts screen. | By hand, with the phone's own screenshot buttons; see the comment in Chapter 15. |

## Still to run

- **Chapter 22, "Run it"**: the IEx call to `MobGoogle.sign_in/2` on the
  phone with a made-up client id, from `code/22` (book app in front).
  Paste Google's error message in place of `"..."` and drop the `RUN`
  comment. If the call doesn't come back, the `erl_eval` explanation in
  that section needs another look.

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
- **Chapter 18's data**: the receipts from Chapters 13 to 15, plus five
  more (four in September), all added over distribution. The Team lunch was
  turned into a refund with `request_refund/2`, and the decisions were made
  with `decide/3`: the 4 Oct Naivas and TotalEnergies approved, the 3 Oct
  Naivas rejected as a duplicate, Safaricom rejected. The month picker and
  search were opened with `Mob.Test.tap/2`, "java" typed with
  `adb shell input text`.
- **`23-report.png`** isn't a phone screenshot: it's page 1 of a report
  rendered with `Report.render/3` from sample rows and turned into a PNG
  with `pdftoppm -r 110`, cropped to the top 42%.
- **Chapter 19's receipt** is an image made with Pillow
  (`QUICKMART LIMITED`, made-up details, eTIMS layout, tilted 3 degrees on
  a brown background), copied into the app's cache with `run-as` and handed
  to the form as `{:camera, :photo, %{path: ...}}`. ML Kit's reading of it
  on the phone is `code/19/test/fixtures/receipts/quickmart_phone.txt`.
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
