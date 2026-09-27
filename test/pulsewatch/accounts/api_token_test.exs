defmodule Pulsewatch.Accounts.ApiTokenTest do
  use Pulsewatch.DataCase, async: true

  import Pulsewatch.AccountsFixtures

  alias Pulsewatch.Accounts

  describe "create_api_token/2" do
    test "returns a plaintext token and persists only its hash" do
      user = user_fixture()

      assert {:ok, token, api_token} = Accounts.create_api_token(user, "CI token")

      assert is_binary(token)
      assert api_token.name == "CI token"
      assert api_token.token_hash != nil
      assert api_token.token_hash != token
    end

    test "two tokens for the same user are never equal" do
      user = user_fixture()
      {:ok, token1, _} = Accounts.create_api_token(user, "one")
      {:ok, token2, _} = Accounts.create_api_token(user, "two")

      assert token1 != token2
    end

    test "requires a name" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.create_api_token(user, "")
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "get_user_by_api_token/1" do
    test "returns the owning user and the token record for a valid token" do
      user = user_fixture()
      {:ok, token, created} = Accounts.create_api_token(user, "test")

      assert {:ok, found_user, found_token} = Accounts.get_user_by_api_token(token)
      assert found_user.id == user.id
      assert found_token.id == created.id
    end

    test "returns {:error, :invalid} for a token that doesn't exist" do
      assert {:error, :invalid} = Accounts.get_user_by_api_token("not-a-real-token")
    end

    test "returns {:error, :invalid} for a revoked token" do
      user = user_fixture()
      {:ok, token, api_token} = Accounts.create_api_token(user, "test")
      {:ok, _} = Accounts.revoke_api_token(user, api_token)

      assert {:error, :invalid} = Accounts.get_user_by_api_token(token)
    end

    test "updates last_used_at as a side effect" do
      user = user_fixture()
      {:ok, token, api_token} = Accounts.create_api_token(user, "test")
      assert api_token.last_used_at == nil

      {:ok, _user, _token} = Accounts.get_user_by_api_token(token)

      [reloaded] = Accounts.list_api_tokens(user)
      assert reloaded.last_used_at != nil
    end
  end

  describe "list_api_tokens/1" do
    test "only lists the given user's tokens, newest first" do
      user = user_fixture()
      other_user = user_fixture()
      {:ok, _, _} = Accounts.create_api_token(other_user, "not mine")
      {:ok, _, older} = Accounts.create_api_token(user, "older")
      {:ok, _, newer} = Accounts.create_api_token(user, "newer")

      assert Accounts.list_api_tokens(user) |> Enum.map(& &1.id) == [newer.id, older.id]
    end
  end

  describe "revoke_api_token/2" do
    test "deletes the token when the user owns it" do
      user = user_fixture()
      {:ok, token, api_token} = Accounts.create_api_token(user, "test")

      assert {:ok, _} = Accounts.revoke_api_token(user, api_token)
      assert {:error, :invalid} = Accounts.get_user_by_api_token(token)
    end

    test "returns {:error, :not_found} when the user doesn't own it" do
      owner = user_fixture()
      stranger = user_fixture()
      {:ok, _token, api_token} = Accounts.create_api_token(owner, "test")

      assert {:error, :not_found} = Accounts.revoke_api_token(stranger, api_token)
      assert [_] = Accounts.list_api_tokens(owner)
    end
  end
end
