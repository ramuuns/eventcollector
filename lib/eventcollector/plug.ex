defmodule Eventcollector.Plug do
  use Plug.Builder

  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Eventcollector.Router)
end
