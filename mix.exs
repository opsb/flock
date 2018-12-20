defmodule Flock.MixProject do
  use Mix.Project

  def project do
    [
      app: :flock,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Flock.CLI],
      dialyzer: [
        plt_add_apps: [:mix],
        ignore_warnings: "dialyzer.ignore-warnings",
        flags: [
          :error_handling,
          :race_conditions,
          :underspecs,
          :no_unused,
          :unmatched_returns
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Flock, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:typed_struct, "~> 0.1.4"},
      {:poison, "~> 3.1"},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false},
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false}
    ]
  end
end
