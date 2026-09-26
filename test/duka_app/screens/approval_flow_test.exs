defmodule DukaApp.Screens.ApprovalFlowTest do
  # The approver's side, against a scripted server (DukaApp.FakeServer).
  # async: false because Mob.ScreenCase screens share global state.
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, FakeServer}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Screens.{ApprovalsScreen, ReceiptsScreen, SettingsScreen}

  @extra [:header, :search_field, :transaction_item, :transaction_sheet, :icon]

  @expense %{
    "id" => "t-1",
    "client_id" => "phone-1",
    "type" => "expense",
    "status" => "pending",
    "date" => "2026-09-20",
    "vendor" => "Naivas",
    "amount_cents" => 245_000,
    "category" => "Food & Groceries",
    "source" => "etims",
    "verified_at" => "2026-09-20T10:00:00Z",
    "has_photo" => true,
    "attachments" => [],
    "submitted_by" => %{"name" => "Otieno", "phone" => "+254722000111"}
  }

  @payment %{
    "id" => "t-2",
    "client_id" => "req-1",
    "type" => "payment_request",
    "pay_to" => "supplier",
    "status" => "approved",
    "date" => "2026-09-24",
    "vendor" => "Toner Supplies",
    "description" => "Toner",
    "amount_cents" => 5_000,
    "category" => "Office Supplies",
    "method" => "till",
    "till_number" => "832909",
    "attachments" => [
      %{"id" => "a-1", "name" => "Quote.pdf", "content_type" => "application/pdf", "size" => 4}
    ],
    "submitted_by" => %{"name" => "Otieno", "phone" => "+254722000111"},
    "inserted_at" => "2026-09-24T08:00:00Z"
  }

  defp nav_action(view), do: view.socket.__mob__[:nav_action]

  defp reply(view, tag) do
    assert_received {^tag, result}
    render_info(view, {tag, result})
  end

  defp connect(permissions) do
    {:ok, profile} =
      Accounts.connect("0712345678", %{
        "token" => "tok-1",
        "user" => %{"id" => "u-1", "team" => "acme", "permissions" => permissions}
      })

    profile
  end

  @manager %{"approve" => true, "mark_paid" => true}

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)
    :ok
  end

  defp serve(transactions, extra \\ fn _ -> {404, %{"error" => "Not found"}} end) do
    FakeServer.stub(fn
      {:get, "/api/approvals", _} -> {200, %{"transactions" => transactions}}
      other -> extra.(other)
    end)
  end

  defp open_approvals do
    ApprovalsScreen |> mount_screen() |> reply(:loaded)
  end

  test "only people the server lets approve or pay get the Approvals button" do
    staff = connect(%{"approve" => false, "mark_paid" => false})
    refute Profile.manager?(staff)

    assert Profile.manager?(connect(%{"mark_paid" => true}))

    manager = connect(@manager)
    assert Profile.manager?(manager)

    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :open_approvals})
    assert nav_action(view) == {:push, ApprovalsScreen, %{}}
  end

  test "before connecting, Approvals and the warning open Settings" do
    Accounts.sign_in("0712345678")

    view = ReceiptsScreen |> mount_screen()

    assert render_info(view, {:tap, :open_approvals}) |> nav_action() ==
             {:push, SettingsScreen, %{}}

    assert render_info(view, {:tap, :open_settings}) |> nav_action() ==
             {:push, SettingsScreen, %{}}
  end

  test "the list comes from the server, with who sent each and the token" do
    connect(@manager)
    serve([@expense, @payment])

    view = open_approvals()
    assert_received {:http, :get, "/api/approvals", %{headers: headers}}
    assert {"authorization", "Bearer tok-1"} in headers

    assert %{decide: %{count: 1, total: 245_000}, pay: %{count: 1, total: 5_000}} =
             assigns(view).summary

    assert [{:heading, "Waiting for you"}, %{vendor: "Naivas", profile: %{name: "Otieno"}}] =
             assigns(view).items

    view = render_info(view, {:select, :approvals, 1})
    assert assigns(view).selected.id == "t-1"
    assert_renderable(view, extra: @extra)
  end

  test "approving and rejecting go to the server; rejecting needs a note" do
    connect(@manager)

    serve([@expense], fn
      {:post, "/api/approvals/t-1/" <> _, _} -> {200, %{"transaction" => @expense}}
    end)

    view = open_approvals() |> render_info({:select, :approvals, 1})

    view = render_info(view, {:tap, :reject})
    assert assigns(view).note_error
    refute_received {:http, :post, _, _}

    view =
      view
      |> render_info({:change, :note, "Attach the invoice"})
      |> render_info({:tap, :reject})
      |> reply({:decided, "Rejected"})

    assert_received {:http, :post, "/api/approvals/t-1/reject",
                     %{body: {:json, %{note: "Attach the invoice"}}}}

    assert assigns(view).selected == nil
    assert_received {:native, :toast, ["Rejected"]}

    view
    |> reply(:loaded)
    |> render_info({:select, :approvals, 1})
    |> render_info({:tap, :approve})
    |> reply({:decided, "Approved"})

    assert_received {:http, :post, "/api/approvals/t-1/approve", %{body: {:json, %{note: nil}}}}
  end

  test "approved claims: pay; attachments download to open" do
    connect(@manager)

    serve([@payment], fn
      {:post, "/api/approvals/t-2/pay", _} ->
        {200, %{"transaction" => %{@payment | "status" => "paid"}}}

      {:get, "/api/attachments/a-1", _} ->
        {200, "%PDF"}
    end)

    view = open_approvals() |> render_info({:tap, {:tab, :pay}})
    assert [{:heading, "Approved — to pay"}, %{status: "approved"}] = assigns(view).items

    view = render_info(view, {:select, :approvals, 1})
    assert_renderable(view, extra: @extra)

    view = view |> render_info({:tap, {:open_attachment, "a-1"}}) |> reply(:downloaded)
    assert_received {:native, :open_file, [path]}
    assert File.read!(path) == "%PDF"

    view |> render_info({:tap, :mark_paid}) |> reply({:decided, "Marked as paid"})
    assert_received {:http, :post, "/api/approvals/t-2/pay", _}
    assert_received {:native, :toast, ["Marked as paid"]}
  end

  test "someone who may only pay starts on To pay" do
    connect(%{"mark_paid" => true})
    serve([@expense, @payment])

    view = open_approvals()
    assert assigns(view).tab == :pay
    assert [{:heading, "Approved — to pay"}, %{id: "t-2"}] = assigns(view).items
  end

  test "a server refusal is shown, and the list reloads" do
    connect(@manager)

    serve([@expense], fn
      {:post, _, _} -> {422, %{"errors" => %{"status" => "is no longer waiting for approval"}}}
    end)

    open_approvals()
    |> render_info({:select, :approvals, 1})
    |> render_info({:tap, :approve})
    |> reply({:decided, "Approved"})

    assert_received {:native, :toast, ["Status is no longer waiting for approval"]}
  end
end
