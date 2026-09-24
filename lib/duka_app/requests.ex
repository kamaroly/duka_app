defmodule DukaApp.Requests do
  @moduledoc """
  Refund and payment requests, waiting for a manager's approval.

  Requests are kept in the on-device database like receipts, scoped to a
  profile. There is no approval backend yet: a new request stays `pending`,
  and `decide/3` is where that backend's answer will be recorded.
  """

  import Ecto.Query, only: [from: 2]

  alias DukaApp.Accounts.Profile
  alias DukaApp.Receipts.Receipt
  alias DukaApp.Repo
  alias DukaApp.Requests.{Attachment, Attachments, Request}

  # A refund in any of these states stops another one for the same receipt;
  # a rejected one doesn't, so the user can ask again.
  @open ~w(pending approved paid)

  @doc "The profile's requests, newest first, with their receipts."
  @spec list_requests(Profile.t()) :: [Request.t()]
  def list_requests(%Profile{id: profile_id}) do
    Repo.all(
      from q in Request,
        where: q.profile_id == ^profile_id,
        order_by: [desc: q.inserted_at, desc: q.id],
        preload: [:receipt, :attachments]
    )
  end

  @spec get_request!(Profile.t(), integer()) :: Request.t()
  def get_request!(%Profile{id: profile_id}, id) do
    Request
    |> Repo.get_by!(id: id, profile_id: profile_id)
    |> Repo.preload([:receipt, :attachments])
  end

  @doc "Pending requests and their total, in cents."
  @spec pending_summary(Profile.t()) :: %{count: integer(), total: integer()}
  def pending_summary(%Profile{id: profile_id}) do
    Repo.one(
      from q in Request,
        where: q.profile_id == ^profile_id and q.status == "pending",
        select: %{count: count(q.id), total: coalesce(sum(q.amount_cents), 0)}
    )
  end

  @doc "The refund already asked for this receipt (and not rejected), if any."
  @spec open_refund(Receipt.t()) :: Request.t() | nil
  def open_refund(%Receipt{id: receipt_id}) do
    Repo.one(
      from q in Request,
        where: q.receipt_id == ^receipt_id and q.kind == "refund" and q.status in ^@open,
        order_by: [desc: q.id],
        limit: 1
    )
  end

  @doc """
  A draft refund for `receipt`: its total, paid by M-Pesa to the profile's
  own number unless the user changes it.
  """
  @spec new_refund(Profile.t(), Receipt.t()) :: Request.t()
  def new_refund(%Profile{phone: phone}, %Receipt{} = receipt) do
    %Request{
      kind: "refund",
      receipt_id: receipt.id,
      receipt: receipt,
      amount_cents: receipt.amount_cents,
      method: "send_money",
      phone: phone
    }
  end

  @spec new_payment() :: Request.t()
  def new_payment, do: %Request{kind: "payment", method: "send_money"}

  @doc """
  Saves a request, with the `attachments` already stored by
  `DukaApp.Requests.Attachments.store/3`, in one transaction. A refund is
  refused when the receipt already has one that wasn't rejected, and its
  amount is always the receipt's total.
  """
  @spec create_request(Profile.t(), Request.t(), map(), [Attachment.t()]) ::
          {:ok, Request.t()} | {:error, Ecto.Changeset.t()}
  def create_request(%Profile{id: profile_id}, %Request{} = draft, attrs, attachments \\ []) do
    changeset =
      %{draft | profile_id: profile_id}
      |> Request.changeset(attrs)
      |> check_refund()

    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, request} ->
          Enum.each(attachments, &Repo.insert!(%{&1 | request_id: request.id}))
          Repo.preload(request, [:receipt, :attachments])

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp check_refund(changeset) do
    with "refund" <- Ecto.Changeset.get_field(changeset, :kind),
         receipt_id when is_integer(receipt_id) <-
           Ecto.Changeset.get_field(changeset, :receipt_id),
         %Receipt{} = receipt <- Repo.get(Receipt, receipt_id) do
      changeset = Ecto.Changeset.put_change(changeset, :amount_cents, receipt.amount_cents)

      if open_refund(receipt),
        do:
          Ecto.Changeset.add_error(
            changeset,
            :base,
            "a refund was already requested for this receipt"
          ),
        else: changeset
    else
      _ -> changeset
    end
  end

  @doc "Withdraws a request and deletes its attachments. Only a pending one can be withdrawn."
  @spec cancel_request(Request.t()) :: {:ok, Request.t()} | {:error, :not_pending}
  def cancel_request(%Request{status: "pending"} = request) do
    attachments = request |> Repo.preload(:attachments) |> Map.fetch!(:attachments)

    with {:ok, deleted} <- Repo.delete(request) do
      Attachments.delete(attachments)
      {:ok, deleted}
    end
  end

  def cancel_request(%Request{}), do: {:error, :not_pending}

  @doc """
  Records a manager's decision: `"approved"` or `"rejected"` (with an
  optional note), or `"paid"` once an approved request has been paid. For
  the approval backend to call when it syncs.
  """
  @spec decide(Request.t(), String.t(), String.t() | nil) ::
          {:ok, Request.t()} | {:error, Ecto.Changeset.t()}
  def decide(%Request{} = request, status, note \\ nil) do
    request
    |> Request.decision_changeset(%{
      status: status,
      decision_note: note,
      decided_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
    |> Repo.update()
  end

  # ── Labels ──────────────────────────────────────────────────────────────────

  @spec status_label(String.t()) :: String.t()
  def status_label("pending"), do: "Pending approval"
  def status_label("approved"), do: "Approved"
  def status_label("rejected"), do: "Rejected"
  def status_label("paid"), do: "Paid"

  @spec method_label(String.t()) :: String.t()
  def method_label("send_money"), do: "Send money"
  def method_label("till"), do: "Till (Buy Goods)"
  def method_label("paybill"), do: "Paybill"

  @doc """
  Where the money goes, in one line.

      iex> DukaApp.Requests.pay_to(%DukaApp.Requests.Request{method: "paybill", paybill_number: "400200", account_number: "12345"})
      "Paybill 400200 · Acc 12345"

      iex> DukaApp.Requests.pay_to(%DukaApp.Requests.Request{method: "send_money", phone: "+254712345678", payee_name: "Wanjiku"})
      "M-Pesa 0712 345 678 · Wanjiku"
  """
  @spec pay_to(Request.t()) :: String.t()
  def pay_to(%Request{method: "send_money", phone: phone} = request),
    do: with_payee("M-Pesa #{local_phone(phone)}", request)

  def pay_to(%Request{method: "till", till_number: till} = request),
    do: with_payee("Till #{till}", request)

  def pay_to(
        %Request{method: "paybill", paybill_number: paybill, account_number: account} = request
      ),
      do: with_payee("Paybill #{paybill} · Acc #{account}", request)

  defp with_payee(line, %Request{payee_name: name}) when is_binary(name) and name != "",
    do: "#{line} · #{name}"

  defp with_payee(line, _request), do: line

  @doc """
  A `+254…` number as it's usually written in Kenya.

      iex> DukaApp.Requests.local_phone("+254712345678")
      "0712 345 678"
  """
  @spec local_phone(String.t() | nil) :: String.t()
  def local_phone("+254" <> <<a::binary-size(3), b::binary-size(3), c::binary-size(3)>>),
    do: "0#{a} #{b} #{c}"

  def local_phone(phone), do: phone || ""
end
