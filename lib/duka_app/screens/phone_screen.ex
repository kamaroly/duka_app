defmodule DukaApp.Screens.PhoneScreen do
  @moduledoc """
  First-launch screen: the phone number that owns this receipt book. Entering
  a number seen before reopens that person's receipts.
  """

  use Mob.Screen

  alias DukaApp.Accounts
  alias DukaApp.Components.{ActionButton, FormField}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(:phone, "")
     |> Mob.Socket.assign(:error, nil)}
  end

  @impl Mob.Screen
  def render(assigns) do
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
        text="Scan KRA eTIMS receipts and keep them on your phone, even offline. Enter your phone number to open your receipt book."
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
        hint: "Your Safaricom, Airtel or Telkom number.",
        error: @error,
        submit: :continue
      )}
      <Spacer size={4} />
      {ActionButton.button("forward", "Continue", :continue)}
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:change, :phone, value}, socket) do
    {:noreply, Mob.Socket.assign(socket, phone: value, error: nil)}
  end

  def handle_info({tag, :continue}, socket) when tag in [:tap, :submit] do
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
