defmodule DukaApp.Api do
  @moduledoc """
  The Risiti server's mobile API (see risiti's `RisitiWeb.Api.*`).

  Errors come back as:

    * `{:error, :offline}` — the server couldn't be reached;
    * `{:error, :unauthorized}` — the token was refused (sign in again);
    * `{:error, {:invalid, errors}}` — the server rejected the data, with a
      field → message map (or `%{"error" => message}`);
    * `{:error, {:http, status, body}}` — anything else.

  The server is always `config :duka_app, :api_url`
  (https://expenses.zippiker.com; tests point it at a stand-in). The HTTP
  module is `config :duka_app, :http` so tests can stand in for the server.
  """

  alias DukaApp.Accounts.Profile
  alias DukaApp.Receipts.Photos
  alias DukaApp.Transactions.{Attachments, Transaction}

  # ── Server address ─────────────────────────────────────────────────────────

  # On the phone the app's config isn't loaded, so the default is what it
  # uses; tests set `:api_url` to their stand-in.
  @spec base_url() :: String.t()
  def base_url, do: Application.get_env(:duka_app, :api_url, "https://expenses.zippiker.com")

  # ── Sign-in ────────────────────────────────────────────────────────────────

  @doc "Asks the server to text a sign-in code to `phone`."
  def request_code(phone), do: post("/api/auth/code", nil, {:json, %{phone: phone}}) |> ok_body()

  @doc "Exchanges the code for a token and the user (with permissions)."
  def verify(phone, code) do
    case post("/api/auth/verify", nil, {:json, %{phone: phone, code: code}}) |> ok_body() do
      # Here a 401 means a wrong code, not a lapsed sign-in.
      {:error, :unauthorized} ->
        {:error, {:invalid, %{"error" => "That code is wrong or has expired"}}}

      other ->
        other
    end
  end

  @doc """
  Signs in with the ID token Sign in with Google gave the phone. A new
  person gets `%{"needs_registration" => true, "signup_token" => ..., "name" => ...}`.
  """
  def google(id_token) do
    case post("/api/auth/google", nil, {:json, %{id_token: id_token}}) |> ok_body() do
      # Here a 401 means Google's answer wasn't accepted, not a lapsed sign-in.
      {:error, :unauthorized} ->
        {:error, {:invalid, %{"error" => "That Google sign-in didn't work. Try again."}}}

      other ->
        other
    end
  end

  @doc """
  Signs up someone new that `verify/2` or `google/1` confirmed: the person's `name`, and a
  `team_name` for a business (blank for a free personal book).
  """
  def register(signup_token, name, team_name) do
    post(
      "/api/auth/register",
      nil,
      {:json, %{signup_token: signup_token, name: name, team_name: team_name}}
    )
    |> ok_body()
  end

  def me(profile), do: call(:get, "/api/me", profile) |> ok_body()

  # ── Push notifications ────────────────────────────────────────────────────

  @doc "Tells the server this phone's push token, so it can notify the person (see `DukaApp.Push`)."
  def register_device(profile, platform, token),
    do:
      call(:put, "/api/devices", profile, {:json, %{platform: platform, token: token}})
      |> ok_body()

  @doc "Asks the server to stop pushing to this phone."
  def forget_device(profile, token),
    do: call(:delete, "/api/devices/#{URI.encode_www_form(token)}", profile) |> ok_body()

  # ── The person's own transactions ─────────────────────────────────────────

  # Sent as they are; nil is left out.
  @fields [
    :type,
    :pay_to,
    :date,
    :vendor,
    :amount_cents,
    :category,
    :source,
    :qr_content,
    :seller_pin,
    :branch_id,
    :invoice_number,
    :verify_url,
    :verified_at,
    :ocr_text
  ]

  # Sent even when blank, so clearing one here clears it on the server too
  # (a refund taken back no longer names a phone to pay).
  @clearable [:description, :method, :phone, :till_number, :paybill_number, :account_number]

  @doc """
  Sends a transaction, keyed by its `client_id` so a resend updates it. The
  photo goes along until the server has it (`photo_pushed`), and so do the
  attachments it hasn't got yet (no `remote_id`); the server skips one it
  already has.
  """
  def put_transaction(%Profile{} = profile, %Transaction{} = transaction) do
    fields =
      Enum.flat_map(@fields, fn key ->
        case Map.fetch!(transaction, key) do
          nil -> []
          value -> [{Atom.to_string(key), field_value(value)}]
        end
      end) ++
        Enum.map(@clearable, fn key ->
          {Atom.to_string(key), field_value(Map.fetch!(transaction, key) || "")}
        end)

    photo =
      with false <- transaction.photo_pushed,
           path when is_binary(path) <- Photos.path(transaction.photo_path),
           true <- File.regular?(path) do
        [{"photo", {:file, path, Path.basename(path), "image/jpeg"}}]
      else
        _ -> []
      end

    files =
      for attachment <- transaction.attachments,
          is_nil(attachment.remote_id),
          path = Attachments.path(attachment.file_name),
          File.regular?(path) do
        {"attachments[]", {:file, path, attachment.name, attachment.content_type}}
      end

    call(
      :put,
      "/api/transactions/#{URI.encode(transaction.client_id)}",
      profile,
      {:multipart, fields ++ photo ++ files}
    )
    |> ok_body()
  end

  @doc "Deletes a transaction deleted on the phone. The server keeps one already decided."
  def delete_transaction(%Profile{} = profile, client_id),
    do: call(:delete, "/api/transactions/#{URI.encode(client_id)}", profile) |> deleted()

  # The server answers 204 even for one it never had, so a 404 means a
  # server without deletes yet.
  defp deleted({:ok, 404, _body}), do: {:error, :not_supported}
  defp deleted(response), do: ok_body(response)

  def list_transactions(profile), do: call(:get, "/api/transactions", profile) |> ok_body()

  # ── Approvers ──────────────────────────────────────────────────────────────

  @doc "What waits for a decision, and approved claims waiting to be paid."
  def approvals(profile), do: call(:get, "/api/approvals", profile) |> ok_body()

  @doc ~s(`decision` is "approve", "reject" \(with a note\) or "pay".)
  def decide(profile, id, decision, note),
    do:
      call(:post, "/api/approvals/#{id}/#{decision}", profile, {:json, %{note: note}})
      |> ok_body()

  @doc "Downloads a receipt photo or attachment (`path` like /api/attachments/ID) to `dest`."
  def download(profile, path, dest) do
    case call(:get, path, profile) do
      {:ok, 200, body} when is_binary(body) -> File.write(dest, body)
      other -> ok_body(other)
    end
  end

  # ── Plumbing ───────────────────────────────────────────────────────────────

  defp post(path, profile, body), do: call(:post, path, profile, body)

  defp call(method, path, profile, body \\ nil) do
    headers =
      case profile do
        %Profile{api_token: token} when is_binary(token) ->
          [{"authorization", "Bearer " <> token}]

        _ ->
          []
      end

    http().request(method, base_url() <> path,
      headers: [{"accept", "application/json"} | headers],
      body: body
    )
  end

  defp ok_body({:ok, status, body}) when status in 200..299, do: {:ok, body}
  defp ok_body({:ok, 401, _body}), do: {:error, :unauthorized}
  defp ok_body({:ok, 422, %{"errors" => errors}}), do: {:error, {:invalid, errors}}

  defp ok_body({:ok, status, %{"error" => _} = body}) when status in 400..499,
    do: {:error, {:invalid, body}}

  defp ok_body({:ok, status, body}), do: {:error, {:http, status, body}}
  defp ok_body(:ok), do: :ok
  defp ok_body({:error, {:invalid, _} = reason}), do: {:error, reason}
  defp ok_body({:error, _reason}), do: {:error, :offline}

  defp field_value(%Date{} = date), do: Date.to_iso8601(date)
  defp field_value(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp field_value(value), do: to_string(value)

  defp http, do: Application.get_env(:duka_app, :http, DukaApp.Http)

  @doc "The message to show for an error from this module."
  @spec error_message(term()) :: String.t()
  def error_message(:offline), do: "Can't reach the server. Check your internet connection."
  def error_message(:unauthorized), do: "Please sign in again."
  def error_message({:invalid, %{"error" => message}}), do: message

  def error_message({:invalid, errors}) when is_map(errors) do
    Enum.map_join(errors, ". ", fn {field, message} -> "#{humanize(field)} #{message}" end)
  end

  def error_message(_error), do: "Something went wrong on the server. Try again."

  defp humanize(field) do
    field
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
