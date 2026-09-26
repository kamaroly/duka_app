defmodule DukaApp.App do
  @moduledoc "Application entry point: an offline tracker for KRA eTIMS receipts."

  # Automatically adjusts to system light/dark settings
  use Mob.App, theme: DukaApp.Theme.Adaptive

  require Logger

  alias DukaApp.Screens.{PhoneScreen, ReceiptsScreen}

  @impl Mob.App
  def navigation(_platform) do
    stack(:main, root: ReceiptsScreen, title: "Receipts")
  end

  @impl Mob.App
  def on_start do
    DukaApp.Components.register_all()
    Mob.Composite.register(:header, {DukaApp.Components.Header, :expand})
    Mob.Composite.register(:search_field, {DukaApp.Components.SearchField, :expand})
    Mob.Composite.register(:transaction_item, {DukaApp.Components.TransactionItem, :expand})
    Mob.Composite.register(:transaction_sheet, {DukaApp.Components.TransactionSheet, :expand})

    # Configure BEAM's DNS path so Req / Finch / Mint / `gen_tcp:connect/3`
    # with a hostname work on iOS without per-host setup. Flips the lookup
    # chain from the iOS-broken `:native` (inet_gethost port program) path
    # to `[:file, :dns]` and seeds Google + Cloudflare as fallback
    # nameservers. Override with `nameservers:` if you need to (corporate
    # resolver, Quad9, etc.) — see `Mob.DNS.configure_pure_beam/1`.
    Mob.DNS.configure_pure_beam()

    # Android has no CA store the BEAM can read, so HTTPS (the KRA receipt
    # lookup) verifies against this bundled copy of the Mozilla trust store.
    # See Mob.Certs. The app works offline without it, so a failure only
    # costs the lookup rather than stopping the app from starting.
    with {:error, reason} <- Mob.Certs.load_cacerts(priv_path("cacerts.pem")) do
      Logger.warning("CA certificates not loaded, KRA lookups will fail: #{inspect(reason)}")
    end

    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = DukaApp.Repo.start_link()

    Ecto.Migrator.with_repo(DukaApp.Repo, fn repo ->
      Ecto.Migrator.run(repo, priv_path("repo/migrations"), :up, all: true)
    end)

    # After Repo/Mob.State are up and before the first screen renders, so the
    # user's Light/Dark/System choice is in place from the first frame.
    DukaApp.Appearance.apply_saved()

    # First launch (or after "Switch phone number") asks for a number;
    # otherwise go straight to that number's receipts.
    root = if DukaApp.Accounts.current_profile(), do: ReceiptsScreen, else: PhoneScreen
    Mob.Screen.start_root(root)
    Mob.Dist.ensure_started(node: :"duka_app_android@127.0.0.1", cookie: :mob_secret)
  end

  # Returns the path to a file or directory under priv/ for the current
  # environment.
  #
  # WHY NOT Application.app_dir/2?
  #
  # Application.app_dir(app, "priv/repo/migrations") calls :code.priv_dir(app)
  # under the hood. That works in a normal `mix run` dev environment where the
  # app lives in $OTP_ROOT/lib/APP-VERSION/ebin/.
  #
  # On Android and iOS, Mob deploys .beam files to a flat -pa directory with no
  # versioned lib structure, so :code.priv_dir/1 returns {error, bad_name}.
  # Ecto.Migrator.run/3 silently finds zero migrations and logs "Migrations
  # already up" — tables are never created and any query against them crashes
  # the screen GenServer, making the screen appear frozen.
  #
  # The fix: mob_beam.c/mob_beam.m set MOB_BEAMS_DIR=beams_dir before erl_start.
  # The deployer pushes priv/ into beams_dir/priv/ and runs chmod -R 755 on it
  # (mkdir-as-root creates system:system drwxrwx--x dirs that the app process
  # can traverse but not list, breaking Path.wildcard). Here we read MOB_BEAMS_DIR
  # and pass the explicit path to Ecto.Migrator.run/4.
  defp priv_path(relative) do
    case System.get_env("MOB_BEAMS_DIR") do
      nil -> Application.app_dir(:duka_app, Path.join("priv", relative))
      beams_dir -> Path.join([beams_dir, "priv", relative])
    end
  end
end
