defmodule ProcessIntermediate do
  defp section_headings(), do: [
    "New Testament History",
    "Old Testament History",
    "Heidelberg Catechism",
    "Essentials of Reformed Doctrine"
  ]

  defp read_file(file_name) do
    Path.dirname(__ENV__.file) <> "/../assets"
    |> Path.join(file_name)
    |> File.read!()
  end

  defp split_lines(text) do
    text
    |> String.split("\n", trim: true)
  end

  defp title_drop_count(list) do
    Enum.reduce_while(list, {0, []}, fn str, {count, result} -> 
      case String.contains?(str, "Lesson 1: ") do
        true -> {:halt, {count, result |> Enum.reverse() }}
        false -> {:cont, {count + 1, [str | result]}}
      end
    end)
  end

  defp create_text_map(type, text, style \\ nil) do
    %{
      type: type,
      words: [
        %{
          style: style,
          text: text
        }
      ]
    }
  end

  defp remove_number_from_str(str) do
    [_head, rest] = String.split(str, ". ", parts: 2)
    rest
  end

  defp process_each_lesson(lessons) do
    lessons
    |> Enum.map(fn [lesson_str | qa] ->
      lesson_map = %{
        text: create_text_map("heading", lesson_str),
        read: %{},
        list: []
      }

      Enum.reduce(qa, lesson_map, fn str, lesson_map -> 
        case str do
          "Read: " <> rest -> %{lesson_map | read: create_text_map("read", rest)} 
          "a. " <> _rest -> %{lesson_map | list: [ create_text_map("answer", str) | lesson_map.list]}
          "A. " <> _rest -> %{lesson_map | list: [ create_text_map("answer", str) | lesson_map.list]}
          "Q. " <> _rest -> %{lesson_map | list: [ create_text_map("question", str) | lesson_map.list]}
          <<x::utf8, _rest::binary>> when x in ?0..?9 -> %{lesson_map | list: [ create_text_map("question", str) | lesson_map.list]}
          "Memory verse: " <> _rest -> %{lesson_map | list: [ create_text_map("memoryverse", str) | lesson_map.list]}
          _ -> %{lesson_map | list: [ create_text_map("answer", str) | lesson_map.list]}
        end
      end)
      |> Map.update!(:list, & Enum.reverse(&1))
    end)
  end

  defp group_by_lessons([], strs), do: strs |> Enum.map(& Enum.reverse/1) |> Enum.reverse()
  defp group_by_lessons([head_str | rest], [latest | rest_result] = result) do
    case head_str do
      "Lesson " <> _rest -> group_by_lessons(rest, [[head_str] | result])
      "Heidelberg Catechism Lord’s " <> _rest -> group_by_lessons(rest, [[head_str] | result])
      _ -> group_by_lessons(rest, [[head_str | latest] | rest_result])
    end
  end

  defp process_lessons(list) do
    {drop_count, strs} = list
      |> Enum.reduce_while({0, []}, fn str, {count, result} -> 
        case str in section_headings() do
          false -> {:cont, {count + 1, [str | result] }}
          true -> {:halt, {count, result }}
        end
      end)

    {drop_count, group_by_lessons(Enum.reverse(strs), [[]]) |> Enum.reject(& &1 == []) |> process_each_lesson()}
  end

  defp handle_lesson_generic(list) do
    {drop_count, title_list} = title_drop_count(list)
    title = title_list |> Enum.join(" ")
    [section | sub_section] = title_list

    list_after_section_heading = Enum.drop(list, drop_count)

    {lesson_drop_count, lesson_list} = process_lessons(list_after_section_heading)

    result = %{
      section: %{
        raw: section,
        text: [create_text_map("heading", section)]
      },
      sub_section: Enum.map(sub_section, fn text -> 
        %{
          raw: text,
          text: [create_text_map("subheading", text)]
        }
      end),
      raw: title,
      lessons: lesson_list
    }

    {drop_count + lesson_drop_count, result}
  end

  defp get_hc_section_header([], result), do: {[], Enum.reverse(result)}
  defp get_hc_section_header(["Introduction to the Belgic Confession, Canons of Dordtrecht, and Heidelberg Catechism" | _rest] = strs_left, result), do: {strs_left, Enum.reverse(result)}
  defp get_hc_section_header(["Heidelberg Catechism Lord’s Day 1" | _rest] = strs_left, result), do: {strs_left, Enum.reverse(result)}
  defp get_hc_section_header([str | rest], result) do
    get_hc_section_header(rest, [str | result])
  end

  defp handle_hc_readings(["Heidelberg Catechism Lord’s Day 1" | _rest_str] = list, result), do: {list, result |> Enum.map(& %{&1 | list: Enum.reverse(&1.list)}) |> Enum.reverse()}
  defp handle_hc_readings(["Introduction to the Belgic Confession, Canons of Dordtrecht, and Heidelberg Catechism" = str | rest], result) do
    lesson_map = %{
      lesson: str,
      text: create_text_map("heading", str),
      read: %{},
      list: []
    }

    handle_hc_readings(rest, [lesson_map | result])
  end
  defp handle_hc_readings([str | rest], [curr_lesson_map | rest_result]) do
    reading_map = case str do 
      x when x in ["Introductory Notes", "Formula of Subscription", "Frederick’s Preface to the Heidelberg Catechism", "Guido de Brès’ Preface to the Belgic Confession", "Conclusion of the Canons of Dordrecht"] ->
        %{curr_lesson_map | list: [create_text_map("subheading", str) | curr_lesson_map.list]}
      "Source: " <> _rest -> 
        %{curr_lesson_map | list: [create_text_map("source", str) | curr_lesson_map.list]}
      "Read: " <> _rest ->
        %{curr_lesson_map | read: create_text_map("read", str)}

      _ -> %{curr_lesson_map | list: [create_text_map("text", str) | curr_lesson_map.list]}
    end


    handle_hc_readings(rest, [reading_map | rest_result])
  end




  defp handle_heidelberger(list) do
    {strs_left, headers} = get_hc_section_header(list, [])
    [section | sub_section] = headers

    {strs_after_readings, readings} = handle_hc_readings(strs_left, [])

    {_drop_count, lessons} = process_lessons(strs_after_readings)

    result = %{
      section: %{
        raw: section,
        text: [create_text_map("heading", section)]
      },
      sub_section: Enum.map(sub_section, fn text -> 
        %{
          raw: text,
          text: [create_text_map("subheading", text)]
        }
      end),
      raw: Enum.join(headers, " "),
      lessons: readings ++ lessons
    }

    {strs_after_readings, result}

  end


  defp group_sections([], result), do: Enum.reverse(result)
  defp group_sections([str | rest] = list, result) do
    case str do
      "Old Testament History" -> 
        {drop_count, section_result} = handle_lesson_generic(list)

        group_sections(Enum.drop(list, drop_count), [section_result | result])
      "New Testament History" ->
        {drop_count, section_result} = handle_lesson_generic(list)

        group_sections(Enum.drop(list, drop_count), [section_result | result])

      "Essentials of Reformed Doctrine" ->
        {drop_count, section_result} = handle_lesson_generic(list)

        group_sections(Enum.drop(list, drop_count), [section_result | result])

      "Heidelberg Catechism" ->
        {strs_left, headers} = handle_heidelberger(list)

        group_sections(strs_left, [headers | result])

      _ -> group_sections(rest, result)

    end
  end

  def main(file_name) do
    json = read_file(file_name)
      |> split_lines()
      # |> Enum.slice(5154..5586//1)
      |> group_sections([])
      |> Enum.reject(& &1 == nil)
      |> IO.inspect(limit: :infinity)
      |> JSON.encode_to_iodata!()

    Path.dirname(__ENV__.file) <> "/../data"
    |> Path.join("catechism.json")
    |> File.write!(json)
  end
end

ProcessIntermediate.main("catechism-intermediate-2.txt")
