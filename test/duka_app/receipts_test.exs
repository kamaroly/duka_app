defmodule DukaApp.ReceiptsTest do
  use DukaApp.DataCase

  alias DukaApp.{Accounts, Receipts}

  doctest Receipts

  @etims "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051234567X00ABCDEF0123456789"

  setup do
    {:ok, profile} = Accounts.sign_in("0712345678")
    %{profile: profile}
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        date: Receipts.today(),
        vendor: "Naivas Westlands",
        description: "Weekly shopping",
        amount_cents: 245_000,
        category: "Food & Groceries"
      },
      overrides
    )
  end

  test "saves a scanned receipt with its QR details", %{profile: profile} do
    draft = Receipts.new_from_qr(@etims)
    assert {:ok, receipt} = Receipts.create_receipt(profile, draft, attrs())

    assert receipt.source == "etims"
    assert receipt.seller_pin == "P051234567X"
    assert receipt.qr_content == @etims
    assert Receipts.find_by_qr(profile, @etims).id == receipt.id
  end

  test "the same QR code cannot be saved twice for one profile", %{profile: profile} do
    {:ok, _} = Receipts.create_receipt(profile, Receipts.new_from_qr(@etims), attrs())

    assert {:error, changeset} =
             Receipts.create_receipt(profile, Receipts.new_from_qr(@etims), attrs())

    assert %{profile_id: ["this receipt has already been saved"]} = errors_on(changeset)
  end

  test "another phone number can save the same QR code" do
    {:ok, alice} = Accounts.sign_in("0711111111")
    {:ok, bob} = Accounts.sign_in("0722222222")

    assert {:ok, _} = Receipts.create_receipt(alice, Receipts.new_from_qr(@etims), attrs())
    assert {:ok, _} = Receipts.create_receipt(bob, Receipts.new_from_qr(@etims), attrs())
    assert [_] = Receipts.list_receipts(alice)
  end

  test "requires vendor, a positive amount and a known category", %{profile: profile} do
    assert {:error, changeset} =
             Receipts.create_receipt(
               profile,
               Receipts.new_manual(),
               attrs(%{vendor: "", amount_cents: 0, category: "Bananas"})
             )

    assert %{vendor: [_], amount_cents: [_], category: [_]} = errors_on(changeset)
  end

  test "lists newest first and searches vendor, description and category", %{profile: profile} do
    {:ok, old} =
      Receipts.create_receipt(profile, Receipts.new_manual(), attrs(%{date: ~D[2026-01-05]}))

    {:ok, new} =
      Receipts.create_receipt(
        profile,
        Receipts.new_manual(),
        attrs(%{vendor: "Total Energies", category: "Fuel", description: "Diesel"})
      )

    assert Enum.map(Receipts.list_receipts(profile), & &1.id) == [new.id, old.id]
    assert [%{id: id}] = Receipts.list_receipts(profile, "diesel")
    assert id == new.id
    assert [%{id: ^id}] = Receipts.list_receipts(profile, "FUEL")
    assert Receipts.list_receipts(profile, "100%") == []
  end

  test "summary totals everything and this month separately", %{profile: profile} do
    {:ok, _} =
      Receipts.create_receipt(profile, Receipts.new_manual(), attrs(%{amount_cents: 1_000}))

    {:ok, _} =
      Receipts.create_receipt(
        profile,
        Receipts.new_manual(),
        attrs(%{amount_cents: 500, date: Date.add(Date.beginning_of_month(Receipts.today()), -1)})
      )

    assert %{count: 2, total: 1_500, month_total: 1_000} = Receipts.summary(profile)
  end

  test "filters by spending group and totals this month per group", %{profile: profile} do
    last_month = Date.add(Date.beginning_of_month(Receipts.today()), -1)

    for {vendor, category, cents, date} <- [
          {"Naivas", "Food & Groceries", 120_500, Receipts.today()},
          {"Shell", "Fuel", 200_000, Receipts.today()},
          {"Matatu", "Transport", 10_000, Receipts.today()},
          {"Java", "Meals & Entertainment", 39_000, Receipts.today()},
          {"Landlord", "Rent", 1_500_000, last_month}
        ] do
      {:ok, _} =
        Receipts.create_receipt(
          profile,
          Receipts.new_manual(),
          attrs(%{vendor: vendor, category: category, amount_cents: cents, date: date})
        )
    end

    vendors = fn group ->
      profile |> Receipts.list_receipts("", group) |> Enum.map(& &1.vendor)
    end

    assert Enum.sort(vendors.(:food)) == ["Java", "Naivas"]
    assert Enum.sort(vendors.(:fuel)) == ["Matatu", "Shell"]
    assert vendors.(:other) == ["Landlord"]
    assert length(vendors.(:all)) == 5
    assert Receipts.list_receipts(profile, "shell", :food) == []

    assert Receipts.summary(profile).month_by_group == %{food: 159_500, fuel: 210_000, other: 0}
  end

  test "parse_amount handles shillings, cents and currency labels" do
    assert Receipts.parse_amount("Ksh 2,450") == {:ok, 245_000}
    assert Receipts.parse_amount("99.9") == {:ok, 9_990}
    assert Receipts.parse_amount("12.345") == :error
    assert Receipts.parse_amount("") == :error
  end
end
