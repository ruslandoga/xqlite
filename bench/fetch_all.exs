# Commit: 08bc57c6a278dcdcd478d528162b3cb2982e09d0
# Date: Thu Oct  3 14:43:57 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# ##### With input 10 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all       53.32 K       18.75 μs    ±58.71%       17.67 μs       40.71 μs

# ##### With input 100 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all       12.54 K       79.72 μs    ±35.58%       68.79 μs      218.65 μs

# ##### With input 1000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        1.48 K      674.92 μs     ±6.37%      684.25 μs      751.03 μs

# ##### With input 10000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        167.57        5.97 ms     ±8.90%        6.37 ms        6.60 ms

sql = """
with recursive cte(i,t) as (
  select 1, 'hello1'
  union all
  select i + 1, 'hello' || i
  from cte
  where i < ?
)
select * from cte
"""

Benchee.run(
  %{
    "fetch_all" => fn resource ->
      %{db: db, stmt: stmt} = resource
      XQLite.fetch_all(db, stmt)
    end
  },
  inputs: %{
    "10 rows" => 10,
    "100 rows" => 100,
    "1000 rows" => 1000,
    "10000 rows" => 10000
  },
  before_scenario: fn rows ->
    db = XQLite.open(":memory:", [:readonly, :nomutex])
    stmt = XQLite.prepare(db, sql, [:persistent])
    XQLite.bind_number(db, stmt, 1, rows)
    %{db: db, stmt: stmt}
  end,
  after_scenario: fn %{db: db, stmt: stmt} ->
    XQLite.finalize(stmt)
    XQLite.close(db)
  end
)
