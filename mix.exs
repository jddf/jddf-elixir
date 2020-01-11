defmodule JDDF.MixProject do
  use Mix.Project

  def project do
    [
      app: :jddf,
      version: "0.1.1",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end

  defp description() do
    """
    An Elixir implementation of JSON Data Definition Format.
    """
  end

  defp package() do
    [
      maintainers: ["Ulysse Carion"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jddf/jddf-elixir"}
    ]
  end

  defp docs() do
    [
      main: "readme",
      name: "JDDF",
      canonical: "http://hexdocs.pm/jddf",
      source_url: "https://github.com/jddf/jddf-elixir",
      extras: [
        "README.md"
      ]
    ]
  end
end
