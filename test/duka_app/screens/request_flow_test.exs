defmodule DukaApp.Screens.RequestFlowTest do
  # Refund and payment requests, from the screens. async: false because
  # Mob.ScreenCase screens share global state.
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, Receipts, Requests}
  alias DukaApp.Requests.Attachments
  alias DukaApp.Screens.{ReceiptsScreen, RequestFormScreen}

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

    assert nav_action(view) ==
             {:push, RequestFormScreen, %{receipt_id: receipt.id, notify: self()}}

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

    # The home list now has the refund too; the Food filter shows the receipt.
    view =
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:tap, {:group, :food}})
      |> render_info({:select, :receipts, 0})

    assert %{status: "pending"} = assigns(view).selected_refund
    assert_renderable(view, extra: @extra)
  end

  test "a payment request picks how to pay and shows up in the home list", %{profile: profile} do
    home = mount_screen(ReceiptsScreen)

    # The + button offers it; so does the action sheet it opens.
    home = render_info(home, {:alert, :new_payment})
    assert {:push, RequestFormScreen, %{notify: notify}} = nav_action(home)
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

    home = render_info(home, {:request_saved, request})

    assert Enum.any?(
             assigns(home).items,
             &(&1.id == request.id and is_struct(&1, DukaApp.Requests.Request))
           )

    home = render_info(home, {:tap, {:group, :requests}})
    assert [%DukaApp.Requests.Request{id: id}] = assigns(home).items
    assert id == request.id
    assert_renderable(home, extra: @extra)
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
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:tap, {:group, :requests}})
      |> render_info({:select, :receipts, 0})

    assert assigns(view).selected_request
    assert_renderable(view, extra: @extra)

    # The confirm alert is native; this is the answer it sends back.
    view = render_info(view, {:alert, :confirm_cancel})

    assert assigns(view).items == []
    assert Requests.list_requests(profile) == []
  end

  describe "attachments" do
    @describetag :tmp_dir

    defp payment_form do
      RequestFormScreen
      |> mount_screen(%{notify: self()})
      |> render_info({:change, :amount, "5000"})
      |> render_info({:change, :purpose, "Printer toner"})
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
      assert [%{attachments: [_, _]}] = Requests.list_requests(profile)

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:tap, {:group, :requests}})
        |> render_info({:select, :receipts, 0})

      assert_renderable(view, extra: @extra)

      pdf = Enum.find(request.attachments, &(&1.name == "Quote.pdf"))
      render_info(view, {:tap, {:open_attachment, pdf.id}})
      path = Attachments.path(pdf.file_name)
      assert_received {:native, :open_file, [^path]}

      # Withdrawing the request deletes its files.
      render_info(view, {:alert, :confirm_cancel})
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
