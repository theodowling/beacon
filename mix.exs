defmodule Beacon.MixProject do
  use Mix.Project

  @version "0.1.0-dev"

  def project do
    [
      app: :beacon,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      name: "Beacon",
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix],
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true
      ]
    ]
  end

  def application do
    [
      mod: {Beacon.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: :dev, runtime: false},
      {:ecto_sql, "~> 3.6"},
      {:esbuild, "~> 0.4"},
      {:ex_doc, "~> 0.29", only: :docs},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.20"},
      {:heroicons, "~> 0.5"},
      {:jason, "~> 1.3"},
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_live_reload, "~> 1.3", only: :dev},
      {:phoenix_live_view, "~> 0.18.18"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_view, "~> 2.0", only: [:dev, :test]},
      {:plug_cowboy, "~> 2.6", only: [:dev, :test]},
      {:postgrex, "~> 0.16"},
      {:safe_code, github: "TheFirstAvenger/safe_code"},
      {:tailwind, "~> 0.2"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.setup.admin", "assets.build", "assets.build.admin", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      dev: "run --no-halt dev.exs",
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing --no-assets", "esbuild.install --if-missing", "cmd --cd assets npm install"],
      "assets.setup.admin": ["tailwind.install --if-missing", "esbuild.install --if-missing", "cmd --cd assets npm install"],
      "assets.build": ["esbuild cdn", "esbuild cdn_min"],
      "assets.build.admin": ["tailwind admin --minify", "cmd --cd assets node build_admin.js --deploy"]
    ]
  end

  defp docs do
    [
      main: "Beacon",
      source_ref: "v#{@version}",
      source_url: "https://github.com/BeaconCMS/beacon"
    ]
  end
end
