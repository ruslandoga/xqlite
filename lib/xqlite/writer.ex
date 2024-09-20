defmodule XQLite.Writer do
  @moduledoc """
  Helpers for working with SQLite3 writers.

  Example usage:

      db = XQLite.open("test.db", [:create, :readwrite, :wal])

      :ok = XQLite.execute(db, "pragma foreign_keys=on")
      :ok = XQLite.execute(db, "pragma busy_timeout=5000")
      :ok = XQLite.execute(db, "create table test(id integer, stuff text) strict")

      :ok = XQLite.Writer.register(:db, db)

      XQLite.Writer.immediate_transaction(:db, fn db ->
        stmt = XQLite.prepare(db, "insert into test(id, stuff) values(?, ?)")

        try do
          XQLite.insert_all(db, stmt, [[1, "a"], [2, "b"], [3, "c"]])
        after
          XQLite.finalize(stmt)
        end
      end)

  """
  use GenServer

  def start_link(opts) do
    {gen_opts, writer_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, writer_opts, gen_opts)
  end

  def insert_all(writer, sql, rows, opts \\ []) do
    checkout_timeout = Keyword.get(opts, :checkout_timeout, :timer.seconds(5))
    insert_timeout = Keyword.get(opts, :timeout, :timer.seconds(5))
    db = GenServer.call(writer, {:checkout, insert_timeout}, checkout_timeout)

    try do
      with {:ok, stmt} <- prepare(db, writer, sql) do
        XQLite.insert_all(db, stmt, rows)
      end
    after
      GenServer.cast(writer, :checkin)
    end
  end

  def transaction(writer, fun, opts \\ []) do
    checkout_timeout = Keyword.get(opts, :checkout_timeout, :timer.seconds(5))
    tx_timeout = Keyword.get(opts, :timeout, :timer.seconds(5))
    db = GenServer.call(writer, {:checkout, tx_timeout}, checkout_timeout)

    try do
      with {:ok, :ok} <- begin_tx(db) do
        try do
          fun.(db)
        after
          rollback_tx(db)
        end
      end
    after
      GenServer.cast(writer, :checkin)
    end
  end

  @impl true
  def init(writer_opts) do
    {:ok, []}
  end
end
