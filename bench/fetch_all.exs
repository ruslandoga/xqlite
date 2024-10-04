# Commit: b7f5705b583bb570766e45ebf95857d51ace9669
# Date: Fri Oct  4 12:35:46 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# ##### With input 10 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all      239.86 K        4.17 μs   ±205.19%        4.08 μs        5.58 μs

# ##### With input 100 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all       30.10 K       33.23 μs    ±11.39%       33.54 μs       42.96 μs

# ##### With input 1000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        4.32 K      231.67 μs     ±3.97%      231.08 μs      265.76 μs

# ##### With input 10000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        469.37        2.13 ms     ±4.21%        2.18 ms        2.43 ms

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
