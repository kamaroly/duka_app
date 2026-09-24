defmodule DukaApp.Components.ReceiptItem do
  @moduledoc """
  One card in the receipts list: a tinted badge (or the receipt photo), the
  vendor over what it was for (tagged KRA, and ticked once verified), and
  the amount over the date.
  """

  import Mob.Sigil

  alias DukaApp.Components.KraBadge
  alias DukaApp.{Receipts, Theme}
  alias DukaApp.Receipts.Photos

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    receipt = Map.fetch!(props, :receipt)

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
          {badge(receipt)}
          <Spacer size={12} />
          <Column weight={1}>
            <Text
              text={receipt.vendor}
              text_size={15}
              font_weight="semibold"
              letter_spacing={-0.3}
              text_color={:on_surface}
              max_lines={1}
            />
            <Spacer size={2} />
            <Row fill_width={true} align={:center}>
              {KraBadge.badge(receipt)}
              <Text
                text={subtitle(receipt)}
                text_size={12}
                text_color={:muted}
                max_lines={1}
                weight={1}
              />
            </Row>
          </Column>
          <Spacer size={12} />
          <Column>
            <Text
              text={Receipts.format_short(receipt.amount_cents)}
              text_size={15}
              font_weight="bold"
              letter_spacing={-0.4}
              text_color={:on_surface}
              fill_width={false}
            />
            <Spacer size={3} />
            <Text
              text={Calendar.strftime(receipt.date, "%d %b")}
              text_size={11}
              text_color={:muted}
              fill_width={false}
            />
          </Column>
        </Row>
      </Box>
    </Column>
    """
  end

  # The receipt photo when there is one, otherwise the vendor's initials on
  # the spending group's tint.
  defp badge(%{photo_path: photo}) when is_binary(photo) do
    ~MOB"""
    <Image src={Photos.path(photo)} width={46} height={46} corner_radius={14} content_mode={:fill} />
    """
  end

  defp badge(receipt) do
    group = Receipts.group(receipt.category)

    ~MOB"""
    <Box
      width={46}
      height={46}
      corner_radius={14}
      background={Theme.color(:"#{group}_tint")}
      align={:center}
    >
      <Text
        text={initials(receipt.vendor)}
        text_color={Theme.color(group)}
        text_size={17}
        font_weight="bold"
      />
    </Box>
    """
  end

  defp subtitle(%{description: description, category: category})
       when is_binary(description) and description != "",
       do: "#{description} · #{category}"

  defp subtitle(%{category: category}), do: category

  @doc """
  Up to two initials for a badge.

      iex> DukaApp.Components.ReceiptItem.initials("Nairobi Java House")
      "NJ"

      iex> DukaApp.Components.ReceiptItem.initials("Food & Groceries")
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
