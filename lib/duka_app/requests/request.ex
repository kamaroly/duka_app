defmodule DukaApp.Requests.Request do
  @moduledoc """
  A request for money, waiting for a manager's approval.

    * **refund** — money back for a saved receipt the user paid for. The
      amount is the receipt's total.
    * **payment** — asks for a payment to be made: M-Pesa send money to a
      phone, a Buy Goods till, or a paybill with an account number.

  Status runs `pending` → `approved` | `rejected`, and `approved` → `paid`.
  Until the approval backend exists every request stays `pending` on the
  phone; `submitted_at`, `decided_at` and `decision_note` are for that
  backend to fill in.

  Amounts are whole cents, like receipts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias DukaApp.Accounts.Profile

  @type t :: %__MODULE__{}

  @kinds ~w(refund payment)
  @statuses ~w(pending approved rejected paid)
  @methods ~w(send_money till paybill)

  # M-Pesa till and paybill numbers are 5 to 7 digits.
  @business_number ~r/^\d{5,7}$/

  schema "requests" do
    field :kind, :string
    field :status, :string, default: "pending"
    field :amount_cents, :integer
    field :purpose, :string
    field :method, :string
    field :phone, :string
    field :till_number, :string
    field :paybill_number, :string
    field :account_number, :string
    field :payee_name, :string
    field :submitted_at, :utc_datetime
    field :decided_at, :utc_datetime
    field :decision_note, :string

    belongs_to :profile, DukaApp.Accounts.Profile
    belongs_to :receipt, DukaApp.Receipts.Receipt

    timestamps()
  end

  @spec methods() :: [String.t()]
  def methods, do: @methods

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Changeset for a new request, as the user fills it in."
  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :kind,
      :amount_cents,
      :purpose,
      :receipt_id,
      :method,
      :phone,
      :till_number,
      :paybill_number,
      :account_number,
      :payee_name
    ])
    |> trim([:purpose, :phone, :till_number, :paybill_number, :account_number, :payee_name])
    |> validate_required([:kind, :amount_cents, :method])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:method, @methods)
    |> validate_number(:amount_cents, greater_than: 0, message: "must be more than zero")
    |> validate_length(:purpose, max: 300)
    |> validate_length(:payee_name, max: 120)
    |> validate_kind()
    |> validate_method()
  end

  @doc "Changeset for the manager's decision (and for marking an approved request paid)."
  def decision_changeset(request, attrs) do
    request
    |> cast(attrs, [:status, :decided_at, :decision_note, :submitted_at])
    |> validate_inclusion(:status, @statuses)
  end

  defp validate_kind(changeset) do
    case get_field(changeset, :kind) do
      "refund" ->
        validate_required(changeset, [:receipt_id], message: "pick the receipt to refund")

      "payment" ->
        validate_required(changeset, [:purpose], message: "say what the payment is for")

      _ ->
        changeset
    end
  end

  defp validate_method(changeset) do
    case get_field(changeset, :method) do
      "send_money" ->
        changeset
        |> validate_required([:phone], message: "enter the phone number to pay")
        |> normalize_phone()

      "till" ->
        changeset
        |> validate_required([:till_number], message: "enter the till number")
        |> validate_format(:till_number, @business_number, message: "is 5 to 7 digits")

      "paybill" ->
        changeset
        |> validate_required([:paybill_number], message: "enter the paybill number")
        |> validate_format(:paybill_number, @business_number, message: "is 5 to 7 digits")
        |> validate_required([:account_number], message: "enter the account number")
        |> validate_length(:account_number, max: 20)

      _ ->
        changeset
    end
  end

  defp normalize_phone(changeset) do
    case get_field(changeset, :phone) do
      nil ->
        changeset

      raw ->
        case Profile.normalize(raw) do
          {:ok, phone} -> put_change(changeset, :phone, phone)
          :error -> add_error(changeset, :phone, "is not a valid Kenyan mobile number")
        end
    end
  end

  defp trim(changeset, fields) do
    Enum.reduce(fields, changeset, &update_change(&2, &1, fn value -> blank_to_nil(value) end))
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
