defmodule DukaApp.Screens.ReceiptsScreen do
  @moduledoc """
  Home screen: this month's spend, the receipt list, and the ways to add a
  receipt.

  "Scan receipt" takes a photo and hands it to the confirm form, which saves
  it and reads the details off it. "Scan QR only" opens the QR scanner; a code
  that was already saved opens the saved receipt instead of a duplicate.
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Native, Receipts, Theme}
  alias DukaApp.Components.{ActionButton, ReceiptItem}
  alias DukaApp.Screens.{PhoneScreen, ReceiptFormScreen, SettingsScreen}

  # The month picker offers this many months back from today.
  @months 12
  @month_actions Map.new(0..(@months - 1), &{:"month_#{&1}", &1})

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    profile = Accounts.current_profile()

    socket =
      socket
      |> Mob.Socket.assign(:profile, profile)
      |> Mob.Socket.assign(:query, "")
      |> Mob.Socket.assign(:group, :all)
      |> Mob.Socket.assign(:searching, false)
      |> Mob.Socket.assign(:month, Date.beginning_of_month(Receipts.today()))
      |> Mob.Socket.assign(:selected, nil)
      |> Mob.Socket.assign(:pending_camera, nil)
      |> Mob.Socket.assign(:locked, profile != nil and profile.app_lock)
      |> load_receipts()
      |> Mob.List.put_renderer(:receipts, fn receipt ->
        ReceiptItem.expand(%{receipt: receipt}, [], %{})
      end)

    socket =
      if socket.assigns.locked,
        do: MobBiometric.authenticate(socket, reason: "Unlock your receipts"),
        else: socket

    {:ok, socket}
  end

  @impl Mob.Screen
  def render(%{profile: nil}) do
    ~MOB"""
    <Column padding={24} background={:background} fill_height={true}>
      <Text text="No receipt book is open." text_size={:lg} text_color={:on_background} />
      <Spacer size={16} />
      {ActionButton.button("phone", "Enter phone number", :sign_in)}
    </Column>
    """
  end

  def render(%{locked: true}) do
    ~MOB"""
    <Column padding={24} background={:background} fill_height={true}>
      <Spacer size={48} />
      <Text text="Receipts are locked" text_size={:xl} text_color={:on_background} />
      <Spacer size={16} />
      {ActionButton.button("lock", "Unlock", :unlock)}
    </Column>
    """
  end

  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header
        kicker={Calendar.strftime(Receipts.today(), "%A, %d %b")}
        title={greeting(@profile)}
        actions={[search_action(@searching), {"settings", "Settings", :open_settings}]}
      />
      <Column fill_width={true} padding_left={18} padding_right={18}>
        <SearchField :if={@searching} query={@query} on_change={{self(), :search}} />
        {if not @searching, do: spend_card(@summary, @month)}
        <Spacer size={14} />
      </Column>
      {chips(@group, @summary.count)}
      <Spacer size={14} />
      <Row fill_width={true} padding_left={22} padding_right={22} padding_bottom={8}>
        <Text
          text={list_title(@group)}
          text_size={13}
          font_weight="semibold"
          text_color={:muted}
          weight={1}
        />
        <Text
          text={count_label(length(@receipts))}
          text_size={13}
          font_weight="semibold"
          text_color={:muted}
        />
      </Row>
      <Text
        :if={@receipts == []}
        text={empty_text(@query, @group)}
        text_color={:muted}
        text_size={14}
        padding_left={22}
        padding_right={22}
        padding_top={12}
      />
      <List
        :if={@receipts != []}
        id={:receipts}
        items={@receipts}
        weight={1}
        padding_left={18}
        padding_right={18}
      />
      <Spacer :if={@receipts == []} weight={1} />
      {dock()}
      <ReceiptDetail :if={@selected} receipt={@selected} />
    </Column>
    """
  end

  defp search_action(false), do: {"search", "Search receipts", :toggle_search}
  defp search_action(true), do: {"close", "Close search", :toggle_search}

  # The dark card: the chosen month's spend, split three ways. The month pill
  # opens the month picker.
  defp spend_card(summary, month) do
    ~MOB"""
    <Box background={Theme.color(:spend_card)} corner_radius={24} padding={20} fill_width={true}>
      <Column fill_width={true}>
        <Row fill_width={true} align={:center}>
          <Text
            text={spent_label(month)}
            text_size={13}
            text_color={Theme.color(:spend_muted)}
            weight={1}
          />
          <Row
            background={Theme.color(:spend_chip)}
            corner_radius={:radius_pill}
            padding_left={10}
            padding_right={6}
            padding_top={5}
            padding_bottom={5}
            align={:center}
            on_tap={{self(), :pick_month}}
            accessibility_label={"Month: #{month_label(month)}. Change month"}
            accessibility_role={:button}
          >
            <Text
              text={month_label(month)}
              text_size={13}
              font_weight="medium"
              text_color={Theme.color(:spend_text)}
            />
            <Spacer size={2} />
            <Icon name="expand_more" text_size={16} text_color={Theme.color(:spend_text)} />
          </Row>
        </Row>
        <Spacer size={10} />
        <Text
          text={Receipts.format_short(summary.month_total)}
          text_size={36}
          font_weight="bold"
          letter_spacing={-1.8}
          text_color={Theme.color(:spend_text)}
        />
        <Spacer size={14} />
        <Row fill_width={true}>
          {Receipts.groups()
           |> Enum.map(&split_cell(&1, summary.month_by_group[&1]))
           |> Enum.intersperse(~MOB(<Spacer size={8} />))}
        </Row>
      </Column>
    </Box>
    """
  end

  defp split_cell(group, cents) do
    ~MOB"""
    <Box weight={1} background={Theme.color(:spend_chip)} corner_radius={14} padding={10}>
      <Column>
        <Row align={:center}>
          <Box width={7} height={7} corner_radius={4} background={Theme.color(group)} />
          <Spacer size={5} />
          <Text
            text={Receipts.group_label(group)}
            text_size={11}
            text_color={Theme.color(:spend_muted)}
          />
        </Row>
        <Spacer size={3} />
        <Text
          text={bare_amount(cents)}
          text_size={13}
          font_weight="semibold"
          text_color={Theme.color(:spend_text)}
        />
      </Column>
    </Box>
    """
  end

  # All / Food / Fuel / Other filter pills. The strip scrolls sideways in case
  # a large font size pushes the last pill off screen.
  defp chips(active, count) do
    pills =
      [{:all, "All · #{count}"} | Enum.map(Receipts.groups(), &{&1, Receipts.group_label(&1)})]
      |> Enum.map(fn {group, label} -> chip(group, label, group == active) end)
      |> Enum.intersperse(~MOB(<Spacer size={8} />))

    ~MOB"""
    <Scroll axis="horizontal" fill_width={true}>
      <Row padding_left={18} padding_right={18}>
        {pills}
      </Row>
    </Scroll>
    """
  end

  # A Row, not a Box: a Box without a width fills the whole row on Android.
  defp chip(group, label, active?) do
    {background, text_color} =
      if active?, do: {:on_background, :background}, else: {:surface, :on_surface}

    ~MOB"""
    <Row
      background={background}
      border_color={if(active?, do: :on_background, else: :border)}
      border_width={1}
      corner_radius={:radius_pill}
      padding_left={12}
      padding_right={12}
      padding_top={7}
      padding_bottom={7}
      on_tap={{self(), {:group, group}}}
      accessibility_role={:button}
    >
      <Text text={label} text_size={13} font_weight="medium" text_color={text_color} />
    </Row>
    """
  end

  # Scan receipt, scan QR, add by hand.
  defp dock do
    ~MOB"""
    <Column
      fill_width={true}
      padding_left={14}
      padding_right={14}
      padding_top={8}
      padding_bottom={18}
    >
      <Box
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={24}
        padding={10}
        fill_width={true}
      >
        <Row fill_width={true} align={:center}>
          <Box
            weight={1}
            height={48}
            background={:primary}
            corner_radius={16}
            align={:center}
            on_tap={{self(), :take_photo}}
            accessibility_label="Scan receipt"
            accessibility_role={:button}
          >
            <Row align={:center}>
              <Icon name="camera" text_size={16} text_color={:on_primary} />
              <Spacer size={8} />
              <Text
                text="Scan receipt"
                text_size={15}
                font_weight="semibold"
                text_color={:on_primary}
              />
            </Row>
          </Box>
          <Spacer size={8} />
          {ghost_button("qr_code", "Scan QR code", :scan_qr)}
          <Spacer size={8} />
          {ghost_button("add", "Add by hand", :add_manual)}
        </Row>
      </Box>
    </Column>
    """
  end

  defp ghost_button(icon, label, tag) do
    ~MOB"""
    <Box
      width={48}
      height={48}
      background={:surface_raised}
      border_color={:border}
      border_width={1}
      corner_radius={16}
      align={:center}
      on_tap={{self(), tag}}
      accessibility_label={label}
      accessibility_role={:button}
    >
      <Icon name={icon} text_size={18} text_color={:on_surface} />
    </Box>
    """
  end

  # ── Scanning ────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:tap, what}, socket) when what in [:take_photo, :scan_qr] do
    # Asking is cheap when permission is already granted, and it covers the
    # case where the user revoked it in system settings since last time.
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
     |> Mob.Alert.alert(
       title: "Camera access needed",
       message: "Allow camera access in Settings to photograph and scan receipts.",
       buttons: [
         [label: "Open Settings", action: :open_app_settings],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  # The form saves and reads the photo; the camera's file is only temporary.
  def handle_info({:camera, :photo, %{path: path}}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, ReceiptFormScreen, %{photo: path})}
  end

  def handle_info({:camera, :cancelled}, socket), do: {:noreply, socket}

  def handle_info({:alert, :open_app_settings}, socket) do
    Mob.Device.open_settings(:app)
    {:noreply, socket}
  end

  def handle_info({:scan, :result, %{value: value}}, socket) when is_binary(value) do
    socket = Native.success(socket)

    case Receipts.find_by_qr(socket.assigns.profile, value) do
      nil ->
        {:noreply, Mob.Socket.push_screen(socket, ReceiptFormScreen, %{qr: value})}

      existing ->
        socket = Native.toast(socket, "You already saved this receipt")
        {:noreply, Mob.Socket.assign(socket, :selected, existing)}
    end
  end

  def handle_info({:scan, :not_available}, socket) do
    socket = Native.toast(socket, "No camera available — add the receipt by hand")
    {:noreply, socket}
  end

  def handle_info({:scan, _cancelled}, socket), do: {:noreply, socket}

  # ── List and detail sheet ───────────────────────────────────────────────────

  def handle_info({:select, :receipts, index}, socket), do: select(socket, index)
  def handle_info({:tap, {:list, :receipts, :select, index}}, socket), do: select(socket, index)

  def handle_info({event, :close_receipt}, socket) when event in [:tap, :dismiss] do
    {:noreply, Mob.Socket.assign(socket, :selected, nil)}
  end

  def handle_info({:tap, :edit_receipt}, socket) do
    %{id: id} = socket.assigns.selected

    {:noreply,
     socket
     |> Mob.Socket.assign(:selected, nil)
     |> Mob.Socket.push_screen(ReceiptFormScreen, %{id: id})}
  end

  def handle_info({:tap, :verify_receipt}, socket) do
    case socket.assigns.selected do
      %{verify_url: url} when is_binary(url) -> Mob.Device.open_url(url)
      _ -> :ok
    end

    {:noreply, socket}
  end

  def handle_info({:tap, :delete_receipt}, socket) do
    {:noreply,
     Mob.Alert.alert(socket,
       title: "Delete this receipt?",
       message: "It will be removed from this phone. This cannot be undone.",
       buttons: [
         [label: "Delete", style: :destructive, action: :confirm_delete],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :confirm_delete}, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, socket}

      receipt ->
        {:ok, _} = Receipts.delete_receipt(receipt)
        socket = Native.toast(socket, "Receipt deleted")

        {:noreply,
         socket
         |> Mob.Socket.assign(:selected, nil)
         |> load_receipts()}
    end
  end

  # ── Everything else ─────────────────────────────────────────────────────────

  def handle_info({:change, :search, query}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(:query, query)
     |> load_receipts()}
  end

  def handle_info({:tap, {:group, group}}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(:group, group)
     |> load_receipts()}
  end

  def handle_info({:tap, :add_manual}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, ReceiptFormScreen, %{})}
  end

  def handle_info({:tap, :toggle_search}, %{assigns: %{searching: true}} = socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(searching: false, query: "")
     |> load_receipts()}
  end

  def handle_info({:tap, :toggle_search}, socket) do
    {:noreply, Mob.Socket.assign(socket, :searching, true)}
  end

  def handle_info({:tap, :pick_month}, socket) do
    buttons =
      @months
      |> Receipts.recent_months()
      |> Enum.with_index()
      |> Enum.map(fn {month, i} -> [label: month_label(month, :long), action: :"month_#{i}"] end)

    {:noreply,
     Mob.Alert.action_sheet(socket,
       title: "Show spending for",
       buttons: buttons ++ [[label: "Cancel", style: :cancel]]
     )}
  end

  def handle_info({:alert, action}, socket) when is_map_key(@month_actions, action) do
    month = Enum.at(Receipts.recent_months(@months), Map.fetch!(@month_actions, action))

    {:noreply,
     socket
     |> Mob.Socket.assign(:month, month)
     |> load_receipts()}
  end

  def handle_info({:tap, :open_settings}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, SettingsScreen)}
  end

  def handle_info({:tap, :sign_in}, socket) do
    {:noreply, Mob.Socket.reset_to(socket, PhoneScreen)}
  end

  def handle_info({:tap, :unlock}, socket) do
    {:noreply, MobBiometric.authenticate(socket, reason: "Unlock your receipts")}
  end

  def handle_info({:biometric, :success}, socket) do
    {:noreply, Mob.Socket.assign(socket, :locked, false)}
  end

  # A phone with no fingerprint/face enrolled cannot lock the app; don't lock
  # the user out of their own receipts because of it.
  def handle_info({:biometric, :not_available}, socket) do
    socket = Native.toast(socket, "Biometric unlock is not set up on this phone")
    {:noreply, Mob.Socket.assign(socket, :locked, false)}
  end

  def handle_info({:biometric, _failure}, socket), do: {:noreply, socket}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp select(socket, index) do
    {:noreply, Mob.Socket.assign(socket, :selected, Enum.at(socket.assigns.receipts, index))}
  end

  defp load_receipts(%{assigns: %{profile: nil}} = socket) do
    socket
    |> Mob.Socket.assign(:receipts, [])
    |> Mob.Socket.assign(:summary, %{
      count: 0,
      total: 0,
      month_total: 0,
      month_by_group: Map.new(Receipts.groups(), &{&1, 0})
    })
  end

  defp load_receipts(socket) do
    %{profile: profile, query: query, group: group, month: month} = socket.assigns

    socket
    |> Mob.Socket.assign(:receipts, Receipts.list_receipts(profile, query, group))
    |> Mob.Socket.assign(:summary, Receipts.summary(profile, month))
  end

  defp greeting(%{name: name}) when is_binary(name) and name != "", do: "Hi, #{name}"
  defp greeting(_profile), do: "Your receipts"

  defp spent_label(month) do
    if month == Date.beginning_of_month(Receipts.today()),
      do: "Spent this month",
      else: "Spent in #{month_label(month, :long)}"
  end

  # "September" this year, "Sep 2025" before it; `:long` always has the year.
  defp month_label(month, style \\ :short) do
    cond do
      style == :long -> Calendar.strftime(month, "%B %Y")
      month.year == Receipts.today().year -> Calendar.strftime(month, "%B")
      true -> Calendar.strftime(month, "%b %Y")
    end
  end

  defp list_title(:all), do: "All receipts"
  defp list_title(group), do: Receipts.group_label(group)

  defp count_label(1), do: "1 receipt"
  defp count_label(count), do: "#{count} receipts"

  # "Ksh 1,205" without the currency, for the small split cells.
  defp bare_amount(cents),
    do: cents |> Receipts.format_short() |> String.replace_prefix("Ksh ", "")

  defp empty_text("", :all),
    do:
      "No receipts yet. Tap “Scan receipt” and take a photo of a receipt — the app reads the details and keeps the picture."

  defp empty_text("", group),
    do: "No #{String.downcase(Receipts.group_label(group))} receipts yet."

  defp empty_text(_query, _group), do: "No receipts match your search."
end
