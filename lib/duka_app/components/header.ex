defmodule DukaApp.Components.Header do
  @moduledoc """
  Screen header: a small muted kicker over a large title, left-aligned, with
  optional square icon buttons for going back and for one action on the right.

  Props: `title`, `kicker` (small line above the title), `subtitle` (small
  line below it), `show_back`, and `actions`: the right-hand buttons as
  `{icon, accessibility_label, tag}`, e.g. `{"settings", "Settings",
  :open_settings}`. Taps arrive as `{:tap, :header_back}` and `{:tap, tag}`.
  """

  import Mob.Sigil

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    title = Map.get(props, :title)
    kicker = Map.get(props, :kicker)
    subtitle = Map.get(props, :subtitle)
    show_back = Map.get(props, :show_back, false)

    actions =
      props
      |> Map.get(:actions, [])
      |> Enum.map(fn {icon, label, tag} -> icon_button(icon, label, {self(), tag}) end)
      |> Enum.intersperse(~MOB(<Spacer size={8} />))

    ~MOB"""
    <Row
      fill_width={true}
      align={:top}
      padding_top={12}
      padding_left={22}
      padding_right={22}
      padding_bottom={14}
    >
      {if show_back, do: back_button()}
      <Column weight={1}>
        <Text
          :if={present?(kicker)}
          text={kicker}
          text_size={13}
          text_color={:muted}
          font_weight="medium"
        />
        <Text
          text={title}
          text_size={26}
          font_weight="bold"
          letter_spacing={-1}
          text_color={:on_background}
          max_lines={2}
        />
        <Text :if={present?(subtitle)} text={subtitle} text_size={13} text_color={:muted} />
      </Column>
      {actions}
    </Row>
    """
  end

  defp back_button do
    ~MOB"""
    <Row>
      {icon_button("back", "Back", {self(), :header_back})}
      <Spacer size={12} />
    </Row>
    """
  end

  @doc "A 40×40 bordered square holding one icon, as used in the header."
  @spec icon_button(String.t(), String.t(), term()) :: map()
  def icon_button(icon, label, on_tap) do
    ~MOB"""
    <Box
      width={40}
      height={40}
      corner_radius={14}
      background={:surface}
      border_color={:border}
      border_width={1}
      align={:center}
      on_tap={on_tap}
      accessibility_label={label}
      accessibility_role={:button}
    >
      <Icon name={icon} text_size={18} text_color={:on_surface} />
    </Box>
    """
  end

  defp present?(text), do: is_binary(text) and text != ""
end
