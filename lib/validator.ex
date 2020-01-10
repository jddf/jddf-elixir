defmodule JDDF.Validator do
  @moduledoc """
  Validates JSON data against instances of `JDDF.Schema`.

  Validators have two properties to control how validation behaves:

  * `max_depth` controls how "deeply" references in JDDF schemas (using the
    `ref` JDDF keyword) should be followed. If `max_depth` is exceeded, then
    `validate/3` or `validate!/3` will throw
    `JDDF.Validator.MaxDepthExceededError`.

    For example, setting `max_depth` to `5` means that a 5-deep chain of `ref`s
    would trigger `JDDF.Validator.MaxDepthExceededError`.

    By default, `max_depth` is `0`. A `max_depth` of `0` disables any maximum
    depth; `JDDF.Validator.MaxDepthExceededError` will never be thrown. In this
    case, validating against a circularly-defined schema may exhaust all memory.

  * `max_errors` controls the maximum number of errors to return. If
    `max_errors` is set to `N`, then `validate/3` and `validate!/3` will return
    `N` `JDDF.Validator.ValidationError`s or fewer. You can use `max_errors` to
    optimize JDDF validation.

    For example, if you only care about whether there exist *any* validation
    errors for an input, you can set `max_errors` to `1`.

    By default, `max_errors` is `0`. A `max_errors` of `0` disables any maximum
    number of errors; `validate/3` and `validate!/3` will return all errors.

  The examples below demonstrate `max_depth` and `max_errors`. See also the docs
  for `JDDF` for more introductory examples.

  ## Examples

  Here's an example of `max_depth` causing an error, rather than letting a
  circularly-defined schema cause an infinite loop:

      iex> schema = JDDF.Schema.from_json!(%{
      ...>   "definitions" => %{
      ...>     "loop" => %{ "ref" => "loop" },
      ...>   },
      ...>   "ref" => "loop",
      ...> })
      iex> validator = %JDDF.Validator{max_depth: 32}
      %JDDF.Validator{max_depth: 32, max_errors: 0}
      iex> JDDF.Validator.validate!(validator, schema, nil)
      ** (JDDF.Validator.MaxDepthExceededError) maximum depth exceeded during validation

  Here's an example of `max_errors` limiting the return value to just 1 value:

      iex> schema = JDDF.Schema.from_json!(%{
      ...>   "elements" => %{ "type" => "string" }
      ...> })
      iex> validator = %JDDF.Validator{max_errors: 1}
      %JDDF.Validator{max_depth: 0, max_errors: 1}
      iex> length(JDDF.Validator.validate!(validator, schema, [nil, nil, nil, nil, nil]))
      1

  Instead of returning five errors (one for each element of `[nil, nil, nil,
  nil, nil]`), just one error comes back. Internally, `validate/3` and
  `validate!/3` optimizes for `max_errors`, and stops validation as soon as
  `max_errors` is reached.
  """

  defmodule ValidationError do
    @moduledoc """
    Represents a single JDDF validation error.

    * `instance_path` is the path to the part of the input that was rejected.
    * `schema_path` is the path the part of the schema that rejected the input.

    The precise values that go into `instance_path` and `schema_path` is
    standardized. The JDDF specification formalizes what exactly needs to go
    into these fields. `JDDF.Validator` confirms to the JDDF specification.
    """

    defstruct [:instance_path, :schema_path]

    @type t :: %__MODULE__{instance_path: list(String.t()), schema_path: list(String.t())}
  end

  defmodule MaxDepthExceededError do
    @moduledoc """
    Indicates that the validator's max depth was exceeded during validation.

    This error is raised when a `JDDF.Validator`'s `max_depth` is exceeded while
    doing validation, through either `JDDF.Validator.validate/3` or
    `JDDF.Validator.validate!/3`. See docs for `JDDF.Validator` for further
    explanation of `max_depth`, and why this error may be considered desirable.
    """
    defexception message: "maximum depth exceeded during validation"

    @type t :: %__MODULE__{message: String.t()}
  end

  defmodule VM do
    @moduledoc false

    defmodule TooManyErrorsError do
      @moduledoc false
      defexception [:message, :errors]
    end

    defstruct [:max_depth, :max_errors, :root, :instance_tokens, :schema_tokens, :errors]

    def validate!(vm, schema, instance, parent_tag \\ nil) do
      case schema.form do
        {:empty} ->
          vm

        {:ref, ref} ->
          if length(vm.schema_tokens) === vm.max_depth do
            raise JDDF.Validator.MaxDepthExceededError
          end

          push_schema(vm, [ref, "definitions"])
          |> validate!(vm.root.definitions[ref], instance)
          |> pop_schema

        {:type, type} ->
          vm = push_schema_token(vm, "type")

          vm =
            case type do
              :boolean ->
                if !is_boolean(instance) do
                  push_error!(vm)
                else
                  vm
                end

              :float32 ->
                if !is_float(instance) && !is_integer(instance) do
                  push_error!(vm)
                else
                  vm
                end

              :float64 ->
                if !is_float(instance) && !is_integer(instance) do
                  push_error!(vm)
                else
                  vm
                end

              :int8 ->
                validate_int!(vm, instance, -128, 127)

              :uint8 ->
                validate_int!(vm, instance, 0, 255)

              :int16 ->
                validate_int!(vm, instance, -32768, 32767)

              :uint16 ->
                validate_int!(vm, instance, 0, 65535)

              :int32 ->
                validate_int!(vm, instance, -2_147_483_648, 2_147_483_647)

              :uint32 ->
                validate_int!(vm, instance, 0, 4_294_967_295)

              :string ->
                if !is_binary(instance) do
                  push_error!(vm)
                else
                  vm
                end

              :timestamp ->
                if !is_binary(instance) || elem(DateTime.from_iso8601(instance), 0) !== :ok do
                  push_error!(vm)
                else
                  vm
                end
            end

          pop_schema_token(vm)

        {:enum, enum} ->
          vm = push_schema_token(vm, "enum")

          vm =
            if MapSet.member?(enum, instance) do
              vm
            else
              push_error!(vm)
            end

          pop_schema_token(vm)

        {:elements, schema} ->
          vm = push_schema_token(vm, "elements")

          if is_list(instance) do
            instance
            |> Enum.with_index()
            |> Enum.reduce(vm, fn {elem, index}, vm ->
              vm
              |> push_instance_token(Integer.to_string(index))
              |> validate!(schema, elem)
              |> pop_instance_token
            end)
          else
            vm |> push_error!
          end
          |> pop_schema_token

        {:properties, required, optional, additional} ->
          if is_map(instance) do
            vm =
              if required !== nil do
                vm = push_schema_token(vm, "properties")

                required
                |> Enum.reduce(vm, fn {key, sub_schema}, vm ->
                  vm = push_schema_token(vm, key)

                  vm =
                    if Map.has_key?(instance, key) do
                      push_instance_token(vm, key)
                      |> validate!(sub_schema, instance[key])
                      |> pop_instance_token
                    else
                      push_error!(vm)
                    end

                  pop_schema_token(vm)
                end)
                |> pop_schema_token
              else
                vm
              end

            vm =
              if optional !== nil do
                vm = push_schema_token(vm, "optionalProperties")

                optional
                |> Enum.reduce(vm, fn {key, sub_schema}, vm ->
                  vm = push_schema_token(vm, key)

                  vm =
                    if Map.has_key?(instance, key) do
                      push_instance_token(vm, key)
                      |> validate!(sub_schema, instance[key])
                      |> pop_instance_token
                    else
                      vm
                    end

                  pop_schema_token(vm)
                end)
                |> pop_schema_token
              else
                vm
              end

            if additional do
              vm
            else
              Map.keys(instance)
              |> Enum.reduce(vm, fn key, vm ->
                if !Map.has_key?(required || %{}, key) && !Map.has_key?(optional || %{}, key) &&
                     key !== parent_tag do
                  push_instance_token(vm, key) |> push_error! |> pop_instance_token
                else
                  vm
                end
              end)
            end
          else
            if required !== nil do
              push_schema_token(vm, "properties")
            else
              push_schema_token(vm, "optionalProperties")
            end
            |> push_error!
            |> pop_schema_token
          end

        {:values, schema} ->
          vm = push_schema_token(vm, "values")

          if is_map(instance) do
            instance
            |> Enum.reduce(vm, fn {key, value}, vm ->
              vm
              |> push_instance_token(key)
              |> validate!(schema, value)
              |> pop_instance_token
            end)
          else
            vm |> push_error!
          end
          |> pop_schema_token

        {:discriminator, tag, mapping} ->
          vm = push_schema_token(vm, "discriminator")

          if is_map(instance) do
            if Map.has_key?(instance, tag) do
              if is_binary(instance[tag]) do
                if Map.has_key?(mapping, instance[tag]) do
                  vm
                  |> push_schema_token("mapping")
                  |> push_schema_token(instance[tag])
                  |> validate!(mapping[instance[tag]], instance, tag)
                  |> pop_schema_token
                  |> pop_schema_token
                else
                  vm
                  |> push_schema_token("mapping")
                  |> push_instance_token(tag)
                  |> push_error!
                  |> pop_instance_token
                  |> pop_schema_token
                end
              else
                vm
                |> push_schema_token("tag")
                |> push_instance_token(tag)
                |> push_error!
                |> pop_instance_token
                |> pop_schema_token
              end
            else
              vm
              |> push_schema_token("tag")
              |> push_error!
              |> pop_schema_token
            end
          else
            push_error!(vm)
          end
          |> pop_schema_token
      end
    end

    defp validate_int!(vm, instance, min, max) do
      if is_float(instance) || is_integer(instance) do
        if round(instance) !== instance || instance < min || instance > max do
          push_error!(vm)
        else
          vm
        end
      else
        push_error!(vm)
      end
    end

    defp push_schema(vm, tokens) do
      %{vm | schema_tokens: [tokens | vm.schema_tokens]}
    end

    defp pop_schema(vm) do
      %{vm | schema_tokens: tl(vm.schema_tokens)}
    end

    defp push_schema_token(vm, token) do
      [tokens | rest] = vm.schema_tokens
      %{vm | schema_tokens: [[token | tokens] | rest]}
    end

    defp pop_schema_token(vm) do
      [[_ | tokens] | rest] = vm.schema_tokens
      %{vm | schema_tokens: [tokens | rest]}
    end

    defp push_instance_token(vm, token) do
      %{vm | instance_tokens: [token | vm.instance_tokens]}
    end

    defp pop_instance_token(vm) do
      %{vm | instance_tokens: vm.instance_tokens |> tl}
    end

    defp push_error!(vm) do
      errors = [
        %JDDF.Validator.ValidationError{
          instance_path: Enum.reverse(vm.instance_tokens),
          schema_path: Enum.reverse(vm.schema_tokens |> hd)
        }
        | vm.errors
      ]

      if length(errors) === vm.max_errors do
        raise TooManyErrorsError, message: "too many errors", errors: errors
      end

      %{vm | errors: errors}
    end
  end

  defstruct max_depth: 0, max_errors: 0

  @type t :: %__MODULE__{max_depth: integer, max_errors: integer}

  @doc """
  Validate a `JDDF.Schema` against a JSON input (an "instance").

  `instance` should be an Elixir representation of JSON data. You should first
  parse the JSON before passing it into `validate/3`. You can construct this
  data manually, or parse it using:

    * [`Jason.decode!/2`](https://hexdocs.pm/jason/Jason.html#decode!/2), or
    * [`Poison.decode!/2`](https://github.com/devinus/poison#usage)

  Most JSON implementations for Elixir are compatible with this function.

  See `JDDF.Validator` docs for how to control certain aspects of this function.
  This function implements the formal specification of JSON Data Definition
  Format validation.

      iex> JDDF.Validator.validate(
      ...>   %JDDF.Validator{},
      ...>   JDDF.Schema.from_json!(%{"type" => "boolean"}),
      ...>   nil
      ...> )
      {:ok, [%JDDF.Validator.ValidationError{instance_path: [], schema_path: ["type"]}]}

      iex> schema = JDDF.Schema.from_json!(%{
      ...>   "definitions" => %{
      ...>     "loop" => %{ "ref" => "loop" },
      ...>   },
      ...>   "ref" => "loop",
      ...> })
      iex> validator = %JDDF.Validator{max_depth: 32}
      %JDDF.Validator{max_depth: 32, max_errors: 0}
      iex> JDDF.Validator.validate(validator, schema, nil)
      {:error, %JDDF.Validator.MaxDepthExceededError{message: "maximum depth exceeded during validation"}}
  """
  @spec validate(validator :: __MODULE__.t(), schema :: JDDF.Schema.t(), instance :: any()) ::
          {:ok, [ValidationError.t()]} | {:error, MaxDepthExceededError.t()}
  def validate(validator, schema, instance) do
    {:ok, validate!(validator, schema, instance)}
  rescue
    e in MaxDepthExceededError -> {:error, e}
  end

  @doc """
  Validate a `JDDF.Schema` against a JSON input (an "instance").

  Similar to `validate/3`, except it will unwrap the result and will raise in
  case of errors.

      iex> JDDF.Validator.validate!(
      ...>   %JDDF.Validator{},
      ...>   JDDF.Schema.from_json!(%{"type" => "boolean"}),
      ...>   nil
      ...> )
      [%JDDF.Validator.ValidationError{instance_path: [], schema_path: ["type"]}]

      iex> schema = JDDF.Schema.from_json!(%{
      ...>   "definitions" => %{
      ...>     "loop" => %{ "ref" => "loop" },
      ...>   },
      ...>   "ref" => "loop",
      ...> })
      iex> validator = %JDDF.Validator{max_depth: 32}
      %JDDF.Validator{max_depth: 32, max_errors: 0}
      iex> JDDF.Validator.validate!(validator, schema, nil)
      ** (JDDF.Validator.MaxDepthExceededError) maximum depth exceeded during validation
  """
  @spec validate!(validator :: __MODULE__.t(), schema :: JDDF.Schema.t(), instance :: any()) :: [
          ValidationError.t()
        ]
  def validate!(validator, schema, instance) do
    vm = %VM{
      max_depth: validator.max_depth,
      max_errors: validator.max_errors,
      root: schema,
      instance_tokens: [],
      schema_tokens: [[]],
      errors: []
    }

    try do
      vm = VM.validate!(vm, schema, instance)
      vm.errors
    rescue
      e in VM.TooManyErrorsError -> e.errors
    end
  end
end
