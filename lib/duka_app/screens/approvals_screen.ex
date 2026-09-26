defmodule DukaApp.Screens.ApprovalsScreen do
  @moduledoc """
  The approver's inbox: transactions — expenses, refunds and payment
  requests — to approve or reject, and approved refunds and payments to
  mark paid.

  Two cards at the top say what's waiting and switch between the lists.
  Tapping an item opens its details with the decision buttons; rejecting
  needs a note so the person knows what to fix.

  Everything comes from the team's server (`DukaApp.Api`), in the
  background; the decisions go straight back to it. Receipt photos and
  attachments download when opened. While it's open, a push from the server
  (received by `ReceiptsScreen`, which sends `:server_changed` to this
  screen's registered name) reloads the lists.
  """

  use Mob.Screen

  alias DukaApp.{Accounts, Api, DataDir, Native, Remote, Transactions}
  alias DukaApp.Accounts.Profile
  alias DukaApp.Components.{ActionButton, FormField, Header, KraBadge, TransactionItem}
  alias DukaApp.Transactions.{Attachment, Transaction}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    profile = Accounts.current_profile()

    socket =
      socket
      |> Mob.Socket.assign(:profile, profile)
      |> Mob.Socket.assign(:tab, if(profile.can_approve, do: :decide, else: :pay))
      |> Mob.Socket.assign(:transactions, [])
      |> Mob.Socket.assign(:items, [])
      |> Mob.Socket.assign(:summary, %{
        decide: %{count: 0, total: 0},
        pay: %{count: 0, total: 0}
      })
      |> Mob.Socket.assign(:loading, true)
      |> Mob.Socket.assign(:busy, false)
      |> Mob.Socket.assign(:selected, nil)
      |> Mob.Socket.assign(:note, "")
      |> Mob.Socket.assign(:note_error, nil)
      |> Mob.List.put_renderer(:approvals, &item/1)
      |> load()

    listen_for_pushes()
    {:ok, socket}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title="Approvals" subtitle="Expenses, refunds and payments" show_back={true} />
      <Row fill_width={true} padding_left={18} padding_right={18}>
        {tab_card(:decide, "To decide", @summary.decide, @tab)}
        <Spacer size={10} />
        {tab_card(:pay, "To pay", @summary.pay, @tab)}
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
        <Text text={Transactions.format_short(total)} text_size={12} text_color={:muted} />
      </Column>
    </Box>
    """
  end

  # List items: a section heading, then transactions with who sent them.
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

  defp item(%Transaction{} = transaction) do
    ~MOB"""
    <Column fill_width={true}>
      {from_line(transaction.profile)}
      {TransactionItem.expand(%{transaction: transaction}, [], %{})}
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
      id={"approval-#{selected.id}"}
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
              {TransactionItem.status_pill(selected.status)}
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

  defp body(transaction) do
    ~MOB"""
    <Column fill_width={true}>
      {TransactionItem.details(transaction)}
      {kra_line(transaction)}
      {photo_row(transaction)}
    </Column>
    """
  end

  defp kra_line(transaction) do
    if Transactions.kra?(transaction) do
      ~MOB"""
      <Row fill_width={true} align={:center} padding_top={10}>
        {KraBadge.badge(transaction)}
        <Text
          text={if(Transactions.verified?(transaction), do: "Verified with KRA", else: "Not verified with KRA yet")}
          text_size={13}
          text_color={if(Transactions.verified?(transaction), do: :secondary, else: :muted)}
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
  defp photo_row(transaction) do
    if Map.get(transaction, :has_photo) do
      ~MOB"""
      <Column fill_width={true} padding_top={10}>
        {ActionButton.button("image", "Open the receipt photo", :open_photo, style: :secondary)}
      </Column>
      """
    else
      []
    end
  end

  # Waiting items get a note and Approve / Reject; an approved claim gets
  # Mark as paid; anything else is already settled. Each only for someone
  # who may do it.
  defp actions(%{selected: selected, profile: profile} = assigns) do
    cond do
      selected.status == "pending" and profile.can_approve ->
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

      selected.status == "approved" and Transaction.claim?(selected) and profile.can_mark_paid ->
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

  def handle_info(:server_changed, socket), do: {:noreply, load(socket)}

  def handle_info({:loaded, {:ok, %{"transactions" => transactions}}}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(
       loading: false,
       transactions: Enum.map(transactions, &Remote.transaction/1)
     )
     |> show()}
  end

  def handle_info({:loaded, {:error, error}}, socket) do
    {:noreply,
     socket |> Mob.Socket.assign(:loading, false) |> Native.toast(Api.error_message(error))}
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
      %Transaction{id: id} ->
        {:noreply, download(socket, "/api/transactions/#{id}/photo", "receipt-#{id}.jpg")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:tap, {:open_attachment, id}}, socket) do
    with %Transaction{attachments: attachments} <- socket.assigns.selected,
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

    {:noreply,
     socket
     |> Mob.Socket.assign(:busy, true)
     |> Native.background({:decided, done_message}, fn ->
       Api.decide(profile, selected.id, verb, note)
     end)}
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

  # One Approvals screen at a time; the name frees itself when it closes.
  defp listen_for_pushes do
    Process.register(self(), __MODULE__)
  rescue
    ArgumentError -> :already_open
  end

  # Everything waiting on an approver, from the server.
  defp load(socket) do
    profile = socket.assigns.profile
    Native.background(socket, :loaded, fn -> Api.approvals(profile) end)
  end

  defp show(socket) do
    %{transactions: transactions, tab: tab} = socket.assigns
    {pending, to_pay} = Enum.split_with(transactions, &(&1.status == "pending"))

    items =
      case tab do
        :decide -> section("Waiting for you", pending)
        :pay -> section("Approved — to pay", to_pay)
      end

    Mob.Socket.assign(socket,
      items: items,
      summary: %{decide: totals(pending), pay: totals(to_pay)}
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

  defp title(%Transaction{type: "expense", vendor: vendor}), do: vendor

  defp title(%Transaction{type: type, vendor: vendor}),
    do: "#{Transactions.type_label(type)} · #{vendor}"

  defp who(%Profile{name: name, phone: phone}) when is_binary(name) and name != "",
    do: "#{name} · #{Transactions.local_phone(phone)}"

  defp who(%Profile{phone: phone}), do: Transactions.local_phone(phone)
  defp who(_profile), do: "someone"

  defp empty_text(:decide),
    do: "Nothing to decide. Expenses, refunds and payment requests from your team appear here."

  defp empty_text(:pay), do: "Nothing to pay. Approved refunds and payments appear here."
end
