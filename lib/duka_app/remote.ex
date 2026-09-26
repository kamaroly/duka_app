defmodule DukaApp.Remote do
  @moduledoc """
  Server records (JSON from `DukaApp.Api`) as the same structs the screens
  already render, so the approver's list reuses `TransactionItem`.

  They are never saved on this phone: `id` holds the server's id (a UUID
  string), `profile` who sent it, and there are no local files — a receipt
  photo or attachment is downloaded when opened.
  """

  alias DukaApp.Accounts.Profile
  alias DukaApp.Transactions.{Attachment, Transaction}

  @spec transaction(map()) :: Transaction.t()
  def transaction(json) do
    %Transaction{
      id: json["id"],
      remote_id: json["id"],
      client_id: json["client_id"],
      type: json["type"] || "expense",
      pay_to: json["pay_to"],
      status: json["status"] || "pending",
      date: date(json["date"]),
      vendor: json["vendor"],
      description: json["description"],
      amount_cents: json["amount_cents"],
      category: json["category"],
      method: json["method"],
      phone: json["phone"],
      till_number: json["till_number"],
      paybill_number: json["paybill_number"],
      account_number: json["account_number"],
      source: json["source"] || "manual",
      seller_pin: json["seller_pin"],
      invoice_number: json["invoice_number"],
      verify_url: json["verify_url"],
      verified_at: time(json["verified_at"]),
      decision_note: json["decision_note"],
      decided_at: time(json["decided_at"]),
      paid_at: time(json["paid_at"]),
      profile: person(json["submitted_by"]),
      attachments: Enum.map(json["attachments"] || [], &attachment/1),
      photo_path: nil,
      inserted_at: naive(json["inserted_at"])
    }
    |> Map.put(:has_photo, json["has_photo"] == true)
  end

  @spec attachment(map()) :: Attachment.t()
  def attachment(json) do
    %Attachment{
      id: json["id"],
      name: json["name"],
      content_type: json["content_type"],
      size: json["size"],
      file_name: nil
    }
  end

  defp person(nil), do: nil
  defp person(json), do: %Profile{name: json["name"], phone: json["phone"]}

  defp date(nil), do: nil

  defp date(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp time(nil), do: nil

  defp time(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _} -> DateTime.truncate(at, :second)
      _ -> nil
    end
  end

  defp naive(text) do
    case time(text) do
      nil -> NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      at -> DateTime.to_naive(at)
    end
  end
end
