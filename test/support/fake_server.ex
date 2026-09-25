defmodule DukaApp.FakeServer do
  @moduledoc """
  Stands in for the Risiti server in tests (`config :duka_app, :http`).

  A test scripts the replies with `stub/1`: a function from
  `{method, path, request}` to `{status, body}` (or `{:error, reason}`).
  Every call is also sent to the test process as
  `{:http, method, path, request}`, where `request` has `:headers` and
  `:body`, so a test can check what the app sent.

  Screen server calls and syncs run in the test process under test config
  (`DukaApp.Native.background/3`), so the stub lives in the process
  dictionary.
  """

  @key {__MODULE__, :handler}

  def stub(handler) when is_function(handler, 1), do: Process.put(@key, handler)

  def request(method, url, opts) do
    path = URI.parse(url).path
    request = %{headers: Keyword.get(opts, :headers, []), body: Keyword.get(opts, :body)}
    send(self(), {:http, method, path, request})

    handler = Process.get(@key) || fn _ -> {:error, :econnrefused} end

    case handler.({method, path, request}) do
      {:error, reason} -> {:error, reason}
      {status, body} -> {:ok, status, body}
    end
  end

  @doc "The fields of a multipart body, as a map (files as `{:file, filename}`)."
  def multipart_fields({:multipart, parts}) do
    Map.new(parts, fn
      {name, {:file, _path, filename, _type}} -> {name, {:file, filename}}
      {name, value} -> {name, value}
    end)
  end

  @doc "All values of a repeated multipart field (e.g. attachments[])."
  def multipart_all({:multipart, parts}, field) do
    for {^field, value} <- parts, do: value
  end
end
