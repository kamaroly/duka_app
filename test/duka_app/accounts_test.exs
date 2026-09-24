defmodule DukaApp.AccountsTest do
  use DukaApp.DataCase

  alias DukaApp.Accounts
  alias DukaApp.Accounts.Profile

  doctest Profile

  test "sign_in creates a profile with a normalised phone and makes it current" do
    assert {:ok, profile} = Accounts.sign_in("0712 345 678")
    assert profile.phone == "+254712345678"
    assert Accounts.current_profile().id == profile.id
  end

  test "signing in again with the same number reuses the profile" do
    {:ok, first} = Accounts.sign_in("0712345678")
    {:ok, second} = Accounts.sign_in("+254712345678")
    assert first.id == second.id
  end

  test "sign_in rejects numbers that are not Kenyan mobiles" do
    assert {:error, changeset} = Accounts.sign_in("12345")
    assert %{phone: [_]} = errors_on(changeset)
  end

  test "sign_out leaves no current profile" do
    {:ok, profile} = Accounts.sign_in("0712345678")
    {:ok, _} = Accounts.sign_out(profile)
    assert Accounts.current_profile() == nil
  end

  test "update_settings validates the KRA PIN and upcases it" do
    {:ok, profile} = Accounts.sign_in("0712345678")

    assert {:ok, %{kra_pin: "A123456789B"}} =
             Accounts.update_settings(profile, %{kra_pin: " a123456789b "})

    assert {:error, changeset} = Accounts.update_settings(profile, %{kra_pin: "nope"})
    assert %{kra_pin: [_]} = errors_on(changeset)
  end
end
