# Commit: b9048130d8c01a3133c310b0bcae0e408596d595
# Date: Tue Oct  8 14:02:53 +07 2024

# Name                           ips        average  deviation         median         99th %
# bind_null                  24.87 M       40.20 ns  ±2031.14%          42 ns          42 ns
# bind_parameter_index        8.38 M      119.38 ns  ±3725.92%         125 ns         167 ns
# named bind_null             7.25 M      137.94 ns  ±3311.78%         125 ns         167 ns

Benchee.run(
  %{
    "bind_parameter_index" => fn %{stmt: stmt} ->
      XQLite.bind_parameter_index(stmt, ":value")
    end,
    "named bind_null" => fn %{stmt: stmt} ->
      XQLite.bind_null(stmt, XQLite.bind_parameter_index(stmt, ":value"))
    end,
    "bind_null" => fn %{stmt: stmt} ->
      XQLite.bind_null(stmt, 1)
    end
  },
  before_scenario: fn _input ->
    db = XQLite.open(":memory:", [:readonly, :nomutex])
    stmt = XQLite.prepare(db, "select :value")
    %{db: db, stmt: stmt}
  end,
  after_scenario: fn %{db: db, stmt: stmt} ->
    XQLite.finalize(stmt)
    XQLite.close(db)
  end,
  # https://github.com/bencheeorg/benchee/issues/389#issuecomment-1801511676
  time: 1
)
