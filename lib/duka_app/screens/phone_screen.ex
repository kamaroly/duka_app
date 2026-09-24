defmodule DukaApp.Screens.PhoneScreen do
  @moduledoc """
  First-launch screen: the phone number that owns this receipt book. Entering
  a number seen before reopens that person's receipts.
  """

  use Mob.Screen

  alias DukaApp.Accounts
  alias DukaApp.Components.FormField

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
    <Column padding={24} gap={16} background={:background} fill_height={true}>
      <Spacer size={32} />
      <Text text="eTIMS Receipts" text_size={:xxl} font_weight="bold" text_color={:primary} />
      <Text
        text="Scan KRA eTIMS receipts and keep them on your phone, even offline. Enter your phone number to open your receipt book."
        text_size={:base}
        text_color={:on_background}
      />
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
      <Button text="Continue" on_tap={{self(), :continue}} fill_width={true} padding={:xs} />
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
