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
    test "a valid number signs in and opens the receipts" do
      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "0712345678"})
        |> render_info({:tap, :continue})

      assert Accounts.current_profile().phone == "+254712345678"
      assert navigated_to(view) == ReceiptsScreen
    end

    test "an invalid number shows an error and stays put" do
      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "123"})
        |> render_info({:tap, :continue})

      assert assigns(view).error =~ "Kenyan mobile number"
      assert Accounts.current_profile() == nil
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
      # The summary card makes way for the results while searching.
      refute text(view) =~ "Spent this month"
      assert_renderable(view, extra: @extra)

      view = render_info(view, {:change, :search, "shell"})
      assert Enum.map(assigns(view).receipts, & &1.vendor) == ["Shell"]

      view = render_info(view, {:tap, :toggle_search})
      assert %{searching: false, query: ""} = assigns(view)
      assert text(view) =~ "Spent this month"
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
