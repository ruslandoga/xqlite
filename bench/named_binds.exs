# Commit: 6b72ef2566696b5097b52af11ddc49c5c5e9d55c
# Date: Mon Oct  7 14:16:50 +07 2024

# Name                           ips        average  deviation         median         99th %
# bind_null                  11.46 M       87.26 ns  ±7117.92%          83 ns          84 ns
# bind_parameter_index        4.43 M      225.91 ns  ±2121.83%         208 ns         292 ns
# named bind_null             3.01 M      332.51 ns  ±4532.92%         250 ns         334 ns

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
