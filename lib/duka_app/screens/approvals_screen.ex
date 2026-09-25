defmodule DukaApp.Screens.ApprovalsScreen do
  @moduledoc """
  The manager's inbox: receipts to approve as expenses, and refund and
  payment requests to approve, reject or mark paid.

  Two cards at the top say what's waiting and switch between the lists.
  Tapping an item opens its details with the decision buttons; rejecting
  needs a note so the person knows what to fix. Approved requests stay
  listed until they're marked paid.

  Everything comes from the team's server (`DukaApp.Api`), in the
  background; the decisions go straight back to it. Receipt photos and
  attachments download when opened.
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Api, DataDir, Native, Receipts, Remote, Requests}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Components.{ActionButton, FormField, Header, KraBadge, ReceiptItem, RequestItem}
  alias DukaApp.Receipts.Receipt
  alias DukaApp.Requests.{Attachment, Request}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    profile = Accounts.current_profile()

    socket =
      socket
      |> Mob.Socket.assign(:profile, profile)
      |> Mob.Socket.assign(:tab, if(profile.can_approve_receipts, do: :receipts, else: :requests))
      |> Mob.Socket.assign(:receipts, [])
      |> Mob.Socket.assign(:requests, [])
      |> Mob.Socket.assign(:items, [])
      |> Mob.Socket.assign(:summary, %{
        receipts: %{count: 0, total: 0},
        requests: %{count: 0, total: 0}
      })
      |> Mob.Socket.assign(:loading, true)
      |> Mob.Socket.assign(:busy, false)
      |> Mob.Socket.assign(:selected, nil)
      |> Mob.Socket.assign(:note, "")
      |> Mob.Socket.assign(:note_error, nil)
      |> Mob.List.put_renderer(:approvals, &item/1)
      |> load()

    {:ok, socket}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title="Approvals" subtitle="Expenses and requests from your team" show_back={true} />
      <Row fill_width={true} padding_left={18} padding_right={18}>
        {tab_card(:receipts, "Receipts", @summary.receipts, @tab)}
        <Spacer size={10} />
        {tab_card(:requests, "Requests", @summary.requests, @tab)}
      </Row>
      <Spacer size={14} />
      <Text
        :if={@items == []}
        text={if(@loading, do: "Loading…", else: empty_text(@tab))}
        text_size={14}
        text_color={:muted}
        padding_left={22}
        padding_right={22}
        padding_top={8}
      />
      <List
        :if={@items != []}
        id={:approvals}
        items={@items}
        weight={1}
        padding_left={18}
        padding_right={18}
      />
      <Spacer :if={@items == []} weight={1} />
      {decision_sheet(assigns)}
    </Column>
    """
  end

  # What's waiting, and the switch between the two lists.
  defp tab_card(tab, label, %{count: count, total: total}, active) do
    border = if tab == active, do: :on_background, else: :border

    ~MOB"""
    <Box
      weight={1}
      background={:surface}
      border_color={border}
      border_width={if(tab == active, do: 2, else: 1)}
      corner_radius={18}
      padding={14}
      on_tap={{self(), {:tab, tab}}}
      accessibility_label={"#{label}: #{count} waiting"}
      accessibility_role={:button}
    >
      <Column fill_width={true}>
        <Text text={label} text_size={13} font_weight="semibold" text_color={:muted} />
        <Spacer size={2} />
        <Text
          text={"#{count} waiting"}
          text_size={20}
          font_weight="bold"
          letter_spacing={-0.6}
          text_color={:on_surface}
        />
        <Text text={Receipts.format_short(total)} text_size={12} text_color={:muted} />
      </Column>
    </Box>
    """
  end

  # List items: section headings, then receipts or requests with who sent them.
  defp item({:heading, text}) do
    ~MOB"""
    <Text
      text={text}
      text_size={13}
      font_weight="semibold"
      text_color={:muted}
      padding_left={4}
      padding_top={6}
      padding_bottom={8}
    />
    """
  end

  defp item(%Receipt{} = receipt) do
    ~MOB"""
    <Column fill_width={true}>
      {from_line(receipt.profile)}
      {ReceiptItem.expand(%{receipt: receipt}, [], %{})}
    </Column>
    """
  end

  defp item(%Request{} = request) do
    ~MOB"""
    <Column fill_width={true}>
      {from_line(request.profile)}
      {RequestItem.row(request)}
    </Column>
    """
  end

  defp from_line(profile) do
    ~MOB"""
    <Text
      text={"From #{who(profile)}"}
      text_size={12}
      text_color={:muted}
      padding_left={4}
      padding_bottom={4}
    />
    """
  end

  # ── Decision sheet ─────────────────────────────────────────────────────────

  defp decision_sheet(%{selected: nil}), do: []

  defp decision_sheet(%{selected: selected} = assigns) do
    ~MOB"""
    <Sheet
      id={"approval-#{sheet_id(selected)}"}
      detents={[:content]}
      background={:background}
      corner_radius={28}
      on_dismiss={{self(), :close_item}}
    >
      <Column fill_width={true} padding={20}>
        <Row fill_width={true} align={:top}>
          <Column weight={1}>
            <Text
              text={title(selected)}
              text_size={20}
              font_weight="bold"
              letter_spacing={-0.5}
              text_color={:on_background}
              max_lines={2}
            />
            <Text text={"From #{who(selected.profile)}"} text_size={13} text_color={:muted} />
            <Spacer size={6} />
            <Row>
              {status_pill(selected)}
            </Row>
          </Column>
          <Spacer size={12} />
          {Header.icon_button("close", "Close", {self(), :close_item})}
        </Row>
        <Spacer size={14} />
        {body(selected)}
        <Spacer size={16} />
        {actions(assigns)}
      </Column>
    </Sheet>
    """
  end

  defp body(%Receipt{} = receipt) do
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
          <Text text="Amount" text_size={12} text_color={:muted} />
          <Text
            text={Receipts.format_amount(receipt.amount_cents)}
            text_size={22}
            font_weight="bold"
            text_color={:on_surface}
          />
        </Column>
      </Box>
      {kra_line(receipt)}
      {detail_row("Date", Calendar.strftime(receipt.date, "%a, %d %b %Y"))}
      {detail_row("Category", receipt.category)}
      {detail_row("Description", receipt.description)}
      {detail_row("Manager's note", receipt.approval_note)}
      {photo_row(receipt)}
    </Column>
    """
  end

  defp body(%Request{} = request), do: RequestItem.details(request)

  defp kra_line(receipt) do
    if Receipts.kra?(receipt) do
      ~MOB"""
      <Row fill_width={true} align={:center} padding_top={10}>
        {KraBadge.badge(receipt)}
        <Text
          text={if(Receipts.verified?(receipt), do: "Verified with KRA", else: "Not verified with KRA yet")}
          text_size={13}
          text_color={if(Receipts.verified?(receipt), do: :secondary, else: :muted)}
          font_weight="medium"
          weight={1}
        />
      </Row>
      """
    else
      []
    end
  end

  # The photo is on the server; it downloads when opened.
  defp photo_row(%Receipt{} = receipt) do
    if Map.get(receipt, :has_photo) do
      ~MOB"""
      <Column fill_width={true} padding_top={10}>
        {ActionButton.button("image", "Open the receipt photo", :open_photo, style: :secondary)}
      </Column>
      """
    else
      []
    end
  end

  defp detail_row(_label, value) when value in [nil, ""], do: []

  defp detail_row(label, value) do
    ~MOB"""
    <Column fill_width={true} padding_top={10}>
      <Text text={label} text_size={12} text_color={:muted} />
      <Text text={value} text_size={14} text_color={:on_background} max_lines={3} />
    </Column>
    """
  end

  # Waiting items get a note and Approve / Reject; an approved request gets
  # Mark as paid; anything else is already settled.
  defp actions(%{selected: selected} = assigns) do
    cond do
      waiting?(selected) ->
        ~MOB"""
        <Column fill_width={true}>
          {FormField.field(
            label: "Note (needed to reject)",
            key: :note,
            value: @note,
            placeholder: "e.g. Please attach the invoice",
            error: @note_error
          )}
          <Row fill_width={true}>
            {ActionButton.button("close", "Reject", :reject, style: :danger, weight: 1)}
            <Spacer size={8} />
            {ActionButton.button("check", "Approve", :approve, weight: 1)}
          </Row>
        </Column>
        """

      match?(%Request{status: "approved"}, selected) ->
        ActionButton.button("payments", "Mark as paid", :mark_paid)

      true ->
        []
    end
  end

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:tap, {:tab, tab}}, socket) do
    {:noreply, socket |> Mob.Socket.assign(:tab, tab) |> show()}
  end

  def handle_info({:loaded, {receipts, requests}}, socket) do
    case {receipts, requests} do
      {{:ok, receipts}, {:ok, requests}} ->
        {:noreply,
         socket
         |> Mob.Socket.assign(
           loading: false,
           receipts: Enum.map(receipts, &Remote.receipt/1),
           requests: Enum.map(requests, &Remote.request/1)
         )
         |> show()}

      {{:error, error}, _} ->
        {:noreply,
         socket |> Mob.Socket.assign(:loading, false) |> Native.toast(Api.error_message(error))}

      {_, {:error, error}} ->
        {:noreply,
         socket |> Mob.Socket.assign(:loading, false) |> Native.toast(Api.error_message(error))}
    end
  end

  def handle_info({:select, :approvals, index}, socket), do: select(socket, index)
  def handle_info({:tap, {:list, :approvals, :select, index}}, socket), do: select(socket, index)

  def handle_info({event, :close_item}, socket) when event in [:tap, :dismiss] do
    {:noreply, Mob.Socket.assign(socket, selected: nil, note: "", note_error: nil)}
  end

  def handle_info({:change, :note, value}, socket) do
    {:noreply, Mob.Socket.assign(socket, note: value, note_error: nil)}
  end

  def handle_info({:tap, :reject}, socket) do
    if String.trim(socket.assigns.note) == "" do
      {:noreply, Mob.Socket.assign(socket, :note_error, "Say why, so they know what to fix")}
    else
      decide(socket, :reject, "Rejected")
    end
  end

  def handle_info({:tap, :approve}, socket), do: decide(socket, :approve, "Approved")

  def handle_info({:tap, :mark_paid}, socket), do: decide(socket, :pay, "Marked as paid")

  def handle_info({{:decided, message}, {:ok, _}}, socket), do: {:noreply, done(socket, message)}

  def handle_info({{:decided, _message}, {:error, error}}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(:busy, false)
     |> Native.toast(Api.error_message(error))
     |> load()}
  end

  def handle_info({:tap, :open_photo}, socket) do
    case socket.assigns.selected do
      %Receipt{id: id} ->
        {:noreply, download(socket, "/api/receipts/#{id}/photo", "receipt-#{id}.jpg")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:tap, {:open_attachment, id}}, socket) do
    with %Request{attachments: attachments} <- socket.assigns.selected,
         %Attachment{name: name} <- Enum.find(attachments, &(&1.id == id)) do
      {:noreply, download(socket, "/api/attachments/#{id}", "#{id}-#{name}")}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:downloaded, {:ok, path}}, socket),
    do: {:noreply, Native.open_file(socket, path)}

  def handle_info({:downloaded, {:error, error}}, socket),
    do: {:noreply, Native.toast(socket, Api.error_message(error))}

  def handle_info({:tap, :header_back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # The decision goes to the server; the list reloads when it answers.
  defp decide(%{assigns: %{busy: true}} = socket, _decision, _message), do: {:noreply, socket}

  defp decide(socket, decision, done_message) do
    %{selected: selected, note: note, profile: profile} = socket.assigns
    note = if String.trim(note) == "", do: nil, else: String.trim(note)
    verb = Atom.to_string(decision)

    call =
      case selected do
        %Receipt{id: id} -> fn -> Api.decide_receipt(profile, id, verb, note) end
        %Request{id: id} -> fn -> Api.decide_request(profile, id, verb, note) end
      end

    {:noreply,
     socket
     |> Mob.Socket.assign(:busy, true)
     |> Native.background({:decided, done_message}, call)}
  end

  defp done(socket, message) do
    socket
    |> Native.success()
    |> Native.toast(message)
    |> Mob.Socket.assign(selected: nil, note: "", note_error: nil, busy: false)
    |> load()
  end

  defp select(socket, index) do
    case Enum.at(socket.assigns.items, index) do
      {:heading, _} -> {:noreply, socket}
      nil -> {:noreply, socket}
      item -> {:noreply, Mob.Socket.assign(socket, selected: item, note: "", note_error: nil)}
    end
  end

  # Fetches both lists (only the ones this person may approve).
  defp load(socket) do
    profile = socket.assigns.profile

    Native.background(socket, :loaded, fn ->
      {fetch(profile.can_approve_receipts, fn -> Api.approval_receipts(profile) end, "receipts"),
       fetch(profile.can_approve_requests, fn -> Api.approval_requests(profile) end, "requests")}
    end)
  end

  defp fetch(false, _call, _key), do: {:ok, []}

  defp fetch(true, call, key) do
    with {:ok, body} <- call.(), do: {:ok, Map.get(body, key, [])}
  end

  defp show(socket) do
    %{receipts: receipts, requests: requests, tab: tab} = socket.assigns
    {pending, to_pay} = Enum.split_with(requests, &(&1.status == "pending"))

    items =
      case tab do
        :receipts -> section("Waiting for you", receipts)
        :requests -> section("Waiting for you", pending) ++ section("Approved — to pay", to_pay)
      end

    Mob.Socket.assign(socket,
      items: items,
      summary: %{receipts: totals(receipts), requests: totals(pending)}
    )
  end

  defp totals(items),
    do: %{count: length(items), total: items |> Enum.map(& &1.amount_cents) |> Enum.sum()}

  # Downloads into the app's cache folder, then opens it.
  defp download(socket, path, name) do
    profile = socket.assigns.profile
    dest = Path.join(DataDir.path("downloads"), String.replace(name, ~r/[^A-Za-z0-9._-]/, "_"))

    socket
    |> Native.toast("Opening…")
    |> Native.background(:downloaded, fn ->
      with :ok <- Api.download(profile, path, dest), do: {:ok, dest}
    end)
  end

  defp section(_heading, []), do: []
  defp section(heading, items), do: [{:heading, heading} | items]

  # ── Labels ──────────────────────────────────────────────────────────────────

  defp waiting?(%Receipt{approval_status: "pending"}), do: true
  defp waiting?(%Request{status: "pending"}), do: true
  defp waiting?(_item), do: false

  defp title(%Receipt{vendor: vendor}), do: vendor
  defp title(%Request{} = request), do: RequestItem.headline(request)

  defp status_pill(%Request{status: status}), do: RequestItem.status_pill(status)
  defp status_pill(%Receipt{approval_status: status}), do: RequestItem.status_pill(status)

  defp sheet_id(%Receipt{id: id}), do: "receipt-#{id}"
  defp sheet_id(%Request{id: id}), do: "request-#{id}"

  defp who(%Profile{name: name, phone: phone}) when is_binary(name) and name != "",
    do: "#{name} · #{Requests.local_phone(phone)}"

  defp who(%Profile{phone: phone}), do: Requests.local_phone(phone)
  defp who(_profile), do: "someone"

  defp empty_text(:receipts),
    do: "No receipts yet. Receipts your team saves appear here for approval."

  defp empty_text(:requests), do: "No requests yet. Refund and payment requests appear here."
end
