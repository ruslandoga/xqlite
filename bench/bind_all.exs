# Commit: bc9590788a32763c95d01e5ab494bcb22e8fc0d4
# Date: Tue Oct  8 14:01:09 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# Name                   ips        average  deviation         median         99th %
# bind_null          23.88 M       41.88 ns  ±5813.10%          42 ns          42 ns
# bind_float         23.19 M       43.12 ns  ±5936.34%          42 ns          42 ns
# bind_integer       22.92 M       43.63 ns  ±6434.12%          42 ns          42 ns
# bind_blob          20.16 M       49.61 ns  ±5284.18%          42 ns          84 ns
# bind_text          20.06 M       49.86 ns  ±4985.34%          42 ns          84 ns

Benchee.run(
  %{
    "bind_null" => fn %{stmt: stmt} -> XQLite.bind_null(stmt, 1) end,
    "bind_integer" => fn %{stmt: stmt} -> XQLite.bind_integer(stmt, 1, 100) end,
    "bind_float" => fn %{stmt: stmt} -> XQLite.bind_float(stmt, 1, 42.5) end,
    "bind_text" => fn %{stmt: stmt} -> XQLite.bind_text(stmt, 1, "hello") end,
    "bind_blob" => fn %{stmt: stmt} -> XQLite.bind_blob(stmt, 1, <<0, 0, 0>>) end
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
