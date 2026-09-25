defmodule DukaApp.Screens.PhoneScreen do
  @moduledoc """
  Sign-in: the phone number that owns this receipt book.

  With a team: the server texts a 6-digit code to the number (it must have
  been added to the team by a manager); entering it connects the receipt
  book, and its receipts and requests go to the team for approval.

  Without one: "Use without a team" opens a receipt book that stays on the
  phone. It can be connected later from Settings.

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
     # :phone (ask the number) → :code (ask the code the server texted)
     |> Mob.Socket.assign(:step, :phone)
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
        text="Scan KRA receipts, keep them on your phone and send them to your team for approval. We'll text you a code to sign in."
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
        hint: "The number your manager added to the team.",
        error: @error,
        submit: :send_code
      )}
      <Spacer size={4} />
      {ActionButton.button("send", if(@busy, do: "Sending code…", else: "Send code"), :send_code,
        enabled: not @busy
      )}
      <Spacer size={12} />
      {ActionButton.button("forward", "Use without a team", :offline, style: :secondary)}
      <Spacer size={6} />
      <Text
        text="Receipts stay on this phone. You can connect to a team later in Settings."
        text_size={12}
        text_color={:muted}
      />
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

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:change, field, value}, socket) when field in [:phone, :code] do
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

  def handle_info({:verified, {:ok, body}}, socket) do
    case Accounts.connect(socket.assigns.phone, body) do
      {:ok, _profile} ->
        {:noreply, Mob.Socket.reset_to(socket, DukaApp.Screens.ReceiptsScreen)}

      {:error, _changeset} ->
        {:noreply,
         Mob.Socket.assign(socket, busy: false, error: "Couldn't save the sign-in. Try again.")}
    end
  end

  def handle_info({:verified, {:error, error}}, socket) do
    {:noreply, Mob.Socket.assign(socket, busy: false, error: Api.error_message(error))}
  end

  def handle_info({:tap, :change_number}, socket) do
    {:noreply, Mob.Socket.assign(socket, step: :phone, code: "", error: nil)}
  end

  def handle_info({:tap, :offline}, socket) do
    case Accounts.sign_in(socket.assigns.phone) do
      {:ok, _profile} ->
        {:noreply, Mob.Socket.reset_to(socket, DukaApp.Screens.ReceiptsScreen)}

      {:error, _changeset} ->
        {:noreply,
         Mob.Socket.assign(socket, :error, "Enter a Kenyan mobile number, e.g. 0712 345 678.")}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
