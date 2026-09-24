defmodule DukaApp.Components.ReceiptDetailSheet do
  @moduledoc """
  Bottom sheet for one receipt. Sends `{:tap, :edit_receipt}`,
  `{:tap, :delete_receipt}`, `{:tap, :verify_receipt}` and
  `{:tap, :close_receipt}` (or `{:dismiss, :close_receipt}` on swipe-down).
  """

  import Mob.Sigil

  alias DukaApp.Components.{ActionButton, Header}
  alias DukaApp.Receipts
  alias DukaApp.Receipts.Photos

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    receipt = Map.fetch!(props, :receipt)

    ~MOB"""
    <Sheet
      id={"receipt-#{receipt.id}"}
      detents={[:content]}
      background={:background}
      corner_radius={28}
      on_dismiss={{self(), :close_receipt}}
    >
      <Column fill_width={true} padding={20}>
        <Row fill_width={true} align={:top}>
          <Text
            text={receipt.vendor}
            text_size={22}
            font_weight="bold"
            letter_spacing={-0.6}
            text_color={:on_background}
            max_lines={2}
            weight={1}
          />
          <Spacer size={12} />
          {Header.icon_button("close", "Close", {self(), :close_receipt})}
        </Row>
        <Spacer size={12} />
        <Image
          :if={receipt.photo_path}
          src={Photos.path(receipt.photo_path)}
          fill_width={true}
          height={300}
          content_mode={:fit}
          corner_radius={16}
        />
        <Spacer :if={receipt.photo_path} size={12} />
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
        <Spacer size={4} />
        {detail_row("Date", Calendar.strftime(receipt.date, "%a, %d %b %Y"))}
        {detail_row("Category", receipt.category)}
        {detail_row("Description", receipt.description)}
        {detail_row("Seller KRA PIN", receipt.seller_pin)}
        {detail_row("Receipt / invoice no.", receipt.invoice_number)}
        {detail_row("Source", source_label(receipt.source))}
        <Spacer size={16} />
        <Row fill_width={true}>
          {ActionButton.button("edit", "Edit", :edit_receipt, weight: 1)}
          <Spacer size={8} />
          {ActionButton.button("trash", "Delete", :delete_receipt, style: :danger, weight: 1)}
        </Row>
        <Spacer :if={is_binary(receipt.verify_url)} size={8} />
        {if is_binary(receipt.verify_url),
          do:
            ActionButton.button("open", "Verify on KRA (needs internet)", :verify_receipt,
              style: :secondary
            )}
      </Column>
    </Sheet>
    """
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

  defp source_label("etims"), do: "Scanned eTIMS receipt"
  defp source_label("tims"), do: "Scanned TIMS (ETR) receipt"
  defp source_label("kra"), do: "Scanned KRA link"
  defp source_label("other"), do: "Scanned QR code"
  defp source_label("ocr"), do: "Read from photo"
  defp source_label(_), do: "Entered by hand"
end
