defmodule Frog do
  def handle_event(
        %{
          "id" => id,
          "epoch" => epoch,
          "persona" => persona,
          "action" => action,
          "tuning" => %{
            "the_request" => the_request,
            "unique_warnings" => warnings,
            "errors" => errors
          }
        } = event
      ) do
    Task.start(fn ->
      data = errors |> parse_error([])

      data =
        case warnings do
          [] -> data
          _ -> warnings |> Map.to_list() |> parse_warning(data)
        end

      unless Enum.empty?(data) do
        {:ok, db} = Depo.open("/opt/eventcollector/data/events.db")

        Depo.transact(db, fn ->
          Depo.teach(db, %{
            new_event: "INSERT INTO events (id, epoch, event) VALUES (?1, ?2, ?3)",
            new_error_warning:
              "INSERT INTO errors_warnings (event_id, epoch, persona, action, the_request, type, key, cnt, item) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"
          })

          Depo.write(db, :new_event, [id, epoch, Jason.encode!(event)])

          data
          |> Enum.each(fn {type, key, item, cnt} ->
            Depo.write(db, :new_error_warning, [
              id,
              epoch,
              persona,
              action,
              the_request,
              type,
              key,
              cnt,
              item
            ])
          end)
        end)

        :ok = Depo.close(db)
      end
    end)

    :ok
  end

  def handle_event(_) do
    :ok
  end

  def parse_error([], ret), do: ret

  def parse_error([error | rest], ret) do
    parsed_error = {:error, make_key(error), error, 1}
    parse_error(rest, [parsed_error | ret])
  end

  def parse_warning([], ret), do: ret

  def parse_warning([{warning, cnt} | rest], ret) do
    parsed_warning = {:warning, make_key(warning), warning, cnt}
    parse_warning(rest, [parsed_warning | ret])
  end

  def make_key(err) do
    [top_line | _] = String.split(err, "\n")
    :crypto.hash(:sha256, top_line |> merge_similar()) |> Base.encode64()
  end

  def cleanup() do
    # delete stuff that's older than $retention period in days
    # epoch = :os.system_time(:seconds)
    days = Application.fetch_env!(:eventcollector, :frog_data_retention_days)
    delete_older_than = :os.system_time(:seconds) - 60 * 60 * 24 * days
    {:ok, db} = Depo.open("/opt/eventcollector/data/events.db")

    Depo.transact(db, fn ->
      Depo.write(db, "DELETE FROM events WHERE epoch < ?1", [delete_older_than])
      Depo.write(db, "DELETE FROM errors_warnings WHERE epoch < ?1", [delete_older_than])
    end)

    :ok = Depo.close(db)
  end

  defp merge_similar(str) do
    str
    |> String.replace(~r"(\d+)ms", "XXms", global: true)
    |> String.replace(~r"(\d+)s", "XXs", gloabl: true)
    |> String.replace(~r"<[^>]+>", "<>", global: true)
    #  use only the first 100 chars of the error message (not that we can normalize otherwise errors with a bunch of keys in them)
    |> String.slice(0, 100)
  end
end
