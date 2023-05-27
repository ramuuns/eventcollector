defmodule Eventcollector.Filters do
  use GenServer

  def init(_) do
    filters = check_for_and_create_filters(%{})
    Process.send_after(self(), :check_filters, 1_000 * 60)
    {:ok, %{filters: filters}}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def handle_info(:check_filters, %{filters: filters}) do
    Process.send_after(self(), :check_filters, 1_000 * 60)
    {:noreply, %{filters: filters |> check_for_and_create_filters()}}
  end

  def apply_filters(pid, event) do
    GenServer.cast(pid, {:apply_filters, event})
  end

  @impl true
  def handle_cast({:apply_filters, event}, %{filters: filters} = state) do
    Enum.each(filters, fn {_, filter_pid} ->
      Eventcollector.Filter.apply_filter(filter_pid, event)
    end)

    {:noreply, state}
  end

  def check_for_and_create_filters(current) do
    filter_dir = Application.fetch_env!(:eventcollector, :filter_dir)

    filters =
      case File.ls(filter_dir) do
        {:ok, files} ->
          files |> Enum.filter(fn file -> file =~ ~r/\.filter$/ end)

        {:error, error} ->
          error |> IO.inspect()
          []
      end

    filter_set = MapSet.new(filters)

    new =
      current
      |> Enum.reduce(current, fn {file, pid}, new ->
        if MapSet.member?(filter_set, file) do
          new
        else
          Eventcollector.Filter.cleanup(pid)
          new |> Map.delete(file)
        end
      end)

    filters
    |> Enum.reduce(new, fn file, new ->
      if Map.has_key?(new, file) do
        new
      else
        case File.read("#{filter_dir}/#{file}") do
          {:ok, contents} ->
            output_file = "#{filter_dir}/#{file}.output"
            condition = contents |> to_string()
            {:ok, pid} = Eventcollector.Filter.start_link({output_file, condition})
            new |> Map.put(file, pid)

          _ ->
            new
        end
      end
    end)
  end
end
