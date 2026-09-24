defmodule DukaApp.Components.FormField do
  @moduledoc """
  A text input with a visible label above it, an example in the placeholder and
  the validation error (if any) below.

  The label is a real `Text` node because `TextField`'s own `label` prop is not
  a native prop on either platform, so it is silently dropped.

      FormField.field(
        label: "Amount (Ksh)",
        key: :amount,
        value: @amount,
        placeholder: "e.g. 1,250.50",
        keyboard: :decimal,
        error: @errors[:amount]
      )

  `on_change` fires as `{:change, key, value}` in the screen. Pass
  `submit: tag` to also get `{:submit, tag}` when the keyboard's return key is
  pressed.
  """

  import Mob.Sigil

  @spec field(keyword()) :: map()
  def field(opts) do
    label = Keyword.fetch!(opts, :label)
    key = Keyword.fetch!(opts, :key)
    value = Keyword.get(opts, :value) || ""
    placeholder = Keyword.get(opts, :placeholder, "")
    keyboard = Keyword.get(opts, :keyboard, :default)
    hint = Keyword.get(opts, :hint)
    error = Keyword.get(opts, :error)

    ~MOB"""
    <Column gap={4} fill_width={true}>
      <Text text={label} text_size={:sm} font_weight="medium" text_color={:on_background} />
      <TextField
        value={value}
        placeholder={placeholder}
        variant={:outlined}
        keyboard={keyboard}
        on_change={{self(), key}}
        fill_width={true}
      />
      <Text :if={hint && !error} text={hint} text_size={:xs} text_color={:muted} />
      <Text :if={error} text={error} text_size={:xs} text_color={:error} />
    </Column>
    """
    |> put_submit(Keyword.get(opts, :submit))
  end

  defp put_submit(node, nil), do: node

  defp put_submit(%{children: children} = node, tag) do
    children =
      Enum.map(children, fn
        %{type: :text_field, props: props} = input ->
          %{input | props: Map.put(props, :on_submit, {self(), tag})}

        other ->
          other
      end)

    %{node | children: children}
  end
end
