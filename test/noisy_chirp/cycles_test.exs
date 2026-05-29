defmodule Chirp.CyclesTest do
  use ExUnit.Case, async: true

  alias Chirp.Cycles

  describe "from_input/2" do
    test "presets resolve to seconds" do
      assert Cycles.from_input("daily", "") == {:ok, 86_400}
      assert Cycles.from_input("bimonthly", "ignored") == {:ok, 60 * 86_400}
    end

    test "custom requires positive days" do
      assert Cycles.from_input("custom", "14") == {:ok, 14 * 86_400}
      assert {:error, _} = Cycles.from_input("custom", "0")
      assert {:error, _} = Cycles.from_input("custom", "")
      assert {:error, _} = Cycles.from_input("custom", "abc")
      assert {:error, _} = Cycles.from_input("custom", "99999")
    end

    test "unknown key errors" do
      assert {:error, _} = Cycles.from_input("nope", "")
    end
  end

  describe "from_seconds/1" do
    test "matches presets" do
      assert {:preset, "daily"} = Cycles.from_seconds(86_400)
      assert {:preset, "yearly"} = Cycles.from_seconds(365 * 86_400)
    end

    test "non-matching becomes custom days" do
      assert {:custom, 17} = Cycles.from_seconds(17 * 86_400)
    end
  end

  describe "label/1" do
    test "uses preset label" do
      assert Cycles.label(7 * 86_400) == "Wöchentlich"
    end

    test "falls back to custom days label" do
      assert Cycles.label(17 * 86_400) == "Alle 17 Tage"
    end
  end
end
