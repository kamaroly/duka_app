defmodule DukaApp.Components.RequestItem do
  @moduledoc """
  How a refund or payment request is shown: as a list card (`row/1`), a
  status tag (`status_pill/1`) and the body of its details sheet
  (`details/1`). Shared by the requester's Requests screen and the
  manager's Approvals screen.
  """

  import Mob.Sigil

  alias DukaApp.Components.{ActionButton, Header, KraBadge, SyncBadge}
  alias DukaApp.{Receipts, Requests}
  alias DukaApp.Requests.{Attachment, Attachments, Request}

  @doc """
  One card in a list: what the request is, where the money goes, the amount,
  its status. `sync: true` (the requester's own list, when connected) marks
  whether the team's server has it.
  """
  @spec row(Request.t(), keyword()) :: map()
  def row(request, opts \\ []) do
    ~MOB"""
    <Column fill_width={true} padding_bottom={2}>
      <Box
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={12}
        padding={4}
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
            <Row fill_width={true} align={:center}>
              {SyncBadge.badge(request, Keyword.get(opts, :sync, false))}
              <Text
                text={Requests.pay_to(request)}
                text_size={12}
                text_color={:muted}
                max_lines={1}
                weight={1}
              />
              {attachment_count(request.attachments)}
            </Row>
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

  defp attachment_count([]), do: []

  defp attachment_count(list) do
    ~MOB"""
    <Row align={:center} accessibility_label={"#{length(list)} attachments"}>
      <Spacer size={6} />
      <Icon name="attach" text_size={14} text_color={:muted} />
      <Text text={Integer.to_string(length(list))} text_size={12} text_color={:muted} />
    </Row>
    """
  end

  @doc "Pending (amber), Approved / Paid (green) or Rejected (red)."
  @spec status_pill(String.t()) :: map()
  def status_pill(status) do
    {background, text_color} = status_colors(status)

    ~MOB"""
    <Row
      background={background}
      corner_radius={:radius_pill}
      padding_left={4}
      padding_right={4}
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

  @doc """
  The details sheet for a request, with Withdraw while it's pending. Sends
  `{:tap, :close_request}` (or `{:dismiss, :close_request}`),
  `{:tap, :cancel_request}` and `{:tap, {:open_attachment, id}}`.
  """
  @spec sheet(Request.t() | nil) :: map() | []
  def sheet(nil), do: []

  def sheet(request) do
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
        {details(request)}
        <Spacer size={16} />
        {if request.status == "pending",
          do: ActionButton.button("trash", "Withdraw request", :cancel_request, style: :secondary)}
      </Column>
    </Sheet>
    """
  end

  @doc "Amount, how and whom to pay, the receipt, notes and attachments."
  @spec details(Request.t()) :: map()
  def details(request) do
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
      {attachments(request.attachments)}
    </Column>
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

  defp attachments([]), do: []

  # Each opens in the phone's own viewer (a PDF reader, the gallery).
  defp attachments(list) do
    ~MOB"""
    <Column fill_width={true} padding_top={10}>
      <Text text="Attachments" text_size={12} text_color={:muted} />
      <Spacer size={6} />
      {Enum.map(list, &attachment_row/1)}
    </Column>
    """
  end

  defp attachment_row(attachment) do
    ~MOB"""
    <Column fill_width={true} padding_bottom={8}>
      <Row
        fill_width={true}
        align={:center}
        background={:surface}
        border_color={:border}
        border_width={1}
        corner_radius={14}
        padding={8}
        on_tap={{self(), {:open_attachment, attachment.id}}}
        accessibility_label={"Open #{attachment.name}"}
        accessibility_role={:button}
      >
        {attachment_thumb(attachment)}
        <Spacer size={10} />
        <Column weight={1}>
          <Text
            text={attachment.name}
            text_size={14}
            font_weight="medium"
            text_color={:on_surface}
            max_lines={1}
          />
          <Text text={Attachments.format_size(attachment.size)} text_size={12} text_color={:muted} />
        </Column>
        <Icon name="open" text_size={18} text_color={:muted} />
      </Row>
    </Column>
    """
  end

  # A server attachment (no local file yet) shows the file icon.
  defp attachment_thumb(attachment) do
    if Attachment.image?(attachment) and is_binary(attachment.file_name) do
      ~MOB"""
      <Image
        src={Attachments.path(attachment.file_name)}
        width={40}
        height={40}
        corner_radius={10}
        content_mode={:fill}
      />
      """
    else
      ~MOB"""
      <Box width={40} height={40} corner_radius={10} background={:surface_raised} align={:center}>
        <Icon name="file" text_size={20} text_color={:on_surface} />
      </Box>
      """
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

  @doc "What the request is, in a line."
  @spec headline(Request.t()) :: String.t()
  def headline(%{kind: "refund", receipt: %Receipts.Receipt{vendor: vendor}}),
    do: "Refund · #{vendor}"

  def headline(%{kind: "refund"}), do: "Refund"

  def headline(%{kind: "payment", purpose: purpose}) when is_binary(purpose),
    do: purpose

  def headline(%{kind: "payment"}), do: "Payment"

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
end
