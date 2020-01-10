defmodule JDDF.Schema do
  @moduledoc """
  Represents a JSON Data Definition Format schema.

  You can construct instances of this type yourself, or you can parse it from
  JSON-like data using `from_json/1` or `from_json!/1`.

  Not all invariants that JDDF schemas must adhere to are checked by
  `from_json/1` or `from_json!/1`. To fully verify the correctness of a schema,
  use `verify/1` or `verify!/1`.
  """

  defmodule InvalidSchemaError do
    @moduledoc """
    Indicates that a schema does not conform to the JDDF syntax rules.
    """
    defexception message: "invalid schema"

    @type t :: %__MODULE__{message: String.t()}
  end

  defstruct [:definitions, :form]

  @type t :: %__MODULE__{definitions: mapping | nil, form: form}

  @type mapping :: %{optional(String.t()) => __MODULE__.t()}

  @type form ::
          {:empty}
          | {:ref, String.t()}
          | {:type, type}
          | {:enum, MapSet.t(String.t())}
          | {:elements, __MODULE__.t()}
          | {:properties, mapping | nil, mapping | nil, boolean}
          | {:values, __MODULE__.t()}
          | {:discriminator, String.t(), mapping}

  @type type ::
          :boolean
          | :float32
          | :float64
          | :int8
          | :uint8
          | :int16
          | :uint16
          | :int32
          | :uint32
          | :string
          | :timestamp

  @doc """
  Construct a JDDF schema from parsed JSON data.

  `json` should be an Elixir representation of JSON data. You should first parse
  the JSON before passing it into `from_json/1`. You can construct this data
  manually, or parse it using:

    * [`Jason.decode!/2`](https://hexdocs.pm/jason/Jason.html#decode!/2), or
    * [`Poison.decode!/2`](https://github.com/devinus/poison#usage)

  Most JSON implementations for Elixir are compatible with this function.

      iex> JDDF.Schema.from_json(%{"type" => "uint32"})
      {:ok, %JDDF.Schema{definitions: nil, form: {:type, :uint32}}}
      iex> JDDF.Schema.from_json(%{"type" => "nonsense"})
      {:error, %JDDF.Schema.InvalidSchemaError{message: "invalid type"}}
  """
  @spec from_json(json :: String.t()) :: {:ok, Schema.t()} | {:error, InvalidSchemaError.t()}
  def from_json(json) do
    {:ok, from_json!(json)}
  rescue
    e in InvalidSchemaError -> {:error, e}
  end

  @doc """
  Construct a JDDF schema from parsed JSON data.

  Similar to `from_json/1`, except it will unwrap the result and will raise in
  case of errors.

      iex> JDDF.Schema.from_json!(%{"type" => "uint32"})
      %JDDF.Schema{definitions: nil, form: {:type, :uint32}}
      iex> JDDF.Schema.from_json!(%{"type" => "nonsense"})
      ** (JDDF.Schema.InvalidSchemaError) invalid type
  """
  @spec from_json!(json :: String.t()) :: Schema.t()
  def from_json!(json) do
    unless is_map(json) do
      raise InvalidSchemaError, "schema must be object"
    end

    definitions =
      if Map.has_key?(json, "definitions") do
        unless is_map(json["definitions"]) do
          raise InvalidSchemaError, "definitions must be object"
        end

        Map.new(json["definitions"], fn {k, v} -> {k, from_json!(v)} end)
      else
        nil
      end

    # Strip out non-keyword properties of the schema.
    json = Map.take(json, ~w(
      ref
      type
      enum
      elements
      properties
      optionalProperties
      additionalProperties
      values
      discriminator
    ))

    # Attempt to match against each of the eight forms. Exactly one of these
    # should succeed.

    form_empty =
      if json === %{} do
        {:empty}
      else
        nil
      end

    form_ref =
      if Map.has_key?(json, "ref") do
        unless is_binary(json["ref"]) do
          raise InvalidSchemaError, "ref must be string"
        end

        {:ref, json["ref"]}
      else
        nil
      end

    form_type =
      if Map.has_key?(json, "type") do
        if Enum.member?(
             ~w(
        boolean
        float32
        float64
        int8
        uint8
        int16
        uint16
        int32
        uint32
        string
        timestamp
      ),
             json["type"]
           ) do
          {:type, String.to_atom(json["type"])}
        else
          raise InvalidSchemaError, message: "invalid type"
        end
      else
        nil
      end

    form_enum =
      if Map.has_key?(json, "enum") do
        unless is_list(json["enum"]) do
          raise InvalidSchemaError, message: "enum must be array"
        end

        if json["enum"] === [] do
          raise InvalidSchemaError, message: "enum must be non-empty"
        end

        for value <- json["enum"] do
          if !is_binary(value) do
            raise InvalidSchemaError, message: "enum must be array of strings"
          end
        end

        set = MapSet.new(json["enum"])

        unless MapSet.size(set) === length(json["enum"]) do
          raise InvalidSchemaError, message: "enum must not contain repeated values"
        end

        {:enum, set}
      else
        nil
      end

    form_elements =
      if Map.has_key?(json, "elements") do
        {:elements, from_json!(json["elements"])}
      else
        nil
      end

    form_properties =
      if Map.has_key?(json, "properties") || Map.has_key?(json, "optionalProperties") do
        if Map.has_key?(json, "properties") && !is_map(json["properties"]) do
          raise InvalidSchemaError, "properties must be object"
        end

        if Map.has_key?(json, "optionalProperties") && !is_map(json["optionalProperties"]) do
          raise InvalidSchemaError, "optionalProperties must be object"
        end

        required =
          if Map.has_key?(json, "properties") do
            Map.new(json["properties"], fn {k, v} -> {k, from_json!(v)} end)
          else
            nil
          end

        optional =
          if Map.has_key?(json, "optionalProperties") do
            Map.new(json["optionalProperties"], fn {k, v} -> {k, from_json!(v)} end)
          else
            nil
          end

        additional = Map.get(json, "additionalProperties", false)

        {:properties, required, optional, additional}
      else
        nil
      end

    form_values =
      if Map.has_key?(json, "values") do
        {:values, from_json!(json["values"])}
      else
        nil
      end

    form_discriminator =
      if Map.has_key?(json, "discriminator") do
        discriminator = json["discriminator"]

        unless is_map(discriminator) do
          raise InvalidSchemaError, "discriminator must be object"
        end

        unless Map.has_key?(discriminator, "tag") do
          raise InvalidSchemaError, "discriminator must have tag"
        end

        unless is_binary(discriminator["tag"]) do
          raise InvalidSchemaError, "discriminator tag must be string"
        end

        unless Map.has_key?(discriminator, "mapping") do
          raise InvalidSchemaError, "discriminator must have mapping"
        end

        unless is_map(discriminator["mapping"]) do
          raise InvalidSchemaError, "discriminator mapping must be object"
        end

        mapping =
          discriminator["mapping"]
          |> Map.new(fn {k, v} -> {k, from_json!(v)} end)

        {:discriminator, discriminator["tag"], mapping}
      else
        nil
      end

    matching_forms =
      [
        form_empty,
        form_ref,
        form_type,
        form_enum,
        form_elements,
        form_properties,
        form_values,
        form_discriminator
      ]
      |> Enum.filter(fn x -> x end)

    if Enum.count(matching_forms) !== 1 do
      raise InvalidSchemaError, message: "invalid form"
    end

    form = List.first(matching_forms)

    %__MODULE__{definitions: definitions, form: form}
  end

  @doc """
  Ensure that the invariants of a JDDF schema are adhered to.

      iex> JDDF.Schema.verify(JDDF.Schema.from_json!(%{}))
      {:ok, nil}

      iex> schema = JDDF.Schema.from_json!(%{
      ...>   "properties" => %{ "a" => %{}},
      ...>   "optionalProperties" => %{ "a" => %{}},
      ...> })
      iex> JDDF.Schema.verify(schema)
      {:error, %JDDF.Schema.InvalidSchemaError{message: "properties and optionalProperties share key"}}
  """
  @spec verify(schema :: __MODULE__.t()) :: {:ok, nil} | {:error, InvalidSchemaError.t()}
  def verify(schema) do
    {:ok, verify!(schema)}
  rescue
    e in InvalidSchemaError -> {:error, e}
  end

  @doc """
  Ensure that the invariants of a JDDF schema are adhered to.

  Similar to `verify/1`, except it will unwrap the result and will raise in case
  of errors.

      iex> JDDF.Schema.verify!(JDDF.Schema.from_json!(%{}))
      nil

      iex> schema = JDDF.Schema.from_json!(%{
      ...>   "properties" => %{ "a" => %{}},
      ...>   "optionalProperties" => %{ "a" => %{}},
      ...> })
      iex> JDDF.Schema.verify!(schema)
      ** (JDDF.Schema.InvalidSchemaError) properties and optionalProperties share key
  """
  @spec verify!(schema :: __MODULE__.t()) :: nil
  def verify!(schema) do
    verify!(schema, schema)
  end

  defp verify!(schema, root) do
    if schema.definitions !== nil do
      unless schema === root do
        raise InvalidSchemaError, message: "non-root definitions"
      end

      for {_, schema} <- schema.definitions do
        verify!(schema, root)
      end
    end

    case schema.form do
      {:empty} ->
        nil

      {:type, _} ->
        nil

      {:enum, _} ->
        nil

      {:ref, ref} ->
        if root.definitions === nil do
          raise InvalidSchemaError, message: "ref but no definitions"
        else
          if !Map.has_key?(root.definitions, ref) do
            raise InvalidSchemaError, message: "ref to non-existent definition"
          end
        end

      {:elements, schema} ->
        verify!(schema, root)

      {:properties, required, optional, _} ->
        required_keys = MapSet.new(Map.keys(required || %{}))
        optional_keys = MapSet.new(Map.keys(optional || %{}))

        unless MapSet.disjoint?(required_keys, optional_keys) do
          raise InvalidSchemaError, "properties and optionalProperties share key"
        end

      {:values, schema} ->
        verify!(schema, root)

      {:discriminator, tag, mapping} ->
        for {_, schema} <- mapping do
          verify!(schema, root)

          case schema.form do
            {:properties, required, optional, _} ->
              if Map.has_key?(required || %{}, tag) || Map.has_key?(optional || %{}, tag) do
                raise InvalidSchemaError,
                      "discriminator mapping value has property equal to tag's value"
              end

            _ ->
              raise InvalidSchemaError, "discriminator mapping value must be of properties form"
          end
        end
    end
  end
end
