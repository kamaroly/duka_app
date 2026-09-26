defmodule DukaApp.Screens.PushFlowTest do
  # Staying in step with the server: push notifications, syncing when the app
  # comes back, and the synced mark on each item.
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, FakeServer, Push, Repo, Transactions}
  alias DukaApp.Components.SyncBadge
  alias DukaApp.Screens.{ApprovalsScreen, ReceiptsScreen, SettingsScreen}

  @manager %{"approve" => true, "mark_paid" => true}

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)
    Mob.State.delete(:push_token)
    Mob.State.delete(:push_token_sent)
    FakeServer.stub(fn _ -> {200, %{"ok" => true}} end)
    :ok
  end

  defp connect(permissions \\ %{}) do
    {:ok, profile} =
      Accounts.connect("0712345678", %{
        "token" => "tok-1",
        "user" => %{"id" => "u-1", "team" => "acme", "permissions" => permissions}
      })

    profile
  end

  defp nav_action(view), do: view.socket.__mob__[:nav_action]

  defp drain_native do
    receive do
      {:native, _name, _args} -> drain_native()
    after
      0 -> :ok
    end
  end

  test "a connected receipt book asks to notify, registers, and sends the token once" do
    connect()
    view = mount_screen(ReceiptsScreen)

    assert_received {:native, :watch_device, []}
    assert_received {:native, :request_notifications, []}

    view = render_info(view, {:permission, :notifications, :granted})
    assert_received {:native, :register_push, []}

    view = render_info(view, {:push_token, :android, "fcm-token"})

    assert_received {:http, :put, "/api/devices",
                     %{body: {:json, %{platform: :android, token: "fcm-token"}}}}

    # The same token again (say, the screen remounted) isn't resent.
    render_info(view, {:push_token, :android, "fcm-token"})
    refute_received {:http, :put, "/api/devices", _}
  end

  test "a token that couldn't be sent goes after the next sync" do
    profile = connect()
    FakeServer.stub(fn _ -> {:error, :econnrefused} end)

    view =
      ReceiptsScreen |> mount_screen() |> render_info({:push_token, :android, "fcm-token"})

    assert_received {:http, :put, "/api/devices", _}
    assert Push.pending?(profile)

    FakeServer.stub(fn _ -> {200, %{"ok" => true}} end)
    render_info(view, {:sync, {:ok, %{pushed: 0, failed: 0, pulled: 0}}})
    assert_received {:http, :put, "/api/devices", _}
    refute Push.pending?(profile)
  end

  test "a receipt book that isn't connected doesn't ask" do
    Accounts.sign_in("0712345678")
    mount_screen(ReceiptsScreen)
    refute_received {:native, :request_notifications, []}
  end

  test "a push syncs and says what happened; a tapped one opens Approvals" do
    connect(@manager)
    view = mount_screen(ReceiptsScreen) |> render_info({:sync, {:error, :offline}})
    drain_native()

    push = %{
      title: "Your expense was approved",
      body: "Naivas · KES 2,450",
      data: %{screen: "transactions"},
      source: :push
    }

    # Well after the app came to the front: the push arrived while in use.
    view = put_in(view.socket.assigns.resumed_at, System.monotonic_time(:millisecond) - 60_000)
    view = render_info(view, {:notification, push})
    assert_received {:native, :sync, []}
    assert_received {:native, :toast, ["Your expense was approved: Naivas · KES 2,450"]}
    assert nav_action(view) == nil

    # Just after coming to the front: the person tapped it.
    view = render_info(view, {:sync, {:error, :offline}})
    view = render_info(view, {:mob_device, :will_enter_foreground})
    assert_received {:native, :sync, []}
    view = render_info(view, {:sync, {:error, :offline}})

    view =
      render_info(view, {:notification, %{push | data: %{screen: "approvals"}, title: "New"}})

    assert nav_action(view) == {:push, ApprovalsScreen, %{}}
    refute_received {:native, :toast, _}
  end

  test "while the app runs, a push arrives as JSON and is handled the same" do
    connect()
    view = mount_screen(ReceiptsScreen) |> render_info({:sync, {:error, :offline}})
    view = put_in(view.socket.assigns.resumed_at, System.monotonic_time(:millisecond) - 60_000)
    drain_native()

    json = ~s({"title":"Your refund was paid","body":"KES 2,450","source":"push","data":{}})
    render_info(view, {:mob_launch_notification, json})

    assert_received {:native, :sync, []}
    assert_received {:native, :toast, ["Your refund was paid: KES 2,450"]}
  end

  test "coming back online syncs" do
    connect()
    view = mount_screen(ReceiptsScreen) |> render_info({:sync, {:error, :offline}})
    drain_native()

    render_info(view, {:mob_device, :connectivity_changed, %{online: true}})
    assert_received {:native, :sync, []}
  end

  test "an open Approvals screen reloads when a push arrives" do
    connect(@manager)

    FakeServer.stub(fn
      {:get, "/api/approvals", _} -> {200, %{"transactions" => []}}
      _ -> {200, %{}}
    end)

    approvals = mount_screen(ApprovalsScreen)
    assert Process.whereis(ApprovalsScreen) == self()
    assert_received {:http, :get, "/api/approvals", _}

    render_info(approvals, :server_changed)
    assert_received {:http, :get, "/api/approvals", _}
  end

  test "disconnecting tells the server to stop pushing to this phone" do
    connect()
    Push.remember(:android, "fcm-token")

    SettingsScreen |> mount_screen() |> render_info({:alert, :confirm_disconnect})

    assert_received {:http, :delete, "/api/devices/fcm-token",
                     %{
                       headers: [
                         {"accept", "application/json"},
                         {"authorization", "Bearer tok-1"}
                       ]
                     }}
  end

  test "each item shows whether the server has it" do
    profile = connect()

    {:ok, receipt} =
      Transactions.create_transaction(profile, Transactions.new_expense(), %{
        date: ~D[2026-09-20],
        vendor: "Naivas",
        amount_cents: 245_000,
        category: "Food & Groceries"
      })

    refute SyncBadge.synced?(receipt)
    assert %{props: %{accessibility_label: "Waiting to sync"}} = SyncBadge.badge(receipt, true)

    receipt =
      receipt |> Ecto.Changeset.change(remote_id: "r-1", needs_push: false) |> Repo.update!()

    assert SyncBadge.synced?(receipt)

    assert %{props: %{accessibility_label: "Synced with your team"}} =
             SyncBadge.badge(receipt, true)

    # Not connected: nothing is ever sent, so no mark.
    assert SyncBadge.badge(receipt, false) == []
  end
end
