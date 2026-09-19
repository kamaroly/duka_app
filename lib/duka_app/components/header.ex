defmodule DukaApp.Components.Header do
  @moduledoc """
  Reusable screen header for DukaApp (eTIMS Receipt Tracker).

  Provides a clean top bar with title, optional subtitle, optional back button,
  and an optional right-side action (notifications, search, or more).

  ## Usage

  Call `DukaApp.Components.Header.render/1` inside any screen's `render/1` function
  and place it at the top of a vertical `<Column>`.

  ### Basic example (no back button)

      def render(assigns) do
        ~MOB\"\"\"
        <Column background={:background} fill_height={true}>
          {DukaApp.Components.Header.render(
            title: "eTIMS Receipts",
            subtitle: "KRA Compliant",
            right_action: :notifications
          )}

          <Scroll weight={1} padding={:space_md}>
            <!-- your content -->
          </Scroll>

          {DukaApp.Components.TabBar.render(@active_tab)}
        </Column>
        \"\"\"
      end

  ### With back button (detail / pushed screens)

      {DukaApp.Components.Header.render(
        title: "Receipt Details",
        subtitle: "INV202505150789",
        show_back: true,
        right_action: :more
      )}

  ## Options

  | Key            | Type          | Required | Description                                      |
  |----------------|---------------|----------|--------------------------------------------------|
  | `:title`       | `String.t()`  | yes      | Main title text                                  |
  | `:subtitle`    | `String.t()`  | no       | Secondary text under the title                   |
  | `:show_back`   | `boolean()`   | no       | Shows a back button (‹). Defaults to `false`     |
  | `:right_action`| `atom()`      | no       | One of `:notifications`, `:search`, `:more`      |

  ## Handling events

  The header emits the following messages that you should handle in `handle_info/2`:

  * `{:tap, :header_back}` – user tapped the back button
    → normally call `Mob.Socket.pop_screen(socket)`

  * `{:tap, :header_right}` – user tapped the right action
    → open notifications, search, menu, etc.

  Example:

      def handle_info({:tap, :header_back}, socket) do
        {:noreply, Mob.Socket.pop_screen(socket)}
      end

      def handle_info({:tap, :header_right}, socket) do
        # your logic here
        {:noreply, socket}
      end
  """

  import Mob.Sigil

  @doc """
  Renders the header.

  See the module documentation for full usage examples and options.
  """
  def render(opts) do
    title = Keyword.fetch!(opts, :title)
    subtitle = Keyword.get(opts, :subtitle)
    show_back = Keyword.get(opts, :show_back, false)
    right_action = Keyword.get(opts, :right_action)

    back_tap = {self(), :header_back}
    right_tap = {self(), :header_right}

    ~MOB"""
    <Box
      background={:surface}
      padding_top={:space_md}
      padding_bottom={:space_sm}
      padding_left={:space_md}
      padding_right={:space_md}
    >
      <Row align={:center} gap={:space_sm}>
        <Button
          :if={show_back}
          text="‹"
          on_tap={back_tap}
          background={:transparent}
          text_color={:primary}
          text_size={:xl}
        />
        <Column weight={1} gap={2}>
          <Text text={title} text_size={:xl} weight={:bold} text_color={:on_surface} />
          <Text :if={subtitle} text={subtitle} text_size={:sm} text_color={:muted} />
        </Column>
        <Button
          :if={right_action == :notifications}
          text="🔔"
          on_tap={right_tap}
          background={:transparent}
          text_size={:xl}
        />
        <Button
          :if={right_action == :search}
          text="🔍"
          on_tap={right_tap}
          background={:transparent}
          text_size={:xl}
        />
        <Button
          :if={right_action == :more}
          text="⋯"
          on_tap={right_tap}
          background={:transparent}
          text_size={:xl}
        />
      </Row>
    </Box>
    """
  end
end
