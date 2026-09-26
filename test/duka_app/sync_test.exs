defmodule DukaApp.SyncTest do
  # Sync against a scripted server (DukaApp.FakeServer).
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, FakeServer, Repo, Sync, Transactions}
  alias DukaApp.Receipts.Photos
  alias DukaApp.Screens.ReceiptsScreen
  alias DukaApp.Transactions.{Attachment, Attachments, Transaction}

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)

    {:ok, profile} =
      Accounts.connect("0712345678", %{
        "token" => "tok-1",
        "user" => %{"id" => "u-1", "team" => "acme", "permissions" => %{}}
      })

    {:ok, expense} =
      Transactions.create_transaction(profile, Transactions.new_expense(), %{
        date: ~D[2026-09-20],
        vendor: "Naivas",
        amount_cents: 245_000,
        category: "Food & Groceries",
        photo_path: "receipt-sync.jpg"
      })

    File.write!(Photos.path("receipt-sync.jpg"), "jpeg")
    %{profile: profile, expense: expense}
  end

  # A server that accepts everything and echoes it back with an id (and ids
  # for the attachments it was sent).
  defp accepting_server(opts \\ %{}) do
    FakeServer.stub(fn
      {:put, "/api/transactions/" <> client_id, %{body: body}} ->
        fields = FakeServer.multipart_fields(body)

        attachments =
          body
          |> FakeServer.multipart_all("attachments[]")
          |> Enum.with_index(fn {:file, path, name, _type}, i ->
            %{"id" => "a-#{client_id}-#{i}", "name" => name, "size" => File.stat!(path).size}
          end)

        {200,
         %{
           "transaction" =>
             Map.merge(
               %{
                 "id" => "t-" <> client_id,
                 "client_id" => client_id,
                 "status" => "pending",
                 "attachments" => attachments
               },
               Map.drop(fields, ["attachments[]"])
             )
         }}

      {:get, "/api/transactions", _} ->
        {200, %{"transactions" => Map.get(opts, :transactions, [])}}

      {:get, "/api/me", _} ->
        {200,
         %{
           "user" => %{
             "id" => "u-1",
             "team" => "acme",
             "permissions" => %{"approve" => true, "export" => true}
           }
         }}

      {:delete, _path, _} ->
        Map.get(opts, :delete, {204, ""})

      {:get, "/api/transactions/" <> _photo, _} ->
        {200, "server-jpeg"}

      {:get, "/api/attachments/" <> _id, _} ->
        {200, "server-pdf"}
    end)
  end

  # What the server has from another phone (or before a reinstall).
  defp server_transaction(overrides) do
    Map.merge(
      %{
        "id" => "t-remote",
        "client_id" => "other-phone-1",
        "type" => "refund",
        "pay_to" => "self",
        "status" => "paid",
        "date" => "2026-09-18",
        "vendor" => "Quickmart",
        "description" => nil,
        "amount_cents" => 99_000,
        "category" => "Office Supplies",
        "method" => "send_money",
        "phone" => "+254712345678",
        "source" => "etims",
        "has_photo" => true,
        "decision_note" => "OK",
        "decided_at" => "2026-09-19T08:00:00Z",
        "paid_at" => "2026-09-20T08:00:00Z",
        "attachments" => [
          %{
            "id" => "a-1",
            "name" => "invoice.pdf",
            "content_type" => "application/pdf",
            "size" => 10
          }
        ]
      },
      overrides
    )
  end

  defp stored_attachment(name) do
    source = Path.join(System.tmp_dir!(), "sync-#{System.unique_integer([:positive])}-#{name}")
    File.write!(source, "%PDF-1.4 #{name}")
    {:ok, attachment} = Attachments.store(source, name, "application/pdf")
    attachment
  end

  test "a new expense goes up once, with its photo", %{profile: profile, expense: expense} do
    accepting_server()

    assert {:ok, %{pushed: 1, failed: 0}} = Sync.run(profile)

    assert_received {:http, :put, path, %{body: body, headers: headers}}
    assert path == "/api/transactions/#{expense.client_id}"
    assert {"authorization", "Bearer tok-1"} in headers

    assert %{
             "type" => "expense",
             "vendor" => "Naivas",
             "amount_cents" => "245000",
             "date" => "2026-09-20",
             "method" => "",
             "photo" => {:file, "receipt-sync.jpg"}
           } = FakeServer.multipart_fields(body)

    assert %Transaction{needs_push: false, photo_pushed: true, remote_id: remote_id} =
             Repo.get!(Transaction, expense.id)

    assert remote_id == "t-" <> expense.client_id

    # Nothing to send the second time; permissions were refreshed.
    assert {:ok, %{pushed: 0}} = Sync.run(profile)

    assert %{can_approve: true, can_export: true, can_list_all: false} =
             Accounts.get_profile!(profile.id)
  end

  test "an edit made while it was uploading is kept for the next sync", %{
    profile: profile,
    expense: expense
  } do
    FakeServer.stub(fn
      {:put, _, _} ->
        # The user edits the expense while the upload is in flight.
        {:ok, _} =
          Transaction
          |> Repo.get!(expense.id)
          |> Ecto.Changeset.change(vendor: "Naivas Karen", updated_at: ~N[2030-01-01 00:00:00])
          |> Repo.update()

        {200, %{"transaction" => %{"id" => "t-1", "client_id" => expense.client_id}}}

      {:get, "/api/transactions", _} ->
        {200, %{"transactions" => []}}

      {:get, "/api/me", _} ->
        {401, %{}}
    end)

    Sync.run(profile)

    assert %Transaction{needs_push: true, vendor: "Naivas Karen"} =
             Repo.get!(Transaction, expense.id)
  end

  test "a payment request goes up with its attachments, each only once", %{profile: profile} do
    accepting_server()

    {:ok, request} =
      Transactions.create_transaction(
        profile,
        Transactions.new_payment(),
        %{
          vendor: "Toner Supplies",
          amount_cents: 500_000,
          method: "till",
          till_number: "832909"
        },
        [stored_attachment("invoice.pdf")]
      )

    assert {:ok, %{pushed: 2}} = Sync.run(profile)

    assert_received {:http, :put, "/api/transactions/" <> _expense, _}
    assert_received {:http, :put, "/api/transactions/" <> client_id, %{body: body}}
    assert client_id == request.client_id

    assert %{"type" => "payment_request", "pay_to" => "supplier", "till_number" => "832909"} =
             FakeServer.multipart_fields(body)

    assert [{:file, _, "invoice.pdf", "application/pdf"}] =
             FakeServer.multipart_all(body, "attachments[]")

    assert [%Attachment{remote_id: "a-" <> _}] = Repo.all(Attachment)

    # A new file on an edit is the only one that goes up.
    {:ok, _} =
      Transactions.update_transaction(
        Transactions.get_transaction!(profile, request.id),
        %{},
        [stored_attachment("quote.pdf")]
      )

    assert {:ok, %{pushed: 1}} = Sync.run(profile)
    assert_received {:http, :put, _, %{body: body}}

    assert [{:file, _, "quote.pdf", _}] = FakeServer.multipart_all(body, "attachments[]")
    assert Repo.all(Attachment) |> Enum.all?(& &1.remote_id)
  end

  test "a refund taken back clears how to pay on the server too", %{
    profile: profile,
    expense: expense
  } do
    accepting_server()

    {:ok, refund} =
      Transactions.request_refund(expense, %{method: "send_money", phone: "0712345678"})

    {:ok, _} = Sync.run(profile)
    assert_received {:http, :put, _, %{body: body}}

    assert %{"type" => "refund", "method" => "send_money", "phone" => "+254712345678"} =
             FakeServer.multipart_fields(body)

    {:ok, _} = Transactions.cancel_refund(Repo.get!(Transaction, refund.id))
    {:ok, _} = Sync.run(profile)
    assert_received {:http, :put, _, %{body: body}}

    assert %{"type" => "expense", "method" => "", "phone" => ""} =
             FakeServer.multipart_fields(body)
  end

  test "decisions come back, except onto unsent edits", %{profile: profile, expense: expense} do
    accepting_server()
    {:ok, _} = Sync.run(profile)

    decided = %{
      "client_id" => expense.client_id,
      "status" => "rejected",
      "decision_note" => "Attach the invoice",
      "decided_at" => "2026-09-24T09:00:00Z"
    }

    accepting_server(%{transactions: [decided]})
    {:ok, %{pulled: 1}} = Sync.run(profile)

    assert %Transaction{status: "rejected", decision_note: "Attach the invoice"} =
             Repo.get!(Transaction, expense.id)

    # An unsent edit wins until it's pushed.
    {:ok, edited} =
      Transactions.update_transaction(Repo.get!(Transaction, expense.id), %{
        vendor: "Naivas Karen"
      })

    FakeServer.stub(fn _ -> {:error, :econnrefused} end)
    assert {:error, :offline} = Sync.run(profile)
    assert %Transaction{needs_push: true} = Repo.get!(Transaction, edited.id)
  end

  test "the home screen syncs when it opens, and a refused token disconnects", %{
    profile: profile
  } do
    view = mount_screen(ReceiptsScreen)
    assert_received {:native, :sync, []}

    view = render_info(view, {:sync, {:error, :unauthorized}})
    refute Accounts.get_profile!(profile.id).api_token
    assert_received {:native, :toast, ["Please sign in again."]}

    assert_renderable(view,
      extra: [:header, :search_field, :transaction_item, :transaction_sheet, :icon]
    )
  end

  describe "what the server has that the phone doesn't" do
    test "is added, with its photo and attachments left on the server", %{profile: profile} do
      # Fresh server ids, so no file from an earlier run is already here.
      n = System.unique_integer([:positive])
      remote = server_transaction(%{"id" => "t-#{n}"})
      attachments = Enum.map(remote["attachments"], &%{&1 | "id" => "a-#{n}"})

      accepting_server(%{transactions: [%{remote | "attachments" => attachments}]})

      assert {:ok, %{pulled: 1}} = Sync.run(profile)

      transaction =
        Transaction |> Repo.get_by!(client_id: "other-phone-1") |> Repo.preload(:attachments)

      assert %Transaction{
               type: "refund",
               pay_to: "self",
               vendor: "Quickmart",
               date: ~D[2026-09-18],
               amount_cents: 99_000,
               status: "paid",
               method: "send_money",
               needs_push: false,
               photo_pushed: true
             } = transaction

      assert transaction.paid_at
      assert transaction.remote_id == "t-#{n}"
      refute Photos.exists?(transaction.photo_path)
      assert [%{name: "invoice.pdf"} = attachment] = transaction.attachments
      assert attachment.remote_id == "a-#{n}"

      # Nothing goes back up, and a second sync adds nothing twice.
      assert {:ok, %{pushed: 0}} = Sync.run(profile)
      assert Repo.aggregate(Transaction, :count) == 2

      # The files come down when opened.
      assert :ok = Sync.fetch_photo(profile, transaction)
      assert File.read!(Photos.path(transaction.photo_path)) == "server-jpeg"
      assert :ok = Sync.fetch_attachment(profile, attachment)
      assert File.read!(Attachments.path(attachment.file_name)) == "server-pdf"
    end
  end

  describe "deleting on the phone" do
    test "deletes on the server at the next sync", %{profile: profile, expense: expense} do
      accepting_server()
      {:ok, _} = Sync.run(profile)

      {:ok, _} = Transactions.delete_transaction(Repo.get!(Transaction, expense.id))
      accepting_server()
      assert {:ok, _} = Sync.run(profile)

      assert_received {:http, :delete, path, _}
      assert path == "/api/transactions/#{expense.client_id}"
      assert Repo.aggregate(DukaApp.Sync.Deletion, :count) == 0
    end

    test "isn't undone by a pull before the server hears of it", %{
      profile: profile,
      expense: expense
    } do
      {:ok, _} = Transactions.delete_transaction(expense)

      # Offline for the delete: the server still lists it, and it stays gone.
      FakeServer.stub(fn
        {:delete, _, _} ->
          {:error, :econnrefused}

        {:get, "/api/transactions", _} ->
          {200, %{"transactions" => [server_transaction(%{"client_id" => expense.client_id})]}}
      end)

      assert {:error, :offline} = Sync.run(profile)
      refute Repo.get_by(Transaction, client_id: expense.client_id)
      assert Repo.aggregate(DukaApp.Sync.Deletion, :count) == 1
    end

    test "is kept for later by a server that can't delete yet", %{
      profile: profile,
      expense: expense
    } do
      {:ok, _} = Transactions.delete_transaction(expense)

      accepting_server(%{
        delete: {404, %{"error" => "Not found"}},
        transactions: [server_transaction(%{"client_id" => expense.client_id})]
      })

      assert {:ok, _} = Sync.run(profile)
      refute Repo.get_by(Transaction, client_id: expense.client_id)
      assert Repo.aggregate(DukaApp.Sync.Deletion, :count) == 1
    end

    test "something decided meanwhile comes back", %{profile: profile, expense: expense} do
      {:ok, _} = Transactions.delete_transaction(expense)

      accepting_server(%{
        delete: {422, %{"errors" => %{"status" => "has already been decided"}}},
        transactions: [
          server_transaction(%{"client_id" => expense.client_id, "status" => "approved"})
        ]
      })

      assert {:ok, _} = Sync.run(profile)

      assert %Transaction{status: "approved"} =
               Repo.get_by!(Transaction, client_id: expense.client_id)
    end
  end

  test "a book that isn't connected doesn't try", %{profile: profile} do
    {:ok, _} = Accounts.disconnect(profile)
    assert Sync.run() == {:error, :not_connected}

    mount_screen(ReceiptsScreen)
    refute_received {:native, :sync, []}
  end
end
