defmodule DukaApp.PushTest do
  use ExUnit.Case, async: true

  alias DukaApp.Push

  doctest Push

  test "a tapped push for the manager opens Approvals; anything else the receipts" do
    assert Push.screen(Push.decode(~s({"source":"push","data":{"screen":"approvals"}}))) ==
             :approvals

    assert Push.screen(Push.decode(~s({"source":"push"}))) == :receipts
    assert Push.decode("not json") == %{source: :local, data: %{}}
  end
end
