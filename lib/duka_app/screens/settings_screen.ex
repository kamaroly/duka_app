defmodule DukaApp.Screens.SettingsScreen do
  @moduledoc """
  Profile and settings for the signed-in phone number: name, email, KRA PIN,
  app lock, and switching to another number.
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Appearance, Transactions}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Components.{ActionButton, FormField}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    profile = Accounts.current_profile()

    {:ok,
     socket
     |> Mob.Socket.assign(:profile, profile)
     |> Mob.Socket.assign(:summary, Transactions.summary(profile))
     |> Mob.Socket.assign(:name, profile.name || "")
     |> Mob.Socket.assign(:email, profile.email || "")
     |> Mob.Socket.assign(:kra_pin, profile.kra_pin || "")
     |> Mob.Socket.assign(:app_lock, profile.app_lock)
     |> Mob.Socket.assign(:appearance, Appearance.current())
     |> Mob.Socket.assign(:errors, %{})}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title="Settings" show_back={true} />
      <Scroll weight={1}>
        <Column padding_left={18} padding_right={18} padding_bottom={16} fill_width={true}>
          <Box
            background={:surface}
            border_color={:border}
            border_width={1}
            corner_radius={16}
            padding={14}
            fill_width={true}
          >
            <Column fill_width={true}>
              <Text text="Phone number" text_size={12} text_color={:muted} />
              <Text
                text={@profile.phone}
                text_size={18}
                font_weight="semibold"
                text_color={:on_surface}
              />
              <Text text={stats(@summary)} text_size={12} text_color={:muted} />
            </Column>
          </Box>
          <Spacer size={16} />
          {team_section(@profile)}
          <Spacer size={16} />
          <Text text="Appearance" text_size={13} font_weight="medium" text_color={:on_background} />
          <Spacer size={6} />
          <Row fill_width={true}>
            {Appearance.modes()
             |> Enum.map(&appearance_button(&1, @appearance))
             |> Enum.intersperse(~MOB(<Spacer size={8} />))}
          </Row>
          <Spacer size={4} />
          <Text text={appearance_hint(@appearance)} text_size={12} text_color={:muted} />
          <Spacer size={16} />
          {FormField.field(
            label: "Your name (optional)",
            key: :name,
            value: @name,
            placeholder: "e.g. Wanjiku Kamau",
            error: @errors[:name]
          )}
          {FormField.field(
            label: "Email (optional)",
            key: :email,
            value: @email,
            placeholder: "e.g. wanjiku@example.com",
            keyboard: :email,
            error: @errors[:email]
          )}
          {FormField.field(
            label: "Your KRA PIN (optional)",
            key: :kra_pin,
            value: @kra_pin,
            placeholder: "e.g. A123456789B",
            hint: "Letter, 9 digits, letter. Handy when filing returns.",
            error: @errors[:kra_pin]
          )}
          {toggle_row("Lock with fingerprint / face", @app_lock, :app_lock)}
          <Spacer size={12} />
          {ActionButton.button("check", "Save changes", :save)}
          <Spacer size={24} />
          {ActionButton.button("phone", "Switch phone number", :switch_phone, style: :secondary)}
          <Spacer size={6} />
          <Text
            text="Receipts stay on this phone under their number. Switching shows a different number's receipts; nothing is deleted."
            text_size={12}
            text_color={:muted}
          />
        </Column>
      </Scroll>
    </Column>
    """
  end

  # Connected: the team, what the person may approve, sync and disconnect.
  # Not connected: connect.
  defp team_section(profile) do
    ~MOB"""
    <Column fill_width={true}>
      <Text text="Team" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Box
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={16}
        padding={14}
        fill_width={true}
      >
        {team_status(profile)}
      </Box>
    </Column>
    """
  end

  defp team_status(%Profile{} = profile) do
    if Profile.connected?(profile) do
      ~MOB"""
      <Column fill_width={true}>
        <Text
          text={"Connected to #{profile.team}"}
          text_size={16}
          font_weight="semibold"
          text_color={:on_surface}
        />
        <Text text={abilities(profile)} text_size={12} text_color={:muted} />
        <Spacer size={10} />
        <Row fill_width={true}>
          {ActionButton.button("refresh", "Sync now", :sync_now, weight: 1)}
          <Spacer size={8} />
          {ActionButton.button("close", "Disconnect", :disconnect, style: :secondary, weight: 1)}
        </Row>
      </Column>
      """
    else
      ~MOB"""
      <Column fill_width={true}>
        <Text
          text="Not connected to a team"
          text_size={16}
          font_weight="semibold"
          text_color={:on_surface}
        />
        <Text
          text="Receipts stay on this phone. Connect with the number your manager added to send them for approval."
          text_size={12}
          text_color={:muted}
        />
        <Spacer size={10} />
        {ActionButton.button("forward", "Connect to a team", :connect)}
      </Column>
      """
    end
  end

  defp abilities(profile) do
    case Enum.filter(
           [
             {profile.can_approve, "approve transactions"},
             {profile.can_mark_paid, "mark refunds and payments paid"},
             {profile.can_list_all, "see the whole team's transactions"},
             {profile.can_export, "export them"}
           ],
           &elem(&1, 0)
         ) do
      [] -> "Your transactions go to your team for approval."
      can -> "You can " <> Enum.map_join(can, ", ", &elem(&1, 1)) <> "."
    end
  end

  # A labelled switch. The label is our own Text: Toggle's `text` prop is not
  # rendered on Android, which left the switches unlabelled.
  defp toggle_row(label, value, key) do
    ~MOB"""
    <Row
      fill_width={true}
      align={:center}
      background={:surface}
      border_color={:border}
      border_width={1}
      corner_radius={16}
      padding_left={16}
      padding_right={12}
      padding_top={8}
      padding_bottom={8}
    >
      <Text text={label} text_size={15} text_color={:on_surface} weight={1} />
      <Spacer size={12} />
      <Toggle value={value} on_change={{self(), key}} accessibility_label={label} />
    </Row>
    """
  end

  # A segmented control: one pill per mode, the chosen one filled.
  defp appearance_button(mode, selected) do
    {background, text_color} =
      if mode == selected, do: {:primary, :on_primary}, else: {:surface, :on_surface}

    ~MOB"""
    <Box
      weight={1}
      height={40}
      background={background}
      border_color={if(mode == selected, do: :primary, else: :border)}
      border_width={1}
      corner_radius={:radius_pill}
      align={:center}
      on_tap={{self(), {:appearance, mode}}}
      accessibility_label={"Appearance: #{Appearance.label(mode)}"}
      accessibility_role={:button}
    >
      <Text
        text={Appearance.label(mode)}
        text_size={14}
        font_weight="medium"
        text_color={text_color}
      />
    </Box>
    """
  end

  defp appearance_hint(:system), do: "Follows your phone's light or dark setting."
  defp appearance_hint(:light), do: "Always light."
  defp appearance_hint(:dark), do: "Always dark."

  @impl Mob.Screen
  def handle_info({:tap, {:appearance, mode}}, socket) do
    # Applies straight away: the new theme is visible on this screen's next
    # render, and the list remounts on the way back.
    :ok = Appearance.choose(mode)
    {:noreply, Mob.Socket.assign(socket, :appearance, mode)}
  end

  def handle_info({:change, toggle, value}, socket) when toggle in [:app_lock] do
    {:noreply, Mob.Socket.assign(socket, toggle, value in [true, "true"])}
  end

  def handle_info({:change, key, value}, socket) when key in [:name, :email, :kra_pin] do
    {:noreply,
     socket
     |> Mob.Socket.assign(key, value)
     |> Mob.Socket.assign(:errors, Map.delete(socket.assigns.errors, key))}
  end

  def handle_info({:tap, :save}, socket) do
    %{profile: profile, name: name, email: email, kra_pin: kra_pin, app_lock: app_lock} =
      socket.assigns

    attrs = %{
      name: name,
      email: email,
      kra_pin: kra_pin,
      app_lock: app_lock
    }

    case Accounts.update_settings(profile, attrs) do
      {:ok, profile} ->
        socket = DukaApp.Native.toast(socket, "Settings saved")
        {:noreply, Mob.Socket.assign(socket, profile: profile, errors: %{})}

      {:error, changeset} ->
        errors =
          Map.new(changeset.errors, fn {field, {message, _opts}} ->
            {field,
             "#{field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()} #{message}"}
          end)

        {:noreply, Mob.Socket.assign(socket, :errors, errors)}
    end
  end

  # ── Team (server) ──────────────────────────────────────────────────────────

  def handle_info({:tap, :connect}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, DukaApp.Screens.PhoneScreen, %{
       phone: socket.assigns.profile.phone
     })}
  end

  def handle_info({:tap, :sync_now}, socket) do
    {:noreply, socket |> DukaApp.Native.toast("Syncing…") |> DukaApp.Native.sync()}
  end

  def handle_info({:sync, {:ok, %{pushed: pushed, failed: failed}}}, socket) do
    message =
      case failed do
        0 -> "Up to date (#{pushed} sent)"
        _ -> "#{pushed} sent, #{failed} refused by the server"
      end

    profile = Accounts.get_profile!(socket.assigns.profile.id)
    {:noreply, socket |> Mob.Socket.assign(:profile, profile) |> DukaApp.Native.toast(message)}
  end

  def handle_info({:sync, {:error, error}}, socket),
    do: {:noreply, DukaApp.Native.toast(socket, DukaApp.Api.error_message(error))}

  def handle_info({:tap, :disconnect}, socket) do
    {:noreply,
     Mob.Alert.alert(socket,
       title: "Disconnect from the team?",
       message:
         "Receipts stay on this phone but stop going to your team until you connect again.",
       buttons: [
         [label: "Disconnect", style: :destructive, action: :confirm_disconnect],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :confirm_disconnect}, socket) do
    connected = socket.assigns.profile
    {:ok, profile} = Accounts.disconnect(connected)

    {:noreply,
     socket
     |> Mob.Socket.assign(:profile, profile)
     # Uses the sign-in token cleared above. Offline, the server keeps
     # pushing until this phone registers for someone else.
     |> DukaApp.Native.background(:push_forgotten, fn -> DukaApp.Push.forget(connected) end)
     |> DukaApp.Native.toast("Disconnected")}
  end

  def handle_info({:push_forgotten, _result}, socket), do: {:noreply, socket}

  def handle_info({:tap, :switch_phone}, socket) do
    {:noreply,
     Mob.Alert.alert(socket,
       title: "Switch phone number?",
       message: "Your receipts stay saved under #{socket.assigns.profile.phone}.",
       buttons: [
         [label: "Switch", action: :confirm_switch],
         [label: "Cancel", style: :cancel]
       ]
     )}
  end

  def handle_info({:alert, :confirm_switch}, socket) do
    {:ok, _} = Accounts.sign_out(socket.assigns.profile)
    {:noreply, Mob.Socket.reset_to(socket, DukaApp.Screens.PhoneScreen, %{}, scope: :all)}
  end

  def handle_info({:tap, :header_back}, socket) do
    # Reset rather than pop so the list picks up a changed name or lock setting.
    {:noreply, Mob.Socket.reset_to(socket, DukaApp.Screens.ReceiptsScreen, %{}, transition: :pop)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp stats(%{count: count, total: total}) do
    "#{count} transactions saved · #{Transactions.format_amount(total)} in total"
  end
end
