defmodule DukaApp.Components.ExpenseDetailSheet do
  import Mob.Sigil

  def expand(props, _children, _ctx) do
    item = Map.get(props, :item)

    ~MOB"""
    <Sheet
      id={item.id}
      detents={[:content]}
      background={:white}
      corner_radius={28}
      scrim={0x99000000}
      on_dismiss={{self(), :sheet_dismissed}}
    >
      <Column fill_width={true} padding={20} gap={16}>
        <Box width={36} height={4} corner_radius={2} background={0xFFE2E8E4} align={:center} />
        <Row fill_width={true} gap={14} align={:center}>
          <Box width={64} height={64} corner_radius={16} background={0xFFE8F6EE}>
            <Image src={item.photo} width={64} height={64} content_mode={:fill} />
          </Box>
          <Spacer size={8} />
          <Column gap={4} weight={1}>
            <Text
              text={item.title}
              text_size={:xl}
              font_weight="medium"
              text_color={:primary}
              max_lines={1}
              fill_width={true}
            />
            <Box
              background={:secondary}
              corner_radius={12}
              padding={6}
              padding_left={10}
              padding_right={10}
              fill_width={false}
            >
              <Text
                text={one_line(item.category)}
                text_size={:xs}
                text_color={:white}
                max_lines={1}
              />
            </Box>
          </Column>
        </Row>
        <Spacer size={16} />
        <Box background={:stone_100} corner_radius={4} padding={8} fill_width={true}>
          <Column gap={4} fill_width={true}>
            <Text text="Amount" text_size={:xs} text_color={:stone_500} />
            <Text
              text={"Ksh. #{format_money(item.amount)}"}
              text_size={:xl}
              text_color={:stone_900}
            />
          </Column>
        </Box>
        <Column gap={0} fill_width={true}>
          {detail_row("Date", format_expense_date(item.date))}
          {detail_row("Merchant / detail", one_line(item.detail))}
          {detail_row("Category", one_line(item.category))}
          {detail_row("Type", type_label(item.filter))}
        </Column>
        <Button
          text="Close"
          on_tap={{self(), :sheet_dismissed}}
          fill_width={true}
          text_color={:on_secondary}
          text_size={:lg}
          padding={:xs}
        />
      </Column>
    </Sheet>
    """
  end

  defp detail_row(label, value) do
    ~MOB"""
    <Row fill_width={true} padding_top={12} padding_bottom={12} align={:center}>
      <Column gap={2} weight={1}>
        <Text text={label} text_size={:xs} text_color={:muted} />
        <Text text={value} text_size={:sm} max_lines={2} fill_width={true} />
      </Column>
    </Row>
    """
  end

  defp format_expense_date(%Date{} = date) do
    Calendar.strftime(date, "%a, %b %d, %Y")
  end

  defp format_expense_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%a, %b %d, %Y")
  end

  defp format_expense_date(date) when is_binary(date), do: date
  defp format_expense_date(_), do: "—"

  defp one_line(nil), do: "—"

  defp one_line(text) when is_binary(text) do
    text |> String.replace(~r/\s+/, " ") |> String.trim()
  end

  defp type_label(:food), do: "Food"
  defp type_label(:bills), do: "Bills"
  defp type_label(:subscription), do: "Subscription"
  defp type_label(_), do: "Other"

  defp format_money(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end
end
