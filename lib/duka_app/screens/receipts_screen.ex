defmodule DukaApp.Screens.ReceiptsScreen do
  @moduledoc """
  Home screen: this month's spend, the receipts and the refund and payment
  requests in one list, and the ways to add either.

  A receipt book connected to a team syncs with the server when this screen
  opens, after a request is sent, when the app comes back to the foreground
  or back online, and when the server pushes a notification (see
  `DukaApp.Sync` and `DukaApp.Push`). Each receipt and request shows whether
  the server has it yet. One that isn't connected gets a short warning that
  opens Settings to connect.

  This screen stays alive under the others, so it is the one that registers
  for pushes and receives them.

  "Scan receipt" takes a photo and hands it to the confirm form, which saves
  it and reads the details off it. "Scan QR only" opens the QR scanner; a code
  that was already saved opens the saved receipt instead of a duplicate.
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Api, Native, Push, Receipts, Sync, Theme}
  alias DukaApp.Components.{ActionButton, Header, ReceiptItem, RequestItem}
  alias DukaApp.Receipts.{Photos, Receipt}
  alias DukaApp.Requests
  alias DukaApp.Requests.{Attachment, Attachments, Request}

  alias DukaApp.Accounts.Profile

  alias DukaApp.Screens.{
    ApprovalsScreen,
    PhoneScreen,
    ReceiptFormScreen,
    RequestFormScreen,
    SettingsScreen
  }

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
      # KRA checks in flight, receipt id => :tap (the user asked, so say how
      # it went) or :background (quiet). `tried` stops a background check
      # that failed from being retried over and over on this screen.
      |> Mob.Socket.assign(:verifying, %{})
      |> Mob.Socket.assign(:tried, MapSet.new())
      |> Mob.Socket.assign(:viewing_photo, false)
      |> Mob.Socket.assign(:month, Date.beginning_of_month(Receipts.today()))
      |> Mob.Socket.assign(:selected, nil)
      # The refund already asked for the open receipt, if any.
      |> Mob.Socket.assign(:selected_refund, nil)
      |> Mob.Socket.assign(:selected_request, nil)
      |> Mob.Socket.assign(:syncing, false)
      |> Mob.Socket.assign(:pending_camera, nil)
      # When the app last came to the front: a push that arrives just after
      # is one the person tapped (see `opened_from_tray?/1`).
      |> Mob.Socket.assign(:resumed_at, now_ms())
      |> Mob.Socket.assign(:locked, profile != nil and profile.app_lock)
      |> load_receipts()
      |> verify_next()
      |> start_sync()
      |> watch_server()

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

  # The receipt photo, full screen: pinch to zoom, save to the gallery.
  def render(%{viewing_photo: true, selected: %{photo_path: photo} = receipt})
      when is_binary(photo) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Row
        fill_width={true}
        align={:center}
        padding_top={12}
        padding_left={18}
        padding_right={18}
        padding_bottom={12}
      >
        {Header.icon_button("close", "Close photo", {self(), :close_photo})}
        <Spacer size={12} />
        <Text
          text={receipt.vendor}
          text_size={16}
          font_weight="semibold"
          text_color={:on_background}
          max_lines={1}
          weight={1}
        />
        <Spacer size={12} />
        {ActionButton.button("download", "Save", :save_photo, width: 96)}
      </Row>
      <Image
        src={Photos.path(photo)}
        zoomable={true}
        content_mode={:fit}
        fill_width={true}
        weight={1}
      />
      <Text
        text="Pinch to zoom · double-tap to zoom in or out"
        text_size={12}
        text_color={:muted}
        text_align={:center}
        padding_top={10}
        padding_bottom={18}
      />
    </Column>
    """
  end

  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header
        kicker={Calendar.strftime(Receipts.today(), "%A, %d %b")}
        title={greeting(@profile)}
        actions={header_actions(@searching, @profile)}
      />
      <Column fill_width={true} padding_left={18} padding_right={18}>
        <SearchField :if={@searching} query={@query} on_change={{self(), :search}} />
        {if not @searching, do: connect_banner(@profile)}
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
          text={count_label(@group, length(@items))}
          text_size={13}
          font_weight="semibold"
          text_color={:muted}
        />
      </Row>
      <Text
        :if={@items == []}
        text={empty_text(@query, @group)}
        text_color={:muted}
        text_size={14}
        padding_left={22}
        padding_right={22}
        padding_top={12}
      />
      <List
        :if={@items != []}
        id={:receipts}
        items={@items}
        weight={1}
        padding_left={18}
        padding_right={18}
      />
      <Spacer :if={@items == []} weight={1} />
      {if not @searching, do: dock()}
      <ReceiptDetail :if={@selected} receipt={@selected} refund={@selected_refund} />
      {RequestItem.sheet(@selected_request)}
    </Column>
    """
  end

  # Managers get the Approvals inbox. It also shows before connecting, when
  # the server can't yet say who may approve; tapping it then opens Settings.
  defp header_actions(searching, profile) do
    approvals =
      if Profile.manager?(profile) or not Profile.connected?(profile),
        do: [{"approvals", "Approvals", :open_approvals}],
        else: []

    [search_action(searching)] ++ approvals ++ [{"settings", "Settings", :open_settings}]
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
      ([{:all, "All · #{count}"} | Enum.map(Receipts.groups(), &{&1, Receipts.group_label(&1)})] ++
         [{:requests, "Requests"}])
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
          {ghost_button("add", "Add by hand or request a payment", :add_menu)}
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
    {:noreply, Mob.Socket.assign(socket, selected: nil, viewing_photo: false)}
  end

  def handle_info({:tap, :edit_receipt}, socket) do
    %{id: id} = socket.assigns.selected

    {:noreply,
     socket
     |> Mob.Socket.assign(:selected, nil)
     |> Mob.Socket.push_screen(ReceiptFormScreen, %{id: id})}
  end

  # Checks the receipt against KRA's verification page in the app. Each
  # lookup carries the receipt's id, so the answer lands on the right receipt
  # even if the sheet has been closed in the meantime.
  def handle_info({:tap, :verify_receipt}, socket) do
    case socket.assigns.selected do
      %{} = receipt ->
        if Receipts.verifiable?(receipt) do
          {:noreply, socket |> Native.toast("Checking with KRA…") |> start_verify(receipt, :tap)}
        else
          {:noreply, socket}
        end

      nil ->
        {:noreply, socket}
    end
  end

  def handle_info({:kra, :result, details, {:verify, id}}, socket) do
    {mode, socket} = finish_verify(socket, id)

    socket =
      case Receipts.get_receipt(socket.assigns.profile, id) do
        nil ->
          socket

        receipt ->
          {:ok, verified} = Receipts.mark_verified(receipt)

          selected =
            case socket.assigns.selected do
              %{id: ^id} -> verified
              other -> other
            end

          socket = Mob.Socket.assign(socket, :selected, selected)

          if mode == :tap,
            do: socket |> Native.success() |> Native.toast(verified_message(verified, details)),
            else: socket
      end

    {:noreply, socket |> load_receipts() |> verify_next()}
  end

  def handle_info({:kra, :error, _reason, {:verify, id}}, socket) do
    {mode, socket} = finish_verify(socket, id)

    socket =
      if mode == :tap,
        do:
          Native.toast(
            socket,
            "Couldn't reach KRA — check your internet connection and try again"
          ),
        else: socket

    {:noreply, verify_next(socket)}
  end

  def handle_info({:tap, :open_on_kra}, socket) do
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
        case Receipts.delete_receipt(receipt) do
          {:ok, _} ->
            {:noreply,
             socket
             |> Native.toast("Receipt deleted")
             |> Mob.Socket.assign(:selected, nil)
             |> load_receipts()
             |> start_sync()}

          {:error, :decided} ->
            {:noreply,
             Native.toast(socket, "Your manager has decided on this receipt, so it stays")}

          {:error, :has_request} ->
            {:noreply, Native.toast(socket, "Withdraw its refund request first")}
        end
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

  def handle_info({:tap, :open_approvals}, socket) do
    if Profile.connected?(socket.assigns.profile) do
      {:noreply, Mob.Socket.push_screen(socket, ApprovalsScreen)}
    else
      {:noreply,
       socket
       |> Native.toast("Connect to your team to see approvals")
       |> Mob.Socket.push_screen(SettingsScreen)}
    end
  end

  # ── Adding, and requests ──────────────────────────────────────────────────

  def handle_info({:tap, :add_menu}, socket) do
    {:noreply,
     Mob.Alert.action_sheet(socket,
       title: "Add",
       buttons: [
         [label: "Add a receipt by hand", action: :add_manual],
         [label: "Request a payment", action: :new_payment],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :add_manual}, socket), do: handle_info({:tap, :add_manual}, socket)

  def handle_info({event, :new_payment}, socket) when event in [:tap, :alert] do
    {:noreply, Mob.Socket.push_screen(socket, RequestFormScreen, %{notify: self()})}
  end

  # The form pops back here rather than remounting this screen.
  def handle_info({:request_saved, _request}, socket) do
    {:noreply, socket |> load_receipts() |> start_sync()}
  end

  def handle_info({event, :close_request}, socket) when event in [:tap, :dismiss] do
    {:noreply, Mob.Socket.assign(socket, :selected_request, nil)}
  end

  def handle_info({:tap, :cancel_request}, socket) do
    {:noreply,
     Mob.Alert.alert(socket,
       title: "Withdraw this request?",
       message: "Your manager won't see it any more.",
       buttons: [
         [label: "Withdraw", style: :destructive, action: :confirm_cancel],
         [label: "Keep", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :confirm_cancel}, socket) do
    case socket.assigns.selected_request &&
           Requests.cancel_request(socket.assigns.selected_request) do
      {:ok, _} ->
        {:noreply,
         socket
         |> Native.toast("Request withdrawn")
         |> Mob.Socket.assign(:selected_request, nil)
         |> load_receipts()
         |> start_sync()}

      {:error, :not_pending} ->
        {:noreply,
         Native.toast(socket, "Only a request still waiting for approval can be withdrawn")}

      nil ->
        {:noreply, socket}
    end
  end

  # One that came from the server downloads first.
  def handle_info({:tap, {:open_attachment, id}}, socket) do
    with %Request{attachments: attachments} <- socket.assigns.selected_request,
         %Attachment{} = attachment <- Enum.find(attachments, &(&1.id == id)) do
      path = Attachments.path(attachment.file_name)

      if File.regular?(path) do
        {:noreply, Native.open_file(socket, path)}
      else
        profile = socket.assigns.profile

        {:noreply,
         socket
         |> Native.toast("Downloading…")
         |> Native.background(:attachment_fetched, fn ->
           with :ok <- Sync.fetch_attachment(profile, attachment), do: {:ok, path}
         end)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:attachment_fetched, {:ok, path}}, socket),
    do: {:noreply, Native.open_file(socket, path)}

  def handle_info({:attachment_fetched, {:error, error}}, socket),
    do: {:noreply, Native.toast(socket, Api.error_message(error))}

  # ── Server sync ────────────────────────────────────────────────────────────

  def handle_info({:sync, {:ok, _summary}}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(:syncing, false)
     |> reload_profile()
     |> load_receipts()
     |> send_push_token()}
  end

  # The server no longer accepts the token: offer to sign in again.
  def handle_info({:sync, {:error, :unauthorized}}, socket) do
    {:ok, profile} = Accounts.disconnect(socket.assigns.profile)

    {:noreply,
     socket
     |> Mob.Socket.assign(profile: profile, syncing: false)
     |> Native.toast(Api.error_message(:unauthorized))}
  end

  # Offline, or not connected: try again next time.
  def handle_info({:sync, {:error, _reason}}, socket),
    do: {:noreply, Mob.Socket.assign(socket, :syncing, false)}

  # Back in the foreground or back online: catch up with the server.
  def handle_info({:mob_device, :will_enter_foreground}, socket),
    do: {:noreply, socket |> Mob.Socket.assign(:resumed_at, now_ms()) |> start_sync()}

  def handle_info({:mob_device, :connectivity_changed, %{online: true}}, socket),
    do: {:noreply, start_sync(socket)}

  # ── Push notifications ─────────────────────────────────────────────────────

  def handle_info({:permission, :notifications, :granted}, socket),
    do: {:noreply, Native.register_push(socket)}

  def handle_info({:permission, :notifications, _denied}, socket), do: {:noreply, socket}

  def handle_info({:push_token, platform, token}, socket) do
    Push.remember(platform, token)
    {:noreply, send_push_token(socket)}
  end

  def handle_info({:push_registered, _result}, socket), do: {:noreply, socket}

  def handle_info({:mob_launch_notification, json}, socket),
    do: handle_info({:notification, Push.decode(json)}, socket)

  # Something changed on the server: sync, refresh Approvals if it's open,
  # and either open what the push is about (tapped) or say what happened.
  def handle_info({:notification, %{source: :push} = notification}, socket) do
    if pid = Process.whereis(ApprovalsScreen), do: send(pid, :server_changed)
    socket = start_sync(socket)

    cond do
      not opened_from_tray?(socket) ->
        {:noreply, Native.toast(socket, notice(notification))}

      Push.screen(notification) == :approvals and Profile.manager?(socket.assigns.profile) and
          Process.whereis(ApprovalsScreen) == nil ->
        {:noreply, Mob.Socket.push_screen(socket, ApprovalsScreen)}

      true ->
        {:noreply, socket}
    end
  end

  # The sheet closes on the way out; reopening the receipt looks the refund
  # up again, so it shows the new one. The form reports back when it's saved.
  def handle_info({:tap, :request_refund}, socket) do
    %{id: id} = socket.assigns.selected

    {:noreply,
     socket
     |> Mob.Socket.assign(selected: nil, selected_refund: nil)
     |> Mob.Socket.push_screen(RequestFormScreen, %{receipt_id: id, notify: self()})}
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

  # ── Receipt photo viewer ────────────────────────────────────────────────────

  # A photo that came from the server downloads first.
  def handle_info({:tap, :view_photo}, socket) do
    case socket.assigns.selected do
      %Receipt{photo_path: photo} = receipt when is_binary(photo) ->
        if Photos.exists?(photo) do
          {:noreply, Mob.Socket.assign(socket, :viewing_photo, true)}
        else
          profile = socket.assigns.profile

          {:noreply,
           socket
           |> Native.toast("Downloading the photo…")
           |> Native.background(:photo_fetched, fn -> Sync.fetch_photo(profile, receipt) end)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:photo_fetched, :ok}, socket),
    do: {:noreply, Mob.Socket.assign(socket, :viewing_photo, true)}

  def handle_info({:photo_fetched, {:error, error}}, socket),
    do: {:noreply, Native.toast(socket, Api.error_message(error))}

  def handle_info({:tap, :close_photo}, socket) do
    {:noreply, Mob.Socket.assign(socket, :viewing_photo, false)}
  end

  def handle_info({:tap, :save_photo}, socket) do
    case socket.assigns.selected do
      %{photo_path: photo} when is_binary(photo) ->
        {:noreply, Native.save_to_gallery(socket, Photos.path(photo))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:storage, :saved_to_library, _path}, socket) do
    {:noreply, Native.toast(socket, "Saved to your phone's gallery")}
  end

  def handle_info({:storage, :error, :save_to_library, _reason}, socket) do
    {:noreply, Native.toast(socket, "Couldn't save the photo to your gallery")}
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

  # Starts a KRA check for `receipt`. A check already running for it is
  # promoted to :tap so the user hears the answer, rather than started twice.
  defp start_verify(socket, receipt, mode) do
    %{verifying: verifying, tried: tried} = socket.assigns

    socket =
      Mob.Socket.assign(socket,
        verifying: Map.put(verifying, receipt.id, mode),
        tried: MapSet.put(tried, receipt.id)
      )

    if Map.has_key?(verifying, receipt.id),
      do: socket,
      else: Native.lookup_kra(socket, receipt.verify_url, {:verify, receipt.id})
  end

  defp finish_verify(socket, id) do
    {mode, verifying} = Map.pop(socket.assigns.verifying, id)
    {mode, Mob.Socket.assign(socket, :verifying, verifying)}
  end

  # Quietly verifies saved KRA receipts one at a time: ones saved before KRA
  # answered (or while offline) and ones from before verification existed.
  defp verify_next(%{assigns: %{profile: nil}} = socket), do: socket

  defp verify_next(%{assigns: %{verifying: verifying}} = socket) when map_size(verifying) > 0,
    do: socket

  defp verify_next(socket) do
    %{profile: profile, tried: tried} = socket.assigns

    case Receipts.next_unverified(profile, tried) do
      nil -> socket
      receipt -> start_verify(socket, receipt, :background)
    end
  end

  defp select(socket, index) do
    case Enum.at(socket.assigns.items, index) do
      %Request{} = request ->
        {:noreply, Mob.Socket.assign(socket, :selected_request, request)}

      receipt ->
        refund = receipt && Requests.open_refund(receipt)
        {:noreply, Mob.Socket.assign(socket, selected: receipt, selected_refund: refund)}
    end
  end

  # `sync` marks what has reached the server, in a connected receipt book.
  defp list_item(%Request{} = request, sync), do: RequestItem.row(request, sync: sync)

  defp list_item(%Receipt{} = receipt, sync),
    do: ReceiptItem.expand(%{receipt: receipt, sync: sync}, [], %{})

  defp start_sync(%{assigns: %{profile: profile, syncing: false}} = socket) do
    if Profile.connected?(profile),
      do: socket |> Mob.Socket.assign(:syncing, true) |> Native.sync(),
      else: socket
  end

  defp start_sync(socket), do: socket

  # A connected receipt book hears from the server: pushes (once Firebase is
  # set up, `config :duka_app, :push`), and the app coming back to the front
  # or back online.
  defp watch_server(%{assigns: %{profile: profile}} = socket) do
    cond do
      not Profile.connected?(profile) ->
        socket

      Application.get_env(:duka_app, :push, false) ->
        socket |> Native.watch_device() |> Native.request_notifications()

      true ->
        Native.watch_device(socket)
    end
  end

  defp send_push_token(%{assigns: %{profile: profile}} = socket) do
    if Profile.connected?(profile) and Push.pending?(profile),
      do: Native.background(socket, :push_registered, fn -> Push.register(profile) end),
      else: socket
  end

  # A tapped push opens (or brings back) the app, so it lands right after.
  defp opened_from_tray?(socket), do: now_ms() - socket.assigns.resumed_at < 3_000

  defp notice(%{title: title, body: body}) when is_binary(body) and body != "",
    do: "#{title}: #{body}"

  defp notice(%{title: title}) when is_binary(title), do: title
  defp notice(_notification), do: "Updated from your team"

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp reload_profile(%{assigns: %{profile: %Profile{id: id}}} = socket),
    do: Mob.Socket.assign(socket, :profile, Accounts.get_profile!(id))

  defp reload_profile(socket), do: socket

  # Not connected to a team: a short warning that opens Settings to connect.
  defp connect_banner(profile) do
    if Profile.connected?(profile) do
      []
    else
      ~MOB"""
      <Column fill_width={true} padding_bottom={12}>
        <Row
          fill_width={true}
          align={:center}
          background={:surface}
          border_color={:border}
          border_width={1}
          corner_radius={14}
          padding={10}
          on_tap={{self(), :open_settings}}
          accessibility_label="Not connected to a team. Open settings to connect."
          accessibility_role={:button}
        >
          <Icon name="warning" text_size={16} text_color={:error} />
          <Spacer size={8} />
          <Text
            text="Not connected to a team"
            text_size={13}
            font_weight="semibold"
            text_color={:on_surface}
            weight={1}
          />
          <Icon name="chevron_right" text_size={16} text_color={:muted} />
        </Row>
      </Column>
      """
    end
  end

  defp load_receipts(%{assigns: %{profile: nil}} = socket) do
    socket
    |> Mob.Socket.assign(:receipts, [])
    |> Mob.Socket.assign(:items, [])
    |> Mob.Socket.assign(:summary, %{
      count: 0,
      total: 0,
      month_total: 0,
      month_by_group: Map.new(Receipts.groups(), &{&1, 0})
    })
  end

  defp load_receipts(socket) do
    %{profile: profile, query: query, group: group, month: month} = socket.assigns

    receipts = if group == :requests, do: [], else: Receipts.list_receipts(profile, query, group)
    requests = if group in [:all, :requests], do: matching_requests(profile, query), else: []

    sync = Profile.connected?(profile)

    socket
    |> Mob.Socket.assign(:receipts, receipts)
    |> Mob.Socket.assign(:items, newest_first(receipts, requests))
    |> Mob.Socket.assign(:summary, Receipts.summary(profile, month))
    |> Mob.List.put_renderer(:receipts, &list_item(&1, sync))
  end

  defp matching_requests(profile, query) do
    requests = Requests.list_requests(profile)

    case String.downcase(String.trim(query)) do
      "" ->
        requests

      term ->
        Enum.filter(requests, fn request ->
          [RequestItem.headline(request), request.payee_name, request.purpose]
          |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), term)))
        end)
    end
  end

  # Receipts by their date, requests by the day they were made.
  defp newest_first(receipts, []), do: receipts

  defp newest_first(receipts, requests) do
    Enum.sort_by(receipts ++ requests, &{sort_date(&1), &1.inserted_at}, :desc)
  end

  defp sort_date(%Receipt{date: date}), do: date
  defp sort_date(%Request{inserted_at: at}), do: NaiveDateTime.to_date(at)

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

  # KRA vouches for the receipt; say so if its total differs from ours.
  defp verified_message(receipt, %{amount_cents: cents})
       when is_integer(cents) and cents != receipt.amount_cents,
       do: "Verified with KRA — but KRA's total is #{Receipts.format_amount(cents)}"

  defp verified_message(_receipt, _details), do: "Verified with KRA"

  defp list_title(:all), do: "Receipts and requests"
  defp list_title(:requests), do: "Refunds and payments"
  defp list_title(group), do: Receipts.group_label(group)

  defp count_label(:requests, 1), do: "1 request"
  defp count_label(:requests, count), do: "#{count} requests"
  defp count_label(:all, 1), do: "1 item"
  defp count_label(:all, count), do: "#{count} items"
  defp count_label(_group, 1), do: "1 receipt"
  defp count_label(_group, count), do: "#{count} receipts"

  # "Ksh 1,205" without the currency, for the small split cells.
  defp bare_amount(cents),
    do: cents |> Receipts.format_short() |> String.replace_prefix("Ksh ", "")

  defp empty_text("", :all),
    do:
      "No receipts yet. Tap “Scan receipt” and take a photo of a receipt — the app reads the details and keeps the picture."

  defp empty_text("", :requests),
    do: "No requests yet. Tap + to request a payment, or open a receipt to ask for a refund."

  defp empty_text("", group),
    do: "No #{String.downcase(Receipts.group_label(group))} receipts yet."

  defp empty_text(_query, _group), do: "Nothing matches your search."
end
