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

  @spec open(Path.t(), [open_flag]) :: db
  def open(path, flags) do
    dirty_io_open_nif(to_charlist(path), bor_open_flags(flags))
  end

  @spec close(db) :: :ok
  def close(db), do: dirty_io_close_nif(db)

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

  @spec prepare(db, binary, [prepare_flag]) :: stmt
  def prepare(db, sql, flags), do: dirty_cpu_prepare_nif(db, sql, bor_prepare_flags(flags))

  @spec bind_all(stmt, [value]) :: :ok
  def bind_all(stmt, values), do: dirty_cpu_bind_all_nif(stmt, values)

  @spec unsafe_bind_all(stmt, [value]) :: :ok
  def unsafe_bind_all(stmt, values), do: bind_all_nif(stmt, values)

  @spec bind_text(stmt, non_neg_integer, binary) :: :ok
  def bind_text(stmt, index, text), do: dirty_cpu_bind_text_nif(stmt, index, text)

  @spec unsafe_bind_text(stmt, non_neg_integer, binary) :: :ok
  def unsafe_bind_text(stmt, index, text), do: bind_text_nif(stmt, index, text)

  @spec bind_blob(stmt, non_neg_integer, binary) :: :ok
  def bind_blob(stmt, index, blob), do: dirty_cpu_bind_blob_nif(stmt, index, blob)

  @spec unsafe_bind_blob(stmt, non_neg_integer, binary) :: :ok
  def unsafe_bind_blob(stmt, index, blob), do: bind_blob_nif(stmt, index, blob)

  @spec bind_number(stmt, non_neg_integer, number) :: :ok
  def bind_number(stmt, index, number), do: dirty_cpu_bind_number_nif(stmt, index, number)

  @spec unsafe_bind_number(stmt, non_neg_integer, number) :: :ok
  def unsafe_bind_number(stmt, index, number), do: bind_number_nif(stmt, index, number)

  @spec finalize(stmt) :: :ok
  def finalize(stmt), do: dirty_cpu_finalize_nif(stmt)

  @spec step(db, stmt) :: {:row, row} | :done
  def step(db, stmt), do: dirty_io_step_nif(db, stmt)

  @spec unsafe_step(db, stmt) :: {:row, row} | :done
  def unsafe_step(db, stmt), do: step_nif(db, stmt)

  @spec step(db, stmt, non_neg_integer) :: {:rows | :done, [row]}
  def step(db, stmt, count), do: dirty_io_step_nif(db, stmt, count)

  @spec unsafe_step(db, stmt, non_neg_integer) :: {:rows | :done, [row]}
  def unsafe_step(db, stmt, count), do: step_nif(db, stmt, count)

  @spec interrupt(db) :: :ok
  def interrupt(db), do: dirty_io_interrupt_nif(db)

  @spec unsafe_interrupt(db) :: :ok
  def unsafe_interrupt(db), do: interrupt_nif(db)

  @spec insert_all(db, stmt, [row]) :: :ok
  def insert_all(db, stmt, rows), do: dirty_io_insert_all_nif(db, stmt, rows)

  @spec unsafe_insert_all(db, stmt, [row]) :: :ok
  def unsafe_insert_all(db, stmt, rows), do: insert_all_nif(db, stmt, rows)

  @spec fetch_all(db, stmt) :: [row]
  def fetch_all(db, stmt), do: dirty_io_fetch_all_nif(db, stmt)

  @spec unsafe_fetch_all(db, stmt) :: [row]
  def unsafe_fetch_all(db, stmt), do: fetch_all_nif(db, stmt)

  @compile {:autoload, false}
  @on_load {:load_nif, 0}

  @doc false
  def load_nif do
    path = :filename.join(:code.priv_dir(:xqlite), ~c"xqlite_nif")
    :erlang.load_nif(path, 0)
  end

  defp dirty_io_open_nif(_path, _flags), do: :erlang.nif_error(:undef)
  defp dirty_io_close_nif(_db), do: :erlang.nif_error(:undef)
  defp dirty_cpu_prepare_nif(_db, _sql, _flags), do: :erlang.nif_error(:undef)
  defp dirty_cpu_bind_all_nif(_stmt, _values), do: :erlang.nif_error(:undef)
  defp bind_all_nif(_stmt, _values), do: :erlang.nif_error(:undef)
  defp dirty_cpu_bind_text_nif(_stmt, _index, _text), do: :erlang.nif_error(:undef)
  defp bind_text_nif(_stmt, _index, _text), do: :erlang.nif_error(:undef)
  defp dirty_cpu_bind_blob_nif(_stmt, _index, _blob), do: :erlang.nif_error(:undef)
  defp bind_blob_nif(_stmt, _index, _blob), do: :erlang.nif_error(:undef)
  defp dirty_cpu_bind_number_nif(_stmt, _index, _number), do: :erlang.nif_error(:undef)
  defp bind_number_nif(_stmt, _index, _number), do: :erlang.nif_error(:undef)
  defp dirty_cpu_finalize_nif(_stmt), do: :erlang.nif_error(:undef)
  defp dirty_io_step_nif(_db, _stmt), do: :erlang.nif_error(:undef)
  defp step_nif(_db, _stmt), do: :erlang.nif_error(:undef)
  defp dirty_io_step_nif(_db, _stmt, _count), do: :erlang.nif_error(:undef)
  defp step_nif(_db, _stmt, _count), do: :erlang.nif_error(:undef)
  defp interrupt_nif(_db), do: :erlang.nif_error(:undef)
  defp dirty_io_interrupt_nif(_db), do: :erlang.nif_error(:undef)
  defp insert_all_nif(_db, _stmt, _rows), do: :erlang.nif_error(:undef)
  defp dirty_io_insert_all_nif(_db, _stmt, _rows), do: :erlang.nif_error(:undef)
  defp fetch_all_nif(_db, _stmt), do: :erlang.nif_error(:undef)
  defp dirty_io_fetch_all_nif(_db, _stmt), do: :erlang.nif_error(:undef)
end
