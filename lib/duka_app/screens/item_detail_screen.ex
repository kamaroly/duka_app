defmodule DukaApp.Screens.ItemDetailScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(params, _session, socket) do
    item_id = Map.get(params, :item_id) |> to_string()
    {:ok, Mob.Socket.assign(socket, item_id: item_id)}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column padding={8} background={:white} gap={16}>
      <Button
        text="Go Back"
        on_tap={{self(), :back}}
        text_size={:lg}
        padding={:xs}
        ext_color={:primary}
      />
      <Spacer size={16} />
      <Text
        text={"You are viewing item #{@item_id}"}
        text_size={:xl}
        text_color={:primary}
        padding={:space_sm}
      />
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:tap, :back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end
end
