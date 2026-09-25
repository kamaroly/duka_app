defmodule DukaApp.Components.ReceiptItem do
  @moduledoc """
  One card in the receipts list: a tinted badge (or the receipt photo), the
  vendor over what it was for (tagged KRA, and ticked once verified), and
  the amount over the date.

  Props: `receipt`, and `sync: true` in a connected receipt book to mark
  whether the team's server has it (see `SyncBadge`).
  """

  import Mob.Sigil

  alias DukaApp.Components.{KraBadge, RequestItem, SyncBadge}
  alias DukaApp.{Receipts, Theme}
  alias DukaApp.Receipts.Photos

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    receipt = Map.fetch!(props, :receipt)
    sync = Map.get(props, :sync, false)

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
            <Row align={:center}>
              {SyncBadge.badge(receipt, sync)}
              <Text
                text={Calendar.strftime(receipt.date, "%d %b")}
                text_size={11}
                text_color={:muted}
                fill_width={false}
              />
            </Row>
            {approval_tag(receipt.approval_status)}
          </Column>
        </Row>
      </Box>
    </Column>
    """
  end

  # The receipt photo when it's on the phone, otherwise the vendor's initials
  # on the spending group's tint.
  defp badge(%{photo_path: photo} = receipt) when is_binary(photo) do
    if Photos.exists?(photo) do
      ~MOB"""
      <Image src={Photos.path(photo)} width={46} height={46} corner_radius={14} content_mode={:fill} />
      """
    else
      initials_badge(receipt)
    end
  end

  defp badge(receipt), do: initials_badge(receipt)

  defp initials_badge(receipt) do
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

  # Decided expenses say so; pending ones stay quiet.
  defp approval_tag(status) when status in ["approved", "rejected"] do
    ~MOB"""
    <Column padding_top={4}>
      {RequestItem.status_pill(status)}
    </Column>
    """
  end

  defp approval_tag(_status), do: []

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
