defmodule DukaApp.Screens.RequestFormScreen do
  @moduledoc """
  Ask for a refund of a saved receipt, or for a payment to be made.

  Mount params:

    * `%{receipt_id: id}` — refund that receipt. The amount is its total and
      the money goes by M-Pesa to a phone number (the user's own by default).
    * `%{}` — request a payment: amount, what it's for, and how to pay —
      send money to a phone, a Buy Goods till, or a paybill and account.
    * `notify: pid` (either) — the screen that opened the form; it gets
      `{:request_saved, request}` after a save, since the screen popped back
      to is restored as it was rather than mounted again.

  Saved requests wait for a manager's approval (see `DukaApp.Requests`).
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Native, Receipts, Requests}
  alias DukaApp.Components.{ActionButton, FormField, KraBadge}
  alias DukaApp.Requests.Request

  @fields [:amount, :purpose, :phone, :till_number, :paybill_number, :account_number, :payee_name]

  @impl Mob.Screen
  def mount(params, _session, socket) do
    profile = Accounts.current_profile()

    draft =
      case params do
        %{receipt_id: id} -> Requests.new_refund(profile, Receipts.get_receipt!(profile, id))
        _ -> Requests.new_payment()
      end

    socket =
      socket
      |> Mob.Socket.assign(:profile, profile)
      |> Mob.Socket.assign(:draft, draft)
      |> Mob.Socket.assign(:notify, params[:notify])
      |> Mob.Socket.assign(:method, draft.method)
      |> Mob.Socket.assign(:amount, Receipts.amount_input(draft.amount_cents))
      |> Mob.Socket.assign(:purpose, "")
      |> Mob.Socket.assign(:phone, Requests.local_phone(draft.phone))
      |> Mob.Socket.assign(:till_number, "")
      |> Mob.Socket.assign(:paybill_number, "")
      |> Mob.Socket.assign(:account_number, "")
      |> Mob.Socket.assign(:payee_name, "")
      |> Mob.Socket.assign(:errors, %{})

    {:ok, socket}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title={title(@draft)} show_back={true} />
      <Scroll weight={1}>
        <Column padding_left={18} padding_right={18} padding_bottom={16} fill_width={true}>
          {intro(assigns)}
          <Spacer size={16} />
          {pay_to(assigns)}
          <Text :if={@errors[:base]} text={@errors[:base]} text_size={13} text_color={:error} />
        </Column>
      </Scroll>
      <Column
        fill_width={true}
        padding_left={18}
        padding_right={18}
        padding_top={8}
        padding_bottom={16}
      >
        <Text
          text="Your manager will review it. You'll see the answer under Requests."
          text_size={12}
          text_color={:muted}
          padding_bottom={8}
        />
        {ActionButton.button("send", "Send request", :submit)}
      </Column>
    </Column>
    """
  end

  # A refund shows the receipt; a payment asks what and how much.
  defp intro(%{draft: %Request{kind: "refund", receipt: receipt}} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      <Box
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={16}
        padding={14}
        fill_width={true}
      >
        <Column fill_width={true}>
          <Text text="Refund for" text_size={12} text_color={:muted} />
          <Text
            text={receipt.vendor}
            text_size={17}
            font_weight="semibold"
            text_color={:on_surface}
            max_lines={1}
          />
          <Spacer size={4} />
          <Row fill_width={true} align={:center}>
            {KraBadge.badge(receipt)}
            <Text
              text={Calendar.strftime(receipt.date, "%d %b %Y") <> " · " <> receipt.category}
              text_size={12}
              text_color={:muted}
              weight={1}
              max_lines={1}
            />
          </Row>
          <Spacer size={10} />
          <Text
            text={Receipts.format_amount(receipt.amount_cents)}
            text_size={24}
            font_weight="bold"
            letter_spacing={-0.8}
            text_color={:on_surface}
          />
        </Column>
      </Box>
      <Spacer size={16} />
      {FormField.field(
        label: "Note for your manager (optional)",
        key: :purpose,
        value: @purpose,
        placeholder: "e.g. Paid for client lunch with my own money",
        error: @errors[:purpose]
      )}
    </Column>
    """
  end

  defp intro(assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Amount (Ksh)",
        key: :amount,
        value: @amount,
        placeholder: "e.g. 2,500",
        keyboard: :decimal,
        error: @errors[:amount]
      )}
      {FormField.field(
        label: "What is it for?",
        key: :purpose,
        value: @purpose,
        placeholder: "e.g. Fuel for the delivery van",
        error: @errors[:purpose]
      )}
    </Column>
    """
  end

  # Refunds go to a phone; a payment picks send money, till or paybill.
  defp pay_to(%{draft: %Request{kind: "refund"}} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "M-Pesa number for the refund",
        key: :phone,
        value: @phone,
        placeholder: "e.g. 0712 345 678",
        keyboard: :phone,
        hint: "Your own number unless you change it.",
        error: @errors[:phone]
      )}
    </Column>
    """
  end

  defp pay_to(assigns) do
    ~MOB"""
    <Column fill_width={true}>
      <Text text="Pay with" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Row fill_width={true}>
        {Request.methods()
         |> Enum.map(&method_pill(&1, @method))
         |> Enum.intersperse(~MOB(<Spacer size={8} />))}
      </Row>
      <Spacer size={16} />
      {method_fields(assigns)}
    </Column>
    """
  end

  defp method_pill(method, selected) do
    {background, text_color, border} =
      if method == selected,
        do: {:primary, :on_primary, :primary},
        else: {:surface, :on_surface, :border}

    ~MOB"""
    <Box
      weight={1}
      height={40}
      background={background}
      border_color={border}
      border_width={1}
      corner_radius={:radius_pill}
      align={:center}
      on_tap={{self(), {:method, method}}}
      accessibility_label={"Pay with #{Requests.method_label(method)}"}
      accessibility_role={:button}
    >
      <Text text={pill_label(method)} text_size={13} font_weight="medium" text_color={text_color} />
    </Box>
    """
  end

  defp method_fields(%{method: "send_money"} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Phone number to send to",
        key: :phone,
        value: @phone,
        placeholder: "e.g. 0712 345 678",
        keyboard: :phone,
        error: @errors[:phone]
      )}
      {FormField.field(
        label: "Recipient's name (optional)",
        key: :payee_name,
        value: @payee_name,
        placeholder: "e.g. John Otieno",
        error: @errors[:payee_name]
      )}
    </Column>
    """
  end

  defp method_fields(%{method: "till"} = assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Till number",
        key: :till_number,
        value: @till_number,
        placeholder: "e.g. 832909",
        keyboard: :number,
        error: @errors[:till_number]
      )}
      {FormField.field(
        label: "Business name (optional)",
        key: :payee_name,
        value: @payee_name,
        placeholder: "e.g. Naivas Westlands",
        error: @errors[:payee_name]
      )}
    </Column>
    """
  end

  defp method_fields(assigns) do
    ~MOB"""
    <Column fill_width={true}>
      {FormField.field(
        label: "Paybill (business) number",
        key: :paybill_number,
        value: @paybill_number,
        placeholder: "e.g. 888880",
        keyboard: :number,
        error: @errors[:paybill_number]
      )}
      {FormField.field(
        label: "Account number",
        key: :account_number,
        value: @account_number,
        placeholder: "e.g. 1234567",
        error: @errors[:account_number]
      )}
      {FormField.field(
        label: "Business name (optional)",
        key: :payee_name,
        value: @payee_name,
        placeholder: "e.g. Kenya Power",
        error: @errors[:payee_name]
      )}
    </Column>
    """
  end

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:change, key, value}, socket) when key in @fields do
    {:noreply,
     socket
     |> Mob.Socket.assign(key, value)
     |> Mob.Socket.assign(:errors, Map.delete(socket.assigns.errors, key))}
  end

  def handle_info({:tap, {:method, method}}, socket) do
    {:noreply, Mob.Socket.assign(socket, method: method, errors: %{})}
  end

  def handle_info({:tap, :submit}, socket) do
    %{profile: profile, draft: draft} = socket.assigns

    with {:ok, attrs} <- build_attrs(socket.assigns),
         {:ok, request} <- Requests.create_request(profile, draft, attrs) do
      if pid = socket.assigns.notify, do: send(pid, {:request_saved, request})

      {:noreply,
       socket
       |> Native.success()
       |> Native.toast("Request sent for approval")
       |> Mob.Socket.pop_screen()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, Mob.Socket.assign(socket, :errors, changeset_errors(changeset))}

      {:error, errors} ->
        {:noreply, Mob.Socket.assign(socket, :errors, errors)}
    end
  end

  def handle_info({:tap, :header_back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @doc false
  # The form's inputs as changeset attrs. A payment's amount needs parsing
  # first; a refund's comes from its receipt. Only the chosen method's
  # fields are sent, so switching method doesn't leave stale ones behind.
  def build_attrs(assigns) do
    %{draft: draft, method: method} = assigns

    amount =
      case draft.kind do
        "refund" -> {:ok, draft.amount_cents}
        "payment" -> Receipts.parse_amount(assigns.amount)
      end

    case amount do
      {:ok, cents} ->
        method_attrs =
          case method do
            "send_money" -> Map.take(assigns, [:phone, :payee_name])
            "till" -> Map.take(assigns, [:till_number, :payee_name])
            "paybill" -> Map.take(assigns, [:paybill_number, :account_number, :payee_name])
          end

        {:ok,
         Map.merge(method_attrs, %{
           kind: draft.kind,
           receipt_id: draft.receipt_id,
           amount_cents: cents,
           purpose: assigns.purpose,
           method: method
         })}

      :error ->
        {:error, %{amount: "enter an amount like 2500 or 2,500.50"}}
    end
  end

  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Map.new(fn
      {:amount_cents, [message | _]} -> {:amount, "Amount #{message}"}
      {:base, [message | _]} -> {:base, String.capitalize(message)}
      {field, [message | _]} -> {field, message_for(field, message)}
    end)
  end

  # "enter the till number" reads fine alone; "is 5 to 7 digits" needs its
  # field in front.
  defp message_for(field, "is " <> _ = message), do: "#{humanize(field)} #{message}"
  defp message_for(_field, message), do: String.capitalize(message)

  defp humanize(field),
    do: field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp title(%Request{kind: "refund"}), do: "Request refund"
  defp title(_draft), do: "Request payment"

  defp pill_label("send_money"), do: "Send money"
  defp pill_label("till"), do: "Till"
  defp pill_label("paybill"), do: "Paybill"
end
