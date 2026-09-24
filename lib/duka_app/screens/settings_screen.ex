defmodule DukaApp.Screens.SettingsScreen do
  @moduledoc """
  Profile and settings for the signed-in phone number: name, email, KRA PIN,
  app lock, and switching to another number.
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Appearance, Receipts}
  alias DukaApp.Components.{ActionButton, FormField}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    profile = Accounts.current_profile()

    {:ok,
     socket
     |> Mob.Socket.assign(:profile, profile)
     |> Mob.Socket.assign(:summary, Receipts.summary(profile))
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
          <Toggle
            text="Lock with fingerprint / face"
            value={@app_lock}
            on_change={{self(), :app_lock}}
          />
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

  def handle_info({:change, :app_lock, value}, socket) do
    {:noreply, Mob.Socket.assign(socket, :app_lock, value in [true, "true"])}
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

    attrs = %{name: name, email: email, kra_pin: kra_pin, app_lock: app_lock}

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
    "#{count} receipts saved · #{Receipts.format_amount(total)} in total"
  end
end
