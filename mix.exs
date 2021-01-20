defmodule NervesHubFwup.MixProject do
  use Mix.Project

  def project do
    [
      app: :nerves_hub_fwup,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
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
      {:fwup, "~> 0.4.0"},
      {:plug_cowboy, "~> 2.0", only: :test}
    ]
  end
end
