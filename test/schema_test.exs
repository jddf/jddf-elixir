defmodule JDDFTest.Schema do
  use ExUnit.Case
  doctest JDDF.Schema

  describe "invalid schemas spec" do
    {:ok, data} = File.read("spec/tests/invalid-schemas.json")
    test_cases = Jason.decode!(data)

    for %{"name" => name, "schema" => schema} <- test_cases do
      @schema schema
      test name do
        assert_raise JDDF.Schema.InvalidSchemaError, fn ->
          JDDF.Schema.from_json!(@schema) |> JDDF.Schema.verify!()
        end
      end
    end
  end

  test "parse empty from json" do
    json = %{
      "definitions" => %{
        "foo" => %{}
      },
      "asdf" => "foo"
    }

    schema = %JDDF.Schema{
      definitions: %{
        "foo" => %JDDF.Schema{definitions: nil, form: {:empty}}
      },
      form: {:empty}
    }

    assert JDDF.Schema.from_json!(json) === schema
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
        "foo" => %JDDF.Schema{definitions: nil, form: {:empty}}
      },
      form: {:ref, "foo"}
    }

    assert JDDF.Schema.from_json!(json) === schema
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
      expected = %JDDF.Schema{definitions: nil, form: {:type, type}}
      actual = JDDF.Schema.from_json!(%{"type" => to_string(type)})

      assert expected === actual
    end
  end

  test "parse enum from json" do
    actual = JDDF.Schema.from_json!(%{"enum" => ["foo"]})

    expected = %JDDF.Schema{
      definitions: nil,
      form: {:enum, MapSet.new(["foo"])}
    }

    assert expected === actual
  end

  test "parse elements from json" do
    actual = JDDF.Schema.from_json!(%{"elements" => %{}})

    expected = %JDDF.Schema{
      definitions: nil,
      form: {:elements, %JDDF.Schema{definitions: nil, form: {:empty}}}
    }

    assert expected === actual
  end

  test "parse properties, optionalProperties, additionalProperties from json" do
    actual =
      JDDF.Schema.from_json!(%{
        "properties" => %{"foo" => %{}},
        "optionalProperties" => %{"foo" => %{}},
        "additionalProperties" => true
      })

    expected = %JDDF.Schema{
      definitions: nil,
      form: {
        :properties,
        %{"foo" => %JDDF.Schema{definitions: nil, form: {:empty}}},
        %{"foo" => %JDDF.Schema{definitions: nil, form: {:empty}}},
        true
      }
    }

    assert expected === actual
  end

  test "parse values from json" do
    actual = JDDF.Schema.from_json!(%{"values" => %{}})

    expected = %JDDF.Schema{
      definitions: nil,
      form: {:values, %JDDF.Schema{definitions: nil, form: {:empty}}}
    }

    assert expected === actual
  end

  test "parse discriminator from json" do
    actual =
      JDDF.Schema.from_json!(%{
        "discriminator" => %{
          "tag" => "foo",
          "mapping" => %{"foo" => %{}}
        }
      })

    expected = %JDDF.Schema{
      definitions: nil,
      form: {
        :discriminator,
        "foo",
        %{"foo" => %JDDF.Schema{definitions: nil, form: {:empty}}}
      }
    }

    assert expected === actual
  end
end
