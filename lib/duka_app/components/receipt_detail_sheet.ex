defmodule DukaApp.Components.ReceiptDetailSheet do
  @moduledoc """
  Bottom sheet for one receipt. Sends `{:tap, :edit_receipt}`,
  `{:tap, :delete_receipt}`, `{:tap, :verify_receipt}` and
  `{:tap, :close_receipt}` (or `{:dismiss, :close_receipt}` on swipe-down).
  """

  import Mob.Sigil

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
      <Column fill_width={true} padding={20} gap={12}>
        <Text
          text={receipt.vendor}
          text_size={:xl}
          font_weight="medium"
          text_color={:primary}
          max_lines={2}
        />
        <Image
          :if={receipt.photo_path}
          src={Photos.path(receipt.photo_path)}
          fill_width={true}
          height={300}
          content_mode={:fit}
          corner_radius={:radius_sm}
        />
        <Box background={:surface} corner_radius={:radius_sm} padding={12} fill_width={true}>
          <Column gap={4} fill_width={true}>
            <Text text="Amount" text_size={:xs} text_color={:muted} />
            <Text text={Receipts.format_amount(receipt.amount_cents)} text_size={:xl} />
          </Column>
        </Box>
        {detail_row("Date", Calendar.strftime(receipt.date, "%a, %d %b %Y"))}
        {detail_row("Category", receipt.category)}
        {detail_row("Description", receipt.description)}
        {detail_row("Seller KRA PIN", receipt.seller_pin)}
        {detail_row("Receipt / invoice no.", receipt.invoice_number)}
        {detail_row("Source", source_label(receipt.source))}
        <Button
          :if={is_binary(receipt.verify_url)}
          text="Verify on KRA (needs internet)"
          on_tap={{self(), :verify_receipt}}
          fill_width={true}
        />
        <Row fill_width={true} gap={8}>
          <Button text="Edit" on_tap={{self(), :edit_receipt}} weight={1} />
          <Button
            text="Delete"
            on_tap={{self(), :delete_receipt}}
            weight={1}
            background={:error}
            text_color={:on_error}
          />
        </Row>
        <Button
          text="Close"
          on_tap={{self(), :close_receipt}}
          fill_width={true}
          background={:surface}
          text_color={:on_surface}
        />
      </Column>
    </Sheet>
    """
  end

  defp detail_row(_label, value) when value in [nil, ""], do: []

  defp detail_row(label, value) do
    ~MOB"""
    <Column gap={2} fill_width={true}>
      <Text text={label} text_size={:xs} text_color={:muted} />
      <Text text={value} text_size={:sm} max_lines={3} fill_width={true} />
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
