defmodule DukaApp.Components.ActionButton do
  @moduledoc """
  A compact icon-and-label button, 44 high with small padding, in place of
  Material's roomy `Button`.

      ActionButton.button("check", "Save receipt", :save)
      ActionButton.button("trash", "Delete", :delete_receipt, style: :danger, weight: 1)

  Styles: `:primary` (ink, the default), `:secondary` (bordered surface) and
  `:danger`. It spans the width unless given a `weight` to share a row;
  `enabled: false` greys it out and ignores taps. Taps arrive as
  `{:tap, tag}`.
  """

  import Mob.Sigil

  @spec button(String.t(), String.t(), term(), keyword()) :: map()
  def button(icon, label, tag, opts \\ []) do
    {background, content, border} = colors(Keyword.get(opts, :style, :primary))
    enabled = Keyword.get(opts, :enabled, true)
    weight = Keyword.get(opts, :weight)

    node = ~MOB"""
    <Box
      height={44}
      background={background}
      border_color={border}
      border_width={1}
      corner_radius={14}
      padding_left={14}
      padding_right={14}
      align={:center}
      on_tap={{self(), tag}}
      disabled={not enabled}
      accessibility_label={label}
      accessibility_role={:button}
    >
      <Row align={:center}>
        <Icon name={icon} text_size={18} text_color={if(enabled, do: content, else: :muted)} />
        <Spacer size={6} />
        <Text
          text={label}
          text_size={14}
          font_weight="semibold"
          text_color={if(enabled, do: content, else: :muted)}
          max_lines={1}
        />
      </Row>
    </Box>
    """

    # A Box fills its row on Android unless it is given a width or a weight.
    case weight do
      nil -> node
      weight -> %{node | props: Map.put(node.props, :weight, weight)}
    end
  end

  defp colors(:primary), do: {:primary, :on_primary, :primary}
  defp colors(:secondary), do: {:surface, :on_surface, :border}
  defp colors(:danger), do: {:error, :on_error, :error}
end
