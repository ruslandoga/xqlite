defmodule XQLite.Readers do
  @moduledoc """
  A pool for SQLite3 readers.

  Example usage:

      readers =
        for _ <- 1..:erlang.system_info(:dirty_io_schedulers) do
          XQLite.open("test.db", [:create, :readonly, :nomutex, :wal])
        end

      {:ok, pool} = XQLite.Readers.start_link(readers: readers)

      XQLite.Readers.checkout(
        pool,
        fn reader ->
          stmt = XQLite.prepare(reader, "select ?, ?")

          try do
            :ok = XQLite.bind_all(reader, stmt, [1, "one"])
            XQLite.fetch_all(reader, stmt)
          after
            XQLite.finalize(stmt)
          end
        end,
        _timeout = :timer.seconds(5)
      )

  """
  use GenServer

  def start_link(opts) do
    {gen_opts, pool_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, pool_opts, gen_opts)
  end

  def checkout(pool, fun, timeout) do
    reader = GenServer.call(pool, {:checkout, timeout}, timeout)

    try do
      fun.(reader)
    after
      GenServer.cast(pool, {:checkin, reader})
    end
  end

  @impl true
  def init(pool_opts) do
    path = Keyword.fetch!(pool_opts, :path)
    size = Keyword.fetch!(pool_opts, :size)
    readers = for _ <- 1..size, do: XQLite.open(path, [:create, :readonly, :nomutex])
    {:ok, %{size: size, readers: readers}}
  end

  @impl true
  def handle_call({:checkout, _timeout}, _from, %{readers: [reader | rest]} = state) do
    {:reply, reader, %{state | readers: rest}}
  end
end
