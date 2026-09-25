defmodule DukaApp.Push do
  @moduledoc """
  Push notifications from the team's server (`mob_notify` on the phone,
  `mob_push` on the server).

  The home screen (`ReceiptsScreen`) asks for the notification permission
  once a receipt book is connected, then registers for pushes. The phone's
  token goes to the server, which pushes when someone else acts: a manager
  hears about new receipts and requests, a requester about decisions and
  payments. A push also makes the app sync, so its lists catch up.

  The token is kept (in `Mob.State`) so disconnecting can tell the server to
  stop pushing to this phone.
  """

  alias DukaApp.Accounts.Profile
  alias DukaApp.Api

  @token_key :push_token
  # {profile id, sign-in token, push token} last sent, so a remount doesn't resend it.
  @sent_key :push_token_sent

  @doc "Keeps the token the phone got for pushes."
  @spec remember(:ios | :android, String.t()) :: :ok
  def remember(platform, token), do: put(@token_key, {platform, token})

  @doc """
  Sends this phone's push token to the server for `profile`, unless it
  already has it. Runs off the screen process (see `DukaApp.Native.background/3`).
  """
  @spec register(Profile.t()) :: :ok | {:error, term()}
  def register(%Profile{} = profile) do
    with {platform, token} <- get(@token_key),
         sent = {profile.id, profile.api_token, token},
         false <- get(@sent_key) == sent,
         {:ok, _} <- Api.register_device(profile, platform, token) do
      put(@sent_key, sent)
    else
      true -> :ok
      nil -> :ok
      {:error, _} = error -> error
    end
  end

  @doc "True when there's a push token the server hasn't been given for `profile`."
  @spec pending?(Profile.t()) :: boolean()
  def pending?(%Profile{} = profile) do
    case get(@token_key) do
      {_platform, token} -> get(@sent_key) != {profile.id, profile.api_token, token}
      nil -> false
    end
  end

  @doc "Asks the server to stop pushing to this phone for `profile` (before disconnecting)."
  @spec forget(Profile.t()) :: :ok | {:error, term()}
  def forget(%Profile{} = profile) do
    put(@sent_key, nil)

    case get(@token_key) do
      {_platform, token} -> with {:ok, _} <- Api.forget_device(profile, token), do: :ok
      nil -> :ok
    end
  end

  @doc """
  Reads a push that reached a screen as JSON: while the app is running, Mob
  hands the registered screen `{:mob_launch_notification, json}` rather than
  the decoded `{:notification, map}` it sends on a cold start.

      iex> DukaApp.Push.decode(~s({"title":"Hi","body":"B","source":"push","data":{"screen":"approvals"}}))
      %{title: "Hi", body: "B", source: :push, data: %{screen: "approvals", kind: nil, id: nil}}
  """
  @spec decode(String.t()) :: map()
  def decode(json) do
    case JSON.decode(json) do
      {:ok, %{} = map} ->
        data = if is_map(map["data"]), do: map["data"], else: %{}

        %{
          title: map["title"],
          body: map["body"],
          source: if(map["source"] == "push", do: :push, else: :local),
          data: %{screen: data["screen"], kind: data["kind"], id: data["id"]}
        }

      _ ->
        %{source: :local, data: %{}}
    end
  end

  @doc """
  The screen a push points at, if the person tapped it: `:approvals` for
  something to decide, `:receipts` for news about their own items.
  """
  @spec screen(map()) :: :approvals | :receipts
  # Mob delivers the push's data with atom keys.
  def screen(%{data: %{screen: "approvals"}}), do: :approvals
  def screen(_notification), do: :receipts

  # Mob.State isn't open outside the app (e.g. a `mix run` script).
  defp get(key) do
    Mob.State.get(key, nil)
  rescue
    ArgumentError -> nil
  end

  defp put(key, value) do
    Mob.State.put(key, value)
  catch
    :exit, _not_running -> :ok
  end
end
