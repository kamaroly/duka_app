defmodule DukaApp.Screens.TodayScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok,
     Mob.Socket.assign(socket,
       transunion: 761,
       equifax: 761,
       net_worth: 137_036,
       car_value: 12_450
     )}
  end

  @impl Mob.Screen
  def render(assigns) do
    net_worth_tap = {self(), :open_net_worth}
    credit_tap = {self(), {:tab, :credit}}
    loans_tap = {self(), :open_loans}
    home_tap = {self(), :open_home}
    notify_tap = {self(), :notify}
    menu_tap = {self(), :menu}

    ~MOB"""
    <Column fill_width={true} fill_height={true} background={:white}>
      <Scroll weight={1} fill_width={true}>
        <Column padding={20} gap={20} fill_width={true}>
          <Row fill_width={true} align={:center}>
            <Text text="Today" text_size={:xxl} font_weight="bold" />
            <Spacer />
            <Button
              text="Bell"
              on_tap={notify_tap}
              fill_width={false}
              background={:surface}
              text_color={:on_surface}
              padding={8}
              corner_radius={:radius_pill}
            />
            <Spacer size={8} />
            <Button
              text="Menu"
              on_tap={menu_tap}
              fill_width={false}
              background={:surface}
              text_color={:on_surface}
              padding={8}
              corner_radius={:radius_pill}
            />
          </Row>
          <Row fill_width={true} gap={12} align={:center}>
            {score_ring("TransUnion", assigns.transunion, "+2 pts · Excellent")}
            {score_ring("Equifax", assigns.equifax, "+2 pts · Excellent")}
          </Row>
          <Text text="Scores calculated using VantageScore 3.0" text_size={:xs} text_color={:muted} />
          <Column gap={12} fill_width={true}>
            <Row fill_width={true}>
              <Button
                text={"Net worth     $#{number(assigns.net_worth)}"}
                on_tap={net_worth_tap}
                background={:background}
                text_color={:on_surface}
                fill_width={true}
              />
            </Row>
            <Row fill_width={true}>
              <Text text="Car value (est)" />
              <Spacer />
              <Text text={"$#{number(assigns.car_value)}"} font_weight="medium" />
            </Row>
          </Column>
          <Text text="Take action" text_size={:lg} font_weight="bold" />
          <Row fill_width={true} gap={10}>
            {action_card("Net Worth", net_worth_tap, :primary)}
            {action_card("Credit cards", credit_tap, "#5B8DEF")}
            {action_card("Personal loans", loans_tap, "#7C5CBF")}
            {action_card("Home loans", home_tap, "#E8A87C")}
          </Row>
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp score_ring(bureau, score, caption) do
    ~MOB"""
    <Column weight={1} align={:center} gap={6}>
      <Box fill_width={true} padding={16} corner_radius={:radius_pill} background={:surface}>
        <Column align={:center} gap={2} fill_width={true}>
          <Text text={"#{score}"} text_size={:xxl} font_weight="bold" text_align="center" />
          <Text text={bureau} text_size={:sm} text_color={:muted} text_align="center" />
          <Text text={caption} text_size={:xs} text_color={:primary} text_align="center" />
        </Column>
      </Box>
    </Column>
    """
  end

  defp action_card(label, tap, bg) do
    ~MOB"""
    <Column weight={1} align={:center} gap={8}>
      <Button
        text="$"
        on_tap={tap}
        background={bg}
        text_color="#ffffff"
        fill_width={true}
        corner_radius={16}
        padding={20}
      />
      <Text text={label} text_size={:xs} text_align="center" max_lines={2} />
    </Column>
    """
  end

  defp number(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @impl true
  def handle_info({:tap, :open_net_worth}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, WealthApp.NetWorthScreen)}
  end

  def handle_info({:tap, :open_loans}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, WealthApp.NetWorthDetailScreen)}
  end

  def handle_info({:tap, :open_home}, socket), do: {:noreply, socket}

  def handle_info({:tap, :notify}, socket) do
    Mob.Alert.toast(socket, "No new alerts")
    {:noreply, socket}
  end

  def handle_info({:tap, :menu}, socket), do: {:noreply, socket}

  def handle_info({:tap, {:tab, tab}}, socket) do
    {:noreply, Mob.Socket.switch_tab(socket, tab)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
