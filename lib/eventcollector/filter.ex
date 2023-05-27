defmodule Eventcollector.Filter do
  use GenServer

  def init({output_file, condition}) do
    {:ok,
     %{
       output_file: output_file,
       filter: make_function(condition)
     }}
  end

  def start_link(data) do
    GenServer.start_link(__MODULE__, data, [])
  end

  def apply_filter(pid, event) do
    GenServer.cast(pid, {:apply_filter, event})
  end

  def cleanup(pid) do
    GenServer.stop(pid, :normal)
  end

  @impl true
  def handle_cast({:apply_filter, event}, %{output_file: output_file, filter: filter} = state) do
    case filter.(event) do
      true ->
        Task.start(fn ->
          File.write!(output_file, event |> Jason.encode!(pretty: true), [:append])
        end)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  defp make_function(condition) do
    {the_fn, _} = Code.eval_string("fn event -> #{condition} end")
    the_fn
  end
end
