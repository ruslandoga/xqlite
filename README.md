Just a bunch of SQLite NIFs.

```elixir
Mix.install([{:xqlite, github: "ruslandoga/xqlite"}], force: true)

db = XQLite.open(":memory:", [:readwrite])

stmt =
  XQLite.prepare(db, """
  SELECT * FROM (VALUES
    (112, 'Hello, ' || :database || '!', date(), -1.0),
    (105, 'Insert a lot of rows per batch', date('now', '-1 day'), 1.41421),
    (101, 'Sort your data based on your commonly-used queries', date('now', '+1 day'), 2.718),
    (115, 'Granules are the smallest chunks of data read', :day, :pi)
  )
  """)

XQLite.bind_text(stmt, XQLite.bind_parameter_index(stmt, ":database"), "ClickHouse")
XQLite.bind_float(stmt, XQLite.bind_parameter_index(stmt, ":pi"), 3.14159)
XQLite.bind_text(stmt, XQLite.bind_parameter_index(stmt, ":day"), Date.to_iso8601(~D[2025-03-14]))

XQLite.fetch_all(stmt)
# [
#   [112, "Hello, ClickHouse!", "2025-06-05", -1.0],
#   [105, "Insert a lot of rows per batch", "2025-06-04", 1.41421],
#   [101, "Sort your data based on your commonly-used queries", "2025-06-06", 2.718],
#   [115, "Granules are the smallest chunks of data read", "2025-03-14", 3.14159]
# ]
```
