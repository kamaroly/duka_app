defmodule DukaApp.Screens.RequestsScreen do
  @moduledoc """
  The user's refund and payment requests with where each one stands, and
  the way to ask for a payment. A pending request can be withdrawn.
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Native, Receipts, Requests}
  alias DukaApp.Components.{ActionButton, Header, KraBadge}
  alias DukaApp.Screens.RequestFormScreen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    socket =
      socket
      |> Mob.Socket.assign(:profile, Accounts.current_profile())
      |> Mob.Socket.assign(:selected, nil)
      |> load()
      |> Mob.List.put_renderer(:requests, &request_row/1)

    {:ok, socket}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title="Requests" subtitle="Refunds and payments for approval" show_back={true} />
      <Column fill_width={true} padding_left={18} padding_right={18}>
        {pending_card(@pending)}
        <Spacer size={14} />
      </Column>
      <Text
        :if={@requests == []}
        text="No requests yet. Ask for a refund from a saved receipt, or tap “Request payment” below."
        text_size={14}
        text_color={:muted}
        padding_left={22}
        padding_right={22}
        padding_top={8}
      />
      <List
        :if={@requests != []}
        id={:requests}
        items={@requests}
        weight={1}
        padding_left={18}
        padding_right={18}
      />
      <Spacer :if={@requests == []} weight={1} />
      <Column
        fill_width={true}
        padding_left={18}
        padding_right={18}
        padding_top={8}
        padding_bottom={18}
      >
        {ActionButton.button("payments", "Request payment", :new_payment)}
      </Column>
      {detail_sheet(@selected)}
    </Column>
    """
  end

  defp pending_card(pending) do
    ~MOB"""
    <Box
      background={:surface}
      border_color={:border}
      border_width={1}
      corner_radius={20}
      padding={16}
      fill_width={true}
    >
      <Row fill_width={true} align={:center}>
        <Column weight={1}>
          <Text text="Waiting for approval" text_size={13} text_color={:muted} />
          <Text
            text={Receipts.format_short(pending.total)}
            text_size={26}
            font_weight="bold"
            letter_spacing={-1}
            text_color={:on_surface}
          />
        </Column>
        <Text
          text={count_label(pending.count)}
          text_size={13}
          font_weight="semibold"
          text_color={:muted}
        />
      </Row>
    </Box>
    """
  end

  @doc false
  # One card in the list: what the request is, where the money goes, the
  # amount and its status.
  def request_row(request) do
    ~MOB"""
    <Column fill_width={true} padding_bottom={10}>
      <Box
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={20}
        padding={12}
        fill_width={true}
      >
        <Row fill_width={true} align={:center}>
          <Box width={46} height={46} corner_radius={14} background={:surface_raised} align={:center}>
            <Icon name={kind_icon(request)} text_size={20} text_color={:on_surface} />
          </Box>
          <Spacer size={12} />
          <Column weight={1}>
            <Text
              text={headline(request)}
              text_size={15}
              font_weight="semibold"
              letter_spacing={-0.3}
              text_color={:on_surface}
              max_lines={1}
            />
            <Spacer size={2} />
            <Text text={Requests.pay_to(request)} text_size={12} text_color={:muted} max_lines={1} />
          </Column>
          <Spacer size={12} />
          <Column>
            <Text
              text={Receipts.format_short(request.amount_cents)}
              text_size={15}
              font_weight="bold"
              letter_spacing={-0.4}
              text_color={:on_surface}
            />
            <Spacer size={4} />
            {status_pill(request.status)}
          </Column>
        </Row>
      </Box>
    </Column>
    """
  end

  defp status_pill(status) do
    {background, text_color} = status_colors(status)

    ~MOB"""
    <Row
      background={background}
      corner_radius={:radius_pill}
      padding_left={8}
      padding_right={8}
      padding_top={2}
      padding_bottom={2}
    >
      <Text
        text={short_status(status)}
        text_size={11}
        font_weight="semibold"
        text_color={text_color}
      />
    </Row>
    """
  end

  defp detail_sheet(nil), do: []

  defp detail_sheet(request) do
    ~MOB"""
    <Sheet
      id={"request-#{request.id}"}
      detents={[:content]}
      background={:background}
      corner_radius={28}
      on_dismiss={{self(), :close_request}}
    >
      <Column fill_width={true} padding={20}>
        <Row fill_width={true} align={:top}>
          <Column weight={1}>
            <Text
              text={headline(request)}
              text_size={20}
              font_weight="bold"
              letter_spacing={-0.5}
              text_color={:on_background}
              max_lines={2}
            />
            <Spacer size={6} />
            <Row>
              {status_pill(request.status)}
            </Row>
          </Column>
          <Spacer size={12} />
          {Header.icon_button("close", "Close", {self(), :close_request})}
        </Row>
        <Spacer size={14} />
        <Box
          background={:surface}
          border_color={:border}
          border_width={1}
          corner_radius={16}
          padding={14}
          fill_width={true}
        >
          <Column fill_width={true}>
            <Text text="Amount" text_size={12} text_color={:muted} />
            <Text
              text={Receipts.format_amount(request.amount_cents)}
              text_size={22}
              font_weight="bold"
              text_color={:on_surface}
            />
          </Column>
        </Box>
        {detail_row("Pay with", Requests.method_label(request.method))}
        {detail_row("Pay to", Requests.pay_to(request))}
        {receipt_row(request)}
        {detail_row(purpose_label(request), request.purpose)}
        {detail_row("Requested", Calendar.strftime(request.inserted_at, "%d %b %Y, %H:%M"))}
        {detail_row("Manager's note", request.decision_note)}
        <Spacer size={16} />
        {if request.status == "pending",
          do: ActionButton.button("trash", "Withdraw request", :cancel_request, style: :secondary)}
      </Column>
    </Sheet>
    """
  end

  defp receipt_row(%{receipt: %Receipts.Receipt{} = receipt}) do
    ~MOB"""
    <Column fill_width={true} padding_top={10}>
      <Text text="Receipt" text_size={12} text_color={:muted} />
      <Row fill_width={true} align={:center}>
        {KraBadge.badge(receipt)}
        <Text
          text={"#{receipt.vendor} · #{Calendar.strftime(receipt.date, "%d %b %Y")}"}
          text_size={14}
          text_color={:on_background}
          weight={1}
          max_lines={1}
        />
      </Row>
    </Column>
    """
  end

  defp receipt_row(_request), do: []

  defp detail_row(_label, value) when value in [nil, ""], do: []

  defp detail_row(label, value) do
    ~MOB"""
    <Column fill_width={true} padding_top={10}>
      <Text text={label} text_size={12} text_color={:muted} />
      <Text text={value} text_size={14} text_color={:on_background} max_lines={3} />
    </Column>
    """
  end

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:tap, :new_payment}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, RequestFormScreen, %{notify: self()})}
  end

  def handle_info({:request_saved, _request}, socket), do: {:noreply, load(socket)}

  def handle_info({:select, :requests, index}, socket), do: select(socket, index)
  def handle_info({:tap, {:list, :requests, :select, index}}, socket), do: select(socket, index)

  def handle_info({event, :close_request}, socket) when event in [:tap, :dismiss] do
    {:noreply, Mob.Socket.assign(socket, :selected, nil)}
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
    case socket.assigns.selected && Requests.cancel_request(socket.assigns.selected) do
      {:ok, _} ->
        {:noreply,
         socket
         |> Native.toast("Request withdrawn")
         |> Mob.Socket.assign(:selected, nil)
         |> load()}

      {:error, :not_pending} ->
        {:noreply,
         Native.toast(socket, "Only a request still waiting for approval can be withdrawn")}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_info({:tap, :header_back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp select(socket, index) do
    {:noreply, Mob.Socket.assign(socket, :selected, Enum.at(socket.assigns.requests, index))}
  end

  defp load(socket) do
    profile = socket.assigns.profile

    socket
    |> Mob.Socket.assign(:requests, Requests.list_requests(profile))
    |> Mob.Socket.assign(:pending, Requests.pending_summary(profile))
  end

  # ── Labels ──────────────────────────────────────────────────────────────────

  defp headline(%{kind: "refund", receipt: %Receipts.Receipt{vendor: vendor}}),
    do: "Refund · #{vendor}"

  defp headline(%{kind: "refund"}), do: "Refund"

  defp headline(%{kind: "payment", purpose: purpose}) when is_binary(purpose),
    do: purpose

  defp headline(%{kind: "payment"}), do: "Payment"

  defp purpose_label(%{kind: "refund"}), do: "Note"
  defp purpose_label(_request), do: "For"

  defp kind_icon(%{kind: "refund"}), do: "refund"
  defp kind_icon(%{method: "send_money"}), do: "phone"
  defp kind_icon(_request), do: "store"

  defp short_status("pending"), do: "Pending"
  defp short_status(status), do: Requests.status_label(status)

  # Pending waits in amber; approved and paid are the accent green.
  defp status_colors("pending"), do: {0x33F59E0B, :on_surface}
  defp status_colors("rejected"), do: {:error, :on_error}
  defp status_colors(_approved_or_paid), do: {:secondary, :on_secondary}

  defp count_label(1), do: "1 request"
  defp count_label(count), do: "#{count} requests"
end
