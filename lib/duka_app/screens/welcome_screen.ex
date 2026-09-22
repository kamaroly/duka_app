defmodule DukaApp.Screens.WelcomeScreen do
  use Mob.Screen

  @items [
    %{
      id: 1,
      title: "Food",
      category: "Grocery",
      detail: "Imtiaz Stores · Meezan Bank · Groceries",
      amount: 10_000,
      icon: "🍔",
      filter: :food
    },
    %{
      id: 2,
      title: "Groceries",
      category: "POS Transaction at SHOP STOP KARACHI PK",
      detail: "SHOP STOP KARACHI PK · NayaPay · Other",
      amount: 1_180,
      icon: "🛒",
      filter: :food
    },
    %{
      id: 3,
      title: "Groceries",
      category: "POS Transaction at SHOP STOP KARACHI PK",
      detail: "SHOP STOP KARACHI PK · NayaPay · Other",
      amount: 901,
      icon: "🛒",
      filter: :food
    }
  ]

  @impl Mob.Screen
  def mount(_, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :items, @items)}
  end

  @impl Mob.Screen
  def render(_assigns) do
    # Event handlers for the two buttons
    inventory_button_tap = {self(), :goto_inventory}
    profile_button_tap = {self(), :goto_profile}
    today_screen_button = {self(), :today_screen}

    ~MOB"""
    <Column padding={16} background={:white}>
      <Text text="Welcome Screen" text_size={:xl} text_color={:primary} padding={:space_sm} />
      <Spacer size={16} />
      <Button
        text="Inventory"
        text_color={:on_primary}
        text_size={:lg}
        padding={:xs}
        on_tap={inventory_button_tap}
      />
      <Spacer size={16} />
      <Button
        text="Profile"
        text_color={:on_primary}
        text_size={:lg}
        on_tap={profile_button_tap}
        padding={:xs}
      />
      <Spacer size={16} />
      <Button
        text="Expenses"
        text_color={:on_primary}
        text_size={:lg}
        on_tap={{self(), :goto_expenses}}
        padding={:xs}
      />
      <Spacer size={16} />
      <Button
        text="Scan Receipt"
        text_color={:on_primary}
        text_size={:lg}
        on_tap={{self(), :scan_receipt}}
        padding={:xs}
      />
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:tap, :goto_inventory}, socket) do
    # Navigate to the Inventory Screen
    {:noreply, Mob.Socket.push_screen(socket, DukaApp.Screens.InventoryScreen)}
  end

  @impl Mob.Screen
  def handle_info({:tap, :goto_profile}, socket) do
    # Navigate to the Profile Screen
    {:noreply, Mob.Socket.push_screen(socket, DukaApp.Screens.ProfileScreen)}
  end

  @impl Mob.Screen
  def handle_info({:tap, "go-to-item-" <> id}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, DukaApp.Screens.ItemDetailScreen, %{item_id: id})}
  end

  @impl Mob.Screen
  def handle_info({:tap, :goto_expenses}, socket) do
    {:noreply, Mob.Socket.push_screen(socket, DukaApp.Screens.ExpensesScreen)}
  end

  @impl Mob.Screen
  def handle_info({:tap, :scan_receipt}, socket) do
    {:ok, MobScanner.scan(socket)}
  end

  @impl Mob.Screen
  def handle_info({:scan, :result, %{type: type, value: value}}, socket) do
    # type: :qr | :ean | :upc | etc.
    {:noreply, Mob.Socket.assign(socket, :scanned, value)}
  end

  @impl Mob.Screen
  def handle_info({:scan, :cancelled}, socket) do
    {:noreply, socket}
  end
end
