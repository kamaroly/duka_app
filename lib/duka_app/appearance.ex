defmodule DukaApp.Appearance do
  @moduledoc """
  Light / dark / follow-the-system theme choice.

  The choice belongs to the phone, not to a profile, so it is stored in
  `Mob.State` and applies on the phone-number screen too.

  `Mob.Theme.AdaptiveWatcher` re-applies its registered "adaptive" theme
  whenever the OS appearance flips. Registering the user's choice there (rather
  than always `DukaApp.Theme.Adaptive`) keeps an explicit Light or Dark choice from
  being overridden when the OS switches.
  """

  alias Mob.Theme.AdaptiveWatcher

  @modes [:system, :light, :dark]
  @key :appearance

  @type mode :: :system | :light | :dark

  @spec modes() :: [mode()]
  def modes, do: @modes

  @doc "The saved choice, `:system` until the user picks one."
  @spec current() :: mode()
  def current do
    case Mob.State.get(@key, :system) do
      mode when mode in @modes -> mode
      _ -> :system
    end
  end

  @doc "Saves `mode` and applies it immediately."
  @spec choose(mode()) :: :ok
  def choose(mode) when mode in @modes do
    :ok = Mob.State.put(@key, mode)
    apply_mode(mode)
  end

  @doc "Applies the saved choice. Called once at boot."
  @spec apply_saved() :: :ok
  def apply_saved, do: apply_mode(current())

  @spec label(mode()) :: String.t()
  def label(:system), do: "System"
  def label(:light), do: "Light"
  def label(:dark), do: "Dark"

  defp apply_mode(mode) do
    theme = theme_module(mode)
    AdaptiveWatcher.register_adaptive(theme)
    Mob.Theme.set(theme)
  end

  defp theme_module(:system), do: DukaApp.Theme.Adaptive
  defp theme_module(:light), do: DukaApp.Theme.Light
  defp theme_module(:dark), do: DukaApp.Theme.Dark
end
