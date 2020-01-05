defmodule JDDF.Schema do
  defstruct [
    :definitions,
    :form
  ]

  @type t :: %__MODULE__{
          definitions: mapping,
          form:
            {:empty}
            | {:ref, String.t()}
            | {:type, type}
            | {:enum, MapSet.t(String.t())}
            | {:elements, __MODULE__.t()}
            | {:properties, mapping, mapping, boolean}
            | {:values, __MODULE__.t()}
            | {:discriminator, String.t(), mapping}
        }

  @type mapping :: %{optional(String.t()) => __MODULE__.t()}

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

  def from_json(json) do
    {definitions, rest} = Map.pop(json, "definitions", %{})

    %__MODULE__{
      definitions: mapping_from_json(definitions),
      form: sub_from_json(rest).form
    }
  end

  defp sub_from_json(json) do
    %__MODULE__{
      definitions: %{},
      form: filter_additional(json) |> form_from_json
    }
  end

  defp filter_additional(json) do
    Map.take(json, ~w(
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
  end

  defp form_from_json(map) when map === %{} do
    {:empty}
  end

  defp form_from_json(%{"ref" => ref}) do
    {:ref, ref}
  end

  defp form_from_json(%{"type" => "boolean"}) do
    {:type, :boolean}
  end

  defp form_from_json(%{"type" => "float32"}) do
    {:type, :float32}
  end

  defp form_from_json(%{"type" => "float64"}) do
    {:type, :float64}
  end

  defp form_from_json(%{"type" => "int8"}) do
    {:type, :int8}
  end

  defp form_from_json(%{"type" => "uint8"}) do
    {:type, :uint8}
  end

  defp form_from_json(%{"type" => "int16"}) do
    {:type, :int16}
  end

  defp form_from_json(%{"type" => "uint16"}) do
    {:type, :uint16}
  end

  defp form_from_json(%{"type" => "int32"}) do
    {:type, :int32}
  end

  defp form_from_json(%{"type" => "uint32"}) do
    {:type, :uint32}
  end

  defp form_from_json(%{"type" => "string"}) do
    {:type, :string}
  end

  defp form_from_json(%{"type" => "timestamp"}) do
    {:type, :timestamp}
  end

  defp form_from_json(%{"enum" => enum}) do
    {:enum, MapSet.new(enum)}
  end

  defp form_from_json(%{"elements" => elements}) do
    {:elements, sub_from_json(elements)}
  end

  defp form_from_json(%{
         "properties" => required,
         "optionalProperties" => optional,
         "additionalProperties" => additional
       }) do
    {:properties, mapping_from_json(required), mapping_from_json(optional), additional}
  end

  defp form_from_json(%{"properties" => required, "optionalProperties" => optional}) do
    {:properties, mapping_from_json(required), mapping_from_json(optional), false}
  end

  defp form_from_json(%{"properties" => required, "additionalProperties" => additional}) do
    {:properties, mapping_from_json(required), %{}, additional}
  end

  defp form_from_json(%{"properties" => required}) do
    {:properties, mapping_from_json(required), %{}, false}
  end

  defp form_from_json(%{"optionalProperties" => optional, "additionalProperties" => additional}) do
    {:properties, %{}, mapping_from_json(optional), additional}
  end

  defp form_from_json(%{"optionalProperties" => optional}) do
    {:properties, %{}, mapping_from_json(optional), false}
  end

  defp form_from_json(%{"values" => values}) do
    {:values, sub_from_json(values)}
  end

  defp form_from_json(%{"discriminator" => %{"tag" => tag, "mapping" => mapping}}) do
    {:discriminator, tag, mapping_from_json(mapping)}
  end

  defp mapping_from_json(mapping) do
    Enum.into(Enum.map(mapping, fn {k, v} -> {k, sub_from_json(v)} end), %{})
  end
end
