# Push notifications

The server tells a phone when someone else acts on a transaction. The phone
uses `mob_notify` (`RisitiApp.Push`); the server uses `mob_push`
(`Risiti.PushWorker`). Push is **off** until Firebase is set up (see
[Turning it on](#turning-it-on)).

## Who gets what

| When | Who hears | Title | Tapping it opens |
|---|---|---|---|
| A refund or payment request is sent | Team members who may approve, except the sender | "New payment request to approve" | Approvals |
| A decided one is changed and needs approving again | The same | "Payment request changed, approve again" | Approvals |
| It's approved or rejected | The person who sent it, unless they decided it themselves | "Your refund was approved" (with the approver's note) | The home list |
| It's paid | The same | "Your payment request has been paid" | The home list |

The body says who sent it (for approvers), the vendor and the amount, e.g.
"Jane · Java House · KES 1,200".

- The server sends a push only after the change is saved, and never sends
  the same one twice.
- Every push is also kept on the web's Notifications page, whether or not
  the person has a phone.
- A push makes the app sync, so its lists catch up without a tap. An open
  Approvals screen reloads.
- With the app closed, the push shows in the notification tray. With it
  open, it shows as a toast.

## On the phone

1. Once the book is connected to a team, the home screen asks for the
   notification permission (Android 13+).
2. If it's granted, the phone gets a token from Firebase and sends it to the
   server (`PUT /api/devices`). It's sent again only if the token or the
   sign-in changes, and after the next sync if the first try failed.
3. Disconnecting from the team tells the server to forget the token
   (`DELETE /api/devices/:token`).

A personal book, or one that isn't connected, never asks.

## Turning it on

You need a Firebase project. It can be the Google Cloud project that holds
the Google sign-in clients.

### 1. The app

1. In the [Firebase console](https://console.firebase.google.com), add an
   **Android app** with package **`com.example.risiti_app`**.
2. Download its `google-services.json` into `android/app/`. The Gradle
   build applies the Google Services plugin only when this file is there.
   It isn't secret, but keep it out of git with the rest of the local setup
   if you prefer.
3. In `config/config.exs`, set:
   ```elixir
   config :risiti_app, :push, true
   ```
4. Build a new release with a higher `versionCode` (see
   [Building for testers](building.md)).

### 2. The server

1. In Firebase: **Project settings → Service accounts → Generate new
   private key**. This downloads a JSON key. It **is** secret.
2. Copy it to the production server, readable by the deploy user only:
   ```sh
   scp -P <port> firebase-key.json <user>@<server>:/opt/risiti_expenses_secrets/firebase-key.json
   ssh -p <port> <user>@<server> chmod 600 /opt/risiti_expenses_secrets/firebase-key.json
   ```
3. In the server's `automate/deploy_risiti.sh`, in `export_env_vars`:
   ```sh
   export FCM_PROJECT_ID="<firebase project id>"
   export FCM_SERVICE_ACCOUNT_KEY="/opt/risiti_expenses_secrets/firebase-key.json"
   ```
   `FCM_SERVICE_ACCOUNT_KEY` is the **path** to the key file, not its
   contents.
4. Deploy the server (push to `expenses-backend`). Without
   `FCM_PROJECT_ID`, the server only logs pushes.

Deploy the server before handing out the app.

### iPhone

iOS would also need an APNs key (`APNS_*` on the server, see the server's
`docs/installation.md`). The app only ships for Android, so it isn't set up.

## Checking it works

1. Install the new APK on two phones: one person who sends, one who can
   approve. Sign both in to the same team and allow notifications.
2. Send a payment request from the first phone. The approver's phone should
   show "New payment request to approve".
3. Approve it on the second phone or the web. The first phone should show
   "Your payment request was approved".

If nothing arrives:

- **Approver sees nothing:** check that they have the approve permission in
  the team, and that they didn't send it themselves.
- **No one gets anything:** check the server log. "Push to android … —"
  lines mean `FCM_PROJECT_ID` isn't set, so pushes are only logged. "Push to
  android device failed" gives FCM's reason.
- **The app never asked for permission:** check that `:push` is `true` in
  the build and that the book is connected to a team.
- **Notifications are blocked:** allow them in Android's settings for the
  app.
