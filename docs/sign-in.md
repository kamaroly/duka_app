# Signing in and signing up

The sign-in screen (`PhoneScreen`) connects the book on this phone to the
person's account on the server. Several people can keep separate books on a
shared phone, each under their own phone number (Settings → **Switch phone
number**; nothing is deleted).

## With a phone number

1. Enter a Kenyan mobile number. The server texts a 6-digit code.
2. Enter the code.
   - A number the server knows (someone a manager added, or who signed up
     before) goes straight in.
   - A new number is asked for a name, then a choice:
     - **Just me:** a free personal book, for your own expenses. It never
       expires. There's no one to approve, so no refunds or payment
       requests.
     - **My business:** a team with the name you give, on a free trial. You
       own it and can add people from the web app.

The server allows 5 codes an hour per number.

## With Google

**Continue with Google** shows Google's account chooser.

- Someone the server knows, by a linked Google account or by the same email,
  goes straight in.
- Someone new signs up as with a new number.
- The book on the phone is still kept under a phone number, so Google users
  also give their M-Pesa number. It stays on the phone, for refunds. The
  server only trusts numbers confirmed by SMS.

The button only shows once Google is set up.

### Setting up Google

| Setting | Where |
|---|---|
| `config :duka_app, :google_client_id` | `config/config.exs`: the **Web** OAuth client id, the same one as the server's `GOOGLE_CLIENT_IDS`. `nil` hides the button. |
| Android OAuth client | The same Google Cloud project: package `com.example.duka_app`, with the SHA-1 of **both** the debug and the release signing keys |

To get the release key's SHA-1:

```sh
keytool -list -v -keystore android/upload_jks.keystore
```

Google sign-in uses the `plugins/mob_google` plugin (Android's Credential
Manager). See [Building](building.md) for enabling it.

## Signing out

Settings → **Disconnect** stops syncing, forgets the sign-in on this phone,
and stops push notifications to it. The book stays on the phone and can
connect again later.
