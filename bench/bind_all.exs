# Commit: c7cdc431196b6778227e4b4931ac70324d0364a2
# Date: Fri Oct  4 12:06:49 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# Name                         ips        average  deviation         median         99th %
# bind_null                16.82 M       59.44 ns ±21786.91%          42 ns          84 ns
# bind_text(nil)           16.09 M       62.16 ns ±20288.25%          42 ns          84 ns
# bind_blob(nil)           16.01 M       62.47 ns ±20250.50%          42 ns          84 ns
# bind_number(nil)         15.98 M       62.56 ns ±20084.52%          42 ns          84 ns
# bind_number(int)         15.56 M       64.27 ns ±13866.89%          42 ns          84 ns
# bind_blob(bin)           11.79 M       84.81 ns ±10521.00%          83 ns          84 ns
# bind_text(text)          11.66 M       85.73 ns ±10866.61%          83 ns          84 ns
# bind_number(float)       11.33 M       88.22 ns ±10524.39%          83 ns         125 ns

db = XQLite.open(":memory:", [:readonly, :nomutex])
stmt = XQLite.prepare(db, "select ?")

Benchee.run(
  %{
    "bind_null" => fn ->
      XQLite.bind_null(db, stmt, 1)
    end,
    "bind_integer(int)" => fn ->
      XQLite.bind_integer(db, stmt, 1, 100)
    end,
    "bind_float(float)" => fn ->
      XQLite.bind_float(db, stmt, 1, 42.5)
    end,
    "bind_text(text)" => fn ->
      XQLite.bind_text(db, stmt, 1, "hello")
    end,
    "bind_blob(bin)" => fn ->
      XQLite.bind_blob(db, stmt, 1, <<0, 0, 0>>)
    end
  },
  # https://github.com/bencheeorg/benchee/issues/389#issuecomment-1801511676
  time: 1
)
