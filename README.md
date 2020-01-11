# jddf-elixir [![][hex-badge]][hex-url] [![][ci-badge]][ci-url]

> Documentation on Hexdocs: https://hexdocs.pm/jddf

This package is an Elixir implementation of **JSON Data Definition Format**. You
can use this package to:

1. Validate input data against a schema,
2. Get a list of validation errors from that input data, or
3. Build your own tooling on top of JSON Data Definition Format

[hex-badge]: https://img.shields.io/hexpm/v/jddf
[ci-badge]: https://github.com/jddf/jddf-elixir/workflows/Elixir%20CI/badge.svg?branch=master
[hex-url]: https://hex.pm/packages/jddf
[ci-url]: https://github.com/jddf/jddf-elixir/actions

## Installation

Add JDDF to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:jddf, "~> 0.1.0"}
  ]
end
```

Then update your dependencies:

```bash
mix deps.get
```

## Usage

See [the docs](https://hexdocs.pm/jddf) for more detailed usage, but at a high
level, here's how you parse schemas and validate input data against them:

```elixir

schema = JDDF.Schema.from_json!(%{
  "properties" => %{
    "name" => %{"type" => "string"},
    "age" => %{"type" => "uint32"},
    "phones" => %{
      "elements" => %{"type" => "string"},
    },
  },
})

validator = %JDDF.Validator{}

# To keep this example simple, we'll construct this data by hand. But you
# could also parse this data from JSON.
#
# This input data is perfect. It satisfies all the schema requirements.
errors_ok = JDDF.Validator.validate!(validator, schema, %{
  "name" => "John Doe",
  "age" => 42,
  "phones" => [
    "+44 1234567",
    "+44 2345678",
  ],
})

IO.inspect(errors_ok)
# Outputs: []

# This input data has problems. "name" is missing, "age" has the wrong type,
# and "phones[1]" has the wrong type.
#
# To make the output predictable for this example, we'll sort the errors. You
# don't have to do this in your applications.
errors_bad = Enum.sort(JDDF.Validator.validate!(validator, schema, %{
  "age" => "42",
  "phones" => [
    "+44 1234567",
    442345678,
  ],
}))

IO.inspect(length(errors_bad)) # 3

[e1, e2, e3] = errors_bad

IO.inspect(e1)
# Outputs: %JDDF.Validator.ValidationError{instance_path: [], schema_path: ["properties", "name"]}
#
# This error indicates that the root is missing "name"

IO.inspect(e2)
# Outputs: %JDDF.Validator.ValidationError{instance_path: ["age"], schema_path: ["properties", "age", "type"]}
#
# This error indicates that "age" has the wrong type

IO.inspect(e3)
# Outputs: %JDDF.Validator.ValidationError{instance_path: ["phones", "1"], schema_path: ["properties", "phones", "elements", "type"]}
#
# This error indicates that "phones[1]" has the wrong type
```
