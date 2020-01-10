defmodule JDDF do
  @moduledoc """
  An Elixir implementation of [JSON Data Definition Format](https://jddf.io), a
  schema language for JSON.

  You can use this module to parse JDDF schemas, and then validate JSON data
  against those schemas.

  `JDDF` doesn't parse JSON data. Instead, you should first parse JSON data, and
  then call `JDDF` with the parsed result. `JDDF` is compatible with the sort of
  data produced by [`Jason`](https://hexdocs.pm/jason) or
  [`Poison`](https://hexdocs.pm/poison). You can also just pass in ordinary
  Elixir data structures, as the examples here will demonstrate.

  ## Example

  For example, let's parse the following JDDF schema:

      {
        "properties": {
          "name": { "type": "string" },
          "age": { "type": "string" },
          "phones": {
            "elements": { "type": "string" }
          }
        }
      }

  And validate it against two inputs. The first passes all the validation rules:

      {
        "name": "John Doe",
        "age": 42,
        "phones": [
          "+44 1234567",
          "+44 2345678",
        ]
      }

  But the second does not:

      {
        "age": "42",
        "phones": [
          "+44 1234567",
          442345678,
        ]
      }

  With this second input, there are three problems:

    * `name` is missing
    * `age` has the wrong type
    * `phones[1]` has the wrong type

  Let's see an example of how we would parse the schema, and then validate the
  two inputs against it. We'll expect to get back no errors for the first input,
  and we expect three validation errors for the second input:

  > To keep things simple, we'll use Elixir data structures directly in these
  > examples. In real life, you'd probably parse this data using
  > [`Jason.decode!`](https://hexdocs.pm/jason/Jason.html#decode!/2) or
  > [`Poison.decode!`](https://github.com/devinus/poison#usage).

      iex> schema = JDDF.Schema.from_json!(%{
      ...>   "properties" => %{
      ...>     "name" => %{"type" => "string"},
      ...>     "age" => %{"type" => "uint32"},
      ...>     "phones" => %{
      ...>       "elements" => %{"type" => "string"},
      ...>     },
      ...>   },
      ...> })
      iex> validator = %JDDF.Validator{}
      %JDDF.Validator{max_depth: 0, max_errors: 0}
      iex> JDDF.Validator.validate!(validator, schema, %{
      ...>   "name" => "John Doe",
      ...>   "age" => 42,
      ...>   "phones" => [
      ...>     "+44 1234567",
      ...>     "+44 2345678",
      ...>   ],
      ...> })
      []
      iex> errors = Enum.sort(JDDF.Validator.validate!(validator, schema, %{
      ...>   "age" => "42",
      ...>   "phones" => [
      ...>     "+44 1234567",
      ...>     442345678,
      ...>   ],
      ...> }))
      iex> length(errors)
      3
      iex> [e1, e2, e3] = errors
      iex> e1
      %JDDF.Validator.ValidationError{instance_path: [], schema_path: ["properties", "name"]}
      iex> e2
      %JDDF.Validator.ValidationError{instance_path: ["age"], schema_path: ["properties", "age", "type"]}
      iex> e3
      %JDDF.Validator.ValidationError{instance_path: ["phones", "1"], schema_path: ["properties", "phones", "elements", "type"]}
  """
end
