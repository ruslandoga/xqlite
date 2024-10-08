# Commit: 74097a2ad636df6b720f37cedb09a32ff620a622
# Date: Sat Oct  5 01:10:17 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# Name                        ips        average  deviation         median         99th %
# bind_null               24.02 M       41.63 ns  ±6270.98%          42 ns          42 ns
# bind_float(float)       23.41 M       42.71 ns  ±5966.85%          42 ns          42 ns
# bind_integer(int)       23.26 M       43.00 ns  ±6126.14%          42 ns          42 ns
# bind_blob(bin)          20.05 M       49.87 ns  ±5774.13%          42 ns          84 ns
# bind_text(text)         19.81 M       50.48 ns  ±5215.76%          42 ns          84 ns

Benchee.run(
  %{
    "bind_null" => fn %{stmt: stmt} -> XQLite.bind_null(stmt, 1) end,
    "bind_integer(int)" => fn %{stmt: stmt} -> XQLite.bind_integer(stmt, 1, 100) end,
    "bind_float(float)" => fn %{stmt: stmt} -> XQLite.bind_float(stmt, 1, 42.5) end,
    "bind_text(text)" => fn %{stmt: stmt} -> XQLite.bind_text(stmt, 1, "hello") end,
    "bind_blob(bin)" => fn %{stmt: stmt} -> XQLite.bind_blob(stmt, 1, <<0, 0, 0>>) end
  },
  before_scenario: fn _input ->
    db = XQLite.open(":memory:", [:readonly, :nomutex])
    stmt = XQLite.prepare(db, "select ?")
    %{db: db, stmt: stmt}
  end,
  after_scenario: fn %{db: db, stmt: stmt} ->
    XQLite.finalize(stmt)
    XQLite.close(db)
  end,
  # https://github.com/bencheeorg/benchee/issues/389#issuecomment-1801511676
  time: 1
)
