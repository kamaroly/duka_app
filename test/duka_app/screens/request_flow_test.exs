defmodule DukaApp.Screens.RequestFlowTest do
  # Refunds and payment requests, from the screens. async: false because
  # Mob.ScreenCase screens share global state.
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, Transactions}
  alias DukaApp.Screens.{ReceiptFormScreen, ReceiptsScreen, RequestFormScreen}
  alias DukaApp.Transactions.{Attachments, Transaction}

  @extra [:header, :search_field, :transaction_item, :transaction_sheet, :icon]

  defp nav_action(view), do: view.socket.__mob__[:nav_action]

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)
    {:ok, profile} = Accounts.sign_in("0712345678")

    {:ok, expense} =
      Transactions.create_transaction(profile, Transactions.new_expense(), %{
        date: ~D[2026-09-20],
        vendor: "Naivas",
        amount_cents: 245_000,
        category: "Food & Groceries"
      })

    %{profile: profile, expense: expense}
  end

  test "an expense's sheet asks for a refund, and the expense becomes one", %{
    profile: profile,
    expense: expense
  } do
    view =
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:select, :receipts, 0})

    assert %Transaction{type: "expense"} = assigns(view).selected
    view = render_info(view, {:tap, :request_refund})

    assert nav_action(view) ==
             {:push, RequestFormScreen, %{refund_of: expense.id, notify: self()}}

    form = mount_screen(RequestFormScreen, %{refund_of: expense.id})
    assert assigns(form).phone == "0712 345 678"
    assert_renderable(form, extra: @extra)

    form =
      form
      |> render_info({:change, :description, "Client lunch"})
      |> render_info({:tap, :submit})

    assert nav_action(form) == {:pop}

    assert [
             %{
               type: "refund",
               pay_to: "self",
               amount_cents: 245_000,
               description: "Client lunch",
               method: "send_money",
               status: "pending"
             }
           ] = Transactions.list_transactions(profile)

    # It shows under Refunds & payments, and its sheet can take it back.
    view =
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:tap, {:group, :claims}})
      |> render_info({:select, :receipts, 0})

    assert %Transaction{type: "refund"} = assigns(view).selected
    assert_renderable(view, extra: @extra)

    view = render_info(view, {:alert, :confirm_cancel_refund})
    assert %Transaction{type: "expense", method: nil} = assigns(view).selected
    assert [%{type: "expense"}] = Transactions.list_transactions(profile)
  end

  test "a payment request says who's paid, picks how, and shows up in the home list", %{
    profile: profile
  } do
    home = mount_screen(ReceiptsScreen)

    # The + button offers it; so does the action sheet it opens.
    home = render_info(home, {:alert, :new_payment})
    assert {:push, RequestFormScreen, %{notify: notify}} = nav_action(home)
    assert notify == self()

    form =
      RequestFormScreen
      |> mount_screen(%{notify: self()})
      |> render_info({:change, :amount, "2,500"})
      |> render_info({:change, :description, "Electricity"})
      |> render_info({:change, :phone, "0722000111"})
      |> render_info({:tap, {:method, "paybill"}})
      # The category sheet is native; this is the answer it sends back.
      |> render_info({:alert, :category_4})

    assert_renderable(form, extra: @extra)

    # Paybill needs its numbers and the payee a name; the phone typed
    # earlier isn't sent.
    form = render_info(form, {:tap, :submit})
    assert assigns(form).errors[:paybill_number]
    assert assigns(form).errors[:vendor]
    assert Transactions.list_transactions(profile, "", :claims) == []

    form =
      form
      |> render_info({:change, :vendor, "Kenya Power"})
      |> render_info({:change, :paybill_number, "888880"})
      |> render_info({:change, :account_number, "1234567"})
      |> render_info({:tap, :submit})

    assert nav_action(form) == {:pop}
    assert_received {:request_saved, request}

    assert %{
             type: "payment_request",
             pay_to: "supplier",
             vendor: "Kenya Power",
             category: "Utilities",
             method: "paybill",
             paybill_number: "888880",
             account_number: "1234567",
             phone: nil,
             amount_cents: 250_000
           } = request

    home = render_info(home, {:request_saved, request})
    assert Enum.any?(assigns(home).items, &(&1.id == request.id))

    home = render_info(home, {:tap, {:group, :claims}})
    assert [%Transaction{id: id}] = assigns(home).items
    assert id == request.id
    assert_renderable(home, extra: @extra)

    # Editing it opens this form again, not the receipt form.
    home = render_info(home, {:select, :receipts, 0}) |> render_info({:tap, :edit_transaction})
    assert {:push, RequestFormScreen, %{id: ^id}} = nav_action(home)

    form =
      RequestFormScreen
      |> mount_screen(%{id: id, notify: self()})
      |> render_info({:tap, {:pay_to, "self"}})
      |> render_info({:tap, :submit})

    assert_received {:request_saved, %{pay_to: "self", vendor: "Kenya Power"}}
    assert nav_action(form) == {:pop}
  end

  test "an expense is edited on the receipt form", %{expense: expense} do
    view =
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:select, :receipts, 0})
      |> render_info({:tap, :edit_transaction})

    assert nav_action(view) == {:push, ReceiptFormScreen, %{id: expense.id}}
  end

  test "a bad amount is reported and nothing is saved", %{profile: profile} do
    form =
      RequestFormScreen
      |> mount_screen()
      |> render_info({:change, :amount, "lots"})
      |> render_info({:change, :vendor, "Shell"})
      |> render_info({:change, :phone, "0722000111"})
      |> render_info({:tap, :submit})

    assert assigns(form).errors[:amount]
    assert Transactions.list_transactions(profile, "", :claims) == []
  end

  test "a pending request can be deleted from its sheet", %{profile: profile} do
    {:ok, _} =
      Transactions.create_transaction(profile, Transactions.new_payment(), %{
        vendor: "Safaricom",
        amount_cents: 1_000,
        description: "Airtime",
        method: "till",
        till_number: "832909"
      })

    view =
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:tap, {:group, :claims}})
      |> render_info({:select, :receipts, 0})

    assert %Transaction{type: "payment_request"} = assigns(view).selected
    assert_renderable(view, extra: @extra)

    # The confirm alert is native; this is the answer it sends back.
    view = render_info(view, {:alert, :confirm_delete})

    assert assigns(view).items == []
    assert Transactions.list_transactions(profile, "", :claims) == []
  end

  describe "attachments" do
    @describetag :tmp_dir

    defp payment_form do
      RequestFormScreen
      |> mount_screen(%{notify: self()})
      |> render_info({:change, :amount, "5000"})
      |> render_info({:change, :vendor, "Toner Supplies"})
      |> render_info({:change, :description, "Printer toner"})
      |> render_info({:tap, {:method, "till"}})
      |> render_info({:change, :till_number, "832909"})
    end

    defp temp_file(dir, name, contents \\ "data") do
      path = Path.join(dir, name)
      File.write!(path, contents)
      path
    end

    test "photos and picked files are attached, sent with the request, and openable", %{
      profile: profile,
      tmp_dir: dir
    } do
      form = render_info(payment_form(), {:tap, :attach_photo})
      assert_received {:native, :request_camera, []}
      form = render_info(form, {:permission, :camera, :granted})
      assert_received {:native, :take_photo, []}

      form = render_info(form, {:camera, :photo, %{path: temp_file(dir, "mob_cam_1.jpg")}})

      form = render_info(form, {:tap, :attach_file})
      assert_received {:native, :pick_files, []}

      form =
        render_info(
          form,
          {:files, :picked,
           [
             %{
               path: temp_file(dir, "a.pdf"),
               name: "Quote.pdf",
               mime: "application/pdf",
               size: 4
             },
             %{path: temp_file(dir, "b.txt"), name: "notes.txt", mime: "text/plain", size: 4}
           ]}
        )

      assert [%{name: "Photo 1.jpg"}, %{name: "Quote.pdf"}] = assigns(form).attachments
      assert_received {:native, :toast, ["notes.txt isn't an image or PDF"]}
      assert_renderable(form, extra: @extra)

      form = render_info(form, {:tap, :submit})
      assert_received {:request_saved, request}
      assert [%{name: "Photo 1.jpg"}, %{name: "Quote.pdf"}] = request.attachments

      assert [%{attachments: [_, _]}] = Transactions.list_transactions(profile, "", :claims)

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:tap, {:group, :claims}})
        |> render_info({:select, :receipts, 0})

      assert_renderable(view, extra: @extra)

      pdf = Enum.find(request.attachments, &(&1.name == "Quote.pdf"))
      render_info(view, {:tap, {:open_attachment, pdf.id}})
      path = Attachments.path(pdf.file_name)
      assert_received {:native, :open_file, [^path]}

      # Deleting the request deletes its files.
      render_info(view, {:alert, :confirm_delete})
      refute File.exists?(path)
      _ = form
    end

    test "removing one, or leaving without sending, deletes the copies", %{tmp_dir: dir} do
      form =
        render_info(
          payment_form(),
          {:files, :picked,
           [
             %{path: temp_file(dir, "a.pdf"), name: "A.pdf", mime: "application/pdf", size: 4},
             %{path: temp_file(dir, "b.jpg"), name: "B.jpg", mime: "image/jpeg", size: 4}
           ]}
        )

      [a, b] = assigns(form).attachments
      form = render_info(form, {:tap, {:remove_attachment, 0}})
      assert [%{name: "B.jpg"}] = assigns(form).attachments
      refute File.exists?(Attachments.path(a.file_name))

      render_info(form, {:tap, :header_back})
      refute File.exists?(Attachments.path(b.file_name))
    end

    test "no more than five", %{tmp_dir: dir} do
      files =
        for i <- 1..6 do
          %{path: temp_file(dir, "#{i}.jpg"), name: "#{i}.jpg", mime: "image/jpeg", size: 4}
        end

      form = render_info(payment_form(), {:files, :picked, files})
      assert [_, _, _, _, _] = assigns(form).attachments
      assert_received {:native, :toast, ["Only 5 attachments fit"]}
    end
  end
end
