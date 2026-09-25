defmodule DukaApp.Sync do
  @moduledoc """
  Keeps a connected receipt book and the Risiti server in step.

  One run:

    1. **pushes** receipts with changes the server hasn't seen
       (`needs_push`), with their photo until the server has it;
    2. **pushes** requests the server hasn't got yet, with attachments
       (after receipts, so a refund's receipt is already there);
    3. **pulls** the manager's decisions back: approval status and note for
       receipts, status and note for requests;
    4. refreshes what the person may approve (`/api/me`).

  Everything is keyed by the phone's `client_id`, so a run cut short by a
  dropped connection is simply repeated. A receipt is marked sent only if
  it wasn't edited while its upload was in flight, so an edit is never lost.

  The phone stays the source of truth for receipt figures; the server for
  decisions.
  """

  import Ecto.Query, only: [from: 2]

  alias DukaApp.{Accounts, Api, Repo}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Receipts.Receipt
  alias DukaApp.Requests.Request

  @type summary :: %{
          pushed: non_neg_integer(),
          failed: non_neg_integer(),
          pulled: non_neg_integer()
        }

  @doc """
  Runs a sync in the background and sends `{:sync, result}` to `notify`
  (if given). A run already in progress is left to finish instead.
  """
  @spec start(pid() | nil) :: :ok
  def start(notify \\ nil) do
    # Registering the name is the lock: a second run can't take it.
    Task.start(fn -> if register(), do: run_and_notify(notify) end)
    :ok
  end

  defp run_and_notify(notify) do
    result = run()
    if notify, do: send(notify, {:sync, result})
  end

  defp register do
    Process.register(self(), __MODULE__)
    true
  rescue
    ArgumentError -> false
  end

  @doc "Syncs the current receipt book. Does nothing unless it's connected."
  @spec run() :: {:ok, summary()} | {:error, :not_connected | :offline | :unauthorized}
  def run do
    case Accounts.current_profile() do
      %Profile{} = profile ->
        if Profile.connected?(profile), do: run(profile), else: {:error, :not_connected}

      nil ->
        {:error, :not_connected}
    end
  end

  @spec run(Profile.t()) :: {:ok, summary()} | {:error, :offline | :unauthorized}
  def run(%Profile{} = profile) do
    with {:ok, receipts} <- push_receipts(profile),
         {:ok, requests} <- push_requests(profile),
         {:ok, pulled} <- pull(profile) do
      refresh_permissions(profile)

      {:ok,
       %{
         pushed: receipts.pushed + requests.pushed,
         failed: receipts.failed + requests.failed,
         pulled: pulled
       }}
    end
  end

  # ── Push ───────────────────────────────────────────────────────────────────

  defp push_receipts(profile) do
    from(r in Receipt,
      where: r.profile_id == ^profile.id and r.needs_push == true,
      order_by: r.id
    )
    |> Repo.all()
    |> push_each(fn receipt ->
      with {:ok, %{"receipt" => json}} <- Api.put_receipt(profile, receipt) do
        mark_receipt_pushed(receipt, json)
      end
    end)
  end

  # Only if nobody edited the receipt while it was being sent.
  defp mark_receipt_pushed(receipt, json) do
    from(r in Receipt, where: r.id == ^receipt.id and r.updated_at == ^receipt.updated_at)
    |> Repo.update_all(
      set:
        [
          needs_push: false,
          photo_pushed: receipt.photo_path != nil,
          remote_id: json["id"],
          synced_at: now()
        ] ++
          decision(json)
    )

    :ok
  end

  defp push_requests(profile) do
    from(q in Request,
      where: q.profile_id == ^profile.id and is_nil(q.remote_id),
      order_by: q.id,
      preload: [:receipt, :attachments]
    )
    |> Repo.all()
    |> push_each(fn request ->
      receipt_client_id = request.receipt && request.receipt.client_id

      with {:ok, %{"request" => json}} <- Api.create_request(profile, request, receipt_client_id) do
        request
        |> Ecto.Changeset.change(remote_id: json["id"], submitted_at: now(), synced_at: now())
        |> Ecto.Changeset.change(request_decision(json))
        |> Repo.update!()

        :ok
      end
    end)
  end

  # Stops at the first sign the server can't be used (offline, signed out);
  # a record the server refuses is counted and skipped.
  defp push_each(records, push) do
    Enum.reduce_while(records, {:ok, %{pushed: 0, failed: 0}}, fn record, {:ok, acc} ->
      case push.(record) do
        :ok -> {:cont, {:ok, %{acc | pushed: acc.pushed + 1}}}
        {:error, reason} when reason in [:offline, :unauthorized] -> {:halt, {:error, reason}}
        {:error, _refused} -> {:cont, {:ok, %{acc | failed: acc.failed + 1}}}
      end
    end)
  end

  # ── Pull ───────────────────────────────────────────────────────────────────

  defp pull(profile) do
    with {:ok, %{"receipts" => receipts}} <- Api.list_receipts(profile),
         {:ok, %{"requests" => requests}} <- Api.list_requests(profile) do
      {:ok, pull_receipts(profile, receipts) + pull_requests(profile, requests)}
    end
  end

  # A receipt with unsent changes keeps its own state until it's pushed.
  defp pull_receipts(profile, jsons) do
    Enum.reduce(jsons, 0, fn json, count ->
      {updated, _} =
        from(r in Receipt,
          where:
            r.profile_id == ^profile.id and r.client_id == ^json["client_id"] and
              r.needs_push == false
        )
        |> Repo.update_all(set: [remote_id: json["id"], synced_at: now()] ++ decision(json))

      count + updated
    end)
  end

  defp pull_requests(profile, jsons) do
    Enum.reduce(jsons, 0, fn json, count ->
      {updated, _} =
        from(q in Request,
          where: q.profile_id == ^profile.id and q.client_id == ^json["client_id"]
        )
        |> Repo.update_all(
          set: [remote_id: json["id"], synced_at: now()] ++ request_decision(json)
        )

      count + updated
    end)
  end

  defp decision(json) do
    [
      approval_status: json["approval_status"] || "pending",
      approval_note: json["approval_note"],
      decided_at: parse_time(json["decided_at"])
    ]
  end

  defp request_decision(json) do
    [
      status: json["status"] || "pending",
      decision_note: json["decision_note"],
      decided_at: parse_time(json["decided_at"])
    ]
  end

  defp refresh_permissions(profile) do
    with {:ok, %{"user" => user}} <- Api.me(profile) do
      Accounts.apply_server_user(profile, user)
    end
  end

  defp parse_time(nil), do: nil

  defp parse_time(text) do
    case DateTime.from_iso8601(text) do
      {:ok, at, _offset} -> DateTime.truncate(at, :second)
      _ -> nil
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
