defmodule DukaApp.Screens.ExpensesScreen do
  use Mob.Screen

  @impl Mob.Screen
  def render(assigns) do
    search_change = {self(), :search_expenses}

    # rows =
    #   Enum.map(assigns.items, fn item ->
    #     tap = {self(), "item-#{item.id}"}
    #     ~MOB(<ExpenseItem item={item} id={item.id} on_tap={tap} />)
    #   end)

    ~MOB"""
    <Column padding={8} background={:white}>
        <TextField
          id="expense-search"
          value={@query}
          placeholder="Search"
          fill_width={true}
          background={0xFFFFFFFF}
          text_color={:on_surface}
          border_color={0xFFFFFFFF}
          padding={1}
          corner_radius={:radius_pill}
          on_change={search_change}
        />
      <List id={:expenses} items={@items} />
      <ExpenseDetailSheet
        item={@selected_item}
        :if={is_nil(@selected_item) == false}
        id={"details-of-item"}
      />
    </Column>
    """
  end

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Mob.Socket.assign(query: "")
     |> Mob.Socket.assign(selected_item: nil)
     |> Mob.Socket.assign(items: DukaApp.Data.expenses())
     |> Mob.List.put_renderer(:expenses, fn item ->
       DukaApp.Components.ExpenseItem.expand(
         %{
           item: item,
           id: item.id,
           on_tap: {self(), "item-#{item.id}"}
         },
         [],
         %{screen: self()}
       )
     end)}
  end

  @impl Mob.Screen
  def handle_info({:tap, "item-" <> id}, socket) do
    selected_item =
      DukaApp.Data.expenses()
      |> Enum.filter(&(&1.id == String.to_integer(id)))
      |> List.first()

    {:noreply, Mob.Socket.assign(socket, selected_item: selected_item)}
  end

  @impl Mob.Screen
  def handle_info({:change, :search_expenses, keyword}, socket) do
    q =
      keyword
      |> to_string()
      |> String.trim()
      |> String.downcase()

    items =
      if q == "" do
        DukaApp.Data.expenses()
      else
        Enum.filter(DukaApp.Data.expenses(), fn expense ->
          matches?(expense.title, q) or
            matches?(expense.detail, q) or
            matches?(expense.category, q)
        end)
      end

    {:noreply,
     socket
     |> Mob.Socket.assign(:query, keyword)
     |> Mob.Socket.assign(:items, items)}
  end

  defp matches?(nil, _q), do: false
  defp matches?(text, q), do: String.contains?(String.downcase(to_string(text)), q)

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
