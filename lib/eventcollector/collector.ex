defmodule Eventcollector.Collector do
  use GenServer

  @impl true
  def init(_) do
    ensure_db()
    {m_send, m_data} = get_initial_state(:minutely)
    {q_send, q_data} = get_initial_state(:quarterly)
    {h_send, h_data} = get_initial_state(:hourly)
    # [m_send, q_send, h_send] |> IO.inspect()
    Process.send_after(self(), :minutely, m_send)
    Process.send_after(self(), :quarterly, q_send)
    Process.send_after(self(), :hourly, h_send)
    store_when(m_send, :minutely)
    store_when(q_send, :quarterly)
    store_when(h_send, :hourly)
    {:ok, {m_data, q_data, h_data}}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def add_event(pid, event) do
    GenServer.cast(pid, {:add_event, event})
  end

  def halt(pid) do
    GenServer.call(pid, :halt)
  end

  @impl true
  def handle_cast(
        {:add_event,
         %{"action" => _, "persona" => _, "tuning" => %{"the_request" => _, "wallclock_ms" => _}} =
           event},
        {minutely, quarterly, hourly}
      ) do
    Frog.handle_event(event)
    Eventcollector.Filters.apply_filters(EventCollectorFilters, event)
    {:noreply, {[event | minutely], [event | quarterly], [event | hourly]}}
  end

  @impl true
  def handle_cast({:add_event, _ev}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:halt, _from, {minutely, quarterly, hourly}) do
    save_data(minutely, :minutely)
    save_data(quarterly, :quarterly)
    save_data(hourly, :hourly)
    {:reply, :ok, {[], [], []}}
  end

  @impl true
  def handle_info(:minutely, {minutely, quarterly, hourly}) do
    Process.send_after(self(), :minutely, 60 * 1000)
    store_when(60 * 1000, :minutely)
    Task.async(fn -> process_data(minutely, :minutely) end)
    {:noreply, {[], quarterly, hourly}}
  end

  @impl true
  def handle_info(:quarterly, {minutely, quarterly, hourly}) do
    Process.send_after(self(), :quarterly, 15 * 60 * 1000)
    store_when(15 * 60 * 1000, :quarterly)
    Task.async(fn -> process_data(quarterly, :quarterly) end)
    {:noreply, {minutely, [], hourly}}
  end

  @impl true
  def handle_info(:hourly, {minutely, quarterly, hourly}) do
    Process.send_after(self(), :hourly, 60 * 60 * 1000)
    store_when(60 * 60 * 1000, :hourly)

    Task.async(fn ->
      process_data(hourly, :hourly)
      Frog.cleanup()
    end)

    {:noreply, {minutely, quarterly, []}}
  end

  @impl true
  def handle_info(_, data) do
    {:noreply, data}
  end

  defp process_data(data, mode) do
    {result, averages_and_histograms, _count} = data |> process_items({%{}, %{}, 0})

    result =
      averages_and_histograms
      |> Map.keys()
      |> Enum.reduce(
        result,
        fn key, res ->
          sorted = averages_and_histograms |> Map.get(key) |> Enum.sort()
          min = Enum.min(sorted)
          max = Enum.max(sorted)
          count = Enum.count(sorted)
          average = Enum.sum(sorted) / count
          pct_50 = Float.ceil(count / 2) - 1
          pct_75 = Float.ceil(count * 0.75) - 1
          pct_90 = Float.ceil(count * 0.9) - 1
          pct_95 = Float.ceil(count * 0.95) - 1
          pct_99 = Float.ceil(count * 0.99) - 1

          {_, res} =
            sorted
            |> Enum.reduce({0, res}, fn
              value, {i, res} ->
                res = if i == pct_50, do: res |> Map.put("#{key}_p50", value), else: res
                res = if i == pct_75, do: res |> Map.put("#{key}_p75", value), else: res
                res = if i == pct_90, do: res |> Map.put("#{key}_p90", value), else: res
                res = if i == pct_95, do: res |> Map.put("#{key}_p95", value), else: res
                res = if i == pct_99, do: res |> Map.put("#{key}_p99", value), else: res
                {i + 1, res}
            end)

          res
          |> Map.put("#{key}_avg", average)
          |> Map.put("#{key}_max", max)
          |> Map.put("#{key}_min", min)
        end
      )

    send_data(result, mode)
  end

  defp process_items([], res), do: res

  defp process_items([item | rest], {result, averages_and_histograms, count}) do
    process_items(
      rest,
      {result |> add_to_result(item),
       averages_and_histograms |> add_to_averages_and_histograms(item), count + 1}
    )
  end

  defp add_to_result(result, item) do
    persona = item["persona"]
    action = item["action"]
    [method, _] = item["tuning"]["the_request"] |> String.split(" ", parts: 2)

    counters = [
      "#{persona}.all.nr_requests",
      "#{persona}.all.nr_requests_#{method}",
      "#{persona}.action.#{action}.nr_requests",
      "#{persona}.action.#{action}.nr_requests_#{method}"
    ]

    counters =
      case item do
        %{"tuning" => %{"status" => status}} ->
          [
            "#{persona}.all.status_#{status}",
            "#{persona}.action.#{action}.status_#{status}" | counters
          ]

        _ ->
          counters
      end

    counters
    |> Enum.reduce(result, fn key, result ->
      result |> Map.put(key, Map.get(result, key, 0) + 1)
    end)
    |> maybe_count_errors_warnings(item)
  end

  def maybe_count_errors_warnings(
        result,
        %{
          "persona" => persona,
          "action" => action,
          "tuning" => %{"nr_errors" => nr_errors, "nr_warnings" => nr_warnings}
        } = item
      ) do
    sums = [
      {"#{persona}.all.nr_errors", nr_errors},
      {"#{persona}.all.nr_warnings", nr_warnings},
      {"#{persona}.action.#{action}.nr_errors", nr_errors},
      {"#{persona}.action.#{action}.nr_warnings", nr_warnings}
    ]

    sums =
      case item do
        %{"tuning" => %{"nr_queries" => nr_queries}} ->
          [
            {"#{persona}.all.nr_queries", nr_queries},
            {"#{persona}.action.#{action}.nr_queries", nr_queries} | sums
          ]

        _ ->
          sums
      end

    sums
    |> Enum.reduce(result, fn {key, value}, result ->
      result |> Map.put(key, Map.get(result, key, 0) + value)
    end)
  end

  def maybe_count_errors_warnings(result, _), do: result

  defp add_to_averages_and_histograms(result, item) do
    persona = item["persona"]
    action = item["action"]
    wallclock_ms = item["tuning"]["wallclock_ms"]

    keys = [
      {"#{persona}.all.wallclock_ms", wallclock_ms},
      {"#{persona}.action.#{action}.wallclock_ms", wallclock_ms}
    ]

    keys =
      case item do
        %{"tuning" => %{"wallclock_queries" => wallclock_queries}} ->
          [
            {"#{persona}.all.wallclock_queries", wallclock_queries},
            {"#{persona}.action.#{action}.wallclock_queries", wallclock_queries}
            | keys
          ]

        _ ->
          keys
      end

    keys =
      case item do
        %{"tuning" => %{"process_memory_bytes_added" => bytes_added}} ->
          [
            {"#{persona}.all.process_memory_bytes_added", bytes_added},
            {"#{persona}.action.#{action}.process_memory_bytes_added", bytes_added}
            | keys
          ]

        _ ->
          keys
      end

    keys
    |> Enum.reduce(result, fn {key, value}, result ->
      result |> Map.put(key, [value | Map.get(result, key, [])])
    end)
  end

  defp send_data(result, mode) do
    epoch = :os.system_time(:seconds)
    IO.inspect("sending data for #{mode} (#{epoch})")
    port = Application.fetch_env!(:eventcollector, :graphite_port)
    host = Application.fetch_env!(:eventcollector, :graphite_host)
    opts = [:binary, active: false]

    case :gen_tcp.connect(host, port, opts) do
      {:ok, socket} ->
        result
        |> Map.keys()
        |> Enum.each(fn key ->
          val = Map.get(result, key)
          key = "tuning.#{mode}.#{key}"
          message = ~c"#{key} #{val} #{epoch}\n"

          case :gen_tcp.send(socket, message) do
            :ok ->
              :ok

            other ->
              {
                other,
                "failed sending #{message}"
              }
              |> IO.inspect()
          end
        end)

        :gen_tcp.close(socket)

      {:error, err} ->
        IO.inspect(err)
        IO.inspect(result)
    end
  end

  defp store_when(seconds, mode) do
    the_when = :os.system_time(:seconds) + (seconds |> div(1000))

    case File.write("/tmp/eventcollector-#{mode}-next", "#{the_when}") do
      :ok -> ""
      {:error, reason} -> reason |> IO.inspect()
    end
  end

  defp save_data(data, mode) do
    case File.write("/tmp/eventcollector-#{mode}-data", Jason.encode!(data)) do
      :ok -> ""
      {:error, reason} -> reason |> IO.inspect()
    end
  end

  defp mode_to_minutes(:minutely), do: 1
  defp mode_to_minutes(:quarterly), do: 15
  defp mode_to_minutes(:hourly), do: 60

  defp get_initial_state(mode) do
    the_when =
      case File.read("/tmp/eventcollector-#{mode}-next") do
        {:ok, bin} ->
          Enum.max([
            bin
            |> String.to_integer()
            |> then(fn t -> t - :os.system_time(:seconds) end),
            0
          ]) * 1000

        {:error, _reason} ->
          mode_to_minutes(mode) * 60 * 1000
      end

    the_data =
      case File.read("/tmp/eventcollector-#{mode}-data") do
        {:ok, bin} -> bin |> Jason.decode!()
        {:error, _reason} -> []
      end

    {the_when, the_data}
  end

  defp ensure_db() do
    unless File.exists?("/opt/eventcollector/data/events.db") do
      {:ok, db} = Depo.open(create: "/opt/eventcollector/data/events.db")

      Depo.transact(db, fn ->
        Depo.write(db, "CREATE TABLE events(id, epoch, event)")

        Depo.write(
          db,
          "CREATE TABLE errors_warnings (event_id, epoch, persona, action, the_request, type, key, cnt, item)"
        )
      end)

      :ok = Depo.close(db)
    end
  end
end
