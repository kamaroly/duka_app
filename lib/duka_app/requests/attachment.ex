defmodule DukaApp.Requests.Attachment do
  @moduledoc """
  A file supporting a payment request: an invoice, a quotation, a photo of
  the goods. Images and PDFs only.

  The file itself lives in the app's data directory (see `Attachments`);
  this row records its stored name, the name the user knows it by, its type
  and size.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "request_attachments" do
    field :file_name, :string
    field :name, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :request, DukaApp.Requests.Request

    timestamps()
  end

  @spec image?(t() | map()) :: boolean()
  def image?(%{content_type: "image/" <> _}), do: true
  def image?(_attachment), do: false
end
