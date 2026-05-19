defmodule ProcessText do

  defp get_text(file_name) do
    current_path = Path.dirname(__ENV__.file) <> "/../assets"
    file_path = Path.join(current_path, file_name)
    File.read!(file_path)
  end

  defp splitlines(text), do: String.split(text, "\n", trim: true)

  defp remove_page_numbers(lines) do
    lines
    |> Enum.reject(fn str ->
      case Integer.parse(str) do
        {_, ""} -> true
        _ -> false
      end
    end)
  end



  defp concat_mem_verse(lines) do
    Enum.reduce_while(lines, {0, ""}, fn line, {count, concat_str} -> 
      case line do
        "Lesson " <> _ -> {:halt, {count, concat_str |> String.trim()}}
        "Heidelberg Catechism" <> _ -> {:halt, {count, concat_str |> String.trim()}}
        "—" -> {:cont, {count + 1, concat_str <> line}}
        _ -> {:cont, {count + 1, concat_str <> " " <> line}}
      end
    end)
  end
  defp concat_lesson(lines) do
    Enum.reduce_while(lines, {0, ""}, fn line, {count, concat_str} -> 
      case line do
        "Read: " <> _ -> {:halt, {count, concat_str |> String.trim()}}
        "Heidelberg Catechism Lord " <> _ -> {:halt, {count, concat_str |> String.trim()}}
        _ -> {:cont, {count + 1, concat_str <> " " <> line}}
      end
    end)
  end
  defp concat_read(lines) do
    Enum.reduce_while(lines, {0, ""}, fn line, {count, concat_str} -> 
      case line do
        "1. " <> _ -> {:halt, {count, concat_str |> String.trim()}}
        "Q. " <> _ -> {:halt, {count, concat_str |> String.trim()}}
        _ -> {:cont, {count + 1, concat_str <> " " <> line}}
      end
    end)
  end

  defp q?(line) do
    [number, rest] = String.split(line, ".", parts: 2)
    case Integer.parse(number) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp concat_q(lines) do
    Enum.reduce_while(lines, {0, ""}, fn line, {count, concat_str} -> 
      case String.last(line) do
        "." -> {:halt, {count + 1, concat_str <> " " <> line |> String.trim() }}
        "?" -> {:halt, {count + 1, concat_str <> " " <> line |> String.trim() }}
        _ -> {:cont, {count + 1, concat_str <> " " <> line }}
      end
    end)
  end

  defp concat_a(lines) do
    Enum.reduce_while(lines, {0, ""}, fn line, {count, concat_str} -> 
      case line do
        "Written Work" <> _ -> {:halt, {count, concat_str |> String.trim()}}
        <<u::utf8, ". ", _::binary>> when u in ?0..?9 -> {:halt, {count, concat_str |> String.trim()}}
        _ ->
          case String.last(line) do
            "." -> {:halt, {count + 1, concat_str <> " " <> line |> String.trim()}}
            "”" -> {:halt, {count + 1, concat_str <> " " <> line |> String.trim()}}
            _ -> {:cont, {count + 1, concat_str <> " " <> line}}
          end
      end
      # case String.last(line) do
      #   "." -> {:halt, {count + 1, concat_str <> " " <> line |> String.trim() }}
      #   _ -> {:cont, {count + 1, concat_str <> " " <> line }}
      # end
    end)
  end

  defp concat_others(lines) do
    Enum.reduce_while(lines, {0, ""}, fn line, {count, concat_str} -> 
      case String.last(line) do
        "”" -> {:halt, {count + 1, concat_str <> line |> String.trim() }}
        _ -> {:cont, {count + 1, concat_str}}
      end
    end)
  end

  defp concat_stray_lines([], result), do: Enum.reverse(result)
  defp concat_stray_lines([line | rest_lines] = lines, [latest_result | rest_result] = result) do
    case line do
      "”" -> concat_stray_lines(rest_lines, [latest_result <> line | rest_result])
      "Heidelberg Catechism Lord’s " <> _ ->
        {drop_count, str} = concat_lesson(lines)
        concat_stray_lines(Enum.drop(lines, drop_count), [str | result])
      "Lesson " <> _ ->
        {drop_count, str} = concat_lesson(lines)
        concat_stray_lines(Enum.drop(lines, drop_count), [str | result])
      "Read: " <> _ ->
        {drop_count, str} = concat_read(lines)
        concat_stray_lines(Enum.drop(lines, drop_count), [str | result])

      "Memory verse: " <> _ ->
        {drop_count, str} = concat_mem_verse(lines)
        concat_stray_lines(Enum.drop(lines, drop_count), [str | result])

      <<"a. ", _::binary>> -> 
        {drop_count, str} =  concat_a(lines)
        concat_stray_lines(Enum.drop(lines, drop_count), [str | result])

      <<"A. ", _::binary>> -> 
        {drop_count, str} =  concat_a(lines)
        concat_stray_lines(Enum.drop(lines, drop_count), [str | result])

      <<x::utf8, _::binary>> when x in ?0..?9 -> 
        case q?(line) do
          true -> 
            {drop_count, str} = concat_q(lines)
            concat_stray_lines(Enum.drop(lines, drop_count), [str | result])
          false -> concat_stray_lines(rest_lines, [line | result])
        end

      # <<x::utf8, y::utf8, ". ", _::binary>> when x in ?0..?9 and y in ?0..?9 -> 
      #   {drop_count, str} = concat_q(lines)
      #   concat_stray_lines(Enum.drop(lines, drop_count), [str | result])

      "Q. " <> _ -> 
        {drop_count, str} = concat_q(lines)
        concat_stray_lines(Enum.drop(lines, drop_count), [str | result])
      <<x::utf8, _::binary>> when x in ?a..?z -> concat_stray_lines(rest_lines, [latest_result <> " " <> line | rest_result])

        _ -> concat_stray_lines(rest_lines, [line | result])
    end
  end

  defp line_numbers_to_q([head | rest] = list, [one | numbers] = list_numbers, result) do
    list_numbers_len = length(list_numbers)
    first = "1. " <> binary_slice(head, (list_numbers_len * 3)..-1//1)

    {_, list_num_result, drop_count} = rest
      |> Enum.reduce_while({numbers, [], 0}, fn line, {numbers, result, count} -> 
        new_count = count + 1
        with [num | rest_numbers] <- numbers,
          first_char <- String.first(line),
          true <- String.upcase(first_char) == first_char do
          {:cont, {rest_numbers, ["#{num}. " <> line | result], new_count}}
        else
          false -> {:cont, {numbers, [line | result], new_count}}
          _ -> {:halt, {numbers, result, count}}
        end

      end)

    match_list_numbers(Enum.drop(rest, drop_count), list_num_result ++ [first | result])
  end

  defp process_list_numbers([str | rest] = list, result) do
    list_numbers = str
      |> String.split(". ")
      |> Enum.take_while(fn char -> 
        case Integer.parse(char) do
          {_number, ""} -> true
          _ -> false
        end
      end)

    case list_numbers do
      [head, second | rest] -> line_numbers_to_q(list, list_numbers, result)
      _ -> match_list_numbers(rest, [str | result])
    end
  end

  defp match_list_numbers([], result), do: Enum.reverse(result)
  defp match_list_numbers([str | rest] = list, result) do
    front = hd(String.split(str, ". ", parts: 2))

    case Integer.parse(front) do
      {_, ""} -> process_list_numbers(list, result)
      _ -> match_list_numbers(rest, [str | result])
    end
  end


  def init(file_name) do
    content = get_text(file_name)
      |> splitlines()
      |> remove_page_numbers()
      |> concat_stray_lines([""])
      |> match_list_numbers([])
      |> IO.inspect(limit: :infinity)
      |> Enum.join("\n")

    File.write!(Path.join(Path.dirname(__ENV__.file) <> "/../assets", "catechism-intermediate-2.txt"), content)
  end
end

ProcessText.init("catechism.txt")
