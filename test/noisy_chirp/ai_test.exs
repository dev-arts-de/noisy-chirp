defmodule Chirp.AITest do
  use ExUnit.Case, async: true

  describe "Chirp.AI.Disabled" do
    test "always returns :error so engine falls back to templates" do
      assert {:error, :disabled} = Chirp.AI.Disabled.write("Pflanzen gießen", 1)
    end
  end

  describe "Chirp.AI.write/2" do
    test "in test env, dispatches to the Disabled writer" do
      assert {:error, _} = Chirp.AI.write("Zahnbürstenkopf wechseln", 2)
    end
  end

  describe "fallback chain in escalation" do
    test "Escalation.text/2 still returns a non-empty bird message" do
      msg = Chirp.Engine.Escalation.text(3, "Pflanzen gießen")
      assert is_binary(msg)
      assert msg =~ "Pflanzen"
    end
  end
end
