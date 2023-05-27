defmodule Eventcollector.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Plug.Cowboy,
       scheme: :http,
       plug: Eventcollector.Plug,
       options: [port: Application.fetch_env!(:eventcollector, :app_port)]},
      {Eventcollector.Collector, name: EventCollector},
      {Eventcollector.Filters, name: EventCollectorFilters}
      # Starts a worker by calling: Eventcollector.Worker.start_link(arg)
      # {Eventcollector.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eventcollector.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
