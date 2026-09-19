defmodule DukaApp.Screens.ExpensesScreen do
  use Mob.Screen

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column padding={8} background={:white}>

      <Scroll gap={8} backgroud={:white}>
        <Box
          :for={item <- @items}
          id={item.id}
          background={:white}
          padding={:space_xs}
          corner_radius={:radius_xs}
          on_tap={{self(), "item-#{item.id}"}}
        >
          <Column padding_top={:space_xs}>
            <Row fill_width={true}>
              <Text text={item.title} text_size={:md} weight={1} font_weight={:medium} />
              <Text text={format_money(item.amount)} text_size={:md} font_weight={:medium} />
            </Row>
            <Row fill_width={true}>
              <Text
                text={item.category}
                text_size={:xs}
                text_color={:muted}
                max_lines={1}
                weight={1}
              />
              <Text text={"Yesterday"} text_size={:xs} text_color={:muted} />
            </Row>
          </Column>
        </Box>
      </Scroll>
      <Column padding={:space_md}>
        <Text text="Main content" />
        <Sheet
          :if={@show_sheet and @selected_item != nil}
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
                <Image src={@selected_item.photo} width={64} height={64} content_mode={:fill} />
              </Box>
              <Spacer size={8} />
              <Column gap={4} weight={1}>
                <Text
                  text={@selected_item.title}
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
                    text={one_line(@selected_item.category)}
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
                  text={"Ksh. #{format_money(@selected_item.amount)}"}
                  text_size={:xl}
                  text_color={:stone_900}
                />
              </Column>
            </Box>
            <Column gap={0} fill_width={true}>
              {detail_row("Date", format_expense_date(@selected_item.date))}
              {detail_row("Merchant / detail", one_line(@selected_item.detail))}
              {detail_row("Category", one_line(@selected_item.category))}
              {detail_row("Type", type_label(@selected_item.filter))}
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
      </Column>
    </Column>
    """
  end

  @impl Mob.Screen
  def mount(params, session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(query: "")
     |> Mob.Socket.assign(show_sheet: false)
     |> Mob.Socket.assign(items: get_items())
     |> Mob.Socket.assign(selected_item: false)}
  end

  @impl Mob.Screen
  def handle_info({:tap, "item-" <> id}, socket) do

    selected_item =
      get_items()
      |> Enum.filter(&(&1.id == String.to_integer(id)))
      |> List.first()



    {:noreply,
     socket
     |> Mob.Socket.assign(selected_item: selected_item)
     |> Mob.Socket.assign(show_sheet: true)}
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

  defp get_items do
    [
      %{
        id: 1,
        title: "Food",
        category: "Grocery",
        detail: "Imtiaz Stores · Meezan Bank · Groceries",
        amount: 10_000,
        icon: "🍔",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=200&h=200&fit=crop",
        date: ~D[2026-05-17]
      },
      %{
        id: 2,
        title: "Groceries",
        category: "POS Transaction at SHOP STOP KARACHI PK",
        detail: "SHOP STOP KARACHI PK · NayaPay · Other",
        amount: 1_180,
        icon: "🛒",
        filter: :food,
        photo: "https://images.unsplash.com/photo-1542838132-92c53300491e?w=200&h=200&fit=crop",
        date: ~D[2026-05-13]
      },
      %{
        id: 3,
        title: "Groceries",
        category: "POS Transaction at SHOP STOP KARACHI PK",
        detail: "SHOP STOP KARACHI PK · NayaPay · Other",
        amount: 901,
        icon: "🛒",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1583258292688-d0213dc5a3a8?w=200&h=200&fit=crop",
        date: ~D[2026-05-12]
      },
      %{
        id: 4,
        title: "Electricity",
        category: "K-Electric bill",
        detail: "K-Electric · Bank Alfalah · Bills",
        amount: 8_450,
        icon: "💡",
        filter: :bills,
        photo:
          "https://images.unsplash.com/photo-1473341304170-971dccb5ac1e?w=200&h=200&fit=crop",
        date: ~D[2026-05-11]
      },
      %{
        id: 5,
        title: "Internet",
        category: "PTCL Fiber monthly",
        detail: "PTCL · JazzCash · Bills",
        amount: 3_200,
        icon: "🌐",
        filter: :bills,
        photo: "https://images.unsplash.com/photo-1544197150-b99a5804f8b0?w=200&h=200&fit=crop",
        date: ~D[2026-05-10]
      },
      %{
        id: 6,
        title: "Netflix",
        category: "Streaming subscription",
        detail: "Netflix · Visa · Subscription",
        amount: 1_750,
        icon: "🎬",
        filter: :subscription,
        photo:
          "https://images.unsplash.com/photo-1574375927938-d5a98e8ffe85?w=200&h=200&fit=crop",
        date: ~D[2026-05-09]
      },
      %{
        id: 7,
        title: "Spotify",
        category: "Music Premium",
        detail: "Spotify · Mastercard · Subscription",
        amount: 599,
        icon: "🎵",
        filter: :subscription,
        photo:
          "https://images.unsplash.com/photo-1614680376573-df3480f0c6ff?w=200&h=200&fit=crop",
        date: ~D[2026-05-09]
      },
      %{
        id: 8,
        title: "Coffee",
        category: "Espresso at Gloria Jean's",
        detail: "Gloria Jean's · Meezan Bank · Food",
        amount: 850,
        icon: "☕",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=200&h=200&fit=crop",
        date: ~D[2026-05-08]
      },
      %{
        id: 9,
        title: "Fuel",
        category: "PSO Clifton pump",
        detail: "PSO · HBL · Transport",
        amount: 6_500,
        icon: "⛽",
        filter: :bills,
        photo:
          "https://images.unsplash.com/photo-1527018601619-a508a2be00cd?w=200&h=200&fit=crop",
        date: ~D[2026-05-08]
      },
      %{
        id: 10,
        title: "Pharmacy",
        category: "Medicines at D.Watson",
        detail: "D.Watson · JazzCash · Health",
        amount: 2_340,
        icon: "💊",
        filter: :bills,
        photo:
          "https://images.unsplash.com/photo-1584308666744-24d5c474f2ae?w=200&h=200&fit=crop",
        date: ~D[2026-05-07]
      },
      %{
        id: 11,
        title: "Lunch",
        category: "Biryani at Student Biryani",
        detail: "Student Biryani · NayaPay · Food",
        amount: 780,
        icon: "🍛",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1589302168068-964664d93dc0?w=200&h=200&fit=crop",
        date: ~D[2026-05-07]
      },
      %{
        id: 12,
        title: "Uber",
        category: "Ride to DHA Phase 6",
        detail: "Uber · Visa · Transport",
        amount: 640,
        icon: "🚗",
        filter: :bills,
        photo:
          "https://images.unsplash.com/photo-1449965408869-eaa3f722e40d?w=200&h=200&fit=crop",
        date: ~D[2026-05-06]
      },
      %{
        id: 13,
        title: "YouTube Premium",
        category: "Family plan",
        detail: "Google · Mastercard · Subscription",
        amount: 1_150,
        icon: "▶️",
        filter: :subscription,
        photo:
          "https://images.unsplash.com/photo-1611162616475-46b635cb6868?w=200&h=200&fit=crop",
        date: ~D[2026-05-06]
      },
      %{
        id: 14,
        title: "Water bill",
        category: "KW&SB monthly",
        detail: "KW&SB · Bank Alfalah · Bills",
        amount: 1_890,
        icon: "💧",
        filter: :bills,
        photo: "https://images.unsplash.com/photo-1548839140-29a749e1cf4d?w=200&h=200&fit=crop",
        date: ~D[2026-05-05]
      },
      %{
        id: 15,
        title: "Bakery",
        category: "Bread & pastry at Delizia",
        detail: "Delizia · Meezan Bank · Groceries",
        amount: 1_420,
        icon: "🥐",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1509440159596-0249088772ff?w=200&h=200&fit=crop",
        date: ~D[2026-05-05]
      },
      %{
        id: 16,
        title: "Gym",
        category: "Fitness First membership",
        detail: "Fitness First · HBL · Subscription",
        amount: 4_500,
        icon: "🏋️",
        filter: :subscription,
        photo:
          "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=200&h=200&fit=crop",
        date: ~D[2026-05-04]
      },
      %{
        id: 17,
        title: "Dinner",
        category: "BBQ Tonight",
        detail: "BBQ Tonight · Visa · Food",
        amount: 5_600,
        icon: "🍖",
        filter: :food,
        photo: "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=200&h=200&fit=crop",
        date: ~D[2026-05-03]
      },
      %{
        id: 18,
        title: "Mobile load",
        category: "Jazz prepaid recharge",
        detail: "Jazz · JazzCash · Bills",
        amount: 1_000,
        icon: "📱",
        filter: :bills,
        photo:
          "https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=200&h=200&fit=crop",
        date: ~D[2026-05-03]
      },
      %{
        id: 19,
        title: "iCloud+",
        category: "200 GB storage",
        detail: "Apple · Mastercard · Subscription",
        amount: 890,
        icon: "☁️",
        filter: :subscription,
        photo:
          "https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=200&h=200&fit=crop",
        date: ~D[2026-05-02]
      },
      %{
        id: 20,
        title: "Fruit",
        category: "Sunday bazaar fruit",
        detail: "Sunday Bazaar · Cash · Groceries",
        amount: 1_650,
        icon: "🍎",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1619566636858-adf3ef46400b?w=200&h=200&fit=crop",
        date: ~D[2026-05-02]
      },
      %{
        id: 21,
        title: "Parking",
        category: "Dolmen Mall parking",
        detail: "Dolmen Mall · NayaPay · Other",
        amount: 200,
        icon: "🅿️",
        filter: :bills,
        photo:
          "https://images.unsplash.com/photo-1506521781263-d8422e82f27a?w=200&h=200&fit=crop",
        date: ~D[2026-05-01]
      },
      %{
        id: 22,
        title: "Pizza",
        category: "Pizza Hut large",
        detail: "Pizza Hut · Visa · Food",
        amount: 2_899,
        icon: "🍕",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=200&h=200&fit=crop",
        date: ~D[2026-05-01]
      },
      %{
        id: 23,
        title: "ChatGPT Plus",
        category: "OpenAI monthly",
        detail: "OpenAI · Mastercard · Subscription",
        amount: 5_600,
        icon: "🤖",
        filter: :subscription,
        photo:
          "https://images.unsplash.com/photo-1677442136019-21780ecad995?w=200&h=200&fit=crop",
        date: ~D[2026-04-30]
      },
      %{
        id: 24,
        title: "School fees",
        category: "Term 2 tuition",
        detail: "Beaconhouse · HBL · Bills",
        amount: 28_000,
        icon: "🎓",
        filter: :bills,
        photo:
          "https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=200&h=200&fit=crop",
        date: ~D[2026-04-29]
      },
      %{
        id: 25,
        title: "Ice cream",
        category: "Baskin Robbins",
        detail: "Baskin Robbins · JazzCash · Food",
        amount: 690,
        icon: "🍦",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1497034825429-c343d7c6a68f?w=200&h=200&fit=crop",
        date: ~D[2026-04-28]
      },
      %{
        id: 26,
        title: "Gas bill",
        category: "SSGC monthly",
        detail: "SSGC · Bank Alfalah · Bills",
        amount: 4_120,
        icon: "🔥",
        filter: :bills,
        photo:
          "https://images.unsplash.com/photo-1581094794329-adc7dba0d0c1?w=200&h=200&fit=crop",
        date: ~D[2026-04-28]
      },
      %{
        id: 27,
        title: "Canva Pro",
        category: "Design subscription",
        detail: "Canva · Visa · Subscription",
        amount: 3_400,
        icon: "🎨",
        filter: :subscription,
        photo: "https://images.unsplash.com/photo-1561070791-2526d30994b5?w=200&h=200&fit=crop",
        date: ~D[2026-04-27]
      },
      %{
        id: 28,
        title: "Vegetables",
        category: "Naheed Super Market",
        detail: "Naheed · Meezan Bank · Groceries",
        amount: 2_110,
        icon: "🥬",
        filter: :food,
        photo:
          "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=200&h=200&fit=crop",
        date: ~D[2026-04-26]
      }
    ]
  end
end
