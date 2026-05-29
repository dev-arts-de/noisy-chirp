defmodule Chirp.Engine.EscalationTest do
  use ExUnit.Case, async: true

  alias Chirp.Engine.Escalation

  describe "gap/1" do
    test "first gap is 12 hours" do
      assert Escalation.gap(1) == 12 * 60 * 60 * 1000
    end

    test "halves on each step" do
      assert Escalation.gap(2) == 6 * 60 * 60 * 1000
      assert Escalation.gap(3) == 3 * 60 * 60 * 1000
      assert Escalation.gap(4) == div(3 * 60 * 60 * 1000, 2)
    end

    test "floors at min_gap_ms (5 minutes)" do
      min = Escalation.min_gap_ms()
      assert min == 5 * 60 * 1000

      # At n=8 the raw is 337_500 ms (~5.6 min) — still above min.
      assert Escalation.gap(8) > min
      assert Escalation.gap(8) < 6 * 60 * 1000

      for n <- 9..30 do
        assert Escalation.gap(n) == min,
               "expected floor at n=#{n}, got #{Escalation.gap(n)}"
      end
    end
  end

  describe "priority/1" do
    test "starts at 3 and saturates at 5" do
      assert Escalation.priority(1) == 3
      assert Escalation.priority(2) == 4
      assert Escalation.priority(3) == 5
      assert Escalation.priority(10) == 5
    end
  end

  describe "tags/1" do
    test "escalates the tag set" do
      assert Escalation.tags(1) == ["bell"]
      assert "warning" in Escalation.tags(2)
      assert "rotating_light" in Escalation.tags(4)
      assert "skull" in Escalation.tags(7)
    end
  end

  describe "render/2" do
    test "produces a complete payload" do
      r = Escalation.render(3, "Zahnbürstenkopf wechseln")
      assert r.priority == 5
      assert is_list(r.tags)
      assert is_binary(r.title)
      assert r.message =~ "Zahnbürstenkopf"
    end
  end
end
