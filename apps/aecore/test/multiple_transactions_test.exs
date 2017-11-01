defmodule MultipleTransactionsTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain

  setup do
    Pool.start_link()
    []
  end

  @tag timeout: 10000000
  test "in one block" do
    {account1, account2, account3} = get_accounts_one_block()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3
    pubkey = elem(Keys.pubkey(), 1)

    # account A has 100 tokens, spends 99 (+1 fee) to B should succeed
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account2, 99,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 99 == Chain.chain_state[account2_pub_key].balance

    # account1 => 0; account2 => 99

    # account A has 100 tokens, spends 109 (+1 fee) to B should be invalid
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account2, 109,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 100 == Chain.chain_state[account1_pub_key].balance

    # acccount1 => 100; account2 => 99

    # account A has 100 tokens, spends 39 (+1 fee) to B, and two times 29 (+1 fee) to C should succeed
    account1_initial_nonce = Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce
    tx = create_signed_tx(account1, account2, 39, account1_initial_nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    tx = create_signed_tx(account1, account3, 29, account1_initial_nonce + 2, 1)
    assert :ok = Pool.add_transaction(tx)
    tx = create_signed_tx(account1, account3, 29, account1_initial_nonce + 3, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 138 == Chain.chain_state[account2_pub_key].balance
    assert 58 == Chain.chain_state[account3_pub_key].balance

    # account1 => 0; account2 => 138; account3 => 58

    # account A has 100 tokens, spends 49 (+1 fee) to B, and two times 29 (+1 fee) to C,
    # last transaction to C should be invalid, others be included
    account1_initial_nonce = Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account2, 49, account1_initial_nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    tx = create_signed_tx(account1, account3, 29, account1_initial_nonce + 2, 1)
    assert :ok = Pool.add_transaction(tx)
    tx = create_signed_tx(account1, account3, 29, account1_initial_nonce + 3, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 20 == Chain.chain_state[account1_pub_key].balance
    assert 187 == Chain.chain_state[account2_pub_key].balance
    assert 87 == Chain.chain_state[account3_pub_key].balance

    # account1 => 20; account2 => 197; account3 => 87

    # account C has 100 tokens, spends 99 (+1 fee) to B, B spends 99 (+1 fee) to A should succeed
    {:ok, tx} = Keys.sign_tx(account3_pub_key, 13,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account3, account2, 99,
                          Map.get(Chain.chain_state, account3_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    tx = create_signed_tx(account2, account1, 99,
                          Map.get(Chain.chain_state, account2_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account3_pub_key].balance
    assert 186 == Chain.chain_state[account2_pub_key].balance
    assert 119 == Chain.chain_state[account1_pub_key].balance
  end

  @tag timeout: 10000000
  test "in multiple blocks" do
    {account1, account2, account3} = get_accounts_multiple_blocks()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3
    pubkey = elem(Keys.pubkey(), 1)

    # account A has 100 tokens, spends 99 (+1 fee) to B should succeed
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account2, 99,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 99 == Chain.chain_state[account2_pub_key].balance

    # account1 => 0; account2 => 99

    # account A has 100 tokens, spends 109 (+1 fee) to B should be invalid
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account2, 109,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 100 == Chain.chain_state[account1_pub_key].balance

    # acccount1 => 100; account2 => 99

    # account A has 100 tokens, spends 39 (+1 fee) to B, and two times 29 (+1 fee) to C should succeed
    tx = create_signed_tx(account1, account2, 39,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account3, 29,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account3, 29,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 138 == Chain.chain_state[account2_pub_key].balance
    assert 58 == Chain.chain_state[account3_pub_key].balance

    # account1 => 0; account2 => 138; account3 => 58

    # account A has 99 (+1 fee) tokens, spends 49 (+1 fee) to B, and two times 29 (+1 fee) to C,
    # last transaction to C should be invalid, others be included
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account2, 49,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account3, 29,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account3, 29,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 20 == Chain.chain_state[account1_pub_key].balance
    assert 187 == Chain.chain_state[account2_pub_key].balance
    assert 87 == Chain.chain_state[account3_pub_key].balance

    # account1 => 20; account2 => 187; account3 => 87

    # account A has 100 tokens, spends 99 (+1 fee) to B, B spends 99 (+1 fee) to C should succeed
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 80,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account2, 99,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account2, account3, 99,
                          Map.get(Chain.chain_state, account2_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state[account1_pub_key].balance
    assert 186 == Chain.chain_state[account2_pub_key].balance
    assert 186 == Chain.chain_state[account3_pub_key].balance
  end

  @tag timeout: 10000000
  test "in one block, miner collects all the fees from the transactions" do
    {account1, account2, account3} = get_accounts_one_block()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3
    pubkey = elem(Keys.pubkey(), 1)

    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    {:ok, tx} = Keys.sign_tx(account1_pub_key, 100,
                             Map.get(Chain.chain_state, pubkey, %{nonce: 0}).nonce + 1, 0)
    assert :ok = Pool.add_transaction(tx)
    Miner.resume()
    Miner.suspend()
    Pool.get_and_empty_pool()
    tx = create_signed_tx(account1, account2, 99,
                          Map.get(Chain.chain_state, account1_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    tx = create_signed_tx(account2, account3, 99,
                          Map.get(Chain.chain_state, account2_pub_key, %{nonce: 0}).nonce + 1, 1)
    assert :ok = Pool.add_transaction(tx)
    miner_balance_before_mining = Map.get(Chain.chain_state, pubkey).balance
    Miner.resume()
    Miner.suspend()
    miner_balance_after_mining = Map.get(Chain.chain_state, pubkey).balance
    assert miner_balance_after_mining == miner_balance_before_mining + Miner.coinbase_transaction_value() + 2
  end

  defp get_accounts_one_block() do
    account1 = {
        <<4, 94, 96, 161, 182, 76, 153, 22, 179, 136, 60, 87, 225, 135, 253, 179, 80,
          40, 80, 149, 21, 26, 253, 48, 139, 155, 200, 45, 150, 183, 61, 46, 151, 42,
          245, 199, 168, 60, 121, 39, 180, 82, 162, 173, 86, 194, 180, 54, 116, 190,
          199, 155, 97, 222, 85, 83, 147, 172, 10, 85, 112, 29, 54, 0, 78>>,
        <<214, 90, 19, 166, 30, 35, 31, 96, 16, 116, 48, 33, 26, 76, 192, 195, 104,
          242, 147, 120, 240, 124, 112, 222, 213, 112, 142, 218, 49, 33, 6, 81>>
      }
    account2 = {
        <<4, 205, 231, 80, 153, 60, 210, 201, 30, 39, 4, 191, 92, 231, 80, 143, 98,
          143, 46, 150, 175, 162, 230, 59, 56, 2, 60, 238, 206, 218, 239, 177, 201, 66,
          161, 205, 159, 69, 177, 155, 172, 222, 43, 225, 241, 181, 226, 244, 106, 23,
          114, 161, 65, 121, 146, 35, 27, 136, 15, 142, 228, 22, 217, 78, 90>>,
        <<151, 121, 56, 150, 179, 169, 141, 25, 212, 247, 156, 162, 120, 205, 59, 184,
          49, 201, 75, 67, 170, 113, 157, 114, 129, 149, 206, 62, 182, 239, 146, 26>>
      }
    account3 = {
        <<4, 167, 170, 180, 131, 214, 204, 39, 21, 99, 168, 142, 78, 66, 54, 118, 143,
          18, 28, 73, 62, 255, 220, 172, 4, 166, 255, 54, 72, 39, 34, 233, 23, 124,
          242, 120, 68, 145, 79, 31, 63, 168, 166, 87, 153, 108, 93, 92, 249, 6, 21,
          75, 159, 180, 17, 18, 6, 186, 42, 199, 140, 254, 115, 165, 199>>,
        <<158, 99, 132, 39, 80, 18, 118, 135, 107, 173, 203, 149, 238, 177, 124, 169,
          207, 241, 200, 73, 154, 108, 205, 151, 103, 197, 21, 0, 183, 163, 137, 228>>
      }

      {account1, account2, account3}
  end

  defp get_accounts_multiple_blocks() do
    account1 = {
        <<4, 113, 73, 130, 150, 200, 126, 80, 231, 110, 11, 224, 246, 121, 247, 201,
          166, 210, 85, 162, 163, 45, 147, 212, 141, 68, 28, 179, 91, 161, 139, 237,
          168, 61, 115, 74, 188, 140, 143, 160, 232, 230, 187, 220, 17, 24, 249, 202,
          222, 19, 20, 136, 175, 241, 203, 82, 23, 76, 218, 9, 72, 42, 11, 123, 127>>,
        <<198, 218, 48, 178, 127, 24, 201, 115, 3, 29, 188, 220, 222, 189, 132, 139,
          168, 1, 64, 134, 103, 38, 151, 213, 195, 5, 219, 138, 29, 137, 119, 229>>
      }
    account2 = {
        <<4, 44, 202, 225, 249, 173, 82, 71, 56, 32, 113, 206, 123, 220, 201, 169, 40,
          91, 56, 206, 54, 114, 162, 48, 226, 255, 87, 3, 113, 161, 45, 231, 163, 50,
          116, 30, 204, 109, 69, 255, 54, 78, 238, 249, 34, 139, 9, 35, 99, 246, 181,
          238, 165, 123, 67, 66, 217, 176, 227, 237, 64, 84, 65, 73, 141>>,
        <<44, 81, 132, 144, 204, 94, 98, 172, 51, 110, 175, 30, 195, 124, 217, 172,
          242, 240, 60, 102, 96, 91, 195, 138, 253, 247, 130, 188, 62, 229, 62, 37>>
      }
    account3 = {
        <<4, 11, 38, 199, 95, 205, 49, 85, 168, 55, 88, 105, 244, 159, 57, 125, 71,
          128, 119, 87, 224, 135, 195, 98, 218, 32, 225, 96, 254, 88, 55, 219, 164,
          148, 30, 203, 57, 24, 121, 208, 160, 116, 231, 94, 229, 135, 225, 47, 16,
          162, 250, 63, 103, 111, 249, 66, 67, 21, 133, 54, 152, 61, 119, 51, 188>>,
        <<19, 239, 205, 35, 76, 49, 9, 230, 59, 169, 195, 217, 222, 135, 204, 201, 160,
          126, 253, 20, 230, 122, 184, 193, 131, 53, 157, 50, 117, 29, 195, 47>>
      }

    {account1, account2, account3}
  end

  defp create_signed_tx(from_acc, to_acc, value, nonce, fee) do
    {from_acc_pub_key, from_acc_priv_key} = from_acc
    {to_acc_pub_key, _to_acc_priv_key} = to_acc
    {:ok, tx_data} = TxData.create(from_acc_pub_key, to_acc_pub_key, value, nonce, fee)
    {:ok, signature} = Keys.sign(tx_data, from_acc_priv_key)

    %SignedTx{data: tx_data, signature: signature}
  end

end
