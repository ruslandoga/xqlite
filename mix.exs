defmodule XQLite.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/ruslandoga/xqlite"

  def project do
    [
      app: :xqlite,
      version: @version,
      elixir: "~> 1.17",
      compilers: [:elixir_make | Mix.compilers()],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # dialyzer
      dialyzer: [
        plt_local_path: "plts",
        plt_core_path: "plts"
      ],
      # hex
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @repo_url}
      ],
      description: "SQLite NIFs",
      # docs
      name: "XQLite",
      docs: [
        main: "XQLite",
        source_url: @repo_url,
        source_ref: "v#{@version}"
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:benchee, "~> 1.3", only: :bench},
      {:elixir_make, "~> 0.8", runtime: false},
      {:stream_data, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.34", only: :docs},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
