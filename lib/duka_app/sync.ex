defmodule DukaApp.Sync do
  @moduledoc """
  Keeps a connected expense book and the Risiti server in step.

  One run:

    1. **deletes** on the server what was deleted on the phone
       (`DukaApp.Sync.Deletion`). The server keeps anything already decided,
       and the pull then brings it back;
    2. **pushes** transactions with changes the server hasn't seen
       (`needs_push`), with their photo until the server has it and the
       attachments it hasn't got yet;
    3. **pulls** the decisions back — status, note, when paid — and adds
       what the server has that the phone doesn't (after a reinstall, or
       from another phone). Their photos and attachments download when
       first opened (`fetch_photo/2`, `fetch_attachment/2`);
    4. refreshes what the person may do (`/api/me`).

  Everything is keyed by the phone's `client_id`, so a run cut short by a
  dropped connection is simply repeated. A transaction is marked sent only
  if it wasn't edited while its upload was in flight, so an edit is never
  lost.

  The phone stays the source of truth for the figures; the server for
  decisions.
  """

  import Ecto.Query, only: [from: 2]

  alias DukaApp.{Accounts, Api, Repo}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Receipts.Photos
  alias DukaApp.Sync.Deletion
  alias DukaApp.Transactions.{Attachment, Attachments, Transaction}

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
    with :ok <- push_deletions(profile),
         {:ok, pushed} <- push_transactions(profile),
         {:ok, pulled} <- pull(profile) do
      refresh_permissions(profile)
      {:ok, Map.put(pushed, :pulled, pulled)}
    end
  end

  # ── Deletions ──────────────────────────────────────────────────────────────

  @doc "Notes that a transaction was deleted, for the next sync to tell the server."
  @spec remember_deletion(integer(), String.t()) :: :ok
  def remember_deletion(profile_id, client_id) do
    Repo.insert!(%Deletion{profile_id: profile_id, kind: "transaction", client_id: client_id},
      on_conflict: :nothing
    )

    :ok
  end

  defp push_deletions(profile) do
    from(d in Deletion, where: d.profile_id == ^profile.id, order_by: [asc: d.id])
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn deletion, :ok ->
      case Api.delete_transaction(profile, deletion.client_id) do
        {:error, reason} when reason in [:offline, :unauthorized] ->
          {:halt, {:error, reason}}

        # Gone, or kept because it was decided: either way the server has the
        # last word, and the pull brings back whatever it kept.
        {:ok, _body} ->
          forget(deletion)

        {:error, {:invalid, _errors}} ->
          forget(deletion)

        # Anything else (say, a server without deletes yet): try next time.
        _other ->
          {:cont, :ok}
      end
    end)
  end

  defp forget(deletion) do
    Repo.delete!(deletion)
    {:cont, :ok}
  end

  defp deleted_ids(profile) do
    from(d in Deletion, where: d.profile_id == ^profile.id, select: d.client_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # ── Push ───────────────────────────────────────────────────────────────────

  # Stops at the first sign the server can't be used (offline, signed out);
  # a transaction the server refuses is counted and skipped.
  defp push_transactions(profile) do
    from(t in Transaction,
      where: t.profile_id == ^profile.id and t.needs_push == true,
      order_by: t.id,
      preload: :attachments
    )
    |> Repo.all()
    |> Enum.reduce_while({:ok, %{pushed: 0, failed: 0}}, fn transaction, {:ok, acc} ->
      case push(profile, transaction) do
        :ok -> {:cont, {:ok, %{acc | pushed: acc.pushed + 1}}}
        {:error, reason} when reason in [:offline, :unauthorized] -> {:halt, {:error, reason}}
        {:error, _refused} -> {:cont, {:ok, %{acc | failed: acc.failed + 1}}}
      end
    end)
  end

  defp push(profile, transaction) do
    with {:ok, %{"transaction" => json}} <- Api.put_transaction(profile, transaction) do
      mark_pushed(transaction, json)
    end
  end

  # Only if nobody edited the transaction while it was being sent. The
  # attachments the server now has get their ids either way (matched by
  # name and size), so they aren't sent again.
  defp mark_pushed(transaction, json) do
    from(t in Transaction,
      where: t.id == ^transaction.id and t.updated_at == ^transaction.updated_at
    )
    |> Repo.update_all(
      set:
        [
          needs_push: false,
          photo_pushed: transaction.photo_path != nil,
          remote_id: json["id"],
          synced_at: now()
        ] ++ decision(json)
    )

    remote = Map.new(json["attachments"] || [], &{{&1["name"], &1["size"]}, &1["id"]})

    for attachment <- transaction.attachments,
        is_nil(attachment.remote_id),
        id = remote[{attachment.name, attachment.size}] do
      attachment |> Ecto.Changeset.change(remote_id: id) |> Repo.update!()
    end

    :ok
  end

  # ── Pull ───────────────────────────────────────────────────────────────────

  # A transaction with unsent changes keeps its own state until it's pushed;
  # one the phone doesn't have is added, unless it was just deleted here.
  defp pull(profile) do
    with {:ok, %{"transactions" => jsons}} <- Api.list_transactions(profile) do
      known = %{local: local_ids(profile), deleted: deleted_ids(profile)}
      {:ok, Enum.reduce(jsons, 0, &(&2 + pull_one(profile, &1, known)))}
    end
  end

  # How many transactions on the phone this changed: 0 or 1.
  defp pull_one(profile, %{"client_id" => client_id} = json, known) do
    cond do
      MapSet.member?(known.local, client_id) ->
        {updated, _} =
          from(t in Transaction,
            where:
              t.profile_id == ^profile.id and t.client_id == ^client_id and t.needs_push == false
          )
          |> Repo.update_all(set: [remote_id: json["id"], synced_at: now()] ++ decision(json))

        updated

      MapSet.member?(known.deleted, client_id) ->
        0

      true ->
        insert_transaction(profile, json)
        1
    end
  end

  # The photo stays on the server until it's opened: `photo_path` names the
  # file it will download to, and `photo_pushed` keeps it from going back
  # up. Attachments are the same.
  defp insert_transaction(profile, json) do
    has_photo? = json["has_photo"] == true

    Repo.transaction(fn ->
      transaction =
        Repo.insert!(%Transaction{
          profile_id: profile.id,
          client_id: json["client_id"],
          remote_id: json["id"],
          type: json["type"] || "expense",
          pay_to: json["pay_to"],
          date: Date.from_iso8601!(json["date"]),
          vendor: json["vendor"],
          description: json["description"],
          amount_cents: json["amount_cents"],
          category: json["category"],
          method: json["method"],
          phone: json["phone"],
          till_number: json["till_number"],
          paybill_number: json["paybill_number"],
          account_number: json["account_number"],
          source: json["source"] || "manual",
          seller_pin: json["seller_pin"],
          invoice_number: json["invoice_number"],
          verify_url: json["verify_url"],
          verified_at: parse_time(json["verified_at"]),
          photo_path: if(has_photo?, do: "remote-#{json["id"]}.jpg"),
          photo_pushed: has_photo?,
          needs_push: false,
          synced_at: now(),
          status: json["status"] || "pending",
          decision_note: json["decision_note"],
          decided_at: parse_time(json["decided_at"]),
          paid_at: parse_time(json["paid_at"])
        })

      Enum.each(json["attachments"] || [], fn attachment ->
        Repo.insert!(%Attachment{
          transaction_id: transaction.id,
          remote_id: attachment["id"],
          file_name: "remote-#{attachment["id"]}#{Path.extname(attachment["name"] || "")}",
          name: attachment["name"],
          content_type: attachment["content_type"],
          size: attachment["size"]
        })
      end)
    end)
  end

  defp local_ids(profile) do
    from(t in Transaction, where: t.profile_id == ^profile.id, select: t.client_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # ── Files kept on the server ───────────────────────────────────────────────

  @doc "Downloads a pulled transaction's photo to its `photo_path`, unless it's already here."
  @spec fetch_photo(Profile.t(), Transaction.t()) :: :ok | {:error, term()}
  def fetch_photo(profile, %Transaction{remote_id: id, photo_path: name}) when is_binary(name) do
    cond do
      Photos.exists?(name) -> :ok
      is_binary(id) -> Api.download(profile, "/api/transactions/#{id}/photo", Photos.path(name))
      true -> {:error, :no_photo}
    end
  end

  def fetch_photo(_profile, _transaction), do: {:error, :no_photo}

  @doc "Downloads a pulled attachment to its `file_name`, unless it's already here."
  @spec fetch_attachment(Profile.t(), Attachment.t()) :: :ok | {:error, term()}
  def fetch_attachment(profile, %Attachment{remote_id: id, file_name: name}) do
    cond do
      File.regular?(Attachments.path(name)) -> :ok
      is_binary(id) -> Api.download(profile, "/api/attachments/#{id}", Attachments.path(name))
      true -> {:error, :missing}
    end
  end

  defp decision(json) do
    [
      status: json["status"] || "pending",
      decision_note: json["decision_note"],
      decided_at: parse_time(json["decided_at"]),
      paid_at: parse_time(json["paid_at"])
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
