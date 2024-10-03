# Commit: 48e1f3f7fae55571e51b97ff02c66ecab71c2363
# Date: Thu Oct  3 14:17:20 +07 2024

# Operating System: macOS
# CPU Information: Apple M2
# Number of Available Cores: 8
# Available memory: 8 GB
# Elixir 1.17.1
# Erlang 27.0
# JIT enabled: true

# ##### With input [path: "./bench/insert_all.db", flags: [:create, :readwrite, :nomutex, :wal], types: [:integer, :text], rows: 1000] #####
# Name                 ips        average  deviation         median         99th %
# insert_all        2.40 K      416.96 μs    ±29.87%      404.46 μs      811.94 μs

# ##### With input [path: "./bench/insert_all.db", flags: [:create, :readwrite, :nomutex], types: [:integer, :text], rows: 3] #####
# Name                 ips        average  deviation         median         99th %
# insert_all      315.74 K        3.17 μs   ±381.10%        3.04 μs        6.21 μs

# ##### With input [path: ":memory:", flags: [:readwrite, :nomutex], types: [:integer, :text], rows: 1000] #####
# Name                 ips        average  deviation         median         99th %
# insert_all        2.54 K      393.84 μs    ±23.09%      390.50 μs      427.30 μs

# ##### With input [path: ":memory:", flags: [:readwrite, :nomutex], types: [:integer, :text], rows: 3] #####
# Name                 ips        average  deviation         median         99th %
# insert_all      329.44 K        3.04 μs    ±93.13%        2.92 μs        3.42 μs

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

  create = XQLite.prepare(db, create)
  :done = XQLite.step(db, create)
  XQLite.finalize(create)

  begin = XQLite.prepare(db, "begin immediate", [:persistent])
  insert = XQLite.prepare(db, insert, [:persistent])
  rollback = XQLite.prepare(db, "rollback", [:persistent])

  %{
    before_scenario: fn ->
      :done = XQLite.step(db, begin)
    end,
    db: db,
    insert: insert,
    types: types,
    rows: rows,
    after_scenario: fn ->
      :done = XQLite.step(db, rollback)
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
      %{db: db, insert: insert, types: types, rows: rows} = input
      XQLite.insert_all(db, insert, types, rows)
    end
  },
  inputs:
    Map.new(inputs, fn input ->
      name =
        input
        |> Keyword.take([:path, :flags, :types, :rows])
        |> Keyword.update!(:rows, &length/1)
        |> inspect()

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
