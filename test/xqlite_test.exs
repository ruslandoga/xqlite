defmodule XQLiteTest do
  use ExUnit.Case, async: true

  describe "open/2" do
    @tag :tmp_dir
    test "creates and opens a database on disk", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.db")
      db = XQLite.open(path, [:readwrite, :create])
      on_exit(fn -> XQLite.close(db) end)
      assert is_reference(db)
    end

    test "opens an in-memory database" do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)
      assert is_reference(db)
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
      stmt = XQLite.prepare(db, "select 1 + 1", [:persistent])
      on_exit(fn -> XQLite.finalize(stmt) end)
      assert is_reference(stmt)
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

  describe "bind_number/4" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)

      stmt = XQLite.prepare(db, "select ?")
      on_exit(fn -> XQLite.finalize(stmt) end)

      {:ok, db: db, stmt: stmt}
    end

    test "binds integer", %{db: db, stmt: stmt} do
      assert :ok = XQLite.bind_number(db, stmt, 1, 42)
      assert {:row, [42]} = XQLite.unsafe_step(db, stmt)
    end

    test "binds float", %{db: db, stmt: stmt} do
      assert :ok = XQLite.bind_number(db, stmt, 1, 21.5)
      assert {:row, [21.5]} = XQLite.unsafe_step(db, stmt)
    end

    test "binds null", %{db: db, stmt: stmt} do
      assert :ok = XQLite.bind_number(db, stmt, 1, nil)
      assert {:row, [nil]} = XQLite.unsafe_step(db, stmt)
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

    test "binds text", %{db: db, stmt: stmt} do
      assert :ok = XQLite.bind_text(db, stmt, 1, "hello")
      assert {:row, ["hello"]} = XQLite.unsafe_step(db, stmt)
    end

    test "binds null", %{db: db, stmt: stmt} do
      assert :ok = XQLite.bind_text(db, stmt, 1, nil)
      assert {:row, [nil]} = XQLite.unsafe_step(db, stmt)
    end
  end

  describe "bind_blob/4" do
    setup do
      db = XQLite.open(":memory:", [:readonly])
      on_exit(fn -> XQLite.close(db) end)

      stmt = XQLite.prepare(db, "select ?")
      on_exit(fn -> XQLite.finalize(stmt) end)

      {:ok, db: db, stmt: stmt}
    end

    test "binds text", %{db: db, stmt: stmt} do
      assert :ok = XQLite.bind_blob(db, stmt, 1, <<0, 0, 0>>)
      assert {:row, [<<0, 0, 0>>]} = XQLite.unsafe_step(db, stmt)
    end

    test "binds null", %{db: db, stmt: stmt} do
      assert :ok = XQLite.bind_blob(db, stmt, 1, nil)
      assert {:row, [nil]} = XQLite.unsafe_step(db, stmt)
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

    test "fetches <count> rows", %{db: db, stmt: stmt} do
      assert {:rows, [[1], [2], [3]]} = XQLite.step(db, stmt, 3)
      assert {:rows, [[4], [5], [6]]} = XQLite.step(db, stmt, 3)
      assert {:rows, [[7], [8], [9]]} = XQLite.step(db, stmt, 3)
      assert {:done, rows} = XQLite.step(db, stmt, 1000)
      assert length(rows) == 91
    end
  end

  describe "fetch_all/2" do
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

    test "fetches all rows", %{db: db, stmt: stmt} do
      assert [[1], [2], [3] | rest] = XQLite.fetch_all(db, stmt)
      assert length(rest) == 97
    end
  end

  describe "insert_all/4" do
    setup do
      db = XQLite.open(":memory:", [:readwrite])
      on_exit(fn -> XQLite.close(db) end)
      {:ok, db: db}
    end

    test "inserts rows", %{db: db} do
      exec(db, "create table users (name text) strict")

      insert = XQLite.prepare(db, "insert into users (name) values (?)")
      on_exit(fn -> XQLite.finalize(insert) end)

      types = [:text]
      rows = [["Alice"], ["Bob"], [nil], ["Charlie"]]
      assert :ok = XQLite.insert_all(db, insert, types, rows)

      select = XQLite.prepare(db, "select rowid, name from users order by rowid")
      on_exit(fn -> XQLite.finalize(select) end)

      # TODO
      # assert XQLite.fetch_all(db, select) == [[1, "Alice"], [2, "Bob"], [3, nil], [4, "Charlie"]]
      assert XQLite.step(db, select, 100) ==
               {:done, [[1, "Alice"], [2, "Bob"], [3, nil], [4, "Charlie"]]}
    end
  end

  defp exec(db, sql) do
    stmt = XQLite.prepare(db, sql)
    on_exit(fn -> XQLite.finalize(stmt) end)
    XQLite.step(db, stmt, 100)
  end
end
