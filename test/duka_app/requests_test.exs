defmodule DukaApp.RequestsTest do
  use DukaApp.DataCase

  alias DukaApp.{Accounts, Receipts, Requests}

  doctest Requests

  setup do
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

  describe "refunds" do
    test "default to the receipt's total, paid to the user's own number", %{
      profile: profile,
      receipt: receipt
    } do
      draft = Requests.new_refund(profile, receipt)
      assert %{amount_cents: 245_000, method: "send_money", phone: "+254712345678"} = draft

      assert {:ok, request} =
               Requests.create_request(profile, draft, %{
                 kind: "refund",
                 receipt_id: receipt.id,
                 method: "send_money",
                 phone: "0712 345 678",
                 amount_cents: 1
               })

      # The amount always comes from the receipt.
      assert %{status: "pending", amount_cents: 245_000, phone: "+254712345678"} = request
      assert Requests.open_refund(receipt).id == request.id
    end

    test "only one open refund per receipt, but a rejected one can be asked again", %{
      profile: profile,
      receipt: receipt
    } do
      attrs = %{kind: "refund", receipt_id: receipt.id, method: "send_money", phone: "0712345678"}

      {:ok, first} =
        Requests.create_request(profile, Requests.new_refund(profile, receipt), attrs)

      assert {:error, changeset} =
               Requests.create_request(profile, Requests.new_refund(profile, receipt), attrs)

      assert %{base: ["a refund was already requested for this receipt"]} = errors_on(changeset)

      {:ok, _} = Requests.decide(first, "rejected", "Not a business expense")
      assert Requests.open_refund(receipt) == nil

      assert {:ok, _} =
               Requests.create_request(profile, Requests.new_refund(profile, receipt), attrs)
    end
  end

  describe "payments" do
    defp payment(profile, attrs) do
      Requests.create_request(
        profile,
        Requests.new_payment(),
        Map.merge(%{kind: "payment", amount_cents: 250_000, purpose: "Van fuel"}, attrs)
      )
    end

    test "send money, till and paybill each need their own details", %{profile: profile} do
      assert {:ok, %{phone: "+254722000111"}} =
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

      assert {:error, cs} =
               payment(profile, %{method: "till", till_number: "832909", purpose: ""})

      assert %{purpose: ["say what the payment is for"]} = errors_on(cs)
    end

    test "list newest first; pending totals; only pending can be withdrawn", %{profile: profile} do
      {:ok, first} = payment(profile, %{method: "till", till_number: "832909"})

      {:ok, second} =
        payment(profile, %{method: "till", till_number: "832909", amount_cents: 1_000})

      assert [%{id: id2}, %{id: id1}] = Requests.list_requests(profile)
      assert {id1, id2} == {first.id, second.id}
      assert Requests.pending_summary(profile) == %{count: 2, total: 251_000}

      {:ok, approved} = Requests.decide(second, "approved")
      assert {:error, :not_pending} = Requests.cancel_request(approved)
      assert {:ok, _} = Requests.cancel_request(first)
      assert Requests.pending_summary(profile) == %{count: 0, total: 0}
    end
  end
end
