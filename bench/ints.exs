defmodule Bench do
  def bind_int(stmt) do
    XQLite.bind_int(stmt, 1, 10)
  end

  def bind_int_or_int64(stmt) do
    XQLite.bind_int_or_int64(stmt, 1, 10)
  end

  def bind_int64(stmt) do
    XQLite.bind_int64(stmt, 1, 10)
  end
end

Benchee.run(
  %{
    "bind_int" => &Bench.bind_int/1,
    "bind_int_or_int64" => &Bench.bind_int_or_int64/1,
    "bind_int64" => &Bench.bind_int64/1
  },
  before_scenario: fn _input ->
    db = XQLite.open(":memory:", [:readonly, :nomutex])
    XQLite.prepare(db, "select ?")
  end
)
