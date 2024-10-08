# Commit: 753592cd7588e0c3132de5a7766230a077aeb3e6
# Date: Tue Oct  8 12:28:17 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# ##### With input 10 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all      245.90 K        4.07 μs   ±145.42%        3.96 μs        5.46 μs

# ##### With input 100 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all       36.74 K       27.21 μs    ±15.49%       27.71 μs       36.13 μs

# ##### With input 1000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        4.99 K      200.58 μs     ±5.08%      199.88 μs      226.84 μs

# ##### With input 10000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        542.23        1.84 ms     ±4.16%        1.80 ms        1.99 ms

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
