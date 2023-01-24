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
      {:ok, db} = Depo.open("/opt/eventcollector/data/db")

      Depo.transact(db, fn ->
        Depo.teach(db, %{
          new_event:
            "INSERT INTO greetings (id, epoch, persona, action, the_request, type, key, item, event) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"
        })

        data
        |> Enum.each(fn {type, key, item} ->
          Depo.write(db, :new_event, [
            id,
            epoch,
            persona,
            action,
            the_request,
            type,
            key,
            item,
            Jason.encode!(event)
          ])
        end)
      end)

      :ok = Depo.close(db)
    end)

    :ok
  end

  def parse_error([], _, ret), do: ret

  def parse_error([error | rest], type, ret) do
    parsed_error = {type, make_key(error), error}
    parse_error(rest, type, [parsed_error | ret])
  end

  def make_key(err) do
    [top_line | _] = String.split("\n", err)
    top_line
  end

  def handle_event(_) do
    :ok
  end
end
