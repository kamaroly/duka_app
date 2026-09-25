defmodule DukaApp.Screens.ReceiptFlowTest do
  # Tier-1 screen tests: the screens run in the BEAM against the sandboxed
  # database, with no device. async: false because Mob.ScreenCase screens
  # share global state.
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, Appearance, Receipts}
  alias DukaApp.Screens.{PhoneScreen, ReceiptFormScreen, ReceiptsScreen, SettingsScreen}
  alias DukaApp.Theme.{Dark, Light}

  @etims "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051300254O695LJT35ZUB2SHJ7N7"
  # :icon renders on both platforms but is missing from mob's priv/tags lists.
  @extra [:header, :search_field, :receipt_item, :receipt_detail, :icon]

  # navigated_to/1 only returns the module; these tests also check params.
  defp nav_action(view), do: view.socket.__mob__[:nav_action]

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)
    :ok
  end

  describe "phone screen" do
    alias DukaApp.FakeServer

    # A server call's reply (DukaApp.Native.background/3) arrives in the
    # test's mailbox; hand it to the screen as the phone would.
    defp reply(view, tag) do
      assert_received {^tag, result}
      render_info(view, {tag, result})
    end

    @user %{
      "id" => "u-1",
      "name" => "Wanjiku",
      "team" => "acme",
      "permissions" => %{
        "approve_receipts" => true,
        "approve_requests" => false,
        "mark_requests_paid" => false
      }
    }

    test "the server texts a code; the code connects the receipt book" do
      FakeServer.stub(fn
        {:post, "/api/auth/code", _} -> {200, %{"sent" => true}}
        {:post, "/api/auth/verify", _} -> {200, %{"token" => "tok-1", "user" => @user}}
      end)

      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "0712 345 678"})
        |> render_info({:tap, :send_code})
        |> reply(:code_sent)

      assert_received {:http, :post, "/api/auth/code",
                       %{body: {:json, %{phone: "+254712345678"}}}}

      assert assigns(view).step == :code

      view =
        view
        |> render_info({:change, :code, " 482913 "})
        |> render_info({:tap, :verify})
        |> reply(:verified)

      assert_received {:http, :post, "/api/auth/verify", %{body: {:json, %{code: "482913"}}}}
      assert navigated_to(view) == ReceiptsScreen

      assert %{
               phone: "+254712345678",
               api_token: "tok-1",
               team: "acme",
               name: "Wanjiku",
               can_approve_receipts: true,
               can_approve_requests: false
             } = Accounts.current_profile()
    end

    test "a number that isn't in a team, and a wrong code, are explained" do
      FakeServer.stub(fn
        {:post, "/api/auth/code", _} ->
          {404, %{"error" => "This number isn't in a team yet. Ask your manager to add it."}}
      end)

      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "0712345678"})
        |> render_info({:tap, :send_code})
        |> reply(:code_sent)

      assert assigns(view).error =~ "Ask your manager"
      assert assigns(view).step == :phone

      FakeServer.stub(fn
        {:post, "/api/auth/code", _} -> {200, %{"sent" => true}}
        {:post, "/api/auth/verify", _} -> {401, %{"error" => "That code is wrong or has expired"}}
      end)

      view =
        view
        |> render_info({:tap, :send_code})
        |> reply(:code_sent)
        |> render_info({:change, :code, "000000"})
        |> render_info({:tap, :verify})
        |> reply(:verified)

      assert assigns(view).error =~ "wrong or has expired"
      assert Accounts.current_profile() == nil
    end

    test "an invalid number is caught before calling the server" do
      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "123"})
        |> render_info({:tap, :send_code})

      assert assigns(view).error =~ "Kenyan mobile number"
      refute_received {:http, _, _, _}
    end

    test "offline, the receipt book can still be used without a team" do
      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "0712345678"})
        |> render_info({:tap, :send_code})
        |> reply(:code_sent)

      assert assigns(view).error =~ "Can't reach the server"

      view = render_info(view, {:tap, :offline})
      assert navigated_to(view) == ReceiptsScreen
      assert %{phone: "+254712345678", api_token: nil} = Accounts.current_profile()
    end
  end

  describe "with a signed-in profile" do
    setup do
      {:ok, profile} = Accounts.sign_in("0712345678")
      %{profile: profile}
    end

    test "every screen renders", %{profile: profile} do
      {:ok, receipt} =
        Receipts.create_receipt(profile, Receipts.new_from_qr(@etims), %{
          date: ~D[2026-09-20],
          vendor: "Naivas",
          amount_cents: 1_000,
          category: "Fuel"
        })

      for {module, params} <- [
            {PhoneScreen, %{}},
            {ReceiptsScreen, %{}},
            {ReceiptFormScreen, %{qr: @etims}},
            {ReceiptFormScreen, %{id: receipt.id}},
            {ReceiptFormScreen, %{}},
            {SettingsScreen, %{}}
          ] do
        assert_renderable(mount_screen(module, params), extra: @extra)
      end

      view = ReceiptsScreen |> mount_screen() |> render_info({:select, :receipts, 0})
      assert assigns(view).selected.id == receipt.id
      assert_renderable(view, extra: @extra)
    end

    test "the filter chips narrow the list", %{profile: profile} do
      for {vendor, category} <- [{"Naivas", "Food & Groceries"}, {"Shell", "Fuel"}] do
        {:ok, _} =
          Receipts.create_receipt(profile, Receipts.new_manual(), %{
            date: Receipts.today(),
            vendor: vendor,
            amount_cents: 1_000,
            category: category
          })
      end

      view = ReceiptsScreen |> mount_screen() |> render_info({:tap, {:group, :fuel}})
      assert Enum.map(assigns(view).receipts, & &1.vendor) == ["Shell"]
      assert_renderable(view, extra: @extra)

      view = render_info(view, {:tap, {:group, :other}})
      assert assigns(view).receipts == []
      assert text(view) =~ "No other receipts yet."

      view = render_info(view, {:tap, {:group, :all}})
      assert [_, _] = assigns(view).receipts
    end

    test "the search button shows the search box and closing it clears the search", %{
      profile: profile
    } do
      for vendor <- ["Naivas", "Shell"] do
        {:ok, _} =
          Receipts.create_receipt(profile, Receipts.new_manual(), %{
            date: Receipts.today(),
            vendor: vendor,
            amount_cents: 1_000,
            category: "Other"
          })
      end

      view = mount_screen(ReceiptsScreen)
      refute text(view) =~ "Search receipts"

      assert text(view) =~ "Spent this month"

      view = render_info(view, {:tap, :toggle_search})
      assert assigns(view).searching
      # The summary card and the scan bar make way for the results.
      refute text(view) =~ "Spent this month"
      refute text(view) =~ "Scan receipt"
      assert_renderable(view, extra: @extra)

      view = render_info(view, {:change, :search, "shell"})
      assert Enum.map(assigns(view).receipts, & &1.vendor) == ["Shell"]

      view = render_info(view, {:tap, :toggle_search})
      assert %{searching: false, query: ""} = assigns(view)
      assert text(view) =~ "Spent this month"
      assert text(view) =~ "Scan receipt"
      assert [_, _] = assigns(view).receipts
    end

    test "the month pill picks which month the card totals", %{profile: profile} do
      [this_month, last_month | _] = Receipts.recent_months(12)

      for {date, cents} <- [{Receipts.today(), 1_000}, {Date.add(last_month, 3), 7_000}] do
        {:ok, _} =
          Receipts.create_receipt(profile, Receipts.new_manual(), %{
            date: date,
            vendor: "Shop",
            amount_cents: cents,
            category: "Fuel"
          })
      end

      view = mount_screen(ReceiptsScreen)
      assert assigns(view).summary.month_total == 1_000
      assert text(view) =~ "Spent this month"

      view = render_info(view, {:alert, :month_1})
      assert assigns(view).month == last_month
      assert assigns(view).summary.month_total == 7_000
      assert assigns(view).summary.month_by_group.fuel == 7_000
      assert text(view) =~ "Spent in #{Calendar.strftime(last_month, "%B %Y")}"
      assert_renderable(view, extra: @extra)

      view = render_info(view, {:alert, :month_0})
      assert assigns(view).month == this_month
    end

    test "a new scan opens the confirm form with the QR details" do
      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:scan, :result, %{type: :qr, value: @etims}})

      assert nav_action(view) == {:push, ReceiptFormScreen, %{qr: @etims}}
    end

    test "scanning a saved receipt opens it instead of a duplicate form", %{profile: profile} do
      {:ok, receipt} =
        Receipts.create_receipt(profile, Receipts.new_from_qr(@etims), %{
          date: ~D[2026-09-20],
          vendor: "Naivas",
          amount_cents: 1_000,
          category: "Fuel"
        })

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:scan, :result, %{type: :qr, value: @etims}})

      assert assigns(view).selected.id == receipt.id
    end

    test "confirming a scan saves Date | Vendor | Description | Amount | Category", %{
      profile: profile
    } do
      view =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:change, :date, "2026-09-21"})
        |> render_info({:change, :vendor, "Carrefour Junction"})
        |> render_info({:change, :description, "Office snacks"})
        |> render_info({:change, :amount, "1,250.50"})
        |> render_info({:alert, :category_1})
        |> render_info({:tap, :save})

      assert {:reset, ReceiptsScreen, %{}, :pop} = nav_action(view)

      assert [receipt] = Receipts.list_receipts(profile)
      assert receipt.date == ~D[2026-09-21]
      assert receipt.vendor == "Carrefour Junction"
      assert receipt.description == "Office snacks"
      assert receipt.amount_cents == 125_050
      assert receipt.category == "Meals & Entertainment"
      assert receipt.seller_pin == "P051300254O"
    end

    test "bad date and amount are reported, nothing is saved", %{profile: profile} do
      view =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:change, :date, "21/09"})
        |> render_info({:change, :vendor, "Shop"})
        |> render_info({:change, :amount, "abc"})
        |> render_info({:tap, :save})

      assert %{date: _, amount: _} = assigns(view).errors
      assert Receipts.list_receipts(profile) == []
    end

    test "every text input has a visible label" do
      form = mount_screen(ReceiptFormScreen, %{qr: @etims})

      for label <- [
            "Date on receipt",
            "Vendor (shop or business name)",
            "Description (optional)",
            "Amount paid (Ksh)",
            "Category"
          ] do
        assert text(form) =~ label
      end

      assert text(mount_screen(PhoneScreen)) =~ "Phone number"

      settings = mount_screen(SettingsScreen)

      for label <- [
            "Appearance",
            "Your name (optional)",
            "Email (optional)",
            "Your KRA PIN (optional)"
          ] do
        assert text(settings) =~ label
      end
    end

    test "appearance can be switched between system, light and dark" do
      on_exit(fn -> Mob.Theme.set(DukaApp.Theme.Adaptive) end)
      view = mount_screen(SettingsScreen)
      assert assigns(view).appearance == :system

      view = render_info(view, {:tap, {:appearance, :dark}})
      assert assigns(view).appearance == :dark
      assert Appearance.current() == :dark
      assert Mob.Theme.current() == Dark.theme()
      assert_renderable(view, extra: @extra)

      render_info(view, {:tap, {:appearance, :light}})
      assert Appearance.current() == :light
      assert Mob.Theme.current() == Light.theme()

      # A fresh settings screen shows the saved choice.
      assert assigns(mount_screen(SettingsScreen)).appearance == :light
    end

    test "settings save profile details", %{profile: profile} do
      SettingsScreen
      |> mount_screen()
      |> render_info({:change, :name, "Wanjiku"})
      |> render_info({:change, :kra_pin, "a123456789b"})
      |> render_info({:change, :app_lock, true})
      |> render_info({:tap, :save})

      assert %{name: "Wanjiku", kra_pin: "A123456789B", app_lock: true} =
               Accounts.get_profile!(profile.id)
    end
  end
end
