defmodule JDDFTest.Validator do
  use ExUnit.Case
  doctest JDDF.Validator

  describe "validation spec" do
    for file <- File.ls!("spec/tests/validation") do
      data = File.read!("spec/tests/validation/#{file}")
      suites = Jason.decode!(data)

      if file === "002-ref.json" do
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

              assert expected === actual
            end
          end
        end
      end
    end
  end
end
