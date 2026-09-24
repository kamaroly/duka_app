defmodule DukaApp.Components.Header do
  @moduledoc """
  Screen header: a small muted kicker over a large title, left-aligned, with
  optional square icon buttons for going back and for one action on the right.

  Props: `title`, `kicker` (small line above the title), `subtitle` (small
  line below it), `show_back`, `right_icon` (a Mob icon name such as
  `"settings"`) and `right_label` (its accessibility label). Taps arrive as
  `{:tap, :header_back}` and `{:tap, :header_right}`.
  """

  import Mob.Sigil

  @spec expand(map(), [map()], map()) :: map()
  def expand(props, _children, _ctx) do
    title = Map.get(props, :title)
    kicker = Map.get(props, :kicker)
    subtitle = Map.get(props, :subtitle)
    show_back = Map.get(props, :show_back, false)
    right_icon = Map.get(props, :right_icon)
    right_label = Map.get(props, :right_label, right_icon)

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
      {if right_icon, do: icon_button(right_icon, right_label, {self(), :header_right})}
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
