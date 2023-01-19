defmodule Eventcollector.Router do
  use Plug.Router

  plug(:match)
  plug(:dispatch)

  post "/event" do
    Eventcollector.Collector.add_event(EventCollector, conn.body_params)
    send_resp(conn, 200, "ok")
  end

  post "/halt" do
    conn |> IO.inspect()

    if conn.remote_ip == {127, 0, 0, 1} do
      Eventcollector.Collector.halt(EventCollector)
      System.stop(0)
    end

    send_resp(conn, 200, "ok")
  end

  match _ do
    send_resp(conn, 404, "oops")
  end
end
