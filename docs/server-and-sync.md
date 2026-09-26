# The server and sync

## Which server

The app always talks to **https://expenses.zippiker.com**
(`config :duka_app, :api_url`, read by `DukaApp.Api.base_url/0`). Users
can't change it.

To try the app against a server on your laptop, with the phone on USB:

1. Temporarily set `config :duka_app, :api_url, "http://127.0.0.1:4000"` in
   `config/config.exs`. Don't commit it.
2. Run `adb reverse tcp:4000 tcp:4000`, so 127.0.0.1 on the phone reaches
   the laptop.

Tests use a stand-in server (`config/test.exs`).

**The app and the server must be on matching releases.** App 1.2 syncs
through the server's transactions endpoints; it can't sync with the older
server, and app 1.1 can't sync with the new one.

## What sync does

Sync (`DukaApp.Sync`) keeps a connected book and the server in step. Each
run:

1. **Deletes** on the server what was deleted on the phone. The server keeps
   anything already decided, and the next step brings it back.
2. **Sends** transactions with changes the server hasn't seen, with their
   photo and new attachments.
3. **Fetches** decisions back (status, note, when paid), and adds what the
   server has that the phone doesn't, such as after a reinstall or from
   another phone. Their photos and attachments download when first opened.
4. **Refreshes** what the person may do (approve, mark paid, and so on).

Everything is keyed by the phone's own id, so a run cut short by a dropped
connection is just repeated, without copies. A transaction edited while its
upload was in flight is sent again, so edits aren't lost.

The phone is the source of truth for the figures; the server is the source
of truth for decisions.

## When it syncs

- when the home screen opens;
- after a request is sent;
- when the app comes back to the foreground, or back online;
- when the server sends a push notification (once push is set up);
- on **Sync now** in Settings.

## When sync fails

| Message | Meaning | What to do |
|---|---|---|
| "Can't reach the server. Check your internet connection." | No answer from the server | Check the connection. On a release APK, check that `inets` is in `otp.zip` (see [Building](building.md)); without it every call fails this way. |
| "Please sign in again." | The server refused the sign-in token | Sign in again from Settings |
| A specific message, such as "Amount must be …" | The server rejected the data | Fix the transaction and sync again |
| "Something went wrong on the server. Try again." | Any other answer, such as a 404 or 500 | See below |

"Something went wrong" usually means one of two things:

- **The server is on an older release** and doesn't have the endpoint. You
  can check from a computer:
  ```sh
  curl -s -o /dev/null -w "%{http_code}\n" https://expenses.zippiker.com/api/transactions
  ```
  `401` means the endpoint is there. `404` means the server needs the
  matching release deployed.
- **The server failed** (500). Check the server's logs.

## Push notifications

When push is on (`config :duka_app, :push`), the server tells the phone
when someone else acts: an approver hears about new transactions, and the
sender about decisions and payments. A push also triggers a sync. Push
needs Firebase set up first (`android/app/google-services.json` and the
server's FCM key), so it's off until then.
