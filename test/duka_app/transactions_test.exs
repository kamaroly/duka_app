defmodule DukaApp.TransactionsTest do
  use DukaApp.DataCase

  alias DukaApp.{Accounts, Repo, Transactions}
  alias DukaApp.Transactions.Transaction

  doctest Transactions

  @etims "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051234567X00ABCDEF0123456789"

  setup do
    {:ok, profile} = Accounts.sign_in("0712345678")
    %{profile: profile}
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        date: Transactions.today(),
        vendor: "Naivas Westlands",
        description: "Weekly shopping",
        amount_cents: 245_000,
        category: "Food & Groceries"
      },
      overrides
    )
  end

  defp expense(profile, overrides \\ %{}),
    do: Transactions.create_transaction(profile, Transactions.new_expense(), attrs(overrides))

  # As a sync would record a decision from the server.
  defp decided(transaction, status) do
    transaction
    |> Transaction.decision_changeset(%{status: status})
    |> Ecto.Changeset.change(needs_push: false)
    |> Repo.update!()
  end

  describe "expenses" do
    test "saves a scanned receipt with its QR details", %{profile: profile} do
      draft = Transactions.new_from_qr(@etims)
      assert {:ok, receipt} = Transactions.create_transaction(profile, draft, attrs())

      assert %{type: "expense", pay_to: nil, source: "etims", seller_pin: "P051234567X"} = receipt
      assert receipt.qr_content == @etims
      assert Transactions.find_by_qr(profile, @etims).id == receipt.id
    end

    test "the same QR code cannot be saved twice for one profile", %{profile: profile} do
      {:ok, _} =
        Transactions.create_transaction(profile, Transactions.new_from_qr(@etims), attrs())

      assert {:error, changeset} =
               Transactions.create_transaction(profile, Transactions.new_from_qr(@etims), attrs())

      assert %{profile_id: ["this receipt has already been saved"]} = errors_on(changeset)
    end

    test "another phone number can save the same QR code" do
      {:ok, alice} = Accounts.sign_in("0711111111")
      {:ok, bob} = Accounts.sign_in("0722222222")

      assert {:ok, _} =
               Transactions.create_transaction(alice, Transactions.new_from_qr(@etims), attrs())

      assert {:ok, _} =
               Transactions.create_transaction(bob, Transactions.new_from_qr(@etims), attrs())

      assert [_] = Transactions.list_transactions(alice)
    end

    test "requires vendor, a positive amount and a known category", %{profile: profile} do
      assert {:error, changeset} =
               expense(profile, %{vendor: "", amount_cents: 0, category: "Bananas"})

      assert %{vendor: [_], amount_cents: [_], category: [_]} = errors_on(changeset)
    end

    test "lists newest first and searches vendor, description and category", %{
      profile: profile
    } do
      {:ok, old} = expense(profile, %{date: ~D[2026-01-05]})

      {:ok, new} =
        expense(profile, %{vendor: "Total Energies", category: "Fuel", description: "Diesel"})

      assert Enum.map(Transactions.list_transactions(profile), & &1.id) == [new.id, old.id]
      assert [%{id: id}] = Transactions.list_transactions(profile, "diesel")
      assert id == new.id
      assert [%{id: ^id}] = Transactions.list_transactions(profile, "FUEL")
      assert Transactions.list_transactions(profile, "100%") == []
    end

    test "summary totals everything but rejections, and this month separately", %{
      profile: profile
    } do
      {:ok, _} = expense(profile, %{amount_cents: 1_000})

      {:ok, _} =
        expense(profile, %{
          amount_cents: 500,
          date: Date.add(Date.beginning_of_month(Transactions.today()), -1)
        })

      {:ok, rejected} = expense(profile, %{amount_cents: 7_000})
      decided(rejected, "rejected")

      assert %{count: 2, total: 1_500, month_total: 1_000} = Transactions.summary(profile)
    end

    test "filters by spending group, or to claims, and totals this month per group", %{
      profile: profile
    } do
      today = Transactions.today()
      last_month = Date.add(Date.beginning_of_month(today), -1)

      for {vendor, category, cents, date} <- [
            {"Naivas", "Food & Groceries", 120_500, today},
            {"Shell", "Fuel", 200_000, today},
            {"Matatu", "Transport", 10_000, today},
            {"Java", "Meals & Entertainment", 39_000, today},
            {"Landlord", "Rent", 1_500_000, last_month}
          ] do
        {:ok, _} =
          expense(profile, %{vendor: vendor, category: category, amount_cents: cents, date: date})
      end

      {:ok, _} =
        Transactions.create_transaction(profile, Transactions.new_payment(), %{
          vendor: "Kenya Power",
          amount_cents: 5_000,
          method: "paybill",
          paybill_number: "888880",
          account_number: "1234567"
        })

      vendors = fn filter ->
        profile |> Transactions.list_transactions("", filter) |> Enum.map(& &1.vendor)
      end

      assert Enum.sort(vendors.(:food)) == ["Java", "Naivas"]
      assert Enum.sort(vendors.(:fuel)) == ["Matatu", "Shell"]
      assert Enum.sort(vendors.(:other)) == ["Kenya Power", "Landlord"]
      assert vendors.(:claims) == ["Kenya Power"]
      assert [_, _, _, _, _, _] = vendors.(:all)
      assert Transactions.list_transactions(profile, "shell", :food) == []

      assert Transactions.summary(profile).month_by_group ==
               %{food: 159_500, fuel: 210_000, other: 5_000}
    end

    test "KRA receipts can be verified; others are not KRA receipts", %{profile: profile} do
      {:ok, kra} =
        Transactions.create_transaction(profile, Transactions.new_from_qr(@etims), attrs())

      {:ok, manual} = expense(profile)

      assert Transactions.kra?(kra) and Transactions.verifiable?(kra)
      refute Transactions.kra?(manual) or Transactions.verifiable?(manual)
      refute Transactions.verified?(kra)

      assert {:ok, verified} = Transactions.mark_verified(kra)
      assert Transactions.verified?(verified)
      assert Transactions.verified?(Transactions.get_transaction!(profile, kra.id))
    end

    test "changing a decided one's figures sends it back for approval and to the server", %{
      profile: profile
    } do
      {:ok, transaction} = expense(profile)
      assert is_binary(transaction.client_id)
      approved = decided(transaction, "approved")

      # A change that isn't a figure keeps the decision...
      {:ok, same} = Transactions.update_transaction(approved, %{photo_path: "receipt-1.jpg"})
      assert %{status: "approved", needs_push: true, photo_pushed: false} = same

      # ...but a new amount needs a fresh one.
      {:ok, changed} = Transactions.update_transaction(same, %{amount_cents: 300_000})
      assert %{status: "pending", decision_note: nil, decided_at: nil} = changed
    end

    test "a connected book only deletes what waits for a decision", %{profile: profile} do
      {:ok, profile} = Accounts.apply_server_user(profile, %{"token" => "t", "id" => "u1"})
      {:ok, pending} = expense(profile)
      {:ok, other} = expense(profile, %{vendor: "Other"})
      approved = decided(other, "approved")

      assert {:error, :decided} = Transactions.delete_transaction(approved)
      assert {:ok, _} = Transactions.delete_transaction(pending)

      assert [%{kind: "transaction", client_id: client_id}] = Repo.all(DukaApp.Sync.Deletion)
      assert client_id == pending.client_id
    end
  end

  describe "refunds" do
    test "an expense becomes a refund to the user's own number, and waits again", %{
      profile: profile
    } do
      {:ok, transaction} = expense(profile)
      approved = decided(transaction, "approved")

      assert {:ok, refund} =
               Transactions.request_refund(approved, %{
                 method: "send_money",
                 phone: "0712 345 678"
               })

      assert %{
               type: "refund",
               pay_to: "self",
               status: "pending",
               amount_cents: 245_000,
               phone: "+254712345678",
               needs_push: true
             } = refund

      # Only once: it's a refund now.
      assert {:error, :not_expense} = Transactions.request_refund(refund, %{})

      # Taken back while it waits, it's an expense again.
      assert {:ok, %{type: "expense", pay_to: nil, method: nil, phone: nil}} =
               Transactions.cancel_refund(refund)

      assert {:error, :not_pending} =
               Transactions.cancel_refund(decided(refund, "approved"))
    end

    test "a refund says how to pay it back", %{profile: profile} do
      {:ok, transaction} = expense(profile)

      assert {:error, cs} = Transactions.request_refund(transaction, %{method: nil})
      assert %{method: ["choose how to pay"]} = errors_on(cs)
    end
  end

  describe "payment requests" do
    defp payment(profile, overrides) do
      Transactions.create_transaction(
        profile,
        Transactions.new_payment(),
        Map.merge(
          %{vendor: "Shell Kilimani", amount_cents: 250_000, description: "Van fuel"},
          overrides
        )
      )
    end

    test "send money, till and paybill each need their own details", %{profile: profile} do
      assert {:ok, %{phone: "+254722000111", pay_to: "supplier"}} =
               payment(profile, %{method: "send_money", phone: "0722 000 111"})

      assert {:ok, %{till_number: "832909"}} =
               payment(profile, %{method: "till", till_number: "832909"})

      assert {:ok, %{paybill_number: "888880", account_number: "1234567"}} =
               payment(profile, %{
                 method: "paybill",
                 paybill_number: "888880",
                 account_number: "1234567"
               })

      assert {:error, cs} = payment(profile, %{method: "send_money", phone: "123"})
      assert %{phone: ["is not a valid Kenyan mobile number"]} = errors_on(cs)

      assert {:error, cs} = payment(profile, %{method: "till", till_number: "12"})
      assert %{till_number: ["is 5 to 7 digits"]} = errors_on(cs)

      assert {:error, cs} = payment(profile, %{method: "paybill", paybill_number: "888880"})
      assert %{account_number: ["enter the account number"]} = errors_on(cs)

      assert {:error, cs} = payment(profile, %{method: "till", till_number: "832909", vendor: ""})
      assert %{vendor: [_]} = errors_on(cs)
    end

    test "an advance pays the person themselves", %{profile: profile} do
      assert {:ok, %{pay_to: "self"}} =
               payment(profile, %{pay_to: "self", method: "send_money", phone: "0712345678"})
    end

    test "pending claims are totalled; a paid one can't be changed", %{profile: profile} do
      {:ok, first} = payment(profile, %{method: "till", till_number: "832909"})

      {:ok, second} =
        payment(profile, %{method: "till", till_number: "832909", amount_cents: 1_000})

      assert Transactions.pending_claims(profile) == %{count: 2, total: 251_000}

      {:ok, approved} = Transactions.decide(second, "approved")
      assert Transactions.pending_claims(profile) == %{count: 1, total: 250_000}

      {:ok, paid} = Transactions.decide(approved, "paid")
      assert paid.paid_at
      assert {:error, :paid} = Transactions.update_transaction(paid, %{amount_cents: 1})
      assert {:ok, _} = Transactions.delete_transaction(first)
    end
  end

  test "parse_amount handles shillings, cents and currency labels" do
    assert Transactions.parse_amount("Ksh 2,450") == {:ok, 245_000}
    assert Transactions.parse_amount("99.9") == {:ok, 9_990}
    assert Transactions.parse_amount("12.345") == :error
    assert Transactions.parse_amount("") == :error
  end
end
