defmodule XQLite.MixProject do
  use Mix.Project

  def project do
    [
      app: :xqlite,
      version: "0.1.0",
      elixir: "~> 1.17",
      compilers: [:elixir_make | Mix.compilers()],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:benchee, "~> 1.3", only: :bench},
      {:exqlite, "~> 0.20", only: :bench},
      {:sqlite, "~> 2.0", only: :bench},
      {:esqlite, "~> 0.8.8", only: :bench},
      {:elixir_make, "~> 0.8", runtime: false}
    ]
  end
end
