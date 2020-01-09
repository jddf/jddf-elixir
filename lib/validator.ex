defmodule JDDF.Validator do
  defmodule ValidationError do
    defstruct [:instance_path, :schema_path]
  end

  defmodule MaxDepthExceededError do
    defexception message: "maximum depth exceeded during validation"
  end

  defmodule VM do
    defmodule TooManyErrorsError do
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

    try do
      vm = VM.validate!(vm, schema, instance)
      vm.errors
    rescue
      e in VM.TooManyErrorsError -> e.errors
    end
  end
end
