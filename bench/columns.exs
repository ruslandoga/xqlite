defmodule Bench do
  def columns_count_and_name_all(%{stmt: stmt}) do
    columns_all(stmt, XQLite.column_count(stmt))
  end

  defp columns_all(stmt, idx) when idx > 0 do
    [XQLite.column_name(stmt, idx) | columns_all(stmt, idx - 1)]
  end

  defp columns_all(_stmt, 0), do: []

  def column_names(%{stmt: stmt}) do
    XQLite.column_names(stmt)
  end
end

Benchee.run(
  %{
    "column_count + column_name" => &Bench.columns_count_and_name_all/1,
    "column_names" => &Bench.column_names/1
  },
  inputs:
    Map.new(
      [
        "1 AS one",
        "1 AS one, 2 AS two, 3 AS three",
        "1 AS one, 2 AS two, 3 AS three, 4 AS four, 5 AS five, 6 AS six, 7 AS seven, 8 AS eight, 9 AS nine, 10 AS ten"
      ],
      fn columns -> {columns, columns} end
    ),
  before_scenario: fn columns ->
    db = XQLite.open(":memory:", [:readonly])
    stmt = XQLite.prepare(db, "SELECT " <> columns)
    %{db: db, stmt: stmt}
  end,
  after_scenario: fn %{db: db, stmt: stmt} ->
    XQLite.finalize(stmt)
    XQLite.close(db)
  end,
  time: 2
)
