defmodule Frog do
  def handle_event(
        %{
          "id" => id,
          "epoch" => epoch,
          "persona" => persona,
          "action" => action,
          "tuning" => %{"the_request" => the_request, "warnings" => warnings, "errors" => errors}
        } = event
      ) do
    Task.start(fn ->
      data = errors |> parse_error(:error, [])
      data = warnings |> parse_error(:warning, data)
      {:ok, db} = Depo.open("/opt/eventcollector/data/events.db")

      Depo.transact(db, fn ->
        Depo.teach(db, %{
          new_event: "INSERT INTO events (id, epoch, event) VALUES (?1, ?2, ?3)",
          new_error_warning:
            "INSERT INTO errors_warnings (event_id, epoch, persona, action, the_request, type, key, item) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"
        })

        Depo.write(db, :new_event, [id, epoch, Jason.encode!(event)])

        data
        |> Enum.each(fn {type, key, item} ->
          Depo.write(db, :new_error_warning, [
            id,
            epoch,
            persona,
            action,
            the_request,
            type,
            key,
            item
          ])
        end)
      end)

      :ok = Depo.close(db)
    end)

    :ok
  end

  def handle_event(_) do
    :ok
  end

  def parse_error([], _, ret), do: ret

  def parse_error([error | rest], type, ret) do
    parsed_error = {type, make_key(error), error}
    parse_error(rest, type, [parsed_error | ret])
  end

  def make_key(err) do
    [top_line | _] = String.split(err, "\n")
    top_line
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
end
