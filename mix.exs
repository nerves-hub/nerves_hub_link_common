defmodule NervesHubLinkCommon.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/nerves-hub/nerves_hub_link_common"

  def project do
    [
      app: :nerves_hub_link_common,
      version: @version,
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        credo: :test,
        docs: :docs,
        "hex.publish": :docs
      ],
      docs: docs(),
      description: description(),
      dialyzer: dialyzer(),
      package: package(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mint, "~> 1.2"},
      {:castore, "~> 0.1.0"},
      {:fwup, "~> 1.0"},
      {:ex_doc, "~> 0.18", only: :docs, runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:plug_cowboy, "~> 2.0", only: :test},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.2", only: :test, runtime: false}
    ]
  end

  defp description do
    "Common modules shared between nerves_hub_link and nerves_hub_link_http"
  end

  defp dialyzer() do
    [
      flags: [:race_conditions, :error_handling, :underspecs, :unmatched_returns],
      plt_add_apps: [],
      list_unused_filters: true
    ]
  end

  defp docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: [
        "lib",
        "CHANGELOG.md",
        "LICENSE",
        "mix.exs",
        "README.md"
      ]
    ]
  end
end
