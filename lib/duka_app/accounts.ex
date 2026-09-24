defmodule DukaApp.Accounts do
  @moduledoc """
  Phone-number profiles. Everything stays on the device: "signing in" picks
  (or creates) the profile for a number and marks it as the current one, so
  several people can keep separate receipt books on a shared phone.
  """

  import Ecto.Query, only: [from: 2]

  alias DukaApp.Accounts.Profile
  alias DukaApp.Repo

  @doc "The most recently signed-in profile, or nil on first launch."
  @spec current_profile() :: Profile.t() | nil
  def current_profile do
    Repo.one(
      from p in Profile,
        where: not is_nil(p.last_signed_in_at),
        order_by: [desc: p.last_signed_in_at, desc: p.id],
        limit: 1
    )
  end

  @spec get_profile!(integer()) :: Profile.t()
  def get_profile!(id), do: Repo.get!(Profile, id)

  @doc """
  Finds the profile for `phone`, creating it if needed, and makes it current.
  """
  @spec sign_in(String.t()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def sign_in(phone) do
    changeset = Profile.phone_changeset(%Profile{}, %{phone: phone})

    with {:ok, %{phone: normalized}} <- Ecto.Changeset.apply_action(changeset, :insert) do
      profile = Repo.get_by(Profile, phone: normalized) || %Profile{phone: normalized}

      profile
      |> Ecto.Changeset.change(last_signed_in_at: now())
      |> Repo.insert_or_update()
    end
  end

  @doc "Clears the current profile so the next launch asks for a number."
  @spec sign_out(Profile.t()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def sign_out(%Profile{} = profile) do
    profile
    |> Ecto.Changeset.change(last_signed_in_at: nil)
    |> Repo.update()
  end

  @spec update_settings(Profile.t(), map()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def update_settings(%Profile{} = profile, attrs) do
    profile
    |> Profile.settings_changeset(attrs)
    |> Repo.update()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
