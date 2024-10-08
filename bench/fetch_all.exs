# Commit: c4f5c0b33655b5bfca370c2ee719173365a1a7e3
# Date: Tue Oct  8 14:37:01 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# ##### With input 10 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all      247.83 K        4.04 μs   ±199.44%        3.92 μs        5.29 μs

# ##### With input 100 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all       37.68 K       26.54 μs    ±12.50%       27.42 μs       35.67 μs

# ##### With input 1000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        5.08 K      196.73 μs     ±5.33%      195.40 μs      221.98 μs

# ##### With input 10000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        549.36        1.82 ms     ±4.28%        1.77 ms        1.98 ms

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
