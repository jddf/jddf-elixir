defmodule JDDFTest.Validator do
  use ExUnit.Case
  doctest JDDF.Validator

  describe "validation spec" do
    for file <- File.ls!("spec/tests/validation") do
      data = File.read!("spec/tests/validation/#{file}")
      suites = Jason.decode!(data)

      if file === "006-properties.json" do
        for %{"name" => name, "schema" => schema, "instances" => instances} <- suites do
          for {%{"instance" => instance, "errors" => errors}, i} <- Enum.with_index(instances) do
            @schema schema
            @instance instance
            @errors errors

            test "#{file}/#{name}/#{i}" do
              expected =
                Enum.map(@errors, fn error ->
                  %JDDF.Validator.ValidationError{
                    instance_path: error["instancePath"] |> String.split("/") |> tl,
                    schema_path: error["schemaPath"] |> String.split("/") |> tl
                  }
                end)

              validator = %JDDF.Validator{}
              schema = JDDF.Schema.from_json!(@schema)
              actual = JDDF.Validator.validate!(validator, schema, @instance)

              assert Enum.sort(expected) === Enum.sort(actual)
            end
          end
        end
      end
    end
  end

  test "max depth" do
    validator = %JDDF.Validator{max_depth: 3}

    schema =
      JDDF.Schema.from_json!(%{
        "definitions" => %{
          "" => %{"ref" => ""}
        },
        "ref" => ""
      })

    assert_raise JDDF.Validator.MaxDepthExceededError, fn ->
      JDDF.Validator.validate!(validator, schema, nil)
    end
  end

  test "max errors" do
    validator = %JDDF.Validator{max_errors: 3}

    schema =
      JDDF.Schema.from_json!(%{
        "elements" => %{
          "type" => "string"
        }
      })

    errors = JDDF.Validator.validate!(validator, schema, [nil, nil, nil, nil, nil])
    assert length(errors) === 3
  end
end
