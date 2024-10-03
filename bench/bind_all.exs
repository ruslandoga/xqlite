# Commit: 48e1f3f7fae55571e51b97ff02c66ecab71c2363
# Date: Thu Oct  3 13:33:38 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# Name                         ips        average  deviation         median         99th %
# bind_null                12.12 M       82.48 ns  ±4386.46%          83 ns         125 ns
# bind_text(nil)           11.52 M       86.77 ns  ±3589.59%          83 ns         125 ns
# bind_number(nil)         11.45 M       87.37 ns  ±3138.51%          83 ns         125 ns
# bind_number(int)         10.38 M       96.33 ns  ±3487.76%          83 ns         125 ns
# bind_text(text)           7.41 M      135.02 ns  ±2256.36%         125 ns         167 ns
# bind_number(float)        6.78 M      147.48 ns  ±2017.03%         125 ns         167 ns

db = XQLite.open(":memory:", [:readonly, :nomutex])
stmt = XQLite.prepare(db, "select ?")

Benchee.run(%{
  "bind_null" => fn ->
    XQLite.bind_null(db, stmt, 1)
  end,
  "bind_number(int)" => fn ->
    XQLite.bind_number(db, stmt, 1, 100)
  end,
  "bind_number(float)" => fn ->
    XQLite.bind_number(db, stmt, 1, 42.5)
  end,
  "bind_number(nil)" => fn ->
    XQLite.bind_number(db, stmt, 1, nil)
  end,
  "bind_text(text)" => fn ->
    XQLite.bind_text(db, stmt, 1, "hello")
  end,
  "bind_text(nil)" => fn ->
    XQLite.bind_text(db, stmt, 1, nil)
  end
})
