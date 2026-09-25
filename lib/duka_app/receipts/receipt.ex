defmodule DukaApp.Receipts.Receipt do
  @moduledoc """
  One receipt: Date | Vendor | Description | Amount | Category, plus whatever
  the QR code and the photo (see `DukaApp.Receipts.Photos`) contributed.

  Amounts are whole cents so totals never pick up floating-point drift.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @categories [
    "Food & Groceries",
    "Meals & Entertainment",
    "Transport",
    "Fuel",
    "Utilities",
    "Airtime & Internet",
    "Rent",
    "Health",
    "Office Supplies",
    "Other"
  ]

  @sources ~w(etims tims kra other ocr manual)

  schema "receipts" do
    field :date, :date
    field :vendor, :string
    field :description, :string
    field :amount_cents, :integer
    field :category, :string
    field :qr_content, :string
    field :source, :string, default: "manual"
    field :seller_pin, :string
    field :branch_id, :string
    field :invoice_number, :string
    field :verify_url, :string
    field :photo_path, :string
    field :ocr_text, :string
    field :verified_at, :utc_datetime
    # The manager's decision on this expense: pending, approved or rejected.
    field :approval_status, :string, default: "pending"
    field :approval_note, :string
    field :decided_at, :utc_datetime

    # Server sync (see DukaApp.Sync): the phone's id for the receipt, the
    # server's, and whether this copy has changes the server hasn't seen.
    field :client_id, :string
    field :remote_id, :string
    field :needs_push, :boolean, default: true
    field :photo_pushed, :boolean, default: false
    field :synced_at, :utc_datetime

    belongs_to :profile, DukaApp.Accounts.Profile

    timestamps()
  end

  @spec categories() :: [String.t()]
  def categories, do: @categories

  @doc "Changeset for a manager's decision on the expense."
  def decision_changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:approval_status, :approval_note, :decided_at])
    |> validate_inclusion(:approval_status, ~w(pending approved rejected))
    |> validate_length(:approval_note, max: 300)
  end

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [
      :date,
      :vendor,
      :description,
      :amount_cents,
      :category,
      :qr_content,
      :source,
      :seller_pin,
      :branch_id,
      :invoice_number,
      :verify_url,
      :photo_path,
      :ocr_text,
      :verified_at
    ])
    |> update_change(:vendor, &String.trim/1)
    |> update_change(:description, &String.trim/1)
    |> validate_required([:date, :vendor, :amount_cents, :category, :source])
    |> validate_number(:amount_cents, greater_than: 0, message: "must be more than zero")
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:source, @sources)
    |> validate_length(:vendor, max: 120)
    |> validate_length(:description, max: 500)
    |> unique_constraint([:profile_id, :qr_content],
      name: :receipts_profile_id_qr_content_index,
      message: "this receipt has already been saved"
    )
  end
end
