defmodule DukaApp.Accounts do
  @moduledoc """
  Phone-number profiles. "Signing in" picks (or creates) the profile for a
  number and marks it as the current one, so several people can keep
  separate receipt books on a shared phone.

  A profile can also be **connected** to a team on the Risiti server
  (`connect/2`, after SMS sign-in): it then keeps the server's token and
  what the person may approve, and `DukaApp.Sync` sends its receipts and
  requests to the team.
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

  @doc """
  After SMS sign-in: signs in to the local profile for the number and
  connects it to the server with the token and user it returned.
  """
  @spec connect(String.t(), map()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def connect(phone, %{"token" => token, "user" => user}) do
    with {:ok, profile} <- sign_in(phone) do
      apply_server_user(profile, Map.put(user, "token", token))
    end
  end

  @doc "Stores what the server says about the person (from sign-in or /api/me)."
  @spec apply_server_user(Profile.t(), map()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def apply_server_user(%Profile{} = profile, user) do
    permissions = user["permissions"] || %{}

    attrs =
      %{
        remote_user_id: user["id"],
        team: user["team"],
        team_kind: user["team_kind"],
        team_name: user["team_name"],
        can_approve: permissions["approve"] == true,
        can_mark_paid: permissions["mark_paid"] == true,
        can_list_all: permissions["list_all"] == true,
        can_export: permissions["export"] == true
      }
      |> maybe_put(:api_token, user["token"])
      # The server's name fills in a blank one, never overwrites the user's.
      |> maybe_put(:name, if(blank?(profile.name), do: user["name"]))

    profile
    |> Profile.server_changeset(attrs)
    |> Repo.update()
  end

  @doc "Disconnects from the server (the receipts stay on the phone)."
  @spec disconnect(Profile.t()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def disconnect(%Profile{} = profile) do
    profile
    |> Ecto.Changeset.change(
      api_token: nil,
      team: nil,
      team_kind: nil,
      team_name: nil,
      can_approve: false,
      can_mark_paid: false,
      can_list_all: false,
      can_export: false
    )
    |> Repo.update()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp blank?(value), do: value in [nil, ""]

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
