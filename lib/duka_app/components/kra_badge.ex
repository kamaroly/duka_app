defmodule DukaApp.Components.KraBadge do
  @moduledoc """
  Marks a KRA receipt: a small "KRA" tag, followed by a green verified tick
  once KRA's verification page has returned the receipt. Renders nothing for
  a receipt that isn't from a KRA QR code.

      <Row>
        {KraBadge.badge(receipt)}
        <Text text="..." />
      </Row>

  The trailing gap is part of the badge, so it can sit directly in front of
  text.
  """

  import Mob.Sigil

  alias DukaApp.Receipts

  @spec badge(DukaApp.Receipts.Receipt.t()) :: map() | []
  def badge(receipt) do
    if Receipts.kra?(receipt), do: tags(Receipts.verified?(receipt)), else: []
  end

  defp tags(verified?) do
    label = if verified?, do: "KRA receipt, verified", else: "KRA receipt, not verified yet"

    ~MOB"""
    <Row align={:center} accessibility_label={label}>
      <Row
        background={:surface_raised}
        border_color={:border}
        border_width={1}
        corner_radius={6}
        padding_left={5}
        padding_right={5}
        padding_top={1}
        padding_bottom={1}
      >
        <Text
          text="KRA"
          text_size={10}
          font_weight="bold"
          letter_spacing={0.4}
          text_color={:on_surface}
        />
      </Row>
      <Spacer :if={verified?} size={4} />
      <Icon :if={verified?} name="verified" text_size={15} text_color={:secondary} />
      <Spacer size={6} />
    </Row>
    """
  end
end
