defmodule DukaApp.Native do
  @moduledoc """
  The native calls screens make: camera, QR scanner, receipt OCR, toasts and
  haptics — plus the one network call, the KRA receipt lookup.

  They go straight to the phone's native layer, which does not exist under
  `mix test`. With `config :duka_app, :native, false` each call instead sends
  `{:native, name, args}` to the calling process, so a screen test can assert
  what the screen asked the phone to do and then feed back the reply message.
  """

  alias DukaApp.Receipts.KraReceipt
  alias Mob.Storage.Android

  @spec toast(Mob.Socket.t(), String.t()) :: Mob.Socket.t()
  def toast(socket, message), do: call(socket, :toast, [message], &Mob.Alert.toast(&1, message))

  @spec success(Mob.Socket.t()) :: Mob.Socket.t()
  def success(socket), do: call(socket, :success, [], &Mob.Haptic.trigger(&1, :success))

  @doc "Replies `{:permission, :camera, :granted | :denied}`."
  @spec request_camera(Mob.Socket.t()) :: Mob.Socket.t()
  def request_camera(socket),
    do: call(socket, :request_camera, [], &Mob.Permissions.request(&1, :camera))

  @doc "Replies `{:scan, :result, %{value: ...}}` or `{:scan, :cancelled}`."
  @spec scan_qr(Mob.Socket.t()) :: Mob.Socket.t()
  def scan_qr(socket), do: call(socket, :scan_qr, [], &MobScanner.scan(&1, formats: [:qr]))

  @doc "Replies `{:camera, :photo, %{path: tmp_path}}` or `{:camera, :cancelled}`."
  @spec take_photo(Mob.Socket.t()) :: Mob.Socket.t()
  def take_photo(socket),
    do: call(socket, :take_photo, [], &MobCamera.capture_photo(&1, quality: :high))

  @doc "Replies `{:ocr, :result, json}` or `{:ocr, :error, json}` — see `MobOcr`."
  @spec process_photo(Mob.Socket.t(), String.t(), String.t()) :: Mob.Socket.t()
  def process_photo(socket, source, dest) do
    call(socket, :process_photo, [source, dest], &MobOcr.process(&1, source, save_to: dest))
  end

  @doc """
  Looks the receipt up on KRA's verification page in the background.
  Replies `{:kra, :result, details}` (see `DukaApp.Receipts.KraReceipt`) or
  `{:kra, :error, reason}`. With a `ref`, the reply carries it as a fourth
  element — `{:kra, :result, details, ref}` — so a screen with several
  lookups in flight can tell them apart.
  """
  @spec lookup_kra(Mob.Socket.t(), String.t(), term()) :: Mob.Socket.t()
  def lookup_kra(socket, url, ref \\ nil) do
    args = if ref == nil, do: [url], else: [url, ref]

    call(socket, :lookup_kra, args, fn socket ->
      screen = self()
      Task.start(fn -> send(screen, kra_reply(KraReceipt.fetch(url), ref)) end)
      socket
    end)
  end

  @doc """
  Copies the file at `path` into the phone's photo gallery. Replies
  `{:storage, :saved_to_library, _}` or `{:storage, :error, :save_to_library, reason}`.
  """
  @spec save_to_gallery(Mob.Socket.t(), String.t()) :: Mob.Socket.t()
  def save_to_gallery(socket, path) do
    call(
      socket,
      :save_to_gallery,
      [path],
      &Android.save_to_media_store(&1, path, :image)
    )
  end

  @doc """
  Opens the system file picker for images and PDFs. Replies
  `{:files, :picked, items}` or `{:files, :cancelled}` — see `Mob.Files`.
  """
  @spec pick_files(Mob.Socket.t()) :: Mob.Socket.t()
  def pick_files(socket),
    do: call(socket, :pick_files, [], &Mob.Files.pick(&1, types: [:images, :pdf]))

  @doc "Opens a file from the app's storage in the phone's own viewer (PDF reader, gallery)."
  @spec open_file(Mob.Socket.t(), String.t()) :: Mob.Socket.t()
  def open_file(socket, path) do
    call(socket, :open_file, [path], fn socket ->
      Mob.Device.open_url(path)
      socket
    end)
  end

  defp kra_reply(reply, nil), do: kra_reply(reply)
  defp kra_reply(reply, ref), do: Tuple.insert_at(kra_reply(reply), 3, ref)

  defp kra_reply({:ok, details}), do: {:kra, :result, details}
  defp kra_reply({:error, reason}), do: {:kra, :error, reason}

  defp call(socket, name, args, native) do
    if Application.get_env(:duka_app, :native, true) do
      native.(socket)
    else
      send(self(), {:native, name, args})
      socket
    end
  end
end
