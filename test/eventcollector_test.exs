defmodule EventcollectorTest do
  use ExUnit.Case
  doctest Eventcollector

  test "greets the world" do
    assert Eventcollector.hello() == :world
  end
end
