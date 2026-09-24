defmodule DukaApp.Components.SearchField do
  @moduledoc "Search box for filtering a list; `on_change` gets the typed text."

  import Mob.Sigil

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    query = Map.get(props, :query)
    on_change = Map.get(props, :on_change)
    placeholder = Map.get(props, :placeholder, "Search receipts")

    ~MOB"""
    <Box
      background={:surface}
      border_color={:border}
      border_width={1}
      corner_radius={16}
      padding_left={14}
      padding_right={6}
      fill_width={true}
    >
      <Row fill_width={true} align={:center}>
        <Icon name="search" text_size={16} text_color={:muted} />
        <Spacer size={4} />
        <TextField
          value={query}
          placeholder={placeholder}
          on_change={on_change}
          weight={1}
          variant={:bare}
          background={:transparent}
          padding={0}
          return_key={:search}
        />
      </Row>
    </Box>
    """
  end
end
