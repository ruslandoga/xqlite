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
# fetch_all      197.54 K        5.06 μs   ±197.25%        4.58 μs        8.88 μs

# ##### With input 100 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all       21.58 K       46.34 μs    ±48.59%       40.54 μs      141.96 μs

# ##### With input 1000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        2.96 K      337.43 μs     ±9.53%      347.38 μs      397.77 μs

# ##### With input 10000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        349.03        2.87 ms    ±11.60%        3.16 ms        3.30 ms

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
