# Chapter 22: Writing a Native Plugin

Previously, Risiti learned to ask for money: refunds of expenses already
saved, payment requests with attachments, and a pill on the home screen to
see only those. Part II's phone app is nearly complete.

Along the way we've used five plugins. Three came from Hex, signed by Mob:
the camera, the fingerprint and the QR scanner. One was Risiti's own,
`mob_ocr`, which in Chapter 19 we copied in and used without opening the
native half. In this chapter we open it. We'll write a plugin from nothing,
every file of it, and follow one call from an Elixir function, through Zig
and JNI into Kotlin, out to an Android system screen, and back to the
Elixir process that asked.

The plugin is `mob_google`: **Sign in with Google**. Part IV needs it, for
signing in to the server. It's also the smallest plugin that does
something real: one call, one native screen, one answer.

By the end of this chapter, you will know:

- What a Mob plugin is made of, and what each file is for.
- How an Elixir function reaches Kotlin: a NIF stub, a Zig NIF, JNI.
- How Kotlin's answer gets back to the right Elixir process.
- How Android's Credential Manager shows the Google account chooser and
  hands back an ID token.
- How the build wires a plugin into the app, and the one build command
  that doesn't.

## Anatomy of a Mob plugin

A Mob plugin is a Mix project. That's the first thing to know, and it
makes the rest less mysterious: it has a `mix.exs`, it compiles like any
dependency, and its Elixir code runs on the phone with the rest of the
app. What makes it a *plugin* is a manifest, `priv/mob_plugin.exs`, that
tells Mob's build what native code to add to the Android app.

Here's `mob_google`, all six files:

```
plugins/mob_google/
├── mix.exs                                   an ordinary Mix project
├── lib/mob_google.ex                         the Elixir API: sign_in/2
├── src/mob_google_nif.erl                    the NIF stub
└── priv/
    ├── mob_plugin.exs                        the manifest
    └── native/
        ├── jni/mob_google_nif.zig            the NIF: BEAM to JNI and back
        └── android/MobGoogleBridge.kt        the Android side
```

And here's how a call travels through them:

```
 Elixir (screen process)          Zig (in the app's .so)           Kotlin (Android)
 ───────────────────────          ──────────────────────           ────────────────
 MobGoogle.sign_in/2
   → :mob_google_nif.google_sign_in(json)
                                  nif_google_sign_in
                                    remembers the caller's pid
                                    calls MobGoogleBridge
                                      .google_sign_in(pid, json) ──→ shows the account chooser
                                                                     … the person picks …
                                  nativeDeliverResult(pid, json) ←── onResult: the ID token
                                    builds {:google, :result, json}
                                    enif_send(pid, …)
 handle_info({:google, :result, json})
```

Three languages, and the boundaries between them are where the work is:

- **Elixir to Zig** is a **NIF**, a *natively implemented function*: a
  function in an Erlang module whose body is C (or Zig, or Rust) compiled
  into the app. You've used NIFs without knowing it; `exqlite`, under our
  database, is one.
- **Zig to Kotlin** is **JNI**, the *Java Native Interface*: the way native
  code calls into the JVM and back. Android's Kotlin runs on ART, Android's
  JVM, so JNI is how anything native talks to it.
- **Kotlin back to Elixir** goes through Zig again, which turns the answer
  into an Erlang message and sends it.

Why Zig, and not C? Mob's own native layer is Zig, and so is `mob_ocr`'s.
Zig compiles C-compatible code, cross-compiles for every Android CPU from
one machine, and catches more mistakes at compile time than C does. If you know C, you can read it. Mob accepts C
NIFs too; its generator, `mix mob.new_plugin <name> --tier 1`, scaffolds
one in C, along with everything needed to publish the plugin on Hex. We'll
write ours by hand, to see every piece.

Let's create the folder and the Mix project:

```elixir
# plugins/mob_google/mix.exs
defmodule MobGoogle.MixProject do
  use Mix.Project

  def project do
    [
      app: :mob_google,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: deps(),
      description: "Sign in with Google (Android Credential Manager) for Mob apps"
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps, do: [{:mob, "~> 0.9"}]
end
```

and add it to the app, the same way as `mob_ocr` in Chapter 19: a path
dependency in `mix.exs`,

```elixir
      # Our own plugin, in plugins/: Sign in with Google.
      {:mob_google, path: "plugins/mob_google"},
```

and activated, and acknowledged as unsigned, in `mob.exs`:

```elixir
config :mob, :plugins, [:mob_camera, :mob_biometric, :mob_scanner, :mob_ocr, :mob_google]

# mob_ocr and mob_google are the app's own plugins (in plugins/), not signed
# with the mob release key. Acknowledge them so the signature check lets them
# build.
config :mob, :acknowledge_unsafe_plugins, [:mob_ocr, :mob_google]
```

### The manifest

```elixir
# plugins/mob_google/priv/mob_plugin.exs
# mob_google — Sign in with Google: an ID token from Android's Credential
# Manager, for the app's server to verify.
%{
  name: :mob_google,
  mob_version: "~> 0.9",
  plugin_spec_version: 1,
  nifs: [
    # Android only: zig NIF bridging to io.mob.google.MobGoogleBridge. On
    # iOS (not built yet) and host builds the Elixir wrapper answers
    # {:google, :error, %{"message" => "not_available"}}.
    %{module: :mob_google_nif, native_dir: "priv/native/jni", lang: :zig, platform: :android}
  ],
  android: %{
    bridge_kt: "priv/native/android/MobGoogleBridge.kt",
    bridge_class: "io.mob.google.MobGoogleBridge",
    gradle_deps: [
      "androidx.credentials:credentials:1.3.0",
      # Lets Credential Manager use Google Play services on Android 13 and
      # older.
      "androidx.credentials:credentials-play-services-auth:1.3.0",
      "com.google.android.libraries.identity.googleid:googleid:1.1.1"
    ]
  }
}
```

It's a plain map, read at build time. Three parts:

- **`nifs`**: one NIF module, `:mob_google_nif`, written in Zig, whose
  source is in `priv/native/jni`, built for Android only.
- **`android.bridge_kt` and `bridge_class`**: a Kotlin file to copy into
  the Android app, and the class in it that Mob should register at start-up.
- **`android.gradle_deps`**: the Android libraries that class needs. Gradle
  is Android's build tool, the Mix of the Android world, and these lines
  end up in the app's `build.gradle`.

That's the whole contract. Mob reads the manifest; everything else is
ordinary code.

## The Elixir side

Start where the screens start. The API is one function that asks and a
message that answers, the shape every plugin call in this book has had:

```elixir
# plugins/mob_google/lib/mob_google.ex
defmodule MobGoogle do
  @moduledoc """
  Sign in with Google on Android: shows the Google account chooser (Android
  Credential Manager) and hands back an ID token for the app's server to
  verify.

      socket = MobGoogle.sign_in(socket, server_client_id: "123-abc.apps.googleusercontent.com")

      def handle_info({:google, :result, json}, socket)
      def handle_info({:google, :error, json}, socket)

  `server_client_id` is the *Web* OAuth client ID of the server's Google
  Cloud project: the token is issued for it (its `aud`), so the server can
  check it was meant for it. The app itself must also be registered there
  as an Android client (its package name and signing certificate's SHA-1),
  or Google refuses.

  Decode the payload with `decode/1`:

    * result — `%{"id_token" => jwt, "email" => email, "name" => name | nil}`
    * error — `%{"message" => reason}`: `"cancelled"` (the person closed the
      chooser), `"no_accounts"` (no Google account on the phone),
      `"not_available"` (not Android), or what Android said.

  The message arrives at the process that called `sign_in/2` (the screen).
  """

  @doc "Shows the Google account chooser. See the module docs for the reply."
  @spec sign_in(socket, keyword()) :: socket when socket: term()
  def sign_in(socket, opts) do
    args = :json.encode(%{"server_client_id" => Keyword.fetch!(opts, :server_client_id)})

    try do
      :mob_google_nif.google_sign_in(IO.iodata_to_binary(args))
    rescue
      # No native implementation on this platform (iOS for now, or a host
      # dev build). Answer the same way a native failure would.
      error in ErlangError ->
        if error.original == :nif_not_loaded do
          send(self(), {:google, :error, ~s({"message":"not_available"})})
        else
          reraise error, __STACKTRACE__
        end
    end

    socket
  end

  @doc "Decodes the JSON payload of a `{:google, _, json}` message (JSON null becomes nil)."
  @spec decode(binary()) :: map()
  def decode(json) when is_binary(json) do
    {decoded, :ok, ""} = :json.decode(json, :ok, %{null: nil})
    decoded
  end
end
```

If this looks like `MobOcr` from Chapter 19, that's on purpose. The
pattern is worth repeating until it's boring:

- **Arguments go in as one JSON string.** The native side is two languages
  away. One string is the simplest thing that survives both crossings, and
  it means adding an option later changes the JSON, not the signature of
  three functions in three languages.
- **The function returns at once.** The account chooser may be on screen
  for a minute while the person decides. A NIF must never block that long:
  it runs on one of the BEAM's schedulers, and a scheduler stuck in native
  code can't run anything else. So the NIF only *starts* the work, and the
  answer comes later as a message.
- **The answer goes to `self()`**: the process that called, which is the
  screen. That's what makes it a `handle_info/2` in the screen, like every
  other answer from the phone.
- **No native side means an ordinary error.** On iOS, or under `mix test`,
  the NIF isn't there, and calling it raises `:nif_not_loaded`. The plugin
  turns that into the same `{:google, :error, ...}` message a real failure
  would send. The screen handles one message, not two kinds of failure.

### The NIF stub

Here's how `:mob_google_nif.google_sign_in/1` exists to be called at all:

```erlang
%% plugins/mob_google/src/mob_google_nif.erl
%% mob_google_nif — Erlang NIF stub for the mob_google plugin.
%%
%% Android: priv/native/jni/mob_google_nif.zig bridging to the Kotlin
%% io.mob.google.MobGoogleBridge (Credential Manager, Sign in with Google).
%% There is no iOS implementation yet, and on a host dev build nothing is
%% linked, so on_load tolerates the failure and calls raise nif_not_loaded
%% (MobGoogle turns that into a {:google, :error, ...} message).
-module(mob_google_nif).
-export([google_sign_in/1]).
-on_load(init/0).

init() ->
    case erlang:load_nif("mob_google_nif", 0) of
        ok -> ok;
        {error, _} -> ok
    end.

google_sign_in(_ArgsJson) ->
    erlang:nif_error(nif_not_loaded).
```

This is how every NIF works, Mob or not. The Erlang module declares the
function with a placeholder body. When the module loads, `-on_load` runs
`init/0`, which calls `erlang:load_nif/2`. If the native library is found,
the BEAM *replaces* the placeholder with the native function. If it isn't,
the placeholder stays, and calling it raises `nif_not_loaded`.

Note `{error, _} -> ok`. Normally `init/0` would return the error and the
module would refuse to load. Here, a missing NIF is expected on your
computer and on iOS, so the module loads anyway and the Elixir wrapper
handles the error. You've seen the other choice already: the warning
`mix test` prints about `mob_nif.so` comes from Mob's own NIF, whose
`on_load` does return the error. Ours stays quiet, because for us it isn't
news.

It's an Erlang file in `src/`, because Mix compiles `.erl` files from
`src/` for you, with no configuration. You could write the stub in Elixir;
Erlang is the convention for NIF stubs, and it's eight lines.

On the phone, `"mob_google_nif"` isn't a separate file to load. We'll see
why when we wire it into the build.

## The Zig NIF

Now the native side. Create `priv/native/jni/mob_google_nif.zig`. It's
146 lines, and it does three things: register with the Kotlin class, start
a sign-in when Elixir calls, and deliver the answer when Kotlin calls
back. We'll read it in that order. The complete file is in
`code/22/plugins/mob_google/priv/native/jni/`.

```zig
const std = @import("std");
const erts = @import("erts");
const jni = @import("jni");

// mob-core exports (linked into the same .so).
extern fn get_jenv(attached: *c_int) ?*jni.JNIEnv;
extern var g_jvm: ?*jni.JavaVM;

var g_google_sign_in: jni.JMethodID = null;
var g_google_cls: jni.JClass = null;
```

`erts` and `jni` are modules Mob's build provides: Zig bindings for the
Erlang NIF API (`enif_*`, from `erl_nif.h`) and for JNI. `get_jenv` and
`g_jvm` come from Mob's own native code, linked into the same library;
they give us a handle on the JVM from any thread.

The two globals will hold the Kotlin class and its method, found once and
kept.

### Registering

```zig
export fn Java_io_mob_google_MobGoogleBridge_nativeRegister(jenv: *jni.JNIEnv, cls: jni.JClass) callconv(.c) void {
    g_google_cls = jni.newGlobalRef(jenv, cls);
    if (g_google_cls == null) return;
    g_google_sign_in = jni.getStaticMethodID(jenv, cls, "google_sign_in", "(JLjava/lang/String;)V");
}
```

That long name is how JNI finds native functions. When Kotlin calls a
method declared `external` (we'll write it below), the JVM looks in the
app's native libraries for a symbol named `Java_`, then the package with
dots as underscores, then the class, then the method:
`Java_io_mob_google_MobGoogleBridge_nativeRegister`. `export` makes the
function visible under exactly that name, and `callconv(.c)` gives it C's
calling convention, which is what JNI calls.

Kotlin calls this once, at start-up. It hands us its class, and we keep
two things:

- **A global reference to the class.** JNI references are *local* by
  default: they're only valid until this call returns. `newGlobalRef`
  keeps the class reachable for the life of the app.
- **The method ID of `google_sign_in`**, looked up by name and by its
  *JNI signature*, `(JLjava/lang/String;)V`. Read it as: takes a `J` (a
  Java `long`) and an `L...;` (a `java.lang.String`), and returns `V`
  (void). A wrong signature here doesn't fail to compile; it fails to find
  the method at run time. It's the one line in this file to check twice.

### Starting a sign-in

When Elixir calls `:mob_google_nif.google_sign_in(json)`, this runs:

```zig
// The argument JSON (the server client id) is copied into a heap buffer;
// newStringUTF copies synchronously, so the buffer is freed right after.
fn nif_google_sign_in(env: ?*erts.ErlNifEnv, argc: c_int, argv: [*]const erts.ERL_NIF_TERM) callconv(.c) erts.ERL_NIF_TERM {
    _ = argc;
    var bin: erts.ErlNifBinary = undefined;
    if (erts.enif_inspect_binary(env, argv[0], &bin) == 0 and
        erts.enif_inspect_iolist_as_binary(env, argv[0], &bin) == 0) return erts.badarg(env);
    if (g_google_cls == null or g_google_sign_in == null) return erts.atom(env, "error");

    const buf = std.heap.c_allocator.allocSentinel(u8, bin.size, 0) catch return erts.atom(env, "error");
    defer std.heap.c_allocator.free(buf);
    @memcpy(buf[0..bin.size], bin.data[0..bin.size]);

    var pid: erts.ErlNifPid = undefined;
    _ = erts.enif_self(env, &pid);

    var attached: c_int = 0;
    const jenv = get_jenv(&attached) orelse return erts.atom(env, "error");
    const jarg = jni.newStringUTF(jenv, buf.ptr);
    jenv.*.CallStaticVoidMethod.?(jenv, g_google_cls, g_google_sign_in, pidToJlong(pid), jarg);
    if (jarg != null) jni.deleteLocalRef(jenv, jarg);
    detachIfAttached(attached);
    return erts.ok(env);
}
```

Step by step:

1. **Read the argument.** `argv[0]` is the Erlang term Elixir passed, our
   JSON binary. `enif_inspect_binary` gives us a pointer to its bytes and
   its length, without copying. If it isn't a binary or iolist, the NIF
   returns `badarg`, which raises `ArgumentError` in Elixir, as calling any
   BIF with the wrong type would.
2. **Copy it, with a zero on the end.** Java wants a C string, which ends
   in a zero byte; an Erlang binary doesn't. `allocSentinel` allocates the
   size plus a terminating `0`, and `defer` frees it when the function
   returns, whichever way it returns. It's like `try ... after` for memory.
3. **Remember who asked.** `enif_self` gives the pid of the process
   calling the NIF: the screen. That pid is how the answer will find its
   way back.
4. **Call Kotlin.** `get_jenv` gets a JNI environment for this thread,
   attaching it to the JVM if it wasn't already. `newStringUTF` makes a
   Java string from our C string (copying it, which is why the buffer can
   be freed). `CallStaticVoidMethod` calls `google_sign_in(pid, json)` on
   the Kotlin object. Then we tidy up: delete the local reference, detach
   the thread if we attached it.
5. **Return `:ok` straight away.** The chooser hasn't even appeared yet.

The pid crosses into Kotlin as a Java `long`:

```zig
inline fn pidToJlong(pid: erts.ErlNifPid) jni.JLong {
    if (@sizeOf(erts.ERL_NIF_TERM) == @sizeOf(jni.JLong)) {
        return @bitCast(pid.pid);
    }
    return @intCast(pid.pid);
}
```

An `ErlNifPid` holds the pid as a term, a machine word. On a 64-bit phone
that's exactly a `long`, and `@bitCast` reinterprets the bits without
changing them. Kotlin never looks inside it; it just hands it back when
it's done. Think of it as a ticket.

### Delivering the answer

When the person has chosen an account, Kotlin calls one of two exported
functions:

```zig
export fn Java_io_mob_google_MobGoogleBridge_nativeDeliverResult(
    jenv: *jni.JNIEnv,
    cls: jni.JClass,
    pid_long: jni.JLong,
    json: jni.JString,
) callconv(.c) void {
    _ = cls;
    deliver(jenv, pid_long, "result", json);
}
```

and `nativeDeliverError`, the same with `"error"`. Both use `deliver`:

```zig
// Sends {:google, <sub>, json_binary} to `pid_long`.
fn deliver(jenv: *jni.JNIEnv, pid_long: jni.JLong, comptime sub: [:0]const u8, json: jni.JString) void {
    var pid = pidFromLong(pid_long);
    const env = erts.enif_alloc_env() orelse return;
    defer erts.enif_free_env(env);

    const json_c = jenv.*.GetStringUTFChars.?(jenv, json, null) orelse return;
    defer jenv.*.ReleaseStringUTFChars.?(jenv, json, json_c);
    const len = std.mem.len(json_c);

    var bin: erts.ErlNifBinary = undefined;
    if (erts.enif_alloc_binary(len, &bin) == 0) return;
    @memcpy(bin.data[0..len], json_c[0..len]);

    const msg = erts.makeTuple(env, .{
        erts.atom(env, "google"),
        erts.atom(env, sub),
        erts.enif_make_binary(env, &bin),
    });
    _ = erts.enif_send(null, &pid, env, msg);
}
```

This runs on one of Android's threads, not inside any BEAM process. So
there's no NIF environment to build terms in, and it makes its own:
`enif_alloc_env` gives a *process-independent environment*, a scratch
space for building terms outside a process. Then:

1. Get the Java string's bytes (`GetStringUTFChars`), and release them on
   the way out.
2. Copy them into a new Erlang binary.
3. Build the tuple `{:google, :result, json}`.
4. `enif_send` it to the pid, the ticket Kotlin handed back.

`enif_send` copies the message into the screen's mailbox, so the scratch
environment can be freed at once. From the screen's point of view, a
message simply arrives, exactly like one from another Elixir process.

`comptime sub` means the atom's name is known when the code is compiled,
so Zig makes two copies of `deliver`, one for `"result"` and one for
`"error"`. It's a small thing, and very Zig.

### The NIF table entry

Last, the boilerplate that makes this file a NIF library: the list of
functions, and the entry point the BEAM looks for.

```zig
const nif_funcs = [_]erts.ErlNifFunc{
    .{ .name = "google_sign_in", .arity = 1, .fptr = nif_google_sign_in, .flags = 0 },
};

var nif_entry: erts.ErlNifEntry = .{
    .major = erts.ERL_NIF_MAJOR_VERSION,
    .minor = erts.ERL_NIF_MINOR_VERSION,
    .name = "mob_google_nif",
    .num_of_funcs = nif_funcs.len,
    .funcs = &nif_funcs,
    .load = nifLoad,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = erts.ERL_NIF_VM_VARIANT,
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = erts.SIZEOF_ErlNifResourceTypeInit,
    .min_erts = erts.ERL_NIF_MIN_ERTS_VERSION,
};

pub export fn mob_google_nif_nif_init() callconv(.c) *erts.ErlNifEntry {
    return &nif_entry;
}
```

`nif_funcs` maps the Erlang name and arity, `google_sign_in/1`, to the Zig
function. `.flags = 0` says it's an ordinary NIF that returns quickly,
which it does: all the slow work happens in Kotlin. The `.name` must match
the Erlang module, `mob_google_nif`, and the init function must be called
`<module>_nif_init`. Those names are how the pieces find each other, so
copy them exactly.

## The Kotlin bridge

Now the Android side: `priv/native/android/MobGoogleBridge.kt`. Its job is
to show Google's account chooser and turn the result into JSON.

Android's modern way to sign in is the **Credential Manager**. It's one
API for passwords, passkeys and "Sign in with Google", and on recent
Android it shows a system screen, so every app's sign-in looks the same and
the app never sees anything but the result. For Google, the result is an
**ID token**: a JWT, signed by Google, that says "this is
wanjiru@example.com, and this token was issued for *your* app". Risiti's
server will check that signature and that audience in Part IV. The phone
never has to trust itself.

```kotlin
package io.mob.google

import android.app.Activity
import android.os.CancellationSignal
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

object MobGoogleBridge : io.mob.plugin.MobActivityAware {
    private var activityRef: WeakReference<Activity>? = null

    // Callbacks run here, off the main thread.
    private val worker = Executors.newSingleThreadExecutor()

    @JvmStatic external fun nativeRegister()

    @JvmStatic external fun nativeDeliverResult(pid: Long, json: String)

    @JvmStatic external fun nativeDeliverError(pid: Long, json: String)

    @JvmStatic fun register() = nativeRegister()

    override fun setActivity(activity: Activity) {
        activityRef = WeakReference(activity)
    }
```

An `object` in Kotlin is a singleton: there's exactly one
`MobGoogleBridge`, which suits a bridge.

The three `external fun`s are the Zig functions we exported. `external`
says "the body is native", and the JVM finds each one by the
`Java_io_mob_google_MobGoogleBridge_...` name. `@JvmStatic` makes them
static methods on the class, which is what the Zig side expects: it was
handed the *class*, not an instance.

`register()` is called once at start-up, and calls `nativeRegister()`, the
Zig function that keeps the class and finds `google_sign_in`. So the
handshake goes Kotlin → Zig first, and only then can Zig call Kotlin.

`MobActivityAware` is an interface from Mob: implement it, and Mob calls
`setActivity` with the app's Activity at start-up. An *Activity* is
Android's name for a screen of an app; a Mob app is one Activity, with
Mob drawing everything inside it. The account chooser needs it, to know
which app it's showing over. The bridge keeps it in a `WeakReference`, so
if Android destroys the Activity (it does, on rotation, for instance), the
bridge doesn't keep a dead one alive.

### Showing the chooser

```kotlin
    // Signature matches the zig NIF call: (JLjava/lang/String;)V.
    @JvmStatic
    fun google_sign_in(pid: Long, argsJson: String) {
        val activity = activityRef?.get()
        if (activity == null) {
            error(pid, "no_activity")
            return
        }

        val serverClientId =
            try {
                JSONObject(argsJson).getString("server_client_id")
            } catch (e: Exception) {
                error(pid, "bad_arguments")
                return
            }

        val request =
            GetCredentialRequest.Builder()
                .addCredentialOption(GetSignInWithGoogleOption.Builder(serverClientId).build())
                .build()

        // The chooser is UI: it has to start from the main thread.
        activity.runOnUiThread {
            CredentialManager.create(activity).getCredentialAsync(
                activity,
                request,
                CancellationSignal(),
                worker,
                object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                    override fun onResult(result: GetCredentialResponse) = deliver(pid, result)

                    override fun onError(e: GetCredentialException) =
                        error(
                            pid,
                            when (e) {
                                is GetCredentialCancellationException -> "cancelled"
                                is NoCredentialException -> "no_accounts"
                                else -> e.message ?: e.type
                            }
                        )
                }
            )
        }
    }
```

This is the method the Zig NIF called. It's on whatever thread the BEAM
scheduler was on, which is not Android's main thread, and that matters:
Android only lets the main thread (the *UI thread*) start anything on
screen. `runOnUiThread` hands the block to the main thread and returns at
once, so the NIF returns at once too, and the scheduler is free.

`GetSignInWithGoogleOption` is the "Sign in with Google" button flavour of
the request: it always shows the account chooser, which is right for a
button the person tapped. (There's another option, for signing in
silently when an app opens; that's not this.)

`getCredentialAsync` shows the chooser and calls back on `worker`, our
own single thread, when the person is done. Every way it can end becomes
one call to `deliver` or `error`, so every request gets exactly one
answer. That's the contract the Elixir side relies on: a screen waiting for
`{:google, ...}` will get it.

The errors are named for what they mean to a screen: `"cancelled"` when
the person closed the chooser (not an error worth a red message),
`"no_accounts"` when there's no Google account on the phone (worth telling
them), and otherwise whatever Android said.

### The answer

```kotlin
    private fun deliver(pid: Long, result: GetCredentialResponse) {
        val credential = result.credential

        if (credential is CustomCredential &&
            credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            try {
                val google = GoogleIdTokenCredential.createFrom(credential.data)
                val json =
                    JSONObject()
                        .put("id_token", google.idToken)
                        .put("email", google.id)
                        .put("name", google.displayName ?: JSONObject.NULL)
                nativeDeliverResult(pid, json.toString())
            } catch (e: Exception) {
                error(pid, e.message ?: "unreadable_credential")
            }
        } else {
            error(pid, "unexpected_credential")
        }
    }

    private fun error(pid: Long, message: String) {
        nativeDeliverError(pid, JSONObject().put("message", message).toString())
    }
}
```

Credential Manager can return several kinds of credential; we only asked
for one, so anything else is an error. The Google one comes as a
`CustomCredential` with Google's type, and `GoogleIdTokenCredential`
unpacks it: the ID token, the email (`id`), and a display name if the
account has one. Note `JSONObject.NULL` for a missing name. That's what
becomes `nil` on the Elixir side, through `decode/1`'s `null: nil`.

## Back to Elixir

Follow the answer home. Kotlin calls `nativeDeliverResult(pid, json)`. The
JVM finds `Java_io_mob_google_MobGoogleBridge_nativeDeliverResult` in the
app's library and calls it. Zig turns the pid back into an `ErlNifPid`,
builds `{:google, :result, json}`, and sends it. The screen that called
`MobGoogle.sign_in/2`, possibly a minute ago, gets a message:

```elixir
  def handle_info({:google, :result, json}, socket) do
    %{"id_token" => token, "email" => email} = MobGoogle.decode(json)
    # Part IV: send the token to the server, which checks it with Google.
    ...
  end
```

In between, the screen went on handling taps and renders as normal. Nothing
waited. That's the whole point of the shape.

For Risiti, the call goes through `Native` like every other device call,
so tests can stand in for it:

```elixir
  @doc """
  Shows the Google account chooser. Replies `{:google, :result, json}` or
  `{:google, :error, json}` (see `MobGoogle`).
  """
  def google_sign_in(socket, server_client_id),
    do:
      call(
        socket,
        :google_sign_in,
        [server_client_id],
        &MobGoogle.sign_in(&1, server_client_id: server_client_id)
      )
```

and the client ID it needs goes in `config/config.exs`, empty until the
server exists:

```elixir
# Sign in with Google (see MobGoogle): the *Web* OAuth client id from the
# server's Google Cloud project. Part IV sets it, with the server.
config :risiti_app, :google_client_id, nil
```

No screen offers Google sign-in yet. That's Chapter 30, when there's a
server to sign in to.

## Wiring it into the build

We've written six files, and none of them is in the Android app yet. The
Kotlin file is in our plugin's `priv/`, not in `android/`. Gradle has never
heard of Credential Manager. And the BEAM on the phone has no idea where
`mob_google_nif` lives. Connecting them is the native build's job:

```
mix mob.deploy --native --device YOUR_DEVICE_ID
```

Before compiling anything, it reads every activated plugin's manifest and
generates four things:

1. **The bridge, copied in.** `MobGoogleBridge.kt` is copied to
   `android/app/src/main/java/io/mob/google/`, where Gradle compiles it
   with the app.
2. **The Gradle dependencies.** Between two marker comments in
   `android/app/build.gradle`, it writes every plugin's `gradle_deps`:

   ```groovy
       // mob:plugin-deps BEGIN (managed — regenerated each build; do not edit)
       implementation "androidx.biometric:biometric:1.1.0"
       implementation "com.google.mlkit:barcode-scanning:17.3.0"
       implementation "com.google.mlkit:text-recognition:16.0.1"
       implementation "androidx.credentials:credentials:1.3.0"
       implementation "androidx.credentials:credentials-play-services-auth:1.3.0"
       implementation "com.google.android.libraries.identity.googleid:googleid:1.1.1"
       // mob:plugin-deps END
   ```

3. **The bootstrap.** `MobPluginBootstrap.kt` is a generated Kotlin file
   that `MainActivity` calls when the app starts. For each plugin, it calls
   the bridge's `register()` and hands it the Activity:

   ```kotlin
           io.mob.google.MobGoogleBridge.register()
           handOff(io.mob.google.MobGoogleBridge, activity)
   ```

   That's where `nativeRegister` gets called, and where `setActivity`
   comes from.
4. **The static NIF table.** This one needs a little background. On a
   server, `erlang:load_nif/2` loads a NIF from a shared library file
   (`.so`) on disk. On a phone, that doesn't work well: Android loads
   native libraries in a way that hides the BEAM's own `enif_*` functions
   from them, and the App Store doesn't accept apps that load libraries of
their own at run time.
   So Mob links every NIF *statically*, into the one native library that
   is the app, and gives the BEAM a table of them. The build regenerates
   that table, `priv/generated/driver_tab_android.zig`, with a line per
   NIF:

   ```zig
   extern fn mob_google_nif_nif_init() callconv(.c) ?*anyopaque;
   ```

   ```zig
       .{ .nif_init = mob_google_nif_nif_init, .is_builtin = 0, .nif_mod = THE_NON_VALUE, .entry = null },
   ```

   When `mob_google_nif`'s `-on_load` calls `erlang:load_nif("mob_google_nif", 0)`,
   the BEAM finds the name in the table, calls `mob_google_nif_nif_init()`,
   and gets our `nif_entry`. That's why the names had to match exactly: the
   module name in the stub, `.name` in the entry, and the `_nif_init`
   function.

Then it compiles our Zig file into the app's library, alongside Mob's own
NIFs, and builds the APK with Gradle.

All four are derived from the manifests, every time. None of them is
something to edit by hand, and the files say so.

### The release build doesn't

Here's the trap, and it caught Risiti when `mob_google` was added. Part V
builds a release APK, the one
testers install, with `mix mob.release --android`. That command packages
the Erlang runtime and your compiled code, but it does **not** regenerate
the plugin wiring. It uses whatever the last native build left in
`android/`.

So after adding or changing a plugin, run the native debug build first,
then the release:

```
mix mob.deploy --native --device YOUR_DEVICE_ID
mix mob.release --android
```

Forget, and the release APK has your new Elixir code calling a NIF that
was never linked: `nif_not_loaded` on a phone, and a sign-in button that
does nothing. We'll come back to this in Chapter 33.

<!-- KAMARO: if you remember the day this bit you (it was adding mob_google, 2026-09-26), a sentence on how you found out would fit here. -->

## Run it

There's no screen for this yet, but there doesn't need to be. After the
native build, open Risiti on the phone and connect from your computer with
`mix mob.connect`. Then, in IEx, start a process on the phone that asks and
waits:

```elixir
iex> node = hd(Node.list())
iex> ask = fn ->
...>   MobGoogle.sign_in(nil, server_client_id: "123-abc.apps.googleusercontent.com")
...>   receive do
...>     {:google, kind, json} -> {kind, MobGoogle.decode(json)}
...>   after
...>     60_000 -> :timeout
...>   end
...> end
iex> :rpc.call(node, Kernel, :apply, [ask, []], 70_000)
```

The anonymous function travels to the phone and runs in a process there,
so that process is the `self()` the NIF remembers, and the answer comes
back to it. (A function typed into IEx is interpreted by `erl_eval`, which
the phone has too, so it can run there even though no module defines it.)

<!-- RUN: result of the IEx call above on the A53, with the made-up client id. -->

With a made-up client ID, Google refuses, and you'll see its answer arrive
in Elixir:

```elixir
{:error, %{"message" => "..."}}
```

That message is the whole round trip working: Elixir to Zig to Kotlin to a
Google system service, and back. To get a real ID token, Google has to
know your app. In the Google Cloud console you create two OAuth clients in
one project:

- a **Web** client, whose ID is the `server_client_id` (it's the audience
  of the token, the thing your server will check), and
- an **Android** client, with your app's package name and the SHA-1
  fingerprint of the key that signs it. Google only issues tokens to apps
  it can identify that way.

We'll set both up in Part III, with the server that checks the token.

## Testing it

The native code can't run under `mix test`: there's no JVM, no Android,
no Google. What can be tested is everything around it.

The plugin's own fallback, in `test/mob_google_test.exs`:

```elixir
defmodule MobGoogleTest do
  use ExUnit.Case, async: true

  # Under mix test the NIF isn't loaded (it's built for the phone), so the
  # plugin answers the way it does on any platform without one.
  test "with no native side, sign_in answers with not_available" do
    assert MobGoogle.sign_in(:socket, server_client_id: "123-abc.apps.googleusercontent.com") ==
             :socket

    assert_received {:google, :error, json}
    assert MobGoogle.decode(json) == %{"message" => "not_available"}
  end

  test "decode turns JSON null into nil" do
    assert MobGoogle.decode(~s({"id_token":"x","email":"a@b.c","name":null})) ==
             %{"id_token" => "x", "email" => "a@b.c", "name" => nil}
  end

  test "the server client id is required" do
    assert_raise KeyError, fn -> MobGoogle.sign_in(:socket, []) end
  end
end
```

The first test is worth more than it looks. It runs the real
`mob_google_nif` stub, gets the real `nif_not_loaded`, and checks the
plugin turns it into the message a screen understands. It's the same path
an iPhone takes today.

And the screens, when Chapter 30 gives them a Google button, will test
against `Native.google_sign_in/2`, which under `mix test` sends
`{:native, :google_sign_in, [client_id]}`, exactly as the camera and the
KRA lookup do.

The native half is tested the only way it can be: on a phone, with the
IEx call above.

```
mix test
```

```
21 doctests, 134 tests, 0 failures
```

## What we have so far

- `mob_google`, a plugin of our own, from nothing: a Mix project with a
  manifest.
- The Elixir side: one function that returns at once, and a message that
  answers later.
- A NIF stub in Erlang, and a NIF in Zig that remembers who asked, calls
  Kotlin through JNI, and sends the answer back with `enif_send`.
- A Kotlin bridge that shows the Google account chooser through Credential
  Manager and turns the result into JSON.
- How the native build wires a plugin in: the bridge, Gradle, the
  bootstrap, the static NIF table. And that `mob.release` doesn't.

The code at the end of this chapter is in `code/22/`.

There's one chapter left in Part II. Risiti can collect a month of
expenses, claims and receipts; in the next chapter it hands them to an
accountant, as a PDF made on the phone.
