defmodule DukaApp.Api do
  @moduledoc """
  The Risiti server's mobile API (see risiti's `RisitiWeb.Api.*`).

  Errors come back as:

    * `{:error, :offline}` — the server couldn't be reached;
    * `{:error, :unauthorized}` — the token was refused (sign in again);
    * `{:error, {:invalid, errors}}` — the server rejected the data, with a
      field → message map (or `%{"error" => message}`);
    * `{:error, {:http, status, body}}` — anything else.

  The server address is `config :duka_app, :api_url`, unless the user set
  another in Settings (kept in `Mob.State`). The HTTP module is
  `config :duka_app, :http` so tests can stand in for the server.
  """

  alias DukaApp.Accounts.Profile
  alias DukaApp.Receipts.{Photos, Receipt}
  alias DukaApp.Requests.{Attachments, Request}

  @server_key :server_url

  # ── Server address ─────────────────────────────────────────────────────────

  @spec base_url() :: String.t()
  def base_url do
    case saved_url() do
      url when is_binary(url) and url != "" -> url
      _ -> Application.get_env(:duka_app, :api_url, "http://127.0.0.1:4000")
    end
  end

  # Mob.State's store isn't open outside the app (e.g. a `mix run` script);
  # the configured address is used then.
  defp saved_url do
    Mob.State.get(@server_key, nil)
  rescue
    ArgumentError -> nil
  end

  @spec set_base_url(String.t()) :: :ok
  def set_base_url(url),
    do: Mob.State.put(@server_key, url |> String.trim() |> String.trim_trailing("/"))

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

  # ── The person's own receipts and requests ────────────────────────────────

  @doc """
  Sends a receipt, keyed by its `client_id` so a resend updates it. The
  photo goes along until the server has it (`photo_pushed`).
  """
  def put_receipt(%Profile{} = profile, %Receipt{} = receipt) do
    fields =
      receipt
      |> Map.take([
        :date,
        :vendor,
        :description,
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
      ])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), field_value(value)} end)

    photo =
      with false <- receipt.photo_pushed,
           path when is_binary(path) <- Photos.path(receipt.photo_path),
           true <- File.regular?(path) do
        [{"photo", {:file, path, Path.basename(path), "image/jpeg"}}]
      else
        _ -> []
      end

    call(
      :put,
      "/api/receipts/#{URI.encode(receipt.client_id)}",
      profile,
      {:multipart, fields ++ photo}
    )
    |> ok_body()
  end

  @doc "Sends a new request with its attachments; a refund names its receipt by client_id."
  def create_request(%Profile{} = profile, %Request{} = request, receipt_client_id) do
    fields =
      request
      |> Map.take([
        :client_id,
        :kind,
        :amount_cents,
        :purpose,
        :method,
        :phone,
        :till_number,
        :paybill_number,
        :account_number,
        :payee_name
      ])
      |> Map.put(:receipt_client_id, receipt_client_id)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map(fn {key, value} -> {Atom.to_string(key), field_value(value)} end)

    files =
      for attachment <- request.attachments,
          path = Attachments.path(attachment.file_name),
          File.regular?(path) do
        {"attachments[]", {:file, path, attachment.name, attachment.content_type}}
      end

    call(:post, "/api/requests", profile, {:multipart, fields ++ files}) |> ok_body()
  end

  @doc "Deletes a receipt deleted on the phone. The server keeps one already decided."
  def delete_receipt(%Profile{} = profile, client_id),
    do: call(:delete, "/api/receipts/#{URI.encode(client_id)}", profile) |> deleted()

  @doc "Withdraws a request withdrawn on the phone. The server keeps one already decided."
  def delete_request(%Profile{} = profile, client_id),
    do: call(:delete, "/api/requests/#{URI.encode(client_id)}", profile) |> deleted()

  # The server answers 204 even for one it never had, so a 404 means a
  # server without deletes yet.
  defp deleted({:ok, 404, _body}), do: {:error, :not_supported}
  defp deleted(response), do: ok_body(response)

  def list_receipts(profile), do: call(:get, "/api/receipts", profile) |> ok_body()
  def list_requests(profile), do: call(:get, "/api/requests", profile) |> ok_body()

  # ── Manager ────────────────────────────────────────────────────────────────

  def approval_receipts(profile), do: call(:get, "/api/approvals/receipts", profile) |> ok_body()
  def approval_requests(profile), do: call(:get, "/api/approvals/requests", profile) |> ok_body()

  @doc ~s(`decision` is "approve" or "reject" \(with a note\).)
  def decide_receipt(profile, id, decision, note),
    do:
      call(:post, "/api/approvals/receipts/#{id}/#{decision}", profile, {:json, %{note: note}})
      |> ok_body()

  @doc ~s(`decision` is "approve", "reject" \(with a note\) or "pay".)
  def decide_request(profile, id, decision, note),
    do:
      call(:post, "/api/approvals/requests/#{id}/#{decision}", profile, {:json, %{note: note}})
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
