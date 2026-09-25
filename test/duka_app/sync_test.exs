defmodule DukaApp.SyncTest do
  # Sync against a scripted server (DukaApp.FakeServer).
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, FakeServer, Receipts, Repo, Requests, Sync}
  alias DukaApp.Receipts.{Photos, Receipt}
  alias DukaApp.Requests.Request
  alias DukaApp.Screens.ReceiptsScreen

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)

    {:ok, profile} =
      Accounts.connect("0712345678", %{
        "token" => "tok-1",
        "user" => %{"id" => "u-1", "team" => "acme", "permissions" => %{}}
      })

    {:ok, receipt} =
      Receipts.create_receipt(profile, Receipts.new_manual(), %{
        date: ~D[2026-09-20],
        vendor: "Naivas",
        amount_cents: 245_000,
        category: "Food & Groceries",
        photo_path: "receipt-sync.jpg"
      })

    File.write!(Photos.path("receipt-sync.jpg"), "jpeg")
    %{profile: profile, receipt: receipt}
  end

  # A server that accepts everything and echoes it back with an id.
  defp accepting_server(decisions \\ %{}) do
    FakeServer.stub(fn
      {:put, "/api/receipts/" <> client_id, %{body: body}} ->
        fields = FakeServer.multipart_fields(body)

        {200,
         %{"receipt" => Map.merge(%{"id" => "r-" <> client_id, "client_id" => client_id}, fields)}}

      {:post, "/api/requests", %{body: body}} ->
        fields = FakeServer.multipart_fields(body)

        {201,
         %{
           "request" => %{
             "id" => "q-1",
             "client_id" => fields["client_id"],
             "status" => "pending"
           }
         }}

      {:get, "/api/receipts", _} ->
        {200, %{"receipts" => Map.get(decisions, :receipts, [])}}

      {:get, "/api/requests", _} ->
        {200, %{"requests" => Map.get(decisions, :requests, [])}}

      {:get, "/api/me", _} ->
        {200,
         %{
           "user" => %{
             "id" => "u-1",
             "team" => "acme",
             "permissions" => %{"approve_receipts" => true}
           }
         }}
    end)
  end

  test "a new receipt goes up once, with its photo", %{profile: profile, receipt: receipt} do
    accepting_server()

    assert {:ok, %{pushed: 1, failed: 0}} = Sync.run(profile)

    assert_received {:http, :put, path, %{body: body, headers: headers}}
    assert path == "/api/receipts/#{receipt.client_id}"
    assert {"authorization", "Bearer tok-1"} in headers

    assert %{
             "vendor" => "Naivas",
             "amount_cents" => "245000",
             "date" => "2026-09-20",
             "photo" => {:file, "receipt-sync.jpg"}
           } = FakeServer.multipart_fields(body)

    assert %Receipt{needs_push: false, photo_pushed: true, remote_id: remote_id} =
             Repo.get!(Receipt, receipt.id)

    assert remote_id == "r-" <> receipt.client_id

    # Nothing to send the second time; permissions were refreshed.
    assert {:ok, %{pushed: 0}} = Sync.run(profile)
    assert Accounts.get_profile!(profile.id).can_approve_receipts
  end

  test "an edit made while the receipt was uploading is kept for the next sync", %{
    profile: profile,
    receipt: receipt
  } do
    FakeServer.stub(fn
      {:put, _, _} ->
        # The user edits the receipt while the upload is in flight.
        {:ok, _} =
          Receipt
          |> Repo.get!(receipt.id)
          |> Ecto.Changeset.change(vendor: "Naivas Karen", updated_at: ~N[2030-01-01 00:00:00])
          |> Repo.update()

        {200, %{"receipt" => %{"id" => "r-1", "client_id" => receipt.client_id}}}

      {:get, "/api/receipts", _} ->
        {200, %{"receipts" => []}}

      {:get, "/api/requests", _} ->
        {200, %{"requests" => []}}

      {:get, "/api/me", _} ->
        {401, %{}}
    end)

    Sync.run(profile)
    assert %Receipt{needs_push: true, vendor: "Naivas Karen"} = Repo.get!(Receipt, receipt.id)
  end

  test "a refund names its receipt and sends its attachments", %{
    profile: profile,
    receipt: receipt
  } do
    accepting_server()

    {:ok, request} =
      Requests.create_request(profile, Requests.new_refund(profile, receipt), %{
        kind: "refund",
        receipt_id: receipt.id,
        method: "send_money",
        phone: "0712345678"
      })

    assert {:ok, %{pushed: 2}} = Sync.run(profile)

    # Receipts go first, so the server knows the refund's receipt.
    assert_received {:http, :put, "/api/receipts/" <> _, _}
    assert_received {:http, :post, "/api/requests", %{body: body}}

    assert %{
             "kind" => "refund",
             "receipt_client_id" => client_id,
             "client_id" => request_client_id
           } =
             FakeServer.multipart_fields(body)

    assert client_id == receipt.client_id
    assert request_client_id == request.client_id
    assert %Request{remote_id: "q-1"} = Repo.get!(Request, request.id)
  end

  test "the manager's decisions come back, except onto unsent edits", %{
    profile: profile,
    receipt: receipt
  } do
    accepting_server()
    {:ok, _} = Sync.run(profile)

    decided = %{
      "client_id" => receipt.client_id,
      "approval_status" => "rejected",
      "approval_note" => "Attach the invoice",
      "decided_at" => "2026-09-24T09:00:00Z"
    }

    accepting_server(%{receipts: [decided]})
    {:ok, %{pulled: 1}} = Sync.run(profile)

    assert %Receipt{approval_status: "rejected", approval_note: "Attach the invoice"} =
             Repo.get!(Receipt, receipt.id)

    # An unsent edit wins until it's pushed.
    {:ok, edited} =
      Receipts.update_receipt(Repo.get!(Receipt, receipt.id), %{vendor: "Naivas Karen"})

    FakeServer.stub(fn _ -> {:error, :econnrefused} end)
    assert {:error, :offline} = Sync.run(profile)
    assert %Receipt{needs_push: true} = Repo.get!(Receipt, edited.id)
  end

  test "the home screen syncs when it opens, and a refused token disconnects", %{profile: profile} do
    view = mount_screen(ReceiptsScreen)
    assert_received {:native, :sync, []}

    view = render_info(view, {:sync, {:error, :unauthorized}})
    refute Accounts.get_profile!(profile.id).api_token
    assert_received {:native, :toast, ["Please sign in again."]}

    assert_renderable(view,
      extra: [:header, :search_field, :receipt_item, :receipt_detail, :icon]
    )
  end

  test "a receipt book that isn't connected doesn't try", %{profile: profile} do
    {:ok, _} = Accounts.disconnect(profile)
    assert Sync.run() == {:error, :not_connected}

    mount_screen(ReceiptsScreen)
    refute_received {:native, :sync, []}
  end
end
