# Commit: 753592cd7588e0c3132de5a7766230a077aeb3e6
# Date: Tue Oct  8 12:29:33 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# ##### With input path: "./bench/insert_all.db", types: 2, rows: 1000 #####
# Name                 ips        average  deviation         median         99th %
# insert_all        4.22 K      237.01 μs    ±36.13%      232.83 μs      261.96 μs

# ##### With input path: "./bench/insert_all.db", types: 2, rows: 3 #####
# Name                 ips        average  deviation         median         99th %
# insert_all      547.67 K        1.83 μs   ±341.69%        1.71 μs        3.38 μs

# ##### With input path: ":memory:", types: 2, rows: 1000 #####
# Name                 ips        average  deviation         median         99th %
# insert_all        4.38 K      228.46 μs    ±15.41%      225.71 μs      259.29 μs

# ##### With input path: ":memory:", types: 2, rows: 3 #####
# Name                 ips        average  deviation         median         99th %
# insert_all      561.56 K        1.78 μs   ±178.78%        1.71 μs        2.25 μs

resource = fn input ->
  path = Keyword.fetch!(input, :path)
  flags = Keyword.fetch!(input, :flags)
  create = Keyword.fetch!(input, :create)
  insert = Keyword.fetch!(input, :insert)
  types = Keyword.fetch!(input, :types)
  rows = Keyword.fetch!(input, :rows)

  if File.exists?(path), do: File.rm!(path)
  if File.exists?(path <> "-wal"), do: File.rm!(path <> "-wal")
  if File.exists?(path <> "-shm"), do: File.rm!(path <> "-shm")

  db = XQLite.open(path, flags)
  XQLite.exec(db, create)

  begin = XQLite.prepare(db, "begin immediate", [:persistent])
  insert = XQLite.prepare(db, insert, [:persistent])
  rollback = XQLite.prepare(db, "rollback", [:persistent])

  %{
    before_scenario: fn ->
      :done = XQLite.step(begin)
    end,
    db: db,
    insert: insert,
    types: types,
    rows: rows,
    after_scenario: fn ->
      :done = XQLite.step(rollback)
      XQLite.finalize(begin)
      XQLite.finalize(insert)
      XQLite.finalize(rollback)
      XQLite.close(db)
    end
  }
end

inputs = [
  [
    path: ":memory:",
    flags: [:readwrite, :nomutex],
    create: "create table test(id integer, name text) strict",
    insert: "insert into test(id, name) values(?, ?)",
    types: [:integer, :text],
    rows: [[1, "Alice"], [2, "Bob"], [3, "Charlie"]]
  ],
  [
    path: ":memory:",
    flags: [:readwrite, :nomutex],
    create: "create table test(id integer, name text) strict",
    insert: "insert into test(id, name) values(?, ?)",
    types: [:integer, :text],
    rows: Stream.cycle([[1, "Alice"], [2, "Bob"], [3, "Charlie"]]) |> Enum.take(1000)
  ],
  [
    path: "./bench/insert_all.db",
    flags: [:create, :readwrite, :nomutex],
    create: "create table test(id integer, name text) strict",
    insert: "insert into test(id, name) values(?, ?)",
    types: [:integer, :text],
    rows: Stream.cycle([[1, "Alice"], [2, "Bob"], [3, "Charlie"]]) |> Enum.take(3)
  ],
  [
    path: "./bench/insert_all.db",
    flags: [:create, :readwrite, :nomutex, :wal],
    create: "create table test(id integer, name text) strict",
    insert: "insert into test(id, name) values(?, ?)",
    types: [:integer, :text],
    rows: Stream.cycle([[1, "Alice"], [2, "Bob"], [3, "Charlie"]]) |> Enum.take(1000)
  ]
]

Benchee.run(
  %{
    "insert_all" => fn input ->
      %{insert: insert, types: types, rows: rows} = input
      XQLite.insert_all(insert, types, rows)
    end
  },
  inputs:
    Map.new(inputs, fn input ->
      name =
        input
        |> Keyword.take([:path, :types, :rows])
        |> Keyword.update!(:rows, &length/1)
        |> Keyword.update!(:types, &length/1)
        |> Enum.map(fn {key, value} -> "#{key}: #{inspect(value)}" end)
        |> Enum.join(", ")

      {name, input}
    end),
  before_scenario: fn input ->
    resource = resource.(input)
    resource.before_scenario.()
    resource
  end,
  after_scenario: fn resource ->
    resource.after_scenario.()
  end
)
