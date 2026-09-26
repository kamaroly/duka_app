defmodule DukaApp.Components.TransactionItem do
  @moduledoc """
  How a transaction is shown: as a list card (`expand/3`), a status tag
  (`status_pill/1`) and the body of a details sheet (`details/1`). Shared by
  the home screen and the approver's Approvals screen.

  The card is a tinted badge (or the receipt photo), the vendor over what it
  was for (tagged KRA, and ticked once verified), and the amount over the
  date. Refunds and payment requests say what they are and always show
  their status; an expense shows it once it's decided.

  Props: `transaction`, `sync: true` in a connected book to mark whether
  the team's server has it (see `SyncBadge`), and `personal: true` in a
  personal book, where there's no approval to show.
  """

  import Mob.Sigil

  alias DukaApp.Components.{KraBadge, SyncBadge}
  alias DukaApp.Receipts.Photos
  alias DukaApp.{Theme, Transactions}
  alias DukaApp.Transactions.{Attachment, Attachments, Transaction}

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    transaction = Map.fetch!(props, :transaction)
    sync = Map.get(props, :sync, false)
    personal = Map.get(props, :personal, false)

    # The amount column sets no text_align: Android stretches an aligned Text
    # to full width, which squeezes the vendor column to nothing.
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
          {badge(transaction)}
          <Spacer size={12} />
          <Column weight={1}>
            <Text
              text={transaction.vendor}
              text_size={15}
              font_weight="semibold"
              letter_spacing={-0.3}
              text_color={:on_surface}
              max_lines={1}
            />
            <Spacer size={2} />
            <Row fill_width={true} align={:center}>
              {KraBadge.badge(transaction)}
              <Text
                text={subtitle(transaction)}
                text_size={12}
                text_color={:muted}
                max_lines={1}
                weight={1}
              />
              {attachment_count(transaction.attachments)}
            </Row>
          </Column>
          <Spacer size={12} />
          <Column>
            <Text
              text={Transactions.format_short(transaction.amount_cents)}
              text_size={15}
              font_weight="bold"
              letter_spacing={-0.4}
              text_color={:on_surface}
              fill_width={false}
            />
            <Spacer size={3} />
            <Row align={:center}>
              {SyncBadge.badge(transaction, sync)}
              <Text
                text={Calendar.strftime(transaction.date, "%d %b")}
                text_size={11}
                text_color={:muted}
                fill_width={false}
              />
            </Row>
            {if not personal, do: status_tag(transaction)}
          </Column>
        </Row>
      </Box>
    </Column>
    """
  end

  # The receipt photo when it's on the phone; a claim's own icon; otherwise
  # the vendor's initials on the spending group's tint.
  defp badge(%{photo_path: photo} = transaction) when is_binary(photo) do
    if Photos.exists?(photo) do
      ~MOB"""
      <Image src={Photos.path(photo)} width={46} height={46} corner_radius={14} content_mode={:fill} />
      """
    else
      plain_badge(transaction)
    end
  end

  defp badge(transaction), do: plain_badge(transaction)

  defp plain_badge(%{type: "expense"} = transaction), do: initials_badge(transaction)

  defp plain_badge(transaction) do
    ~MOB"""
    <Box width={46} height={46} corner_radius={14} background={:surface_raised} align={:center}>
      <Icon name={type_icon(transaction)} text_size={20} text_color={:on_surface} />
    </Box>
    """
  end

  defp initials_badge(transaction) do
    group = Transactions.group(transaction.category)

    ~MOB"""
    <Box
      width={46}
      height={46}
      corner_radius={14}
      background={Theme.color(:"#{group}_tint")}
      align={:center}
    >
      <Text
        text={initials(transaction.vendor)}
        text_color={Theme.color(group)}
        text_size={17}
        font_weight="bold"
      />
    </Box>
    """
  end

  defp type_icon(%{type: "refund"}), do: "refund"
  defp type_icon(%{method: "send_money"}), do: "phone"
  defp type_icon(_transaction), do: "store"

  # Claims always say where they stand; expenses once they're decided.
  defp status_tag(%{type: "expense", status: "pending"}), do: []

  defp status_tag(%{status: status}) do
    ~MOB"""
    <Column padding_top={4}>
      {status_pill(status)}
    </Column>
    """
  end

  defp attachment_count(list) when list in [[], nil], do: []
  defp attachment_count(%Ecto.Association.NotLoaded{}), do: []

  defp attachment_count(list) do
    ~MOB"""
    <Row align={:center} accessibility_label={"#{length(list)} attachments"}>
      <Spacer size={6} />
      <Icon name="attach" text_size={14} text_color={:muted} />
      <Text text={Integer.to_string(length(list))} text_size={12} text_color={:muted} />
    </Row>
    """
  end

  @doc "What it was for: its type (for a claim), description and category."
  @spec subtitle(Transaction.t()) :: String.t()
  def subtitle(transaction) do
    [claim_label(transaction), transaction.description, transaction.category]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp claim_label(%{type: "expense"}), do: nil
  defp claim_label(%{type: type}), do: Transactions.type_label(type)

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
  The amount, then what a sheet shows about the transaction: how it's paid
  and to whom, when, the category and description, notes and attachments.
  Attachments send `{:tap, {:open_attachment, id}}`.
  """
  @spec details(Transaction.t()) :: map()
  def details(transaction) do
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
          <Text text={Transactions.type_label(transaction.type)} text_size={12} text_color={:muted} />
          <Text
            text={Transactions.format_amount(transaction.amount_cents)}
            text_size={22}
            font_weight="bold"
            text_color={:on_surface}
          />
        </Column>
      </Box>
      {detail_row(pay_label(transaction), Transactions.pay_details(transaction))}
      {detail_row("Pay to", pay_to_label(transaction.pay_to))}
      {detail_row("Date", Calendar.strftime(transaction.date, "%a, %d %b %Y"))}
      {detail_row("Category", transaction.category)}
      {detail_row("Description", transaction.description)}
      {detail_row("Seller KRA PIN", transaction.seller_pin)}
      {detail_row("Receipt / invoice no.", transaction.invoice_number)}
      {detail_row("Approver's note", transaction.decision_note)}
      {detail_row("Paid", paid_on(transaction.paid_at))}
      {attachments(transaction.attachments)}
    </Column>
    """
  end

  defp pay_label(%{type: "expense"}), do: "Paid with"
  defp pay_label(_claim), do: "Pay with"

  defp pay_to_label("self"), do: "You"
  defp pay_to_label("supplier"), do: "A supplier"
  defp pay_to_label(_), do: nil

  defp paid_on(%DateTime{} = at), do: Calendar.strftime(at, "%d %b %Y")
  defp paid_on(_), do: nil

  defp attachments(list) when list in [[], nil], do: []
  defp attachments(%Ecto.Association.NotLoaded{}), do: []

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
    if Attachment.image?(attachment) and is_binary(attachment.file_name) and
         File.regular?(Attachments.path(attachment.file_name)) do
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

  defp short_status("pending"), do: "Pending"
  defp short_status(status), do: Transactions.status_label(status)

  # Pending waits in amber; approved and paid are the accent green.
  defp status_colors("pending"), do: {0x33F59E0B, :on_surface}
  defp status_colors("rejected"), do: {:error, :on_error}
  defp status_colors(_approved_or_paid), do: {:secondary, :on_secondary}

  @doc """
  Up to two initials for a badge.

      iex> DukaApp.Components.TransactionItem.initials("Nairobi Java House")
      "NJ"

      iex> DukaApp.Components.TransactionItem.initials("Food & Groceries")
      "FG"
  """
  @spec initials(String.t() | nil) :: String.t()
  def initials(nil), do: "?"

  def initials(name) do
    name
    |> String.split(~r/[^[:alnum:]]+/u, trim: true)
    |> Enum.map_join(&String.first/1)
    |> String.slice(0, 2)
    |> String.upcase()
    |> case do
      "" -> "?"
      initials -> initials
    end
  end
end
