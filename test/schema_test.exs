defmodule JDDFTest.Schema do
  use ExUnit.Case
  doctest JDDF.Schema

  test "parse empty from json" do
    json = %{
      "definitions" => %{
        "foo" => %{}
      },
      "asdf" => "foo"
    }

    schema = %JDDF.Schema{
      definitions: %{
        "foo" => %JDDF.Schema{definitions: %{}, form: {:empty}}
      },
      form: {:empty}
    }

    assert JDDF.Schema.from_json(json) === schema
  end

  test "parse ref from json" do
    json = %{
      "definitions" => %{
        "foo" => %{}
      },
      "ref" => "foo"
    }

    schema = %JDDF.Schema{
      definitions: %{
        "foo" => %JDDF.Schema{definitions: %{}, form: {:empty}}
      },
      form: {:ref, "foo"}
    }

    assert JDDF.Schema.from_json(json) === schema
  end

  test "parse type from json" do
    types = ~w(
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
    )a

    for type <- types do
      expected = %JDDF.Schema{definitions: %{}, form: {:type, type}}
      actual = JDDF.Schema.from_json(%{"type" => to_string(type)})

      assert expected === actual
    end
  end

  test "parse enum from json" do
    actual = JDDF.Schema.from_json(%{"enum" => ["foo"]})

    expected = %JDDF.Schema{
      definitions: %{},
      form: {:enum, MapSet.new(["foo"])},
    }

    assert expected === actual
  end

  test "parse elements from json" do
    actual = JDDF.Schema.from_json(%{"elements" => %{}})

    expected = %JDDF.Schema{
      definitions: %{},
      form: {:elements, %JDDF.Schema{definitions: %{}, form: {:empty}}},
    }

    assert expected === actual
  end

  test "parse properties, optionalProperties, additionalProperties from json" do
    actual =
      JDDF.Schema.from_json(%{
        "properties" => %{"foo" => %{}},
        "optionalProperties" => %{"foo" => %{}},
        "additionalProperties" => true
      })

    expected = %JDDF.Schema{
      definitions: %{},
      form: {
        :properties,
        %{"foo" => %JDDF.Schema{definitions: %{}, form: {:empty}}},
        %{"foo" => %JDDF.Schema{definitions: %{}, form: {:empty}}},
        true
      }
    }

    assert expected === actual
  end

  test "parse values from json" do
    actual = JDDF.Schema.from_json(%{"values" => %{}})

    expected = %JDDF.Schema{
      definitions: %{},
      form: {:values, %JDDF.Schema{definitions: %{}, form: {:empty}}},
    }

    assert expected === actual
  end

  test "parse discriminator from json" do
    actual = JDDF.Schema.from_json(%{"discriminator" => %{
      "tag" => "foo",
      "mapping" => %{"foo" => %{}},
    }})

    expected = %JDDF.Schema{
      definitions: %{},
      form: {
        :discriminator,
        "foo",
        %{"foo" => %JDDF.Schema{definitions: %{}, form: {:empty}}},
      },
    }

    assert expected === actual
  end
end
