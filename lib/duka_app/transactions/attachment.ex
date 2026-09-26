defmodule DukaApp.Transactions.Attachment do
  @moduledoc """
  A file supporting a transaction: an invoice, a quotation, a photo of the
  goods. Images and PDFs only. (The receipt photo itself is the
  transaction's `photo_path`.)

  The file itself lives in the app's data directory (see `Attachments`);
  this row records its stored name, the name the user knows it by, its type
  and size. `remote_id` is its id on the server once it's there; one pulled
  from the server has no file until it's opened.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "transaction_attachments" do
    field :file_name, :string
    field :name, :string
    field :content_type, :string
    field :size, :integer
    # Its id on the server once sent, or when it came from there.
    field :remote_id, :string

    belongs_to :transaction, DukaApp.Transactions.Transaction

    timestamps()
  end

  @spec image?(t() | map()) :: boolean()
  def image?(%{content_type: "image/" <> _}), do: true
  def image?(_attachment), do: false
end
