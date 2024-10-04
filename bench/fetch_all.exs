# Commit: c7cdc431196b6778227e4b4931ac70324d0364a2
# Date: Fri Oct  4 12:13:19 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# ##### With input 10 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all      149.61 K        6.68 μs   ±143.72%        5.25 μs       15.88 μs

# ##### With input 100 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all       18.37 K       54.43 μs    ±34.42%       49.79 μs      142.08 μs

# ##### With input 1000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        2.52 K      397.30 μs     ±6.82%      405.38 μs      454.21 μs

# ##### With input 10000 rows #####
# Name                ips        average  deviation         median         99th %
# fetch_all        291.83        3.43 ms     ±9.06%        3.54 ms        3.86 ms

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
