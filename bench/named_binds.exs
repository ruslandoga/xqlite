# Commit: 753592cd7588e0c3132de5a7766230a077aeb3e6
# Date: Tue Oct  8 12:30:28 +07 2024

# Name                           ips        average  deviation         median         99th %
# bind_null                  20.05 M       49.87 ns   ±177.12%          42 ns          84 ns
# bind_parameter_index        6.58 M      152.01 ns  ±3150.23%         125 ns         209 ns
# named bind_null             5.90 M      169.58 ns  ±2826.46%         166 ns         250 ns

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
