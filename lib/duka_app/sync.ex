defmodule DukaApp.Sync do
  @moduledoc """
  Keeps a connected receipt book and the Risiti server in step.

  One run:

    1. **deletes** on the server what was deleted or withdrawn on the phone
       (`DukaApp.Sync.Deletion`) — requests first, since the server keeps a
       receipt that still has one. The server keeps anything already
       decided, and the pull then brings it back;
    2. **pushes** receipts with changes the server hasn't seen
       (`needs_push`), with their photo until the server has it;
    3. **pushes** requests the server hasn't got yet, with attachments
       (after receipts, so a refund's receipt is already there);
    4. **pulls** the manager's decisions back: approval status and note for
       receipts, status and note for requests — and adds what the server
       has that the phone doesn't (after a reinstall, or from another
       phone). Their photos and attachments download when first opened
       (`fetch_photo/2`, `fetch_attachment/2`);
    5. refreshes what the person may approve (`/api/me`).

  Everything is keyed by the phone's `client_id`, so a run cut short by a
  dropped connection is simply repeated. A receipt is marked sent only if
  it wasn't edited while its upload was in flight, so an edit is never lost.

  The phone stays the source of truth for receipt figures; the server for
  decisions.
  """

  import Ecto.Query, only: [from: 2]

  alias DukaApp.{Accounts, Api, Repo}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Receipts.{Photos, Receipt}
  alias DukaApp.Requests.{Attachment, Attachments, Request}
  alias DukaApp.Sync.Deletion

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
         {:ok, receipts} <- push_receipts(profile),
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

  # ── Deletions ──────────────────────────────────────────────────────────────

  @doc "Notes that a receipt or request (`kind`) was deleted, for the next sync to tell the server."
  @spec remember_deletion(integer(), String.t(), String.t()) :: :ok
  def remember_deletion(profile_id, kind, client_id) do
    Repo.insert!(%Deletion{profile_id: profile_id, kind: kind, client_id: client_id},
      on_conflict: :nothing
    )

    :ok
  end

  # "request" sorts after "receipt", so descending sends requests first.
  defp push_deletions(profile) do
    from(d in Deletion, where: d.profile_id == ^profile.id, order_by: [desc: d.kind, asc: d.id])
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn deletion, :ok ->
      case delete_remote(profile, deletion) do
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

  defp delete_remote(profile, %Deletion{kind: "receipt", client_id: id}),
    do: Api.delete_receipt(profile, id)

  defp delete_remote(profile, %Deletion{kind: "request", client_id: id}),
    do: Api.delete_request(profile, id)

  defp deleted_ids(profile, kind) do
    from(d in Deletion,
      where: d.profile_id == ^profile.id and d.kind == ^kind,
      select: d.client_id
    )
    |> Repo.all()
    |> MapSet.new()
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

  # A receipt with unsent changes keeps its own state until it's pushed; one
  # the phone doesn't have is added, unless it was just deleted here.
  defp pull_receipts(profile, jsons) do
    local = local_ids(Receipt, profile)
    deleted = deleted_ids(profile, "receipt")

    Enum.reduce(jsons, 0, fn json, count ->
      client_id = json["client_id"]

      cond do
        MapSet.member?(local, client_id) ->
          {updated, _} =
            from(r in Receipt,
              where:
                r.profile_id == ^profile.id and r.client_id == ^client_id and
                  r.needs_push == false
            )
            |> Repo.update_all(set: [remote_id: json["id"], synced_at: now()] ++ decision(json))

          count + updated

        MapSet.member?(deleted, client_id) ->
          count

        true ->
          insert_receipt(profile, json)
          count + 1
      end
    end)
  end

  # The photo stays on the server until it's opened: `photo_path` names the
  # file it will download to, and `photo_pushed` keeps it from going back up.
  defp insert_receipt(profile, json) do
    has_photo? = json["has_photo"] == true

    Repo.insert!(%Receipt{
      profile_id: profile.id,
      client_id: json["client_id"],
      remote_id: json["id"],
      date: Date.from_iso8601!(json["date"]),
      vendor: json["vendor"],
      description: json["description"],
      amount_cents: json["amount_cents"],
      category: json["category"],
      source: json["source"] || "manual",
      seller_pin: json["seller_pin"],
      invoice_number: json["invoice_number"],
      verify_url: json["verify_url"],
      verified_at: parse_time(json["verified_at"]),
      photo_path: if(has_photo?, do: "remote-#{json["id"]}.jpg"),
      photo_pushed: has_photo?,
      needs_push: false,
      synced_at: now(),
      approval_status: json["approval_status"] || "pending",
      approval_note: json["approval_note"],
      decided_at: parse_time(json["decided_at"])
    })
  end

  defp pull_requests(profile, jsons) do
    local = local_ids(Request, profile)
    deleted = deleted_ids(profile, "request")

    Enum.reduce(jsons, 0, fn json, count ->
      client_id = json["client_id"]

      cond do
        MapSet.member?(local, client_id) ->
          {updated, _} =
            from(q in Request,
              where: q.profile_id == ^profile.id and q.client_id == ^client_id
            )
            |> Repo.update_all(
              set: [remote_id: json["id"], synced_at: now()] ++ request_decision(json)
            )

          count + updated

        MapSet.member?(deleted, client_id) ->
          count

        true ->
          insert_request(profile, json)
          count + 1
      end
    end)
  end

  # Pulled after receipts, so a refund's receipt is already here to link to.
  defp insert_request(profile, json) do
    Repo.transaction(fn ->
      request =
        Repo.insert!(%Request{
          profile_id: profile.id,
          client_id: json["client_id"],
          remote_id: json["id"],
          kind: json["kind"],
          status: json["status"] || "pending",
          amount_cents: json["amount_cents"],
          purpose: json["purpose"],
          receipt_id: local_receipt_id(profile, json["receipt_client_id"]),
          method: json["method"],
          phone: json["phone"],
          till_number: json["till_number"],
          paybill_number: json["paybill_number"],
          account_number: json["account_number"],
          payee_name: json["payee_name"],
          submitted_at: parse_time(json["inserted_at"]),
          decision_note: json["decision_note"],
          decided_at: parse_time(json["decided_at"]),
          synced_at: now()
        })

      Enum.each(json["attachments"] || [], fn attachment ->
        Repo.insert!(%Attachment{
          request_id: request.id,
          remote_id: attachment["id"],
          file_name: "remote-#{attachment["id"]}#{Path.extname(attachment["name"] || "")}",
          name: attachment["name"],
          content_type: attachment["content_type"],
          size: attachment["size"]
        })
      end)
    end)
  end

  defp local_ids(schema, profile) do
    from(r in schema, where: r.profile_id == ^profile.id, select: r.client_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp local_receipt_id(_profile, nil), do: nil

  defp local_receipt_id(profile, client_id) do
    Repo.one(
      from(r in Receipt,
        where: r.profile_id == ^profile.id and r.client_id == ^client_id,
        select: r.id
      )
    )
  end

  # ── Files kept on the server ───────────────────────────────────────────────

  @doc "Downloads a pulled receipt's photo to its `photo_path`, unless it's already here."
  @spec fetch_photo(Profile.t(), Receipt.t()) :: :ok | {:error, term()}
  def fetch_photo(profile, %Receipt{remote_id: id, photo_path: name}) when is_binary(name) do
    cond do
      Photos.exists?(name) -> :ok
      is_binary(id) -> Api.download(profile, "/api/receipts/#{id}/photo", Photos.path(name))
      true -> {:error, :no_photo}
    end
  end

  def fetch_photo(_profile, _receipt), do: {:error, :no_photo}

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
