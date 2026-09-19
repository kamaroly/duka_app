defmodule DukaApp.Screens.InventoryScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Mob.Screen
  def render(_assigns) do
    go_back = {self(), :back}

    ~MOB"""
    <Column padding={:space_lg} background={:white} gap={16}>
      <Button text="Go Back" on_tap={go_back} text_size={:lg} padding={:xs} />
      <Text text="Inventory" text_size={:xl} text_color={:on_surface} padding={:space_sm} />
      <Button text="Go Back" on_tap={go_back} text_size={:lg} padding={:xs} />
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:tap, :back}, socket) do
    # Instruct the mobile app to go to the previous screen
    {:noreply, Mob.Socket.pop_screen(socket)}
  end
end
