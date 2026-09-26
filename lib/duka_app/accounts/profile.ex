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

    # Set by SMS sign-in with the Risiti server (see DukaApp.Api). No token
    # means the receipt book isn't connected to a team yet.
    field :api_token, :string, redact: true
    field :remote_user_id, :string
    field :team, :string
    # What the server says this person may do in their team (see /api/me).
    field :can_approve, :boolean, default: false
    field :can_mark_paid, :boolean, default: false
    field :can_list_all, :boolean, default: false
    field :can_export, :boolean, default: false

    has_many :transactions, DukaApp.Transactions.Transaction

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

  @doc "Changeset for what the server said at sign-in or /api/me."
  def server_changeset(profile, attrs) do
    cast(profile, attrs, [
      :api_token,
      :remote_user_id,
      :team,
      :name,
      :can_approve,
      :can_mark_paid,
      :can_list_all,
      :can_export
    ])
  end

  @spec connected?(t() | nil) :: boolean()
  def connected?(%__MODULE__{api_token: token}) when is_binary(token), do: true
  def connected?(_profile), do: false

  @doc "A manager is anyone the server lets approve, or pay out, transactions."
  @spec manager?(t() | nil) :: boolean()
  def manager?(%__MODULE__{} = profile),
    do: connected?(profile) and (profile.can_approve or profile.can_mark_paid)

  def manager?(_profile), do: false

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
