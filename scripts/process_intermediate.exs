Mix.install([:jason])

defmodule ProcessIntermediate do

  defp bible_names() do
    read_file("bible_names.json") |> JSON.decode!()
  end

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

  defp create_md5(str) do
    :crypto.hash(:md5, str)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 10)
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

  defp remove_number_from_str(nil), do: nil
  defp remove_number_from_str(str) do
    case String.split(str, [": ", ". "], parts: 2) do
    [_head, rest] -> rest
    [head] -> head
    end
  end

  defp process_written_work_list([], result), do: result
  defp process_written_work_list(["Written Work" | rest], _result) do
    Enum.map(rest, fn str ->
      str_content = remove_number_from_str(str)
      %{
        question: create_text_map(:question, str_content),
        uid: create_md5(str_content)
      }
    end)
  end

  defp group_qa([], result), do: Enum.reverse(result)
  defp group_qa(["a. " <> rest_str | rest], [curr_result | rest_result]) do
    group_qa(rest, [ 
      Map.put(curr_result, :answer, create_text_map(:answer, rest_str))
        |> Map.put(:uid, create_md5(hd(curr_result.question.words).text <> rest_str))
        | rest_result])
  end
  defp group_qa(["A. " <> rest_str | rest], [curr_result | rest_result]) do
    group_qa(rest, [
      Map.put(curr_result, :answer, create_text_map(:hc_answer, rest_str))
        |> Map.put(:uid, create_md5(hd(curr_result.question.words).text <> rest_str))
        | rest_result ])
  end

  defp group_qa([<<x::utf8, _rest::binary>> = str | rest], result) when x in ?0..?9 do
    [_num, question] = String.split(str, ". ", parts: 2)
    case question do
      "" -> group_qa(rest, [create_text_map(:unknown, str) | result])
      _ -> group_qa(rest, [ 
        %{
          question: create_text_map(:question, question)
        } | result])
    end
  end
  defp group_qa(["Q. " <> rest_str | rest], result) do
    group_qa(rest, [
      %{
        question: create_text_map(:hc_question, rest_str)
      } | result])
  end

  defp put_written_work_map(lesson_map, []), do: lesson_map
  defp put_written_work_map(lesson_map, nil), do: lesson_map
  defp put_written_work_map(lesson_map, written_work), do: Map.put(lesson_map, :written_work, written_work)

  defp process_memory_verse(memory_verse) do
    emDash = "—"
    [verse, ref] = memory_verse
      |> String.split(emDash, parts: 2)
    %{
      type: :memory_verse,
      words: [
        %{
          style: nil,
          text: remove_number_from_str(verse) <> emDash,
        },
        %{
          style: :bible_link,
          text: ref
        }
      ]
    }
  end

  defp create_creeds_link(str, creed) do
    %{
      style: :creeds_link,
      text: str,
      creed: creed,
      indexes: [[]]
    }
  end

  defp handle_creeds_link(str) do
    lower_str = String.downcase(str)
    cond do
      String.contains?(lower_str, ["heidelberg", "q&a", "lord’s day"]) -> create_creeds_link(str, :hc)
      String.contains?(lower_str, ["canons", "rejection"]) -> create_creeds_link(str, :cod)
      String.contains?(lower_str, ["belgic"]) -> create_creeds_link(str, :bc)
      String.contains?(lower_str, ["formula of subscription"]) -> create_creeds_link(str, :fos)
      String.contains?(lower_str, ["nicene"]) -> create_creeds_link(str, :nicene)
      String.contains?(lower_str, ["apostles"]) -> create_creeds_link(str, :apostles)
      true -> create_creeds_link(str, :unknown)
    end
  end

  defp put_mem_verse_map(lesson_map, []), do: lesson_map
  defp put_mem_verse_map(lesson_map, [memory_verse]), do: Map.put(lesson_map, :memory_verse, process_memory_verse(memory_verse))

  defp handle_readings(text) do
    list = text
      |> String.split("; ")
      |> Enum.map(fn str ->
      case String.contains?(String.upcase(str), bible_names()) do
        true -> %{style: :bible_link, text: str}
        false -> handle_creeds_link(str)
      end
    end)

    %{
      type: :read,
      words: list
    }

  end

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

      numberless_lesson_str = remove_number_from_str(lesson_str)


      %{
        text: create_text_map(:heading, numberless_lesson_str),
        uid: create_md5(numberless_lesson_str),
        read: handle_readings(remove_number_from_str(hd(read))),
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
      uid: create_md5(title),
      text: Map.update!(section_text_map, :words, fn words ->
        words ++ Enum.map(sub_headings, fn text -> %{text: text, style: "subheading"} end)
      end),
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
      text: create_text_map(:heading, str),
      read: %{},
      list: [],
      uid: create_md5(str)
    }

    handle_hc_readings(rest, [lesson_map | result])
  end
  defp handle_hc_readings([str | rest], [curr_lesson_map | rest_result]) do
    reading_map = case str do 
      x when x in ["Introductory Notes", "Formula of Subscription", "Frederick’s Preface to the Heidelberg Catechism", "Guido de Brès’ Preface to the Belgic Confession", "Conclusion of the Canons of Dordrecht"] ->
        %{curr_lesson_map | list: [create_text_map(:subheading, str) | curr_lesson_map.list]}
      "Source: " <> rest ->
        %{curr_lesson_map | list: [handle_source(rest) | curr_lesson_map.list]}
      "Read: " <> rest ->
        %{curr_lesson_map | read: handle_readings(rest)}

      _ -> %{curr_lesson_map | list: [create_text_map(:text, str) | curr_lesson_map.list]}
    end


    handle_hc_readings(rest, [reading_map | rest_result])
  end

  defp handle_source("Original Preface of Heidelberg Catechism (1563).pdf" = str) do
    %{
      type: :source,
      words: [
        %{
          style: :external_link,
          text: str,
          url: "https://heidelberg-catechism.s3.amazonaws.com/Original%20Preface%20of%20Heidelberg%20Catechism%20%281563%29.pdf"
        }
      ]
    }
  end
  defp handle_source(str) do
    create_text_map(:source, str)
  end




  defp handle_heidelberger(list) do
    {strs_left, headers} = get_hc_section_header(list, [])
    [section | sub_headings] = headers

    {strs_after_readings, readings} = handle_hc_readings(strs_left, [])
    {_drop_count, lessons} = process_lessons(strs_after_readings)

    section_text_map = create_text_map(:heading, section)

    result = %{
      text: Map.update!(section_text_map, :words, fn words ->
        words ++ Enum.map(sub_headings, fn text -> %{text: text, style: "subheading"} end)
      end),
      lessons: readings ++ lessons,
      uid: create_md5(Enum.join(headers, " "))
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
