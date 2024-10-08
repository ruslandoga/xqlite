# Commit: 4ba792923b90bb1daa66671e309348508ba34fd3
# Date: Fri Oct  4 14:15:11 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# ##### With input 10 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all      245.23 K        4.08 μs   ±197.25%           4 μs        5.50 μs

# ##### With input 100 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all       37.06 K       26.99 μs    ±15.49%       27.67 μs       36.08 μs

# ##### With input 1000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        4.96 K      201.76 μs     ±5.17%      201.42 μs      232.77 μs

# ##### With input 10000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        532.55        1.88 ms     ±4.70%        1.83 ms        2.17 ms

sql = """
with recursive cte(i) as (
  values(0)
  union all
  select i + 1 from cte where i < ?
)
select i, 'hello' || i, null from cte
"""

Benchee.run(
  %{"fetch_all" => fn %{stmt: stmt} -> XQLite.fetch_all(stmt) end},
  inputs: %{
    "10 rows" => 10,
    "100 rows" => 100,
    "1000 rows" => 1000,
    "10000 rows" => 10000
  },
  before_scenario: fn rows ->
    db = XQLite.open(":memory:", [:readonly, :nomutex])
    stmt = XQLite.prepare(db, sql, [:persistent])
    XQLite.bind_integer(stmt, 1, rows)
    %{db: db, stmt: stmt}
  end,
  after_scenario: fn %{db: db, stmt: stmt} ->
    XQLite.finalize(stmt)
    XQLite.close(db)
  end
)
