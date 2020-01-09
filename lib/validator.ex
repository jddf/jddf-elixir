defmodule JDDF.Validator do
  defmodule ValidationError do
    defstruct [:instance_path, :schema_path]
  end

  defmodule VM do
    defmodule TooManyErrors do
      defexception [:message, :errors]
    end

    defstruct [:max_depth, :max_errors, :root, :instance_tokens, :schema_tokens, :errors]

    def validate!(vm, schema, instance) do
      case schema.form do
        {:empty} -> vm
        {:ref, ref} ->
          push_schema(vm, [ref, "definitions"])
            |> validate!(vm.root.definitions[ref], instance)
            |> pop_schema
        {:elements, schema} ->
          vm = push_schema_token(vm, "elements")

          if is_list(instance) do
            instance
              |> Enum.with_index
              |> Enum.reduce(vm, fn ({elem, index}, vm) ->
                vm
                  |> push_instance_token(Integer.to_string(index))
                  |> validate!(schema, elem)
                  |> pop_instance_token
              end)
          else
            vm |> push_error!
          end |> pop_schema_token

        {:type, :string} ->
          vm = push_schema_token(vm, "type")
          vm = if !is_binary(instance) do push_error!(vm) else vm end
          pop_schema_token(vm)

        _ -> vm
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
      error = %JDDF.Validator.ValidationError{
        instance_path: Enum.reverse(vm.instance_tokens),
        schema_path: Enum.reverse(vm.schema_tokens |> hd),
      }

      %{vm | errors: [error | vm.errors]}
    end
  end

  defstruct max_depth: 0, max_errors: 0

  @type t :: %__MODULE__{max_depth: integer, max_errors: integer}

  def validate(validator, schema, instance) do
    {:ok, validate!(validator, schema, instance)}
  end

  def validate!(validator, schema, instance) do
    vm = %VM{
      max_depth: validator.max_depth,
      max_errors: validator.max_errors,
      root: schema,
      instance_tokens: [],
      schema_tokens: [[]],
      errors: []
    }

    vm = VM.validate!(vm, schema, instance)
    vm.errors
  end
end
