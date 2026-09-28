defmodule RisitiApp.Components.KraBadge do
  @moduledoc """
  Marks a KRA receipt with a small green "KRA" tag. Renders nothing for a
  receipt that isn't from a KRA QR code. The receipt's sheet says whether
  KRA has verified it; in the list a green tick means approved (see
  `TransactionItem`).

      <Row>
        {KraBadge.badge(receipt)}
        <Text text="..." />
      </Row>

  The trailing gap is part of the badge, so it can sit directly in front of
  text.
  """

  import Mob.Sigil

  alias RisitiApp.Transactions

  @spec badge(RisitiApp.Transactions.Transaction.t()) :: map() | []
  def badge(receipt) do
    if Transactions.kra?(receipt), do: tags(Transactions.verified?(receipt)), else: []
  end

  defp tags(verified?) do
    label = if verified?, do: "KRA receipt, verified", else: "KRA receipt, not verified yet"

    ~MOB"""
    <Row align={:center} accessibility_label={label}>
      <Row
        background={:secondary}
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
          text_color={:on_secondary}
        />
      </Row>
      <Spacer size={6} />
    </Row>
    """
  end
end
