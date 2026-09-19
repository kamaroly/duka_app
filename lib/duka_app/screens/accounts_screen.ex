defmodule DukaApp.Screens.AccountsScreen do
  use Mob.Screen

  def mount(_params, _session, socket) do
    # Hardcoded dummy state modeled exactly from the image snippet
    initial_state = %{
      net_worth: "$685,957.63",
      net_worth_change: "↑ $23,276.32 (3.5%) 1 month",
      selected_tab: :net_worth,
      selected_period: :one_month,
      cash_total: "$65,602.83",
      cash_change: "↑ $1,081.99 (1.7%) 1 month",
      cash_percentage: "7% of assets",
      accounts: [
        %{
          id: 1,
          name: "Melanie's Checking",
          type: "Checking",
          amount: "$15,483.62",
          updated: "9 hours ago",
          avatar: "Citi"
        },
        %{
          id: 2,
          name: "Joint Savings",
          type: "Savings",
          amount: "$50,119.21",
          updated: "9 hours ago",
          avatar: "Joint"
        }
      ]
    }

    {:ok, Mob.Socket.assign(socket, initial_state)}
  end

  def render(assigns) do
    %{
      type: :column,
      props: %{background: :white},
      children: [
        # 1. Custom Navigation Bar Top Area
        render_app_bar(assigns),

        # Screen Scrollable Container Body
        %{
          type: :scroll_view,
          props: %{padding: :space_md},
          children: [
            # 2. Segmented Horizontal Tab List
            render_tabs(assigns),

            # 3. Hero Net Worth Figures
            %{
              type: :column,
              props: %{padding_top: :space_md, gap: :space_xs},
              children: [
                %{
                  type: :text,
                  props: %{
                    text: assigns.net_worth,
                    text_size: :xxl,
                    weight: :bold,
                    text_color: :on_background
                  },
                  children: []
                },
                %{
                  type: :text,
                  props: %{text: assigns.net_worth_change, text_size: :sm, text_color: :success},
                  children: []
                }
              ]
            },

            # 4. Interactive Trend Graphic Visual Anchor (Canvas/Component placeholder)
            %{
              type: :container,
              props: %{height: 160, margin_vertical: :space_md, background: :surface_variant},
              children: [
                %{
                  type: :text,
                  props: %{
                    text: "[Line Chart Visual Representation]",
                    text_size: :sm,
                    text_color: :secondary
                  },
                  children: []
                }
              ]
            },

            # 5. Timeline Interval Filters
            render_timeline_filters(assigns),

            # 6. Asset Grouping Breakdown section (Cash Card Example)
            render_asset_section(assigns)
          ]
        }
      ]
    }
  end

  # --- Helper Layout Building Functions ---

  defp render_app_bar(_assigns) do
    %{
      type: :row,
      props: %{padding: :space_md, justify_content: :space_between, align_items: :center},
      children: [
        %{
          type: :icon_button,
          props: %{icon: :menu, on_tap: {self(), :toggle_menu}},
          children: []
        },
        %{type: :text, props: %{text: "Accounts", text_size: :lg, weight: :bold}, children: []},
        %{
          type: :row,
          props: %{gap: :space_sm},
          children: [
            %{
              type: :icon_button,
              props: %{icon: :more_horizontal, on_tap: {self(), :more_options}},
              children: []
            },
            %{
              type: :icon_button,
              props: %{icon: :plus, on_tap: {self(), :add_account}},
              children: []
            }
          ]
        }
      ]
    }
  end

  defp render_tabs(assigns) do
    %{
      type: :row,
      props: %{gap: :space_sm, scroll_horizontal: true},
      children:
        Enum.map(
          [
            {:net_worth, "NET WORTH"},
            {:cash, "CASH"},
            {:investments, "INVESTMENTS"},
            {:real_estate, "REAL ESTATE"}
          ],
          fn {key, label} ->
            is_selected = assigns.selected_tab == key

            %{
              type: :container,
              props: %{
                padding_horizontal: :space_md,
                padding_vertical: :space_xs,
                border_radius: :full,
                background: :transparent
              },
              children: [
                %{
                  type: :text,
                  props: %{
                    text: label,
                    text_size: :xs,
                    weight: :bold,
                    text_color: if(is_selected, do: :on_secondary_container, else: :outline)
                  },
                  children: []
                }
              ]
            }
          end
        )
    }
  end

  defp render_timeline_filters(assigns) do
    %{
      type: :row,
      props: %{justify_content: :space_between, padding_vertical: :space_sm},
      children:
        Enum.map(
          [
            {:one_month, "1M"},
            {:three_month, "3M"},
            {:six_month, "6M"},
            {:one_year, "1Y"},
            {:all, "ALL"}
          ],
          fn {key, label} ->
            is_active = assigns.selected_period == key

            %{
              type: :text,
              props: %{
                text: label,
                text_size: :sm,
                weight: :bold,
                text_color: if(is_active, do: :on_background, else: :outline)
              },
              children: []
            }
          end
        )
    }
  end

  defp render_asset_section(assigns) do
    %{
      type: :column,
      props: %{margin_top: :space_lg},
      children: [
        # Asset Group Header Row
        %{
          type: :row,
          props: %{justify_content: :space_between},
          children: [
            %{type: :text, props: %{text: "Cash", text_size: :md, weight: :bold}, children: []},
            %{
              type: :text,
              props: %{text: assigns.cash_total, text_size: :md, weight: :bold},
              children: []
            }
          ]
        },
        # Asset Group Stats Secondary Row
        %{
          type: :row,
          props: %{justify_content: :space_between, margin_bottom: :space_sm},
          children: [
            %{
              type: :text,
              props: %{text: assigns.cash_change, text_size: :xs, text_color: :success},
              children: []
            },
            %{
              type: :text,
              props: %{text: assigns.cash_percentage, text_size: :xs, text_color: :outline},
              children: []
            }
          ]
        },
        # Sub-Items Loop
        %{
          type: :column,
          props: %{gap: :space_sm},
          children: Enum.map(assigns.accounts, &render_account_item/1)
        }
      ]
    }
  end

  defp render_account_item(account) do
    %{
      type: :row,
      props: %{
        padding_vertical: :space_sm,
        align_items: :center,
        justify_content: :space_between
      },
      children: [
        # Left Side Row Layout Structure
        %{
          type: :row,
          props: %{gap: :space_md, align_items: :center},
          children: [
            %{
              type: :container,
              props: %{
                width: 36,
                height: 36,
                border_radius: :full,
                background: :primary,
                align_items: :center,
                justify_content: :center
              },
              children: [
                %{
                  type: :text,
                  props: %{
                    text: String.slice(account.avatar, 0..1),
                    text_color: :on_primary,
                    text_size: :xs
                  },
                  children: []
                }
              ]
            },
            %{
              type: :column,
              props: %{gap: :space_xs},
              children: [
                # FIX: Use :bold or remove custom weights if NIF type scaling fails
                %{
                  type: :text,
                  props: %{text: account.name, weight: :bold, text_size: :md},
                  children: []
                },
                %{
                  type: :text,
                  props: %{text: account.type, text_size: :xs, text_color: :muted},
                  children: []
                }
              ]
            }
          ]
        },
        # Right Side Data Layout Structure
        %{
          type: :column,
          props: %{align_items: :end, gap: :space_xs},
          children: [
            %{
              type: :text,
              props: %{text: account.amount, weight: :bold, text_size: :md},
              children: []
            },
            %{
              type: :text,
              props: %{text: account.updated, text_size: :xs, text_color: :muted},
              children: []
            }
          ]
        }
      ]
    }
  end

  # --- Interaction Event Handlers ---

  def handle_info({:tap, :toggle_menu}, socket), do: {:noreply, socket}
  def handle_info({:tap, :more_options}, socket), do: {:noreply, socket}
  def handle_info({:tap, :add_account}, socket), do: {:noreply, socket}
end
