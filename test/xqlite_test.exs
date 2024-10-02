defmodule XQLiteTest do
  use ExUnit.Case, async: true

  describe "open/2" do
    @tag :tmp_dir
    test "opens a database", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.db")
      db = XQLite.open(path, [:readwrite, :create])
      on_exit(fn -> XQLite.close(db) end)
      assert is_reference(db)
    end
  end
end
