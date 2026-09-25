defmodule DukaApp.Screens.PhotoFlowTest do
  # The photo -> OCR -> confirm flow. `config :duka_app, :native, false`
  # turns each native call into a {:native, name, args} message to the test
  # process; the tests then feed back the reply the phone would send.
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, Receipts}
  alias DukaApp.Receipts.Photos
  alias DukaApp.Screens.{ReceiptFormScreen, ReceiptsScreen}

  @etims "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051234567X00ABCDEF0123456789"
  @ocr_text "NAIVAS LIMITED\nPIN: P051234567X\nTOTAL  2,450.00\nDate: 21/09/2026"

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)
    File.rm_rf!(Photos.dir())
    {:ok, profile} = Accounts.sign_in("0712345678")
    %{profile: profile}
  end

  defp nav_action(view), do: view.socket.__mob__[:nav_action]

  # What the phone would do: write the processed JPEG, reply with the JSON.
  defp ocr_reply(dest, text, qr \\ nil) do
    File.write!(dest, "jpeg")
    json = :json.encode(%{"text" => text, "qr" => qr || :null, "path" => dest})
    {:ocr, :result, IO.iodata_to_binary(json)}
  end

  defp start_photo_form do
    view = mount_screen(ReceiptFormScreen, %{photo: "/cache/mob_cam_1.jpg"})
    assert_received {:native, :process_photo, ["/cache/mob_cam_1.jpg", dest]}
    {view, dest}
  end

  test "Scan receipt asks for the camera, takes a photo and opens the form" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :take_photo})
    assert_received {:native, :request_camera, []}

    view = render_info(view, {:permission, :camera, :granted})
    assert_received {:native, :take_photo, []}

    view =
      render_info(view, {:camera, :photo, %{path: "/cache/mob_cam_1.jpg", width: 1, height: 1}})

    assert nav_action(view) == {:push, ReceiptFormScreen, %{photo: "/cache/mob_cam_1.jpg"}}
  end

  describe "KRA lookup" do
    @kra_details %{
      vendor: "Stabex International Limited",
      date: ~D[2026-09-20],
      amount_cents: 199_845,
      description: "Unleaded",
      invoice_number: "KRACU0300010612/58385"
    }

    test "a scanned eTIMS code fills the form from KRA's record" do
      view = mount_screen(ReceiptFormScreen, %{qr: @etims})
      assert_received {:native, :lookup_kra, [@etims]}
      assert assigns(view).notice =~ "from KRA"

      view = render_info(view, {:kra, :result, @kra_details})

      assert %{
               vendor: "Stabex International Limited",
               date: "2026-09-20",
               amount: "1998.45",
               description: "Unleaded"
             } = assigns(view)

      assert assigns(view).notice =~ "Verified with KRA and filled in"
    end

    test "a receipt filled from KRA is saved as verified", %{profile: profile} do
      view =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:kra, :result, @kra_details})

      assert assigns(view).receipt.verified_at
      assert_renderable(view, extra: [:header, :icon])

      render_info(view, {:tap, :save})
      assert [receipt] = Receipts.list_receipts(profile)
      assert Receipts.verified?(receipt)
    end

    defp save_kra_receipt(profile, cents \\ 200_000) do
      {:ok, receipt} =
        Receipts.create_receipt(profile, Receipts.new_from_qr(@etims), %{
          date: ~D[2026-09-20],
          vendor: "Stabex",
          amount_cents: cents,
          category: "Fuel"
        })

      receipt
    end

    test "saved KRA receipts are verified quietly in the background", %{profile: profile} do
      receipt = save_kra_receipt(profile)
      refute Receipts.verified?(receipt)

      view = mount_screen(ReceiptsScreen)
      ref = {:verify, receipt.id}
      assert_received {:native, :lookup_kra, [@etims, ^ref]}

      render_info(view, {:kra, :result, @kra_details, ref})
      assert Receipts.verified?(Receipts.get_receipt!(profile, receipt.id))
      refute_received {:native, :toast, _}
    end

    test "a failed background check isn't retried on the same screen", %{profile: profile} do
      receipt = save_kra_receipt(profile)
      view = mount_screen(ReceiptsScreen)
      assert_received {:native, :lookup_kra, [@etims, {:verify, _}]}

      render_info(view, {:kra, :error, :nxdomain, {:verify, receipt.id}})
      refute_received {:native, :lookup_kra, _}
      refute_received {:native, :toast, _}
      refute Receipts.verified?(Receipts.get_receipt!(profile, receipt.id))
    end

    test "tapping Verify tells the user how it went", %{profile: profile} do
      receipt = save_kra_receipt(profile)
      ref = {:verify, receipt.id}

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:select, :receipts, 0})
        |> render_info({:tap, :verify_receipt})

      # The background check already running for it is reused, not repeated.
      assert_received {:native, :lookup_kra, [@etims, ^ref]}
      refute_received {:native, :lookup_kra, _}
      assert_received {:native, :toast, ["Checking with KRA…"]}

      view = render_info(view, {:kra, :result, @kra_details, ref})

      assert Receipts.verified?(assigns(view).selected)
      assert Receipts.verified?(Receipts.get_receipt!(profile, receipt.id))
      # The saved total differs from KRA's, so the user is told.
      assert_received {:native, :toast, ["Verified with KRA — but KRA's total is Ksh 1,998.45"]}

      assert_renderable(view,
        extra: [:header, :icon, :receipt_item, :receipt_detail, :search_field]
      )
    end

    test "a failed tap-to-verify says so", %{profile: profile} do
      receipt = save_kra_receipt(profile, 199_845)

      ReceiptsScreen
      |> mount_screen()
      |> render_info({:select, :receipts, 0})
      |> render_info({:tap, :verify_receipt})
      |> render_info({:kra, :error, :timeout, {:verify, receipt.id}})

      refute Receipts.verified?(Receipts.get_receipt!(profile, receipt.id))
      assert_received {:native, :toast, ["Couldn't reach KRA" <> _]}
    end

    test "the photo opens full screen and can be saved to the gallery", %{profile: profile} do
      {:ok, _} =
        Receipts.create_receipt(profile, Receipts.new_manual(), %{
          date: ~D[2026-09-20],
          vendor: "Naivas",
          amount_cents: 1_000,
          category: "Other",
          photo_path: "receipt-1.jpg"
        })

      File.write!(Photos.path("receipt-1.jpg"), "jpeg")

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:select, :receipts, 0})
        |> render_info({:tap, :view_photo})

      assert assigns(view).viewing_photo
      assert_renderable(view, extra: [:header, :icon])

      view = render_info(view, {:tap, :save_photo})
      path = Photos.path("receipt-1.jpg")
      assert_received {:native, :save_to_gallery, [^path]}

      render_info(view, {:storage, :saved_to_library, path})
      assert_received {:native, :toast, ["Saved to your phone's gallery"]}

      view = render_info(view, {:tap, :close_photo})
      refute assigns(view).viewing_photo
      assert assigns(view).selected
    end

    test "KRA doesn't overwrite what the user typed, and a later photo doesn't overwrite KRA" do
      view =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:change, :vendor, "Stabex Karen"})
        |> render_info({:kra, :result, @kra_details})

      assert assigns(view).vendor == "Stabex Karen"
      assert assigns(view).amount == "1998.45"

      view = render_info(view, {:tap, :take_photo})
      view = render_info(view, {:permission, :camera, :granted})
      view = render_info(view, {:camera, :photo, %{path: "/cache/mob_cam_3.jpg"}})
      assert_received {:native, :process_photo, [_, dest]}

      view = render_info(view, ocr_reply(dest, @ocr_text))
      assert assigns(view).amount == "1998.45"
      assert assigns(view).date == "2026-09-20"
    end

    test "a failed lookup says so and leaves the form to the user" do
      view =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:kra, :error, :timeout})

      assert assigns(view).notice =~ "Couldn't get this receipt from KRA"
      assert assigns(view).vendor == ""
    end

    test "a QR code found in a photo is looked up too" do
      {view, dest} = start_photo_form()
      render_info(view, ocr_reply(dest, @ocr_text, @etims))
      assert_received {:native, :lookup_kra, [@etims]}
    end

    test "a QR code that isn't a KRA link is not looked up" do
      mount_screen(ReceiptFormScreen, %{qr: "https://l.ead.me/beUwqW"})
      refute_received {:native, :lookup_kra, _}
    end
  end

  test "Scan QR only still opens the QR scanner" do
    ReceiptsScreen
    |> mount_screen()
    |> render_info({:tap, :scan_qr})
    |> render_info({:permission, :camera, :granted})

    assert_received {:native, :scan_qr, []}
  end

  test "OCR fills the form, the QR in the photo is attached, and saving keeps the photo",
       %{profile: profile} do
    {view, dest} = start_photo_form()
    assert assigns(view).reading
    assert_renderable(view, extra: [:header, :icon])

    view = render_info(view, ocr_reply(dest, @ocr_text, @etims))

    assert %{vendor: "Naivas Limited", date: "2026-09-21", amount: "2450.00", reading: false} =
             assigns(view)

    assert assigns(view).notice =~ "Read the vendor, date, total"
    assert assigns(view).receipt.source == "etims"
    assert_renderable(view, extra: [:header, :icon])

    view = view |> render_info({:alert, :category_0}) |> render_info({:tap, :save})
    assert {:reset, ReceiptsScreen, _, _} = nav_action(view)

    assert [receipt] = Receipts.list_receipts(profile)
    assert receipt.photo_path == Path.basename(dest)
    assert receipt.ocr_text == @ocr_text
    assert receipt.seller_pin == "P051234567X"
    assert receipt.qr_content == @etims
    assert File.exists?(Photos.path(receipt.photo_path))

    # Search covers the text read off the photo.
    assert [_] = Receipts.list_receipts(profile, "p051234567x")
  end

  test "text read off a photo never overwrites what the user typed" do
    {view, dest} = start_photo_form()

    view =
      view
      |> render_info({:change, :vendor, "Naivas Westlands"})
      |> render_info(ocr_reply(dest, @ocr_text))

    assert assigns(view).vendor == "Naivas Westlands"
    assert assigns(view).amount == "2450.00"
    assert assigns(view).receipt.source == "ocr"
  end

  test "retaking replaces the unsaved photo; going back deletes it" do
    {view, first} = start_photo_form()
    view = render_info(view, ocr_reply(first, @ocr_text))

    view =
      view
      |> render_info({:tap, :take_photo})
      |> render_info({:permission, :camera, :granted})
      |> render_info({:camera, :photo, %{path: "/cache/mob_cam_2.jpg"}})

    assert_received {:native, :take_photo, []}
    assert_received {:native, :process_photo, ["/cache/mob_cam_2.jpg", second]}
    view = render_info(view, ocr_reply(second, @ocr_text))

    refute File.exists?(first)
    assert File.exists?(second)

    render_info(view, {:tap, :header_back})
    refute File.exists?(second)
  end

  test "when OCR fails the photo is still kept and the user is told" do
    {view, dest} = start_photo_form()
    File.write!(dest, "jpeg")

    view =
      render_info(
        view,
        {:ocr, :error, IO.iodata_to_binary(:json.encode(%{"message" => "boom", "path" => dest}))}
      )

    assert assigns(view).receipt.photo_path == Path.basename(dest)
    assert assigns(view).notice =~ "Couldn't read the text"
    refute assigns(view).reading
  end

  test "a photo whose QR is already saved warns about the duplicate", %{profile: profile} do
    {:ok, _} =
      Receipts.create_receipt(profile, Receipts.new_from_qr(@etims), %{
        date: ~D[2026-09-20],
        vendor: "Naivas",
        amount_cents: 1_000,
        category: "Fuel"
      })

    {view, dest} = start_photo_form()
    view = render_info(view, ocr_reply(dest, @ocr_text, @etims))
    assert assigns(view).errors.base =~ "already saved this receipt"
  end

  test "deleting a receipt deletes its photo", %{profile: profile} do
    {view, dest} = start_photo_form()

    view
    |> render_info(ocr_reply(dest, @ocr_text))
    |> render_info({:tap, :save})

    [receipt] = Receipts.list_receipts(profile)
    {:ok, _} = Receipts.delete_receipt(receipt)
    refute File.exists?(dest)
  end

  test "MobOcr reports not_available where there is no native OCR" do
    MobOcr.process(:socket, "/tmp/x.jpg", save_to: "/tmp/y.jpg")
    assert_received {:ocr, :error, json}
    assert %{"message" => "not_available", "path" => nil} = MobOcr.decode(json)
  end
end
