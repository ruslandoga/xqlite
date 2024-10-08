defmodule XQLiteTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest XQLite

  describe "open/2" do
    @tag :tmp_dir
    test "creates and opens a database on disk", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test-💽.db")

      db = XQLite.open(path, [:readwrite, :create])
      on_exit(fn -> XQLite.close(db) end)

      assert [[0, "main", path]] = prepare_fetch_all(db, "pragma database_list")
      assert Path.basename(path) == "test-💽.db"
    end

    test "opens an in-memory database" do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)
      assert prepare_fetch_all(db, "pragma database_list") == [[0, "main", ""]]
    end
  end

  describe "close/1" do
    test "closes a database" do
      db = XQLite.open(":memory:", [:readonly])
      assert :ok = XQLite.close(db)
    end
  end

  describe "prepare/2" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)
      {:ok, db: db}
    end

    test "prepares a statement", %{db: db} do
      stmt = XQLite.prepare(db, "select 1 + 1, '🤷‍♂️'", [:persistent])
      on_exit(fn -> XQLite.finalize(stmt) end)
      assert {:row, [2, "🤷‍♂️"]} = XQLite.unsafe_step(stmt)
    end
  end

  describe "finalize/1" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)
      {:ok, db: db}
    end

    test "finalizes a statement", %{db: db} do
      stmt = XQLite.prepare(db, "select 1 + 1")
      assert :ok = XQLite.finalize(stmt)
    end
  end

  describe "bind and fetch_all" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)

      stmt = XQLite.prepare(db, "select ?, ?, ?, ?, ?")
      on_exit(fn -> XQLite.finalize(stmt) end)

      {:ok, db: db, stmt: stmt}
    end

    property "integer, float, text, blob, and null", %{stmt: stmt} do
      check all(integer <- integer(), float <- float(), binary <- binary()) do
        XQLite.bind_integer(stmt, 1, integer)
        XQLite.bind_float(stmt, 2, float)
        XQLite.bind_text(stmt, 3, binary)
        XQLite.bind_blob(stmt, 4, binary)
        XQLite.bind_null(stmt, 5)
        assert [[^integer, ^float, ^binary, ^binary, nil]] = XQLite.fetch_all(stmt)
      end
    end
  end

  describe "bind_integer/4" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)

      stmt = XQLite.prepare(db, "select ?")
      on_exit(fn -> XQLite.finalize(stmt) end)

      {:ok, db: db, stmt: stmt}
    end

    test "binds integers larger than INT32_MAX", %{stmt: stmt} do
      XQLite.bind_integer(stmt, 1, 0xFFFFFFFF + 1)
      assert {:row, [0x100000000]} = XQLite.unsafe_step(stmt)
    end
  end

  describe "bind_text/4" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)

      stmt = XQLite.prepare(db, "select ?")
      on_exit(fn -> XQLite.finalize(stmt) end)

      {:ok, db: db, stmt: stmt}
    end

    test "binds emojis", %{stmt: stmt} do
      XQLite.bind_text(stmt, 1, "hello 👋 world 🌏")
      assert {:row, ["hello 👋 world 🌏"]} = XQLite.unsafe_step(stmt)
    end
  end

  describe "step/3" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)

      stmt =
        XQLite.prepare(db, """
        with recursive cte(x) as (
          select 1 union all select x + 1 from cte where x < 100
        )
        select x from cte
        """)

      on_exit(fn -> XQLite.finalize(stmt) end)

      {:ok, db: db, stmt: stmt}
    end

    test "fetches <count> rows", %{stmt: stmt} do
      assert {:rows, [[1]]} = XQLite.step(stmt, 1)
      assert {:rows, [[2], [3]]} = XQLite.step(stmt, 2)
      assert {:rows, [[4], [5], [6]]} = XQLite.step(stmt, 3)

      assert {:done, rows} = XQLite.step(stmt, 94 + 1)
      assert length(rows) == 94

      assert {:done, rows} = XQLite.step(stmt, 100 + 1)
      assert length(rows) == 100
    end
  end

  describe "fetch_all/2" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)

      stmt =
        XQLite.prepare(db, """
        with recursive cte(x) as (
          values(1)
          union all
          select x + 1 from cte where x < 100
        )
        select
          x as integer,
          x / 3.0 as float,
          'hello' || x as text,
          x'000000' as blob,
          null
        from cte
        """)

      on_exit(fn -> XQLite.finalize(stmt) end)

      {:ok, db: db, stmt: stmt}
    end

    test "fetches all rows", %{stmt: stmt} do
      assert [
               [1, 0.3333333333333333, "hello1", <<0, 0, 0>>, nil],
               [2, 0.6666666666666666, "hello2", <<0, 0, 0>>, nil],
               [3, 1.0, "hello3", <<0, 0, 0>>, nil],
               [4, 1.3333333333333333, "hello4", <<0, 0, 0>>, nil],
               [5, 1.6666666666666667, "hello5", <<0, 0, 0>>, nil],
               [6, 2.0, "hello6", <<0, 0, 0>>, nil]
               | rest
             ] = XQLite.fetch_all(stmt)

      assert length(rest) == 94
    end
  end

  describe "insert_all/4" do
    setup do
      db = XQLite.open(":memory:", [:readwrite])
      on_exit(fn -> XQLite.close(db) end)
      {:ok, db: db}
    end

    test "inserts rows", %{db: db} do
      :done = exec(db, "create table test(i integer, f real, txt text, bin blob) strict")

      insert = XQLite.prepare(db, "insert into test(i, f, txt, bin) values(?, ?, ?, ?)")
      on_exit(fn -> XQLite.finalize(insert) end)

      types = [:integer, :float, :text, :blob]

      rows = [
        [1, 0.3, "Alice 🤦‍♀️", <<0>>],
        [nil, 3.14, nil, <<1>>],
        [2, nil, "🤷‍♂️ Bob", nil],
        [nil, nil, nil, nil]
      ]

      assert :done = exec(db, "begin immediate")
      assert :done = XQLite.insert_all(insert, types, rows)
      assert :done = exec(db, "commit")

      assert prepare_fetch_all(db, "select rowid, * from test order by rowid") == [
               [1, 1, 0.3, "Alice 🤦‍♀️", <<0>>],
               [2, nil, 3.14, nil, <<1>>],
               [3, 2, nil, "🤷‍♂️ Bob", nil],
               [4, nil, nil, nil, nil]
             ]
    end
  end

  defp exec(db, sql) do
    stmt = XQLite.prepare(db, sql)
    on_exit(fn -> XQLite.finalize(stmt) end)
    XQLite.step(stmt)
  end

  defp prepare_fetch_all(db, sql) do
    select = XQLite.prepare(db, sql)
    on_exit(fn -> XQLite.finalize(select) end)
    XQLite.fetch_all(select)
  end
end
