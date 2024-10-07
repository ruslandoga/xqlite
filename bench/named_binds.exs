# Commit: ...
# Date: Mon Oct  7 14:16:50 +07 2024

# Name                           ips        average  deviation         median         99th %
# bind_null                  11.46 M       87.26 ns  ±7117.92%          83 ns          84 ns
# bind_parameter_index        4.43 M      225.91 ns  ±2121.83%         208 ns         292 ns
# named bind_null             3.01 M      332.51 ns  ±4532.92%         250 ns         334 ns

db = XQLite.open(":memory:", [:readonly, :nomutex])
stmt = XQLite.prepare(db, "select :value")

Benchee.run(
  %{
    "bind_parameter_index" => fn ->
      XQLite.bind_parameter_index(stmt, ":value")
    end,
    "named bind_null" => fn ->
      XQLite.bind_null(db, stmt, XQLite.bind_parameter_index(stmt, ":value"))
    end,
    "bind_null" => fn ->
      XQLite.bind_null(db, stmt, 1)
    end
  },
  # https://github.com/bencheeorg/benchee/issues/389#issuecomment-1801511676
  time: 1
)
