defmodule DukaApp.Components.TransactionSheet do
  @moduledoc """
  Bottom sheet for one of the person's transactions. Sends
  `{:tap, :view_photo}` (the photo thumbnail), `{:tap, :edit_transaction}`,
  `{:tap, :delete_transaction}`, `{:tap, :request_refund}` (an expense),
  `{:tap, :cancel_refund}` (a refund still waiting), `{:tap, :verify_receipt}`
  (check with KRA in the app), `{:tap, :open_on_kra}` (open KRA's page in the
  browser), `{:tap, {:open_attachment, id}}` and `{:tap, :close_transaction}`
  (or `{:dismiss, :close_transaction}` on swipe-down).

  With `personal: true` (a personal book) there's nobody to approve or pay
  back, so the sheet doesn't offer a refund or say where approval stands.
  """

  import Mob.Sigil

  alias DukaApp.Components.{ActionButton, Header, KraBadge, TransactionItem}
  alias DukaApp.Receipts.Photos
  alias DukaApp.Transactions

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    transaction = Map.fetch!(props, :transaction)
    personal = Map.get(props, :personal, false)

    ~MOB"""
    <Sheet
      id={"transaction-#{transaction.id}"}
      detents={[:content]}
      background={:background}
      corner_radius={28}
      on_dismiss={{self(), :close_transaction}}
    >
      <Column fill_width={true} padding={20}>
        <Row fill_width={true} align={:top}>
          {thumbnail(transaction)}
          <Column weight={1}>
            <Text
              text={transaction.vendor}
              text_size={20}
              font_weight="bold"
              letter_spacing={-0.5}
              text_color={:on_background}
              max_lines={2}
            />
            {kra_status(transaction)}
          </Column>
          <Spacer size={12} />
          {Header.icon_button("close", "Close", {self(), :close_transaction})}
        </Row>
        <Spacer size={14} />
        {TransactionItem.details(transaction)}
        {if not personal, do: status_line(transaction)}
        {detail_row("Source", source_label(transaction.source))}
        <Spacer size={16} />
        {edit_buttons(transaction)}
        {kra_button(transaction)}
        {if not personal, do: refund_button(transaction)}
      </Column>
    </Sheet>
    """
  end

  # The receipt photo, small; tapping it opens it full screen to zoom and save.
  defp thumbnail(%{photo_path: photo}) when is_binary(photo) do
    ~MOB"""
    <Row align={:top}>
      <Box
        width={64}
        height={64}
        corner_radius={14}
        border_color={:border}
        border_width={1}
        on_tap={{self(), :view_photo}}
        accessibility_label="Receipt photo. Open to zoom and save"
        accessibility_role={:button}
      >
        {thumbnail_image(photo)}
      </Box>
      <Spacer size={12} />
    </Row>
    """
  end

  defp thumbnail(_transaction), do: []

  # A photo still on the server shows an icon until it's opened.
  defp thumbnail_image(photo) do
    if Photos.exists?(photo) do
      ~MOB"""
      <Image src={Photos.path(photo)} width={64} height={64} content_mode={:fill} />
      """
    else
      ~MOB"""
      <Box width={64} height={64} align={:center}>
        <Icon name="image" text_size={24} text_color={:muted} />
      </Box>
      """
    end
  end

  # "Verified with KRA · 24 Sep 2026", or a nudge to verify.
  defp kra_status(transaction) do
    if Transactions.kra?(transaction) do
      ~MOB"""
      <Row fill_width={true} align={:center} padding_top={6}>
        {KraBadge.badge(transaction)}
        <Text
          text={kra_status_text(transaction)}
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

  defp kra_status_text(%{verified_at: %DateTime{} = at}),
    do: "Verified with KRA · #{Calendar.strftime(at, "%d %b %Y")}"

  defp kra_status_text(transaction) do
    if Transactions.verifiable?(transaction),
      do: "Not verified yet",
      else: "KRA link"
  end

  # Where the decision stands.
  defp status_line(transaction) do
    {icon, color, text} = status(transaction)

    ~MOB"""
    <Column fill_width={true} padding_top={12}>
      <Row fill_width={true} align={:center}>
        <Icon name={icon} text_size={18} text_color={color} />
        <Spacer size={8} />
        <Text text={text} text_size={13} font_weight="medium" text_color={color} weight={1} />
      </Row>
    </Column>
    """
  end

  defp status(%{status: "paid", paid_at: at}), do: {"payments", :secondary, "Paid#{on(at)}"}

  defp status(%{status: "approved", decided_at: at} = t),
    do: {"check", :secondary, "Approved#{on(at)}#{if claim?(t), do: " · waiting to be paid"}"}

  defp status(%{status: "rejected", decided_at: at}), do: {"close", :error, "Rejected#{on(at)}"}
  defp status(_pending), do: {"approvals", :muted, "Waiting for approval"}

  defp on(%DateTime{} = at), do: " · #{Calendar.strftime(at, "%d %b")}"
  defp on(_at), do: ""

  defp claim?(%{type: type}), do: type in ["refund", "payment_request"]

  # A paid transaction is settled: nothing left to change.
  defp edit_buttons(%{status: "paid"}), do: []

  defp edit_buttons(_transaction) do
    ~MOB"""
    <Row fill_width={true}>
      {ActionButton.button("edit", "Edit", :edit_transaction, weight: 1)}
      <Spacer size={8} />
      {ActionButton.button("trash", "Delete", :delete_transaction, style: :danger, weight: 1)}
    </Row>
    """
  end

  # Unverified receipts get checked in the app; once verified (or for a KRA
  # link whose page the app can't read) the button opens KRA's page instead.
  defp kra_button(transaction) do
    cond do
      Transactions.verifiable?(transaction) and not Transactions.verified?(transaction) ->
        ~MOB"""
        <Column fill_width={true} padding_top={8}>
          {ActionButton.button("verified", "Verify with KRA", :verify_receipt, style: :secondary)}
        </Column>
        """

      is_binary(transaction.verify_url) ->
        ~MOB"""
        <Column fill_width={true} padding_top={8}>
          {ActionButton.button("open", "View on KRA", :open_on_kra, style: :secondary)}
        </Column>
        """

      true ->
        []
    end
  end

  # An expense can be claimed back; a refund still waiting can be taken back.
  defp refund_button(%{type: "expense", status: status}) when status != "paid" do
    ~MOB"""
    <Column fill_width={true} padding_top={8}>
      {ActionButton.button("refund", "Request refund", :request_refund, style: :secondary)}
    </Column>
    """
  end

  defp refund_button(%{type: "refund", status: "pending"}) do
    ~MOB"""
    <Column fill_width={true} padding_top={8}>
      {ActionButton.button("close", "Take back refund request", :cancel_refund, style: :secondary)}
    </Column>
    """
  end

  defp refund_button(_transaction), do: []

  defp detail_row(_label, value) when value in [nil, ""], do: []

  defp detail_row(label, value) do
    ~MOB"""
    <Column fill_width={true} padding_top={10}>
      <Text text={label} text_size={12} text_color={:muted} />
      <Text text={value} text_size={14} text_color={:on_background} max_lines={3} />
    </Column>
    """
  end

  defp source_label("etims"), do: "Scanned eTIMS receipt"
  defp source_label("tims"), do: "Scanned TIMS (ETR) receipt"
  defp source_label("kra"), do: "Scanned KRA link"
  defp source_label("other"), do: "Scanned QR code"
  defp source_label("ocr"), do: "Read from photo"
  defp source_label(_), do: "Entered by hand"
end
