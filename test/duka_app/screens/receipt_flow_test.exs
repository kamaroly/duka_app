defmodule DukaApp.Screens.ReceiptFlowTest do
  # Tier-1 screen tests: the screens run in the BEAM against the sandboxed
  # database, with no device. async: false because Mob.ScreenCase screens
  # share global state.
  use Mob.ScreenCase, async: false

  alias DukaApp.{Accounts, Appearance, Transactions}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Screens.{PhoneScreen, ReceiptFormScreen, ReceiptsScreen, SettingsScreen}
  alias DukaApp.Theme.{Dark, Light}

  @etims "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051300254O695LJT35ZUB2SHJ7N7"
  # :icon renders on both platforms but is missing from mob's priv/tags lists.
  @extra [:header, :search_field, :transaction_item, :transaction_sheet, :icon]

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
        "approve" => true,
        "mark_paid" => false,
        "list_all" => false,
        "export" => false
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
               can_approve: true,
               can_mark_paid: false
             } = Accounts.current_profile()
    end

    test "someone new signs up with Google, giving their M-Pesa number" do
      FakeServer.stub(fn
        {:post, "/api/auth/google", _} ->
          {200,
           %{"needs_registration" => true, "signup_token" => "signup-g", "name" => "Achieng O."}}

        {:post, "/api/auth/register", _} ->
          {201,
           %{
             "token" => "tok-g",
             "user" => %{"id" => "u-g", "team" => "p_x", "team_kind" => "personal"}
           }}
      end)

      view = PhoneScreen |> mount_screen() |> render_info({:tap, :google})
      assert_received {:native, :google_sign_in, []}

      view =
        view
        |> render_info({:google, :result, ~s({"id_token":"google-jwt","email":"a@gmail.com"})})
        |> reply(:google_verified)

      assert_received {:http, :post, "/api/auth/google",
                       %{body: {:json, %{id_token: "google-jwt"}}}}

      assert %{step: :register, name: "Achieng O.", via: :google} = assigns(view)
      assert_renderable(view, extra: @extra)

      # The M-Pesa number is needed: the book is kept under it.
      view = render_info(view, {:tap, :register})
      assert assigns(view).error =~ "M-Pesa number"

      view =
        view
        |> render_info({:change, :phone, "0712 345 678"})
        |> render_info({:tap, :register})
        |> reply(:registered)

      assert navigated_to(view) == ReceiptsScreen
      assert %{phone: "+254712345678", api_token: "tok-g"} = Accounts.current_profile()
    end

    test "Google signs in someone the server knows; cancelling does nothing" do
      FakeServer.stub(fn
        {:post, "/api/auth/google", _} ->
          {200, %{"token" => "tok-k", "user" => Map.put(@user, "phone", nil)}}
      end)

      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:tap, :google})
        |> render_info({:google, :error, ~s({"message":"cancelled"})})

      assert %{busy: false, error: nil, step: :phone} = assigns(view)

      view =
        view
        |> render_info({:tap, :google})
        |> render_info({:google, :result, ~s({"id_token":"google-jwt"})})
        |> reply(:google_verified)

      # No number confirmed by SMS on the server: which is theirs?
      assert assigns(view).step == :google_phone

      view =
        view
        |> render_info({:change, :phone, "0722 000 111"})
        |> render_info({:tap, :finish_google})

      assert navigated_to(view) == ReceiptsScreen
      assert %{phone: "+254722000111", api_token: "tok-k"} = Accounts.current_profile()
    end

    test "a refused code, and a wrong code, are explained" do
      FakeServer.stub(fn
        {:post, "/api/auth/code", _} ->
          {429, %{"error" => "Too many codes. Try again in an hour."}}
      end)

      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "0712345678"})
        |> render_info({:tap, :send_code})
        |> reply(:code_sent)

      assert assigns(view).error =~ "Too many codes"
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

    test "a new number signs up: just me is a free personal book" do
      FakeServer.stub(fn
        {:post, "/api/auth/code", _} ->
          {200, %{"sent" => true}}

        {:post, "/api/auth/verify", _} ->
          {200, %{"needs_registration" => true, "signup_token" => "signup-1"}}

        {:post, "/api/auth/register", _} ->
          {201,
           %{
             "token" => "tok-2",
             "user" => %{
               "id" => "u-2",
               "name" => "Achieng",
               "team" => "p_abc",
               "team_kind" => "personal",
               "team_name" => "Personal",
               "permissions" => %{"approve" => true, "mark_paid" => true}
             }
           }}
      end)

      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "0712345678"})
        |> render_info({:tap, :send_code})
        |> reply(:code_sent)
        |> render_info({:change, :code, "482913"})
        |> render_info({:tap, :verify})
        |> reply(:verified)

      assert assigns(view).step == :register
      assert_renderable(view, extra: @extra)

      # A name is needed.
      view = render_info(view, {:tap, :register})
      assert assigns(view).error =~ "your name"
      refute_received {:http, :post, "/api/auth/register", _}

      view =
        view
        |> render_info({:change, :name, "Achieng"})
        |> render_info({:tap, :register})
        |> reply(:registered)

      assert_received {:http, :post, "/api/auth/register",
                       %{
                         body:
                           {:json, %{signup_token: "signup-1", name: "Achieng", team_name: ""}}
                       }}

      assert navigated_to(view) == ReceiptsScreen

      profile = Accounts.current_profile()
      assert %{api_token: "tok-2", team_kind: "personal"} = profile

      # Nobody else to approve in a personal book.
      assert Profile.personal?(profile)
      refute Profile.manager?(profile)
    end

    test "a new number signs up a business, with its name" do
      FakeServer.stub(fn
        {:post, "/api/auth/code", _} ->
          {200, %{"sent" => true}}

        {:post, "/api/auth/verify", _} ->
          {200, %{"needs_registration" => true, "signup_token" => "signup-1"}}

        {:post, "/api/auth/register", _} ->
          {201, %{"token" => "tok-3", "user" => Map.put(@user, "team_kind", "business")}}
      end)

      view =
        PhoneScreen
        |> mount_screen()
        |> render_info({:change, :phone, "0712345678"})
        |> render_info({:tap, :send_code})
        |> reply(:code_sent)
        |> render_info({:change, :code, "482913"})
        |> render_info({:tap, :verify})
        |> reply(:verified)
        |> render_info({:change, :name, "Achieng"})
        |> render_info({:tap, {:for, :business}})

      view = render_info(view, {:tap, :register})
      assert assigns(view).error =~ "business a name"

      view
      |> render_info({:change, :team_name, "Achieng Traders"})
      |> render_info({:tap, :register})
      |> reply(:registered)

      assert_received {:http, :post, "/api/auth/register",
                       %{body: {:json, %{team_name: "Achieng Traders"}}}}

      assert %{team_kind: "business"} = Accounts.current_profile()
    end
  end

  describe "with a signed-in profile" do
    setup do
      {:ok, profile} = Accounts.sign_in("0712345678")
      %{profile: profile}
    end

    test "every screen renders", %{profile: profile} do
      {:ok, receipt} =
        Transactions.create_transaction(profile, Transactions.new_from_qr(@etims), %{
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
          Transactions.create_transaction(profile, Transactions.new_expense(), %{
            date: Transactions.today(),
            vendor: vendor,
            amount_cents: 1_000,
            category: category
          })
      end

      view = ReceiptsScreen |> mount_screen() |> render_info({:tap, {:group, :fuel}})
      assert Enum.map(assigns(view).items, & &1.vendor) == ["Shell"]
      assert_renderable(view, extra: @extra)

      view = render_info(view, {:tap, {:group, :other}})
      assert assigns(view).items == []
      assert text(view) =~ "No other expenses yet."

      view = render_info(view, {:tap, {:group, :all}})
      assert [_, _] = assigns(view).items
    end

    test "the search button shows the search box and closing it clears the search", %{
      profile: profile
    } do
      for vendor <- ["Naivas", "Shell"] do
        {:ok, _} =
          Transactions.create_transaction(profile, Transactions.new_expense(), %{
            date: Transactions.today(),
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
      assert Enum.map(assigns(view).items, & &1.vendor) == ["Shell"]

      view = render_info(view, {:tap, :toggle_search})
      assert %{searching: false, query: ""} = assigns(view)
      assert text(view) =~ "Spent this month"
      assert text(view) =~ "Scan receipt"
      assert [_, _] = assigns(view).items
    end

    test "the month pill picks which month the card totals", %{profile: profile} do
      [this_month, last_month | _] = Transactions.recent_months(12)

      for {date, cents} <- [{Transactions.today(), 1_000}, {Date.add(last_month, 3), 7_000}] do
        {:ok, _} =
          Transactions.create_transaction(profile, Transactions.new_expense(), %{
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
        Transactions.create_transaction(profile, Transactions.new_from_qr(@etims), %{
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

      assert [receipt] = Transactions.list_transactions(profile)
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
      assert Transactions.list_transactions(profile) == []
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
