defmodule DukaApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :duka_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      deps: deps(),
      aliases: aliases(),
      erlc_paths: ["src"],
      erlc_options: [:debug_info],
      consolidate_protocols: Mix.env() != :dev,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {DukaApp.Application, []}]
  end

  defp deps do
    [
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:mob, "~> 0.9.3"},
      {:mob_dev, "~> 0.6", only: :dev, runtime: false},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.18"},
      # Device capabilities. Keep this list in step with `config :mob, :plugins`
      # in mob.exs. mob_scanner reads the receipt QR codes; it needs mob_camera
      # for the camera permission. mob_biometric backs the optional app lock.
      {:mob_camera, "~> 0.1"},
      {:mob_scanner, "~> 0.1"},
      {:mob_biometric, "~> 0.1"},
      # Local plugin: receipt photo processing + on-device OCR (ML Kit).
      {:mob_ocr, path: "plugins/mob_ocr"},
      {:mob_themes, "~> 0.1"},
      # Code quality — Credo + ex_slop (catches AI-generated patterns
      # like blanket rescue, narrator docs, redundant Enum chains, etc).
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.2", only: [:dev, :test], runtime: false}
    ]
  end

  # Shorthands for the common mob workflows — `mix deploy` is `mix mob.deploy`,
  # etc. Extra args pass through to the underlying task, so `mix deploy
  # --device <udid>` works as expected.
  defp aliases do
    [
      connect: ["mob.connect"],
      deploy: ["mob.deploy"],
      watch: ["mob.watch"],
      icon: ["mob.icon"],
      ios: ["mob.deploy --ios"],
      "ios.native": ["mob.deploy --native --ios"],
      android: ["mob.deploy --android"],
      "android.native": ["mob.deploy --native --android"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp elixirc_paths(:test),
    do: elixirc_paths(:dev) ++ ["test/support"]

  defp elixirc_paths(_),
    do: ["lib"]
end
