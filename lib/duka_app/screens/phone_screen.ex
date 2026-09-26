defmodule DukaApp.Screens.PhoneScreen do
  @moduledoc """
  Sign-in and sign-up: the phone number that owns this expense book.

  The server texts a 6-digit code to the number; entering it connects the
  book. A number the server already knows (added by a manager, or signed up
  before) goes straight in. A new one is asked for a name and whether it's
  "Just me" — a free personal book — or a business, which they then own
  and can add people to.

  Mount params: `%{phone: number}` fills the number in (e.g. from Settings).
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Api, Native}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Components.{ActionButton, FormField}

  @impl Mob.Screen
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(:phone, Map.get(params, :phone, ""))
     |> Mob.Socket.assign(:code, "")
     # :phone (ask the number) → :code (ask the code the server texted) →
     # :register (a new number: name, and just me or a business)
     |> Mob.Socket.assign(:step, :phone)
     |> Mob.Socket.assign(:signup_token, nil)
     |> Mob.Socket.assign(:name, "")
     |> Mob.Socket.assign(:business?, false)
     |> Mob.Socket.assign(:team_name, "")
     |> Mob.Socket.assign(:busy, false)
     |> Mob.Socket.assign(:error, nil)}
  end

  @impl Mob.Screen
  def render(%{step: :phone} = assigns) do
    ~MOB"""
    <Column padding_left={22} padding_right={22} background={:background} fill_height={true}>
      <Spacer size={56} />
      <Text
        text="eTIMS Receipts"
        text_size={26}
        font_weight="bold"
        letter_spacing={-1}
        text_color={:on_background}
      />
      <Spacer size={8} />
      <Text
        text="Scan KRA receipts and keep track of what you spend, alone or with your team. We'll text you a code to sign in or sign up."
        text_size={15}
        text_color={:muted}
      />
      <Spacer size={24} />
      {FormField.field(
        label: "Phone number",
        key: :phone,
        value: @phone,
        placeholder: "e.g. 0712 345 678",
        keyboard: :phone,
        hint: "Your own number, or the one your manager added to the team.",
        error: @error,
        submit: :send_code
      )}
      <Spacer size={4} />
      {ActionButton.button("send", if(@busy, do: "Sending code…", else: "Send code"), :send_code,
        enabled: not @busy
      )}
    </Column>
    """
  end

  def render(%{step: :register} = assigns) do
    ~MOB"""
    <Column padding_left={22} padding_right={22} background={:background} fill_height={true}>
      <Spacer size={56} />
      <Text
        text="Welcome to Risiti"
        text_size={26}
        font_weight="bold"
        letter_spacing={-1}
        text_color={:on_background}
      />
      <Spacer size={8} />
      <Text text="A couple of things and you're in." text_size={15} text_color={:muted} />
      <Spacer size={24} />
      {FormField.field(
        label: "Your name",
        key: :name,
        value: @name,
        placeholder: "e.g. Achieng Otieno",
        error: @error
      )}
      <Text text="Who's it for?" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Row fill_width={true}>
        {choice("Just me", "Free", :just_me, not @business?)}
        <Spacer size={8} />
        {choice("My business", "Free trial", :business, @business?)}
      </Row>
      <Spacer size={16} />
      {if @business?,
        do:
          FormField.field(
            label: "Business name",
            key: :team_name,
            value: @team_name,
            placeholder: "e.g. Achieng Traders"
          )}
      {ActionButton.button("check", if(@busy, do: "Setting up…", else: "Start"), :register,
        enabled: not @busy
      )}
    </Column>
    """
  end

  def render(assigns) do
    ~MOB"""
    <Column padding_left={22} padding_right={22} background={:background} fill_height={true}>
      <Spacer size={56} />
      <Text
        text="Enter the code"
        text_size={26}
        font_weight="bold"
        letter_spacing={-1}
        text_color={:on_background}
      />
      <Spacer size={8} />
      <Text text={"We texted a 6-digit code to #{@phone}."} text_size={15} text_color={:muted} />
      <Spacer size={24} />
      {FormField.field(
        label: "Code",
        key: :code,
        value: @code,
        placeholder: "e.g. 482913",
        keyboard: :number,
        error: @error,
        submit: :verify
      )}
      <Spacer size={4} />
      {ActionButton.button("check", if(@busy, do: "Checking…", else: "Sign in"), :verify,
        enabled: not @busy
      )}
      <Spacer size={12} />
      <Row fill_width={true}>
        {ActionButton.button("back", "Change number", :change_number, style: :secondary, weight: 1)}
        <Spacer size={8} />
        {ActionButton.button("refresh", "Resend", :send_code, style: :secondary, weight: 1)}
      </Row>
    </Column>
    """
  end

  defp choice(title, subtitle, tag, selected?) do
    {background, text_color, border} =
      if selected?,
        do: {:primary, :on_primary, :primary},
        else: {:surface, :on_surface, :border}

    ~MOB"""
    <Box
      weight={1}
      background={background}
      border_color={border}
      border_width={1}
      corner_radius={16}
      padding={14}
      on_tap={{self(), {:for, tag}}}
      accessibility_label={title}
      accessibility_role={:button}
    >
      <Column>
        <Text text={title} text_size={15} font_weight="semibold" text_color={text_color} />
        <Text text={subtitle} text_size={12} text_color={text_color} />
      </Column>
    </Box>
    """
  end

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:change, field, value}, socket)
      when field in [:phone, :code, :name, :team_name] do
    {:noreply, Mob.Socket.assign(socket, [{field, value}, {:error, nil}])}
  end

  def handle_info({event, :send_code}, %{assigns: %{busy: false}} = socket)
      when event in [:tap, :submit] do
    case Profile.normalize(socket.assigns.phone) do
      {:ok, phone} ->
        {:noreply,
         socket
         |> Mob.Socket.assign(phone: phone, busy: true, error: nil)
         |> Native.background(:code_sent, fn -> Api.request_code(phone) end)}

      :error ->
        {:noreply,
         Mob.Socket.assign(socket, :error, "Enter a Kenyan mobile number, e.g. 0712 345 678.")}
    end
  end

  def handle_info({:code_sent, {:ok, _}}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(step: :code, busy: false, code: "", error: nil)
     |> Native.toast("Code sent")}
  end

  def handle_info({:code_sent, {:error, error}}, socket) do
    {:noreply, Mob.Socket.assign(socket, busy: false, error: Api.error_message(error))}
  end

  def handle_info({event, :verify}, %{assigns: %{busy: false}} = socket)
      when event in [:tap, :submit] do
    %{phone: phone, code: code} = socket.assigns

    {:noreply,
     socket
     |> Mob.Socket.assign(busy: true, error: nil)
     |> Native.background(:verified, fn -> Api.verify(phone, String.trim(code)) end)}
  end

  # A new number: ask who they are before signing them up.
  def handle_info(
        {:verified, {:ok, %{"needs_registration" => true, "signup_token" => token}}},
        socket
      ) do
    {:noreply,
     Mob.Socket.assign(socket, step: :register, signup_token: token, busy: false, error: nil)}
  end

  def handle_info({result, {:ok, body}}, socket) when result in [:verified, :registered] do
    case Accounts.connect(socket.assigns.phone, body) do
      {:ok, _profile} ->
        {:noreply, Mob.Socket.reset_to(socket, DukaApp.Screens.ReceiptsScreen)}

      {:error, _changeset} ->
        {:noreply,
         Mob.Socket.assign(socket, busy: false, error: "Couldn't save the sign-in. Try again.")}
    end
  end

  def handle_info({result, {:error, error}}, socket) when result in [:verified, :registered] do
    {:noreply, Mob.Socket.assign(socket, busy: false, error: Api.error_message(error))}
  end

  def handle_info({:tap, {:for, choice}}, socket) do
    {:noreply, Mob.Socket.assign(socket, :business?, choice == :business)}
  end

  def handle_info({event, :register}, %{assigns: %{busy: false}} = socket)
      when event in [:tap, :submit] do
    %{signup_token: token, name: name, business?: business?, team_name: team_name} =
      socket.assigns

    cond do
      String.trim(name) == "" ->
        {:noreply, Mob.Socket.assign(socket, :error, "Tell us your name")}

      business? and String.trim(team_name) == "" ->
        {:noreply, Mob.Socket.assign(socket, :error, "Give your business a name")}

      true ->
        team_name = if business?, do: String.trim(team_name), else: ""

        {:noreply,
         socket
         |> Mob.Socket.assign(busy: true, error: nil)
         |> Native.background(:registered, fn ->
           Api.register(token, String.trim(name), team_name)
         end)}
    end
  end

  def handle_info({:tap, :change_number}, socket) do
    {:noreply, Mob.Socket.assign(socket, step: :phone, code: "", error: nil)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
