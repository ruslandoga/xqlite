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

  @spec bor_open_flags([open_flag]) :: integer
  defp bor_open_flags(flags) do
    Enum.reduce(flags, 0, fn flag, acc -> Bitwise.bor(acc, open_flag(flag)) end)
  end

  @doc """
  Opens a database.

  Example:

      iex> _writer = XQLite.open("test.db", [:readwrite, :create, :wal, :exrescode])
      iex> _reader = XQLite.open("test.db", [:readonly, :exrescode])
      iex> _memory = XQLite.open(":memory:", [:readwrite])

  """
  @spec open(Path.t(), [open_flag]) :: db
  def open(path, flags) do
    dirty_io_open_nif(to_charlist(path), bor_open_flags(flags))
  end

  @doc """
  Closes a database.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> XQLite.close(db)

  """
  @spec close(db) :: :ok
  def close(db), do: dirty_io_close_nif(db)

  @doc "Same as `prepare/3` but with no flags."
  @spec prepare(db, binary) :: stmt
  def prepare(db, sql), do: dirty_cpu_prepare_nif(db, sql, 0)

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

  @spec bor_prepare_flags([prepare_flag]) :: integer
  defp bor_prepare_flags(flags) do
    Enum.reduce(flags, 0, fn flag, acc -> Bitwise.bor(acc, prepare_flag(flag)) end)
  end

  @doc """
  Prepares a statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> XQLite.prepare(db, "SELECT ?", [:persistent])

  """
  @spec prepare(db, binary, [prepare_flag]) :: stmt
  def prepare(db, sql, flags), do: dirty_cpu_prepare_nif(db, sql, bor_prepare_flags(flags))

  @doc """
  Binds a text or null value to a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_text(db, stmt, 1, "Alice")
      iex> XQLite.bind_text(db, stmt, 1, nil)

  """
  @spec bind_text(db, stmt, non_neg_integer, binary | nil) :: :ok
  def bind_text(_db, _stmt, _index, _text), do: :erlang.nif_error(:undef)

  @doc """
  Binds a blob or null value to a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_blob(db, stmt, 1, <<0, 0, 0>>)
      iex> XQLite.bind_blob(db, stmt, 1, nil)

  """
  @spec bind_blob(db, stmt, non_neg_integer, binary | nil) :: :ok
  def bind_blob(_db, _stmt, _index, _blob), do: :erlang.nif_error(:undef)

  @doc """
  Binds a numeric or null value to a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.bind_number(db, stmt, 1, 42)
      iex> XQLite.bind_number(db, stmt, 1, 42.5)
      iex> XQLite.bind_number(db, stmt, 1, nil)

  """
  @spec bind_number(db, stmt, non_neg_integer, number | nil) :: :ok
  def bind_number(_db, _stmt, _index, _number), do: :erlang.nif_error(:undef)

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
  Releases resources associated with a prepared statement.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT ?")
      iex> XQLite.finalize(stmt)

  """
  @spec finalize(stmt) :: :ok
  def finalize(stmt), do: dirty_cpu_finalize_nif(stmt)

  @doc """
  Executes a prepared statement once.

  Example:

      iex> db = XQLite.open(":memory:", [:readonly])
      iex> stmt = XQLite.prepare(db, "SELECT 1")
      iex> XQLite.step(db, stmt)
      {:row, [1]}

  """
  @spec step(db, stmt) :: {:row, row} | :done
  def step(db, stmt), do: dirty_io_step_nif(db, stmt)

  @doc "Same as `step/2` but runs on a main scheduler."
  @spec unsafe_step(db, stmt) :: {:row, row} | :done
  def unsafe_step(db, stmt), do: step_nif(db, stmt)

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
  @spec insert_all(db, stmt, [:integer | :real | :text | :blob], [row]) :: :ok
  def insert_all(db, stmt, types, rows) do
    dirty_io_insert_all_nif(db, stmt, process_types(types), rows)
  end

  defp process_types([type | types]) do
    [process_type(type) | process_types(types)]
  end

  defp process_types([] = done), do: done

  defp process_type(:integer), do: 1
  defp process_type(:real), do: 2
  defp process_type(:text), do: 3
  defp process_type(:blob), do: 4

  # TODO
  # @spec interupt(db) :: :ok
  # def interupt(_db), do: :erlang.nif_error(:undef)

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

  defp dirty_cpu_prepare_nif(_db, _sql, _flags), do: :erlang.nif_error(:undef)
  defp dirty_cpu_finalize_nif(_stmt), do: :erlang.nif_error(:undef)

  defp dirty_io_step_nif(_db, _stmt), do: :erlang.nif_error(:undef)
  defp step_nif(_db, _stmt), do: :erlang.nif_error(:undef)

  defp dirty_io_step_nif(_db, _stmt, _count), do: :erlang.nif_error(:undef)
  defp step_nif(_db, _stmt, _count), do: :erlang.nif_error(:undef)

  defp dirty_io_fetch_all_nif(_db, _stmt), do: :erlang.nif_error(:undef)
  defp dirty_io_insert_all_nif(_db, _stmt, _types, _rows), do: :erlang.nif_error(:undef)
end
