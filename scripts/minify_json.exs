
Mix.install([:jason])

defmodule MinifyDataJSON do
  defp file_names() do
    data_path()
    |> Path.join("_version.json")
    |> File.read!()
    |> Jason.decode!()
    |> Enum.flat_map(fn {k, _v} ->
      case k do
        "max_app_version" -> []
        _ -> [k]
      end
    end)
  end

  defp data_path() do
    Path.dirname(__ENV__.file) <> "/../data"
  end

  defp read_file(file_name) do
    data_path()
    |> Path.join(["_", file_name, ".json"])
    |> File.read!()
  end


  defp minify() do
    file_names()
    |> Enum.map(fn file_name -> 
      minimized = read_file(file_name)
        |> Jason.Formatter.minimize_to_iodata([])
      {file_name, minimized}
    end)
  end

  defp save_to_files(files) do
    files
    |> Enum.each(fn {file_name, content} -> 
      File.write!(Path.join(data_path(), ["final/", file_name, ".json"]), content)
    end)
  end

  def main() do
    minify()
    |> save_to_files()
  end
end

MinifyDataJSON.main()
