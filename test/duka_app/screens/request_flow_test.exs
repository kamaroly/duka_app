defmodule DukaApp.Screens.RequestFlowTest do
  # Refund and payment requests, from the screens. async: false because
  # Mob.ScreenCase screens share global state.
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, Receipts, Requests}
  alias DukaApp.Screens.{ReceiptsScreen, RequestFormScreen, RequestsScreen}

  @extra [:header, :search_field, :receipt_item, :receipt_detail, :icon]

  defp nav_action(view), do: view.socket.__mob__[:nav_action]

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)
    {:ok, profile} = Accounts.sign_in("0712345678")

    {:ok, receipt} =
      Receipts.create_receipt(profile, Receipts.new_manual(), %{
        date: ~D[2026-09-20],
        vendor: "Naivas",
        amount_cents: 245_000,
        category: "Food & Groceries"
      })

    %{profile: profile, receipt: receipt}
  end

  test "a receipt's sheet asks for a refund, then shows it pending", %{
    profile: profile,
    receipt: receipt
  } do
    view =
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:select, :receipts, 0})

    assert assigns(view).selected_refund == nil
    view = render_info(view, {:tap, :request_refund})
    assert nav_action(view) == {:push, RequestFormScreen, %{receipt_id: receipt.id}}

    form = mount_screen(RequestFormScreen, %{receipt_id: receipt.id})
    assert assigns(form).phone == "0712 345 678"
    assert_renderable(form, extra: @extra)

    form =
      form
      |> render_info({:change, :purpose, "Client lunch"})
      |> render_info({:tap, :submit})

    assert nav_action(form) == {:pop}

    assert [%{kind: "refund", amount_cents: 245_000, purpose: "Client lunch", status: "pending"}] =
             Requests.list_requests(profile)

    view = ReceiptsScreen |> mount_screen() |> render_info({:select, :receipts, 0})
    assert %{status: "pending"} = assigns(view).selected_refund
    assert_renderable(view, extra: @extra)
  end

  test "a payment request picks how to pay and tells the requests screen", %{profile: profile} do
    requests = mount_screen(RequestsScreen)
    assert_renderable(requests, extra: @extra)

    requests = render_info(requests, {:tap, :new_payment})
    assert {:push, RequestFormScreen, %{notify: notify}} = nav_action(requests)
    assert notify == self()

    form =
      RequestFormScreen
      |> mount_screen(%{notify: self()})
      |> render_info({:change, :amount, "2,500"})
      |> render_info({:change, :purpose, "Electricity"})
      |> render_info({:change, :phone, "0722000111"})
      |> render_info({:tap, {:method, "paybill"}})

    assert_renderable(form, extra: @extra)

    # Paybill needs its numbers; the phone typed earlier isn't sent.
    form = render_info(form, {:tap, :submit})
    assert assigns(form).errors[:paybill_number]
    assert Requests.list_requests(profile) == []

    form =
      form
      |> render_info({:change, :paybill_number, "888880"})
      |> render_info({:change, :account_number, "1234567"})
      |> render_info({:tap, :submit})

    assert nav_action(form) == {:pop}
    assert_received {:request_saved, request}

    assert %{
             method: "paybill",
             paybill_number: "888880",
             account_number: "1234567",
             phone: nil,
             amount_cents: 250_000
           } = request

    requests = render_info(requests, {:request_saved, request})
    assert [%{id: id}] = assigns(requests).requests
    assert id == request.id
    assert assigns(requests).pending == %{count: 1, total: 250_000}
  end

  test "a bad amount is reported and nothing is saved", %{profile: profile} do
    form =
      RequestFormScreen
      |> mount_screen()
      |> render_info({:change, :amount, "lots"})
      |> render_info({:change, :purpose, "Fuel"})
      |> render_info({:change, :phone, "0722000111"})
      |> render_info({:tap, :submit})

    assert assigns(form).errors[:amount]
    assert Requests.list_requests(profile) == []
  end

  test "a pending request can be withdrawn from its sheet", %{profile: profile} do
    {:ok, _} =
      Requests.create_request(profile, Requests.new_payment(), %{
        kind: "payment",
        amount_cents: 1_000,
        purpose: "Airtime",
        method: "till",
        till_number: "832909"
      })

    view =
      RequestsScreen
      |> mount_screen()
      |> render_info({:select, :requests, 0})

    assert assigns(view).selected
    assert_renderable(view, extra: @extra)

    # The confirm alert is native; this is the answer it sends back.
    view = render_info(view, {:alert, :confirm_cancel})

    assert assigns(view).requests == []
    assert Requests.list_requests(profile) == []
  end
end
