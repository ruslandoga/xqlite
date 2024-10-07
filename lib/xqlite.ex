defmodule XQLite do
  @moduledoc "SQLite for Elixir"

  @type db :: reference
  @type stmt :: reference
  @type value :: binary | number | nil
  @type row :: [value]

  open_flags = [
    readonly: 0x00000001,
    readwrite: 0x00000002,
    create: 0x00000004,
    deleteonclose: 0x00000008,
    exclusive: 0x00000010,
    autoproxy: 0x00000020,
    uri: 0x00000040,
    memory: 0x00000080,
    main_db: 0x00000100,
    temp_db: 0x00000200,
    transient_db: 0x00000400,
    main_journal: 0x00000800,
    temp_journal: 0x00001000,
    subjournal: 0x00002000,
    super_journal: 0x00004000,
    nomutex: 0x00008000,
    fullmutex: 0x00010000,
    sharedcache: 0x00020000,
    privatecache: 0x00040000,
    wal: 0x00080000,
    nofollow: 0x01000000,
    exrescode: 0x02000000
  ]

  open_flag_names = Enum.map(open_flags, fn {name, _value} -> name end)
  open_flag_union = Enum.reduce(open_flag_names, &{:|, [], [&1, &2]})
  @type open_flag :: unquote(open_flag_union)

  for {name, value} <- open_flags do
    defp open_flag(unquote(name)), do: unquote(value)
  end

  defp open_flag(invalid) do
    raise ArgumentError, "unknown flag: #{inspect(invalid)}"
  end

  @spec bor_open_flags([open_flag], integer) :: integer
  defp bor_open_flags([flag | flags], acc) do
    bor_open_flags(flags, Bitwise.bor(acc, open_flag(flag)))
  end

  defp bor_open_flags([] = _done, result), do: result

  @doc """
  Opens a database using [sqlite3_open_v2()](https://www.sqlite.org/c3ref/open.html)

  Example:

      iex> _writer = XQLite.open("test.db", [:readwrite, :create, :wal, :exrescode])
      iex> _reader = XQLite.open("test.db", [:readonly, :exrescode])
      iex> _memory = XQLite.open(":memory:", [:readwrite])

  """
  @spec open(Path.t(), [open_flag]) :: db
  def open(path, flags) do
    dirty_io_open_nif(path <> <<0>>, bor_open_flags(flags, 0))
  end

  @doc """
  Closes a database using [sqlite3_close_v2()](https://www.sqlite.org/c3ref/close.html)

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> XQLite.close(db)

  """
  @spec close(db) :: :ok
  def close(db), do: dirty_io_close_nif(db)

  @doc "Same as `prepare/3` but with no flags."
  @spec prepare(db, binary) :: stmt
  def prepare(db, sql), do: prepare_nif(db, sql, 0)

  prepare_flags = [persistent: 0x01, normalize: 0x02, no_vtab: 0x04]
  prepare_flag_names = Enum.map(prepare_flags, fn {name, _value} -> name end)
  prepare_flag_union = Enum.reduce(prepare_flag_names, &{:|, [], [&1, &2]})
  @type prepare_flag :: unquote(prepare_flag_union)

  for {name, value} <- prepare_flags do
    defp prepare_flag(unquote(name)), do: unquote(value)
  end

  defp prepare_flag(invalid) do
    raise ArgumentError, "unknown flag: #{inspect(invalid)}"
  end

  @spec bor_prepare_flags([prepare_flag], integer) :: integer
  defp bor_prepare_flags([flag | flags], acc) do
    bor_prepare_flags(flags, Bitwise.bor(acc, prepare_flag(flag)))
  end

  defp bor_prepare_flags([] = _done, result), do: result

  @doc """
  Prepares a statement using [sqlite3_prepare_v3()](https://www.sqlite.org/c3ref/prepare.html)

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> XQLite.prepare(db, "SELECT ?", [:persistent])

  """
  @spec prepare(db, binary, [prepare_flag]) :: stmt
  def prepare(db, sql, flags), do: prepare_nif(db, sql, bor_prepare_flags(flags, 0))

  @doc """
  Binds a text value to a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_text(db, stmt, 1, "Alice")

  """
  @spec bind_text(db, stmt, non_neg_integer, String.t()) :: :ok
  def bind_text(_db, _stmt, _index, _text), do: :erlang.nif_error(:undef)

  @doc """
  Binds a blob value to a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_blob(db, stmt, 1, <<0, 0, 0>>)

  """
  @spec bind_blob(db, stmt, non_neg_integer, binary) :: :ok
  def bind_blob(_db, _stmt, _index, _blob), do: :erlang.nif_error(:undef)

  @doc """
  Binds an integer value to a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_integer(db, stmt, 1, 42)

  """
  @spec bind_integer(db, stmt, non_neg_integer, integer) :: :ok
  def bind_integer(_db, _stmt, _index, _integer), do: :erlang.nif_error(:undef)

  @doc """
  Binds a float value to a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_float(db, stmt, 1, 0.334)

  """
  @spec bind_float(db, stmt, non_neg_integer, float) :: :ok
  def bind_float(_db, _stmt, _index, _float), do: :erlang.nif_error(:undef)

  @doc """
  Binds a null value to a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_null(db, stmt, 1)

  """
  @spec bind_null(db, stmt, non_neg_integer) :: :ok
  def bind_null(_db, _stmt, _index), do: :erlang.nif_error(:undef)

  @doc """
  Resets a prepared statement using [sqlite3_reset()](https://www.sqlite.org/c3ref/reset.html)

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_integer(db, stmt, 1, 42)
      iex> XQLite.step(db, stmt, 2)
      iex> XQLite.reset(db, stmt)
      iex> XQLite.bind_text(db, stmt, 1, "answer")
      iex> XQLite.step(db, stmt, 2)
      {:done, [["answer"]]}

  """
  @spec reset(db, stmt) :: :ok
  def reset(_db, _stmt), do: :erlang.nif_error(:undef)

  @doc """
  Releases resources associated with a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.finalize(stmt)

  """
  @spec finalize(stmt) :: :ok
  def finalize(_stmt), do: :erlang.nif_error(:undef)

  @doc """
  Executes a prepared statement once.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT 1")
      iex> XQLite.step(db, stmt)
      {:row, [1]}

  """
  @spec step(db, stmt) :: {:row, row} | :done
  def step(_db, _stmt), do: :erlang.nif_error(:undef)

  @doc "Same as `step/2` but runs on a main scheduler."
  @spec unsafe_step(db, stmt) :: {:row, row} | :done
  def unsafe_step(_db, _stmt), do: :erlang.nif_error(:undef)

  @doc """
  Executes a prepared statement `count` times.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "select 1")
      iex> XQLite.step(db, stmt, 2)
      {:done, [[1]]}

  """
  @spec step(db, stmt, non_neg_integer) :: {:rows | :done, [row]}
  def step(db, stmt, count) do
    with {tag, rows} <- dirty_io_step_nif(db, stmt, count) do
      {tag, :lists.reverse(rows)}
    end
  end

  @doc "Same as `step/3` but runs on a main scheduler."
  @spec unsafe_step(db, stmt, non_neg_integer) :: {:rows | :done, [row]}
  def unsafe_step(db, stmt, count) do
    with {tag, rows} <- step_nif(db, stmt, count) do
      {tag, :lists.reverse(rows)}
    end
  end

  @doc """
  Causes any pending operation to stop at its earliest opportunity.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "with recursive c(x) as (values(1) union all select x+1 from c where x < 10000000000000) select sum(x) from c")
      iex> spawn(fn -> :timer.sleep(10); XQLite.interrupt(db) end)
      iex> XQLite.step(db, stmt)
      ** (ErlangError) Erlang error: {:error, 9, ~c"interrupted"}

  """
  @spec interrupt(db) :: :ok
  def interrupt(_db), do: :erlang.nif_error(:undef)

  @doc """
  Returns all rows from a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT 1")
      iex> XQLite.fetch_all(db, stmt)
      [[1]]

  """
  @spec fetch_all(db, stmt) :: [row]
  def fetch_all(db, stmt) do
    :lists.reverse(dirty_io_fetch_all_nif(db, stmt))
  end

  @doc """
  Bulk-insert rows into a prepared statement. Must be called inside a transaction.

  Example:

      iex> db = XQLite.open(":memory:", [:readwrite])
      iex> create = XQLite.prepare(db, "CREATE TABLE users (name TEXT)")
      iex> XQLite.step(db, create)
      iex> begin = XQLite.prepare(db, "BEGIN IMMEDIATE")
      iex> insert = XQLite.prepare(db, "INSERT INTO users (name) VALUES (?)")
      iex> commit = XQLite.prepare(db, "COMMIT")
      iex> XQLite.step(db, begin)
      iex> XQLite.insert_all(db, insert, [:text], [["Alice"], [nil], ["Bob"]])
      iex> XQLite.step(db, commit)

  """
  @spec insert_all(db, stmt, [:integer | :float | :text | :blob], [row]) :: :ok
  def insert_all(db, stmt, types, rows) do
    dirty_io_insert_all_nif(db, stmt, process_types(types), rows)
  end

  defp process_types([type | types]) do
    [process_type(type) | process_types(types)]
  end

  defp process_types([] = done), do: done

  defp process_type(:integer), do: 1
  defp process_type(:float), do: 2
  defp process_type(:text), do: 3
  defp process_type(:blob), do: 4

  @doc """
  Returns the number of rows changed by the most recent statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readwrite])
      iex> XQLite.step(db, XQLite.prepare(db, "CREATE TABLE users (name TEXT)"))
      iex> XQLite.step(db, XQLite.prepare(db, "INSERT INTO users (name) VALUES ('Alice'), ('Bob')"))
      iex> XQLite.changes(db)
      2

  """
  @spec changes(db) :: integer
  def changes(_db), do: :erlang.nif_error(:undef)

  @doc """
  Returns the total number of rows changed since the database connection was open.

  Example:

      iex> db = XQLite.open(":memory:", [:readwrite])
      iex> XQLite.step(db, XQLite.prepare(db, "CREATE TABLE users (name TEXT)"))
      iex> XQLite.step(db, XQLite.prepare(db, "INSERT INTO users (name) VALUES ('Alice'), ('Bob')"))
      iex> XQLite.step(db, XQLite.prepare(db, "INSERT INTO users (name) VALUES ('Charlie')"))
      iex> XQLite.total_changes(db)
      3

  """
  @spec total_changes(db) :: integer
  def total_changes(_db), do: :erlang.nif_error(:undef)

  @doc """
  Resets all bindings on a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_integer(db, stmt, 1, 42)
      iex> XQLite.clear_bindings(db, stmt)
      iex> XQLite.step(db, stmt, 2)
      {:done, [[nil]]}

  """
  @spec clear_bindings(db, stmt) :: :ok
  def clear_bindings(_db, _stmt), do: :erlang.nif_error(:undef)

  @doc """
  Enables or disables extension loading.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> XQLite.enable_load_extension(db, true)
      iex> XQLite.enable_load_extension(db, false)

  """
  @spec enable_load_extension(db, boolean) :: :ok
  def enable_load_extension(db, onoff) do
    case onoff do
      true -> enable_load_extension_nif(db, 1)
      false -> enable_load_extension_nif(db, 0)
    end
  end

  @doc """
  Returns the SQL text used to create a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "select ?")
      iex> XQLite.bind_integer(db, stmt, 1, 42)
      iex> XQLite.sql(stmt)
      "select ?"

  """
  @spec sql(stmt) :: String.t()
  def sql(_stmt), do: :erlang.nif_error(:undef)

  @doc """
  Returns the SQL text used to create a prepared statement with bound parameters expanded.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "select ?")
      iex> XQLite.bind_integer(db, stmt, 1, 42)
      iex> XQLite.expanded_sql(stmt)
      "select 42"

  """
  @spec expanded_sql(stmt) :: String.t()
  def expanded_sql(_stmt), do: :erlang.nif_error(:undef)

  @doc """
  Tests for auto-commit mode.

  Example:

      iex> db = XQLite.open(":memory:", [:readwrite])
      iex> XQLite.get_autocommit(db)
      1

      iex> db = XQLite.open(":memory:", [:readwrite])
      iex> XQLite.step(db, XQLite.prepare(db, "begin"))
      iex> XQLite.get_autocommit(db)
      0

  """
  @spec get_autocommit(db) :: integer
  def get_autocommit(_db), do: :erlang.nif_error(:undef)

  @doc """
  Returns the rowid of the most recent successful INSERT.

  Example:

      iex> db = XQLite.open(":memory:", [:readwrite])
      iex> XQLite.step(db, XQLite.prepare(db, "CREATE TABLE users (name TEXT)"))
      iex> XQLite.step(db, XQLite.prepare(db, "INSERT INTO users (name) VALUES ('Alice'), ('Bob')"))
      iex> XQLite.last_insert_rowid(db)
      2

  """
  @spec last_insert_rowid(db) :: integer
  def last_insert_rowid(_db), do: :erlang.nif_error(:undef)

  @doc """
  Returns the number of bytes of memory currently outstanding (malloced but not freed).

  Example:

      iex> XQLite.memory_used()
      0

      iex> XQLite.open(":memory:", [:readonly])
      iex> memory_used = XQLite.memory_used()
      iex> memory_used > 0
      true

  """
  @spec memory_used :: integer
  def memory_used, do: :erlang.nif_error(:undef)

  @doc """
  Returns number of columns in a result set.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT 1, 2, 3")
      iex> XQLite.column_count(stmt)
      3

  """
  @spec column_count(stmt) :: integer
  def column_count(_stmt), do: :erlang.nif_error(:undef)

  @doc """
  Returns the name of a column in a result set.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT 1 AS one, 2 AS two, 3 AS three")
      iex> XQLite.column_name(stmt, 0)
      "one"

  """
  @spec column_name(stmt, integer) :: String.t() | nil
  def column_name(_stmt, _idx), do: :erlang.nif_error(:undef)

  @doc """
  Returns the names of all columns in a result set.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT 1 AS one, 2 AS two, 3 AS three")
      iex> XQLite.column_names(stmt)
      ["one", "two", "three"]

  """
  @spec column_names(stmt) :: [String.t() | nil]
  def column_names(_stmt), do: :erlang.nif_error(:undef)

  @compile {:autoload, false}
  @on_load {:load_nif, 0}

  @doc false
  def load_nif do
    :code.priv_dir(:xqlite)
    |> :filename.join(~c"xqlite_nif")
    |> :erlang.load_nif(0)
  end

  defp dirty_io_open_nif(_path, _flags), do: :erlang.nif_error(:undef)
  defp dirty_io_close_nif(_db), do: :erlang.nif_error(:undef)

  defp prepare_nif(_db, _sql, _flags), do: :erlang.nif_error(:undef)

  defp dirty_io_step_nif(_db, _stmt, _count), do: :erlang.nif_error(:undef)
  defp step_nif(_db, _stmt, _count), do: :erlang.nif_error(:undef)

  defp enable_load_extension_nif(_db, _onoff), do: :erlang.nif_error(:undef)

  defp dirty_io_fetch_all_nif(_db, _stmt), do: :erlang.nif_error(:undef)
  defp dirty_io_insert_all_nif(_db, _stmt, _types, _rows), do: :erlang.nif_error(:undef)
end
