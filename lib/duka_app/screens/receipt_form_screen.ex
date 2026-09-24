defmodule DukaApp.Screens.ReceiptFormScreen do
  @moduledoc """
  Confirm a scanned receipt, add one by hand, or edit a saved one.

  Mount params:

    * `%{photo: tmp_path}` — a photo was just taken: save it and read it
      (OCR + QR) on the phone, then pre-fill the form.
    * `%{qr: content}` — a QR code was just scanned.
    * `%{id: id}` — edit a saved receipt.
    * `%{}` — enter a receipt by hand.

  A photo can be added, retaken or removed from any of these, and a QR code
  scanned when the photo didn't contain a readable one. Text read off a photo
  only fills fields the user hasn't typed in.
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Native, Receipts}
  alias DukaApp.Components.FormField
  alias DukaApp.Receipts.{OcrParser, Photos, QrParser, Receipt}

  @categories Receipt.categories()
  @category_actions @categories
                    |> Enum.with_index()
                    |> Map.new(fn {category, i} -> {:"category_#{i}", category} end)

  @text_fields [:date, :vendor, :description, :amount]

  @impl Mob.Screen
  def mount(params, _session, socket) do
    profile = Accounts.current_profile()

    {mode, receipt} =
      case params do
        %{id: id} -> {:edit, Receipts.get_receipt!(profile, id)}
        %{qr: qr} -> {:new, Receipts.new_from_qr(qr)}
        _ -> {:new, Receipts.new_manual()}
      end

    socket =
      socket
      |> Mob.Socket.assign(:profile, profile)
      |> Mob.Socket.assign(:mode, mode)
      |> Mob.Socket.assign(:receipt, receipt)
      # The photo the saved receipt already had, so a replaced one can be
      # deleted on save and a new, unsaved one deleted on back.
      |> Mob.Socket.assign(:saved_photo, receipt.photo_path)
      |> Mob.Socket.assign(:date, Date.to_iso8601(receipt.date))
      |> Mob.Socket.assign(:vendor, receipt.vendor || "")
      |> Mob.Socket.assign(:description, receipt.description || "")
      |> Mob.Socket.assign(:amount, Receipts.amount_input(receipt.amount_cents))
      |> Mob.Socket.assign(:category, receipt.category)
      |> Mob.Socket.assign(:touched, MapSet.new())
      |> Mob.Socket.assign(:reading, false)
      |> Mob.Socket.assign(:notice, nil)
      |> Mob.Socket.assign(:pending_camera, nil)
      |> Mob.Socket.assign(:errors, %{})
      |> duplicate_check()

    socket =
      case params do
        %{photo: tmp} -> read_photo(socket, tmp)
        _ -> socket
      end

    {:ok, socket}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title={title(@mode, @receipt)} show_back={true} />
      <Scroll weight={1}>
        <Column padding={16} gap={12} fill_width={true}>
          {photo_section(assigns)}
          <Box
            :if={@notice}
            background={:surface}
            corner_radius={:radius_sm}
            padding={12}
            fill_width={true}
          >
            <Text text={@notice} text_size={:sm} text_color={:on_surface} />
          </Box>
          {qr_section(assigns)}
          {FormField.field(
            label: "Date on receipt",
            key: :date,
            value: @date,
            placeholder: "YYYY-MM-DD, e.g. 2026-09-23",
            hint: "Year-month-day, as printed on the receipt.",
            error: @errors[:date]
          )}
          {FormField.field(
            label: "Vendor (shop or business name)",
            key: :vendor,
            value: @vendor,
            placeholder: "e.g. Naivas Westlands",
            error: @errors[:vendor]
          )}
          {FormField.field(
            label: "Description (optional)",
            key: :description,
            value: @description,
            placeholder: "e.g. Office stationery",
            hint: "What you bought, so you can find it later.",
            error: @errors[:description]
          )}
          {FormField.field(
            label: "Amount paid (Ksh)",
            key: :amount,
            value: @amount,
            placeholder: "e.g. 1,250.50",
            keyboard: :decimal,
            hint: "The total on the receipt, including VAT.",
            error: @errors[:amount]
          )}
          <Column gap={4} fill_width={true}>
            <Text text="Category" text_size={:sm} font_weight="medium" text_color={:on_background} />
            <Button
              text={@category}
              on_tap={{self(), :pick_category}}
              fill_width={true}
              background={:surface}
              text_color={:on_surface}
            />
            <Text
              :if={@errors[:category]}
              text={@errors[:category]}
              text_size={:xs}
              text_color={:error}
            />
          </Column>
          <Text :if={@errors[:base]} text={@errors[:base]} text_color={:error} />
        </Column>
      </Scroll>
      <Column padding={12} fill_width={true}>
        <Button
          text={if @reading, do: "Reading receipt…", else: "Save receipt"}
          on_tap={{self(), :save}}
          enabled={not @reading}
          fill_width={true}
          padding={:xs}
        />
      </Column>
    </Column>
    """
  end

  defp photo_section(%{reading: true}) do
    ~MOB"""
    <Box background={:surface} corner_radius={:radius_sm} padding={16} fill_width={true}>
      <Column gap={4} fill_width={true}>
        <Text text="Reading receipt…" text_size={:base} font_weight="medium" />
        <Text
          text="Finding the vendor, date and total in your photo."
          text_size={:xs}
          text_color={:muted}
        />
      </Column>
    </Box>
    """
  end

  defp photo_section(%{receipt: %Receipt{photo_path: nil}}) do
    ~MOB"""
    <Button
      text="Add receipt photo (reads the details for you)"
      on_tap={{self(), :take_photo}}
      fill_width={true}
      background={:surface}
      text_color={:on_surface}
    />
    """
  end

  defp photo_section(%{receipt: receipt}) do
    ~MOB"""
    <Column gap={8} fill_width={true}>
      <Text text="Receipt photo" text_size={:sm} font_weight="medium" text_color={:on_background} />
      <Image
        src={Photos.path(receipt.photo_path)}
        fill_width={true}
        height={260}
        content_mode={:fit}
        corner_radius={:radius_sm}
      />
      <Row gap={8} fill_width={true}>
        <Button
          text="Retake"
          on_tap={{self(), :take_photo}}
          weight={1}
          background={:surface}
          text_color={:on_surface}
        />
        <Button
          text="Remove photo"
          on_tap={{self(), :remove_photo}}
          weight={1}
          background={:surface}
          text_color={:on_surface}
        />
      </Row>
    </Column>
    """
  end

  defp qr_section(%{receipt: %Receipt{qr_content: nil}, reading: false}) do
    ~MOB"""
    <Button
      text="Scan the receipt's QR code"
      on_tap={{self(), :scan_qr}}
      fill_width={true}
      background={:surface}
      text_color={:on_surface}
    />
    """
  end

  defp qr_section(%{receipt: %Receipt{qr_content: nil}}), do: []

  defp qr_section(%{receipt: receipt}) do
    ~MOB"""
    <Box background={:surface} corner_radius={:radius_sm} padding={12} fill_width={true}>
      <Column gap={4} fill_width={true}>
        <Text text={qr_heading(receipt)} text_size={:sm} font_weight="medium" />
        <Text
          :if={receipt.seller_pin}
          text={"Seller KRA PIN: #{receipt.seller_pin}"}
          text_size={:sm}
        />
        <Text :if={receipt.branch_id} text={"Branch: #{receipt.branch_id}"} text_size={:sm} />
        <Text
          :if={receipt.invoice_number}
          text={"Receipt no.: #{receipt.invoice_number}"}
          text_size={:sm}
          max_lines={2}
        />
      </Column>
    </Box>
    """
  end

  # ── Typing ──────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:change, key, value}, socket) when key in @text_fields do
    {:noreply,
     socket
     |> Mob.Socket.assign(key, value)
     |> Mob.Socket.assign(:touched, MapSet.put(socket.assigns.touched, key))
     |> Mob.Socket.assign(:errors, Map.delete(socket.assigns.errors, key))}
  end

  def handle_info({:tap, :pick_category}, socket) do
    buttons =
      @categories
      |> Enum.with_index()
      |> Enum.map(fn {category, i} -> [label: category, action: :"category_#{i}"] end)

    {:noreply,
     Mob.Alert.action_sheet(socket,
       title: "Category",
       buttons: buttons ++ [[label: "Cancel", style: :cancel]]
     )}
  end

  def handle_info({:alert, action}, socket) when is_map_key(@category_actions, action) do
    {:noreply, Mob.Socket.assign(socket, :category, Map.fetch!(@category_actions, action))}
  end

  # ── Camera: photo and QR ────────────────────────────────────────────────────

  def handle_info({:tap, what}, socket) when what in [:take_photo, :scan_qr] do
    {:noreply,
     socket
     |> Mob.Socket.assign(:pending_camera, what)
     |> Native.request_camera()}
  end

  def handle_info({:permission, :camera, :granted}, socket) do
    pending = socket.assigns.pending_camera
    socket = Mob.Socket.assign(socket, :pending_camera, nil)

    case pending do
      :take_photo -> {:noreply, Native.take_photo(socket)}
      :scan_qr -> {:noreply, Native.scan_qr(socket)}
      nil -> {:noreply, socket}
    end
  end

  def handle_info({:permission, :camera, _denied}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(:pending_camera, nil)
     |> Native.toast("Camera access is off. Allow it in Settings to add photos.")}
  end

  def handle_info({:camera, :photo, %{path: tmp}}, socket),
    do: {:noreply, read_photo(socket, tmp)}

  def handle_info({:ocr, :result, json}, socket) do
    data = MobOcr.decode(json)
    text = data["text"] || ""
    fields = OcrParser.parse(text)

    socket =
      socket
      |> replace_photo(Photos.name(data["path"]))
      |> update_receipt(&%{&1 | ocr_text: text, source: photo_source(&1)})
      |> attach_qr(data["qr"])
      |> update_receipt(fn r ->
        %{
          r
          | seller_pin: r.seller_pin || fields.seller_pin,
            invoice_number: r.invoice_number || fields.invoice_number
        }
      end)
      |> fill_untouched(fields)
      |> Mob.Socket.assign(:reading, false)

    {:noreply, Mob.Socket.assign(socket, :notice, ocr_notice(fields, socket.assigns))}
  end

  def handle_info({:ocr, :error, json}, socket) do
    data = MobOcr.decode(json)

    socket =
      case data["path"] do
        path when is_binary(path) -> replace_photo(socket, Photos.name(path))
        _ -> socket
      end

    notice =
      if data["message"] == "not_available",
        do:
          "Reading text from photos isn't available on this phone yet. Fill in the details below.",
        else:
          "Couldn't read the text in this photo. Fill in the details below, or retake it in better light."

    {:noreply, Mob.Socket.assign(socket, reading: false, notice: notice)}
  end

  def handle_info({:scan, :result, %{value: value}}, socket) when is_binary(value) do
    parsed = QrParser.parse(value)

    socket =
      socket
      |> attach_qr(value)
      |> fill_untouched(%{date: parsed.date, amount_cents: parsed.amount_cents, vendor: nil})
      |> Native.success()

    {:noreply, socket}
  end

  def handle_info({:tap, :remove_photo}, socket) do
    socket = replace_photo(socket, nil)
    {:noreply, update_receipt(socket, &%{&1 | ocr_text: nil})}
  end

  # ── Save / leave ────────────────────────────────────────────────────────────

  def handle_info({:tap, :save}, %{assigns: %{reading: true}} = socket), do: {:noreply, socket}

  def handle_info({:tap, :save}, socket) do
    case build_attrs(socket.assigns) do
      {:ok, attrs} -> save(socket, attrs)
      {:error, errors} -> {:noreply, Mob.Socket.assign(socket, :errors, errors)}
    end
  end

  def handle_info({:tap, :header_back}, socket) do
    discard_unsaved_photo(socket.assigns)
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp save(socket, attrs) do
    %{mode: mode, profile: profile, receipt: receipt, saved_photo: saved_photo} = socket.assigns

    result =
      case mode do
        :new -> Receipts.create_receipt(profile, receipt, attrs)
        :edit -> Receipts.update_receipt(Receipts.get_receipt!(profile, receipt.id), attrs)
      end

    case result do
      {:ok, saved} ->
        # The receipt now points at its new photo (or none); the old file is
        # no longer referenced.
        if saved_photo != saved.photo_path, do: Photos.delete(saved_photo)
        socket = Native.toast(socket, "Receipt saved")
        # Reset rather than pop so the list remounts with the new totals.
        {:noreply,
         Mob.Socket.reset_to(socket, DukaApp.Screens.ReceiptsScreen, %{}, transition: :pop)}

      {:error, changeset} ->
        {:noreply, Mob.Socket.assign(socket, :errors, changeset_errors(changeset))}
    end
  end

  @doc false
  # Turns the form's inputs into changeset attrs, catching the two fields
  # (date and amount) that need parsing before Ecto sees them. The QR and
  # photo details ride along from the draft receipt.
  def build_attrs(assigns) do
    date_result = Date.from_iso8601(String.trim(assigns.date))
    amount_result = Receipts.parse_amount(assigns.amount)

    errors =
      %{}
      |> put_error_if(match?({:error, _}, date_result), :date, "use the format 2026-09-23")
      |> put_error_if(amount_result == :error, :amount, "enter an amount like 1250 or 1,250.50")

    if errors == %{} do
      {:ok, date} = date_result
      {:ok, amount_cents} = amount_result

      receipt_attrs =
        Map.take(assigns.receipt, [
          :qr_content,
          :source,
          :seller_pin,
          :branch_id,
          :invoice_number,
          :verify_url,
          :photo_path,
          :ocr_text
        ])

      {:ok,
       Map.merge(receipt_attrs, %{
         date: date,
         vendor: assigns.vendor,
         description: assigns.description,
         amount_cents: amount_cents,
         category: assigns.category
       })}
    else
      {:error, errors}
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp read_photo(socket, tmp) do
    socket
    |> Mob.Socket.assign(reading: true, notice: nil)
    |> Native.process_photo(tmp, Photos.new_path())
  end

  # Points the draft at a new photo file. The file it pointed at before is
  # deleted unless it is the saved receipt's photo (that one goes on save,
  # so backing out of an edit leaves the receipt as it was).
  defp replace_photo(socket, name) do
    %{receipt: receipt, saved_photo: saved_photo} = socket.assigns
    if receipt.photo_path not in [nil, saved_photo, name], do: Photos.delete(receipt.photo_path)
    update_receipt(socket, &%{&1 | photo_path: name})
  end

  defp discard_unsaved_photo(%{receipt: %{photo_path: photo}, saved_photo: saved_photo}) do
    if photo != saved_photo, do: Photos.delete(photo)
  end

  defp update_receipt(socket, fun),
    do: Mob.Socket.assign(socket, :receipt, fun.(socket.assigns.receipt))

  defp photo_source(%Receipt{source: "manual"}), do: "ocr"
  defp photo_source(%Receipt{source: source}), do: source

  # A QR code already on the draft wins: it was scanned on purpose.
  defp attach_qr(socket, qr) when is_binary(qr) and qr != "" do
    case socket.assigns.receipt do
      %Receipt{qr_content: nil} = receipt ->
        socket
        |> Mob.Socket.assign(:receipt, Receipts.put_qr(receipt, qr))
        |> duplicate_check()

      _ ->
        socket
    end
  end

  defp attach_qr(socket, _qr), do: socket

  # Warns (the unique index will refuse the save anyway) when this QR code
  # is already on another saved receipt.
  defp duplicate_check(%{assigns: %{receipt: %Receipt{qr_content: nil}}} = socket), do: socket

  defp duplicate_check(socket) do
    %{profile: profile, receipt: receipt} = socket.assigns

    case Receipts.find_by_qr(profile, receipt.qr_content) do
      %Receipt{id: id} = existing when id != receipt.id ->
        Mob.Socket.assign(socket, :errors, %{
          base:
            "You already saved this receipt (#{existing.vendor}, " <>
              "#{Calendar.strftime(existing.date, "%d %b %Y")})."
        })

      _ ->
        socket
    end
  end

  # Values read off the photo or QR fill a field only if the user hasn't
  # typed in it — never overwrite what they entered.
  defp fill_untouched(socket, fields) do
    candidates = [
      date: fields.date && Date.to_iso8601(fields.date),
      vendor: fields.vendor,
      amount: fields.amount_cents && Receipts.amount_input(fields.amount_cents)
    ]

    Enum.reduce(candidates, socket, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc ->
        if MapSet.member?(acc.assigns.touched, key),
          do: acc,
          else: Mob.Socket.assign(acc, key, value)
    end)
  end

  defp ocr_notice(fields, assigns) do
    found =
      [vendor: "vendor", date: "date", amount_cents: "total"]
      |> Enum.filter(fn {key, _} -> fields[key] end)
      |> Enum.map(&elem(&1, 1))

    missing =
      [vendor: "vendor", date: "date", amount_cents: "total"]
      |> Enum.reject(fn {key, _} -> fields[key] end)
      |> Enum.map(&elem(&1, 1))

    qr_line =
      if assigns.receipt.qr_content, do: " Found the receipt's QR code.", else: ""

    cond do
      found == [] ->
        "Couldn't find the details in this photo. Fill them in below." <> qr_line

      missing == [] ->
        "Read the #{Enum.join(found, ", ")} from the photo. Check them against the receipt." <>
          qr_line

      true ->
        "Read the #{Enum.join(found, ", ")} from the photo. Couldn't find the " <>
          "#{Enum.join(missing, " or ")} — please fill it in." <> qr_line
    end
  end

  defp put_error_if(errors, true, key, message), do: Map.put(errors, key, message)
  defp put_error_if(errors, false, _key, _message), do: errors

  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.reduce(%{}, fn
      {:amount_cents, [message | _]}, acc -> Map.put(acc, :amount, "Amount #{message}")
      {:profile_id, [message | _]}, acc -> Map.put(acc, :base, String.capitalize(message))
      {field, [message | _]}, acc -> Map.put(acc, field, "#{humanize(field)} #{message}")
    end)
  end

  defp humanize(field), do: field |> Atom.to_string() |> String.capitalize()

  defp title(:edit, _receipt), do: "Edit receipt"
  defp title(:new, %Receipt{source: "manual", photo_path: nil}), do: "New receipt"
  defp title(:new, _receipt), do: "Confirm receipt"

  defp qr_heading(%Receipt{source: "etims"}), do: "KRA eTIMS QR code"
  defp qr_heading(%Receipt{source: "tims"}), do: "KRA TIMS (ETR) QR code"
  defp qr_heading(%Receipt{source: "kra"}), do: "KRA link"
  defp qr_heading(_receipt), do: "QR code (not a KRA receipt link)"
end
