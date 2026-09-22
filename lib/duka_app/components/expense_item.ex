defmodule DukaApp.Components.ExpenseItem do
  import Mob.Sigil

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    # 1. Safely retrieve the item property map
    item = Map.get(props, :item)

    # 2. Extract and format values
    # Note: If your handler property is on_tap="item-X",
    # it arrives in the expander pre-shaped as {screen_pid, "item-X"}.
    on_tap_handler = Map.fetch!(props, :on_tap)

    ~MOB"""
    <Box background={:white} padding={:space_xs} corner_radius={:radius_xs} on_tap={on_tap_handler}>
      <Row fill_width={true} gap={14} align={:center}>
        <Box width={64} height={64} corner_radius={40} background={0xFFE8F6EE}>
          <Image src={item.photo} width={64} height={64} content_mode={:fill} />
        </Box>
        <Spacer size={8} />
        <Column padding_top={:space_xs}>
          <Row fill_width={true}>
            <Text text={item.title} text_size={:md} font_weight="medium" weight={1} />
            <Text text={format_money(item.amount)} text_size={:sm} font_weight="medium" />
          </Row>
          <Row fill_width={true}>
            <Text text={item.category} text_size={:xs} text_color={:muted} max_lines={1} weight={1} />
            <Text text={to_string(item.date)} text_size={:xs} text_color={:muted} />
          </Row>
        </Column>
      </Row>
    </Box>
    """
  end

  defp format_money(n) when is_integer(n) do
    amount =
      n
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/.{3}(?=.)/, "\\0,")
      |> String.reverse()

    "Ksh. #{amount}"
  end
end
