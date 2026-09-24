defmodule DukaApp.Accounts.Profile do
  @moduledoc """
  The person whose receipts are on this phone, identified by phone number.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "profiles" do
    field :phone, :string
    field :name, :string
    field :email, :string
    field :kra_pin, :string
    field :app_lock, :boolean, default: false
    field :last_signed_in_at, :utc_datetime

    has_many :receipts, DukaApp.Receipts.Receipt

    timestamps()
  end

  # Individual PINs start with A, companies with P: letter, 9 digits, letter.
  @kra_pin ~r/^[AP]\d{9}[A-Z]$/

  @doc "Changeset for creating a profile from a phone number."
  def phone_changeset(profile, attrs) do
    profile
    |> cast(attrs, [:phone])
    |> normalize_phone()
    |> validate_required([:phone])
    |> unique_constraint(:phone)
  end

  @doc "Changeset for the settings screen."
  def settings_changeset(profile, attrs) do
    profile
    |> cast(attrs, [:name, :email, :kra_pin, :app_lock])
    |> update_change(:name, &String.trim/1)
    |> update_change(:email, &String.trim/1)
    |> update_change(:kra_pin, &(&1 |> String.trim() |> String.upcase()))
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "is not a valid email")
    |> validate_format(:kra_pin, @kra_pin, message: "should look like A123456789B")
  end

  defp normalize_phone(changeset) do
    case get_change(changeset, :phone) do
      nil ->
        changeset

      raw ->
        case normalize(raw) do
          {:ok, phone} -> put_change(changeset, :phone, phone)
          :error -> add_error(changeset, :phone, "is not a valid Kenyan mobile number")
        end
    end
  end

  @doc """
  Normalises a Kenyan mobile number to `+254XXXXXXXXX`.

      iex> DukaApp.Accounts.Profile.normalize("0712 345 678")
      {:ok, "+254712345678"}

      iex> DukaApp.Accounts.Profile.normalize("254110000000")
      {:ok, "+254110000000"}

      iex> DukaApp.Accounts.Profile.normalize("12345")
      :error
  """
  @spec normalize(String.t()) :: {:ok, String.t()} | :error
  def normalize(raw) when is_binary(raw) do
    digits = String.replace(raw, ~r/[\s\-()]/, "")

    case Regex.run(~r/^(?:\+?254|0)?([17]\d{8})$/, digits) do
      [_, local] -> {:ok, "+254" <> local}
      nil -> :error
    end
  end
end
