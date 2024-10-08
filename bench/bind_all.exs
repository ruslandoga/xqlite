# Commit: 753592cd7588e0c3132de5a7766230a077aeb3e6
# Date: Tue Oct  8 12:26:57 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# Name                   ips        average  deviation         median         99th %
# bind_null          24.30 M       41.16 ns  ±5503.83%          42 ns          42 ns
# bind_integer       23.59 M       42.39 ns  ±5375.42%          42 ns          42 ns
# bind_float         23.54 M       42.48 ns  ±5892.62%          42 ns          42 ns
# bind_blob          19.71 M       50.74 ns  ±4647.68%          42 ns          84 ns
# bind_text          19.58 M       51.06 ns  ±5114.93%          42 ns          84 ns

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
