Mix.install([:jason])

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
    |> Enum.map(& String.trim(&1))
  end

  defp title_drop_count(list) do
    Enum.reduce_while(list, {0, []}, fn str, {count, result} -> 
      case String.contains?(str, "Lesson 1: ") do
        true -> {:halt, {count, result |> Enum.reverse() }}
        false -> {:cont, {count + 1, [str | result]}}
      end
    end)
  end

  defp create_text_map(type, text, should_hash \\ false, style \\ nil) do

    text_map = %{
      type: type,
      words: [
        %{
          style: style,
          text: text
        }
      ]
    }

    case should_hash do
      true -> Map.put_new(text_map, :uid, :crypto.hash(:md5, text) |> Base.encode16(case: :lower) |> String.slice(0, 10))
      false -> text_map
    end

  end

  defp remove_number_from_str(nil), do: nil
  defp remove_number_from_str(str) do
    [_head, rest] = String.split(str, [": ", ". "], parts: 2)
    rest
  end

  defp process_written_work_list([], result), do: result
  defp process_written_work_list(["Written Work" | rest], result) do
    Enum.map(rest, fn str ->
      create_text_map(:question, remove_number_from_str(str), true)
    end)
  end

  defp group_qa([], result), do: Enum.reverse(result)
  defp group_qa(["a. " <> rest_str | rest], [curr_result | rest_result]) do
    group_qa(rest, [ Map.put(curr_result, :answer, create_text_map(:answer, rest_str)) | rest_result])
  end
  defp group_qa(["A. " <> rest_str | rest], [curr_result | rest_result]) do
    group_qa(rest, [Map.put(curr_result, :answer, create_text_map(:hc_answer, rest_str)) | rest_result])
  end

  defp group_qa([<<x::utf8, _rest::binary>> = str | rest], result) when x in ?0..?9 do
    [num, question] = String.split(str, ". ", parts: 2)
    case question do
      "" -> group_qa(rest, [create_text_map(:unknown, str) | result])
      _ -> group_qa(rest, [ 
        %{
          question: create_text_map(:question, question, true)
        } | result])
    end
  end
  defp group_qa(["Q. " <> rest_str | rest], result) do
    group_qa(rest, [
      %{
        question: create_text_map(:hc_question, rest_str, true)
      } | result])
  end

  defp put_written_work_map(lesson_map, []), do: lesson_map
  defp put_written_work_map(lesson_map, written_work), do: Map.put(lesson_map, :written_work, written_work)

  defp put_mem_verse_map(lesson_map, []), do: lesson_map
  defp put_mem_verse_map(lesson_map, memory_verse), do: Map.put(lesson_map, :memory_verse, create_text_map(:memory_verse, remove_number_from_str(hd(memory_verse))))

  defp process_each_lesson(lessons) do
    lessons
    |> Enum.map(fn [lesson_str | lines] ->
      {read, non_read} = Enum.split_with(lines, fn 
        "Read: " <> _ -> true 
        _ -> false
      end)

      {main, written_work} = Enum.split_while(non_read, fn str -> str != "Written Work" end)

      {qa, memory_verse} = Enum.split_while(main, fn 
        "Memory verse: " <> _ -> false
        "Memory Verse: " <> _ -> false
        "Memory Work: " <> _ -> false
        "Memory work: " <> _ -> false
        _ -> true
      end)

      list = group_qa(qa, [])
        |> IO.inspect(label: "qa")


      lesson_map = %{
        text: create_text_map(:heading, lesson_str, true),
        read: create_text_map(:read, remove_number_from_str(hd(read))),
        list: list
      }
        |> put_written_work_map(process_written_work_list(written_work, nil))
        |> put_mem_verse_map(memory_verse)
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
    [section | sub_headings] = title_list

    list_after_section_heading = Enum.drop(list, drop_count)

    {lesson_drop_count, lesson_list} = process_lessons(list_after_section_heading)

    section_text_map = create_text_map(:heading, section)

    result = %{
      section: %{
        text: Map.update!(section_text_map, :words, fn words ->
          words ++ Enum.map(sub_headings, fn text -> %{text: text, style: "subheading"} end)
        end)
      },
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
      text: create_text_map(:heading, str, true),
      read: %{},
      list: []
    }

    handle_hc_readings(rest, [lesson_map | result])
  end
  defp handle_hc_readings([str | rest], [curr_lesson_map | rest_result]) do
    reading_map = case str do 
      x when x in ["Introductory Notes", "Formula of Subscription", "Frederick’s Preface to the Heidelberg Catechism", "Guido de Brès’ Preface to the Belgic Confession", "Conclusion of the Canons of Dordrecht"] ->
        %{curr_lesson_map | list: [create_text_map(:subheading, str, true) | curr_lesson_map.list]}
      "Source: " <> _rest -> 
        %{curr_lesson_map | list: [create_text_map(:source, str) | curr_lesson_map.list]}
      "Read: " <> _rest ->
        %{curr_lesson_map | read: create_text_map(:read, str)}

      _ -> %{curr_lesson_map | list: [create_text_map(:text, str) | curr_lesson_map.list]}
    end


    handle_hc_readings(rest, [reading_map | rest_result])
  end




  defp handle_heidelberger(list) do
    {strs_left, headers} = get_hc_section_header(list, [])
    [section | sub_headings] = headers

    {strs_after_readings, readings} = handle_hc_readings(strs_left, [])

    {_drop_count, lessons} = process_lessons(strs_after_readings)

    section_text_map = create_text_map(:heading, section)

    result = %{
      section: %{
        text: Map.update!(section_text_map, :words, fn words ->
          words ++ Enum.map(sub_headings, fn text -> %{text: text, style: "subheading"} end)
        end)
      },
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

  defp validate_unique_hash(data) do
    data
    |> Enum.flat_map(fn item ->
      list_uid = Enum.flat_map(item.lessons, fn lesson -> Enum.map(lesson.list, fn li -> Map.get(li, :uid) end) end)
      [Map.get(item.section.text, :uid) | list_uid]
    end)
    |> Enum.reject(& &1 == nil)
    |> Enum.frequencies()
    |> Enum.filter(fn {_k, v} -> v > 1 end)

  end

  def main(file_name) do
    data = read_file(file_name)
      |> split_lines()
      # |> Enum.slice(5154..5586//1)
      |> group_sections([])
      |> Enum.reject(& &1 == nil)
      |> IO.inspect(limit: :infinity)

    json = data
      |> Jason.encode!()
      |> Jason.Formatter.pretty_print()

    validate_unique_hash(data)
    |> IO.inspect(limit: :infinity)

    Path.dirname(__ENV__.file) <> "/../data"
    |> Path.join("_catechism.json")
    |> File.write!(json)
  end
end

ProcessIntermediate.main("catechism-intermediate-2.txt")
