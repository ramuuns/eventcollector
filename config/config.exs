import Config

defmodule JsonParser do
  def parse(json) do
    parse_internal(json, :obj, %{}, [], [])
  end

  def parse_internal(" " <> json, :obj, ret, stack, curr) do
    parse_internal(json, :obj, ret, stack, curr)
  end

  def parse_internal("{" <> json, :obj, ret, stack, curr) do
    parse_internal(json, :key, ret, stack, curr)
  end

  def parse_internal(" " <> json, :key, ret, stack, curr) do
    parse_internal(json, :key, ret, stack, curr)
  end

  def parse_internal("\"" <> json, :key, ret, stack, curr) do
    parse_internal(json, :in_key, ret, stack, curr)
  end

  def parse_internal("\"" <> json, :in_key, ret, stack, curr) do
    key = curr |> Enum.reverse() |> Enum.join("")
    parse_internal(json, :needs_col, ret, [key | stack], [])
  end

  def parse_internal(<<ch::utf8, rest::binary>>, :in_key, ret, stack, curr) do
    parse_internal(rest, :in_key, ret, stack, [<<ch::utf8>> | curr])
  end

  def parse_internal(" " <> json, :needs_col, ret, stack, curr) do
    parse_internal(json, :needs_col, ret, stack, curr)
  end

  def parse_internal(":" <> json, :needs_col, ret, stack, curr) do
    parse_internal(json, :needs_value, ret, stack, curr)
  end

  def parse_internal(" " <> json, :needs_value, ret, stack, curr) do
    parse_internal(json, :needs_value, ret, stack, curr)
  end

  def parse_internal("\"" <> json, :needs_value, ret, stack, curr) do
    parse_internal(json, :string_value, ret, stack, curr)
  end

  def parse_internal("[" <> json, :needs_value, ret, stack, curr) do
    parse_internal(json, :array, [], [{:obj, ret} | stack], curr)
  end

  def parse_internal("{" <> json, :needs_value, ret, stack, curr) do
    parse_internal(json, :key, %{}, [{:obj, ret} | stack], curr)
  end

  def parse_internal(<<ch::utf8, rest::binary>>, :needs_value, ret, stack, curr)
      when ch >= 48 and ch < 57 do
    parse_internal(rest, :number, ret, stack, [<<ch::utf8>> | curr])
  end

  def parse_internal("t" <> json, :needs_value, ret, stack, curr) do
    parse_internal(json, :true_rue, ret, stack, curr)
  end

  def parse_internal("f" <> json, :needs_value, ret, stack, curr) do
    parse_internal(json, :false_alse, ret, stack, curr)
  end

  def parse_internal("n" <> json, :needs_value, ret, stack, curr) do
    parse_internal(json, :null_ull, ret, stack, curr)
  end

  def parse_internal("r" <> json, :true_rue, ret, stack, curr) do
    parse_internal(json, :true_ue, ret, stack, curr)
  end

  def parse_internal("u" <> json, :true_ue, ret, stack, curr) do
    parse_internal(json, :true_e, ret, stack, curr)
  end

  def parse_internal("e" <> json, :true_e, ret, [key | stack], _curr) when is_map(ret) do
    parse_internal(json, :comma, ret |> Map.put(key, true), stack, [])
  end

  def parse_internal("e" <> json, :true_e, ret, stack, _curr) when is_list(ret) do
    parse_internal(json, :comma, [true | ret], stack, [])
  end

  def parse_internal("a" <> json, :false_alse, ret, stack, curr) do
    parse_internal(json, :false_lse, ret, stack, curr)
  end

  def parse_internal("l" <> json, :false_lse, ret, stack, curr) do
    parse_internal(json, :false_se, ret, stack, curr)
  end

  def parse_internal("s" <> json, :false_se, ret, stack, curr) do
    parse_internal(json, :false_e, ret, stack, curr)
  end

  def parse_internal("e" <> json, :false_e, ret, [key | stack], _curr) when is_map(ret) do
    parse_internal(json, :comma, ret |> Map.put(key, false), stack, [])
  end

  def parse_internal("e" <> json, :false_e, ret, stack, _curr) when is_list(ret) do
    parse_internal(json, :comma, [false | ret], stack, [])
  end

  def parse_internal("u" <> json, :null_ull, ret, stack, curr) do
    parse_internal(json, :null_ll, ret, stack, curr)
  end

  def parse_internal("l" <> json, :null_ll, ret, stack, curr) do
    parse_internal(json, :null_l, ret, stack, curr)
  end

  def parse_internal("l" <> json, :null_l, ret, [key | stack], _curr) when is_map(ret) do
    parse_internal(json, :comma, ret |> Map.put(key, nil), stack, [])
  end

  def parse_internal("l" <> json, :null_l, ret, stack, _curr) when is_list(ret) do
    parse_internal(json, :comma, [nil | ret], stack, [])
  end

  def parse_internal(" " <> json, :number, ret, [key | stack], curr) when is_map(ret) do
    num = make_num(curr)
    parse_internal(json, :comma, ret |> Map.put(key, num), stack, [])
  end

  def parse_internal(" " <> json, :number, ret, stack, curr) when is_list(ret) do
    num = make_num(curr)
    parse_internal(json, :comma, [num | ret], stack, [])
  end

  def parse_internal("\n" <> json, :number, ret, [key | stack], curr) when is_map(ret) do
    num = make_num(curr)
    parse_internal(json, :comma, ret |> Map.put(key, num), stack, [])
  end

  def parse_internal("\n" <> json, :number, ret, stack, curr) when is_list(ret) do
    num = make_num(curr)
    parse_internal(json, :comma, [num | ret], stack, [])
  end

  def parse_internal("," <> json, :number, ret, [key | stack], curr) when is_map(ret) do
    num = make_num(curr)
    parse_internal(json, :key, ret |> Map.put(key, num), stack, [])
  end

  def parse_internal("," <> json, :number, ret, stack, curr) when is_list(ret) do
    num = make_num(curr)
    parse_internal(json, :array, [num | ret], stack, [])
  end

  def parse_internal("}" <> json, :number, ret, [key | stack], curr) do
    value = make_num(curr)
    next_for_curly_brace(json, ret |> Map.put(key, value), stack)
  end

  def parse_internal("]" <> json, :number, ret, stack, curr) do
    value = make_num(curr)
    next_for_square_bracket(json, [value | ret], stack)
  end

  def parse_internal("." <> json, :number, ret, stack, curr) do
    parse_internal(json, :number, ret, stack, ["." | curr])
  end

  def parse_internal(<<ch::utf8, rest::binary>>, :number, ret, stack, curr)
      when ch >= 48 and ch < 57 do
    parse_internal(rest, :number, ret, stack, [<<ch>> | curr])
  end

  def parse_internal("\"" <> json, :string_value, ret, [key | stack], curr) when is_map(ret) do
    value = curr |> Enum.reverse() |> Enum.join("")
    parse_internal(json, :comma, ret |> Map.put(key, value), stack, [])
  end

  def parse_internal("\"" <> json, :string_value, ret, stack, curr) when is_list(ret) do
    value = curr |> Enum.reverse() |> Enum.join("")
    parse_internal(json, :comma, [value | ret], stack, [])
  end

  def parse_internal(<<ch::utf8, rest::binary>>, :string_value, ret, stack, curr) do
    parse_internal(rest, :string_value, ret, stack, [<<ch>> | curr])
  end

  def parse_internal(" " <> json, :comma, ret, stack, curr) do
    parse_internal(json, :comma, ret, stack, curr)
  end

  def parse_internal("," <> json, :comma, ret, stack, curr) when is_map(ret) do
    parse_internal(json, :key, ret, stack, curr)
  end

  def parse_internal("}" <> json, :comma, ret, stack, _curr) when is_map(ret) do
    next_for_curly_brace(json, ret, stack)
  end

  def parse_internal("," <> json, :comma, ret, stack, _curr) when is_list(ret) do
    parse_internal(json, :array, ret, stack, [])
  end

  def parse_internal("]" <> json, :comma, ret, stack, _curr) when is_list(ret) do
    next_for_square_bracket(json, ret, stack)
  end

  def parse_internal(" " <> json, :array, ret, stack, curr) do
    parse_internal(json, :array, ret, stack, curr)
  end

  def parse_internal("\"" <> json, :array, ret, stack, curr) do
    parse_internal(json, :string_value, ret, stack, curr)
  end

  def parse_internal("[" <> json, :array, ret, stack, curr) do
    parse_internal(json, :array, [], [{:array, ret} | stack], curr)
  end

  def parse_internal("{" <> json, :array, ret, stack, curr) do
    parse_internal(json, :key, %{}, [{:array, ret} | stack], curr)
  end

  def parse_internal(<<ch::utf8, rest::binary>>, :array, ret, stack, curr)
      when ch >= 48 and ch < 57 do
    parse_internal(rest, :number, ret, stack, [<<ch::utf8>> | curr])
  end

  def parse_internal("t" <> json, :array, ret, stack, curr) do
    parse_internal(json, :true_rue, ret, stack, curr)
  end

  def parse_internal("f" <> json, :array, ret, stack, curr) do
    parse_internal(json, :false_alse, ret, stack, curr)
  end

  def parse_internal("n" <> json, :array, ret, stack, curr) do
    parse_internal(json, :null_ull, ret, stack, curr)
  end

  def parse_internal("\n" <> json, state, ret, stack, curr)
      when state == :comma or state == :key or state == :obj or state == :array or
             state == :needs_value or state == :needs_col do
    parse_internal(json, state, ret, stack, curr)
  end

  def next_for_square_bracket(json, arr, [{:obj, o} | stack]) do
    [p_key | stack] = stack
    parse_internal(json, :comma, o |> Map.put(p_key, arr |> Enum.reverse()), stack, [])
  end

  def next_for_square_bracket(json, ret, [{:array, arr} | stack]) do
    parse_internal(json, :comma, [ret |> Enum.reverse() | arr], stack, [])
  end

  def next_for_curly_brace(_json, ret, []) do
    ret
  end

  def next_for_curly_brace(json, ret, [{:obj, o} | stack]) do
    [p_key | stack] = stack
    parse_internal(json, :comma, o |> Map.put(p_key, ret), stack, [])
  end

  def next_for_curly_brace(json, ret, [{:array, arr} | stack]) do
    parse_internal(json, :comma, [ret | arr], stack, [])
  end

  def make_num(curr) do
    curr = curr |> Enum.reverse()

    if Enum.any?(curr, fn i -> i == "." end) do
      curr |> Enum.join("") |> String.to_float()
    else
      curr |> Enum.join("") |> String.to_integer()
    end
  end
end

config_path = "/etc/eventcollector/config.json"

json_config = config_path |> File.read!() |> JsonParser.parse()

config :eventcollector,
  graphite_host: json_config["graphite_host"] |> to_charlist,
  graphite_port: json_config["graphite_port"],
  app_port: json_config["app_port"],
  filter_dir: json_config["filter_dir"],
  halt_allow_ips:
    json_config["halt_allow_ips"]
    |> Enum.map(fn ip ->
      [a, b, c, d] =
        ip
        |> String.split(".")
        |> Enum.map(fn i ->
          i |> String.to_integer()
        end)

      {a, b, c, d}
    end)
    |> Enum.reduce(MapSet.new(), fn ip, set -> set |> MapSet.put(ip) end),
  frog_data_retention_days: Map.get(json_config, "frog_data_retention_days", 14)
