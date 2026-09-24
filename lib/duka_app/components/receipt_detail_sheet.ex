defmodule DukaApp.Components.ReceiptDetailSheet do
  @moduledoc """
  Bottom sheet for one receipt. Sends `{:tap, :view_photo}` (the photo
  thumbnail), `{:tap, :edit_receipt}`,
  `{:tap, :delete_receipt}`, `{:tap, :verify_receipt}` (check with KRA in
  the app), `{:tap, :open_on_kra}` (open KRA's page in the browser) and
  `{:tap, :close_receipt}` (or `{:dismiss, :close_receipt}` on swipe-down).
  """

  import Mob.Sigil

  alias DukaApp.Components.{ActionButton, Header, KraBadge}
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
          {thumbnail(receipt)}
          <Column weight={1}>
            <Text
              text={receipt.vendor}
              text_size={20}
              font_weight="bold"
              letter_spacing={-0.5}
              text_color={:on_background}
              max_lines={2}
            />
            {kra_status(receipt)}
          </Column>
          <Spacer size={12} />
          {Header.icon_button("close", "Close", {self(), :close_receipt})}
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
        {kra_button(receipt)}
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
        <Image src={Photos.path(photo)} width={64} height={64} content_mode={:fill} />
      </Box>
      <Spacer size={12} />
    </Row>
    """
  end

  defp thumbnail(_receipt), do: []

  # "Verified with KRA · 24 Sep 2026", or a nudge to verify.
  defp kra_status(receipt) do
    if Receipts.kra?(receipt) do
      ~MOB"""
      <Row fill_width={true} align={:center} padding_top={6}>
        {KraBadge.badge(receipt)}
        <Text
          text={kra_status_text(receipt)}
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

  defp kra_status_text(%{verified_at: %DateTime{} = at}),
    do: "Verified with KRA · #{Calendar.strftime(at, "%d %b %Y")}"

  defp kra_status_text(receipt) do
    if Receipts.verifiable?(receipt),
      do: "Not verified yet",
      else: "KRA link"
  end

  # Unverified receipts get checked in the app; once verified (or for a KRA
  # link whose page the app can't read) the button opens KRA's page instead.
  defp kra_button(receipt) do
    cond do
      Receipts.verifiable?(receipt) and not Receipts.verified?(receipt) ->
        ~MOB"""
        <Column fill_width={true} padding_top={8}>
          {ActionButton.button("verified", "Verify with KRA", :verify_receipt, style: :secondary)}
        </Column>
        """

      is_binary(receipt.verify_url) ->
        ~MOB"""
        <Column fill_width={true} padding_top={8}>
          {ActionButton.button("open", "View on KRA", :open_on_kra, style: :secondary)}
        </Column>
        """

      true ->
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

  defp source_label("etims"), do: "Scanned eTIMS receipt"
  defp source_label("tims"), do: "Scanned TIMS (ETR) receipt"
  defp source_label("kra"), do: "Scanned KRA link"
  defp source_label("other"), do: "Scanned QR code"
  defp source_label("ocr"), do: "Read from photo"
  defp source_label(_), do: "Entered by hand"
end
