defmodule BitcoinSimulator.BitcoinCore.Blockchain do

  alias BitcoinSimulator.BitcoinCore.{Mining, Wallet}
  alias BitcoinSimulator.Simulation.Param
  alias BitcoinSimulator.Const

  defmodule Blockchain do
    defstruct [
      blocks: Map.new(),
      unspent_txout: Map.new(),
      confirmation_queue: :queue.new(),
      block_count: 0,
      genesis_block: nil,
      tip: nil
    ]
  end

  defmodule BlockHeader do
    defstruct [
      previous_block_hash: nil,
      merkleRoot_hash: nil,
      time: nil,
      n_bits: nil,
      nonce: nil
    ]
  end

  defmodule Block do
    defstruct [
      header: %BlockHeader{},
      transactions: []
    ]
  end

  defmodule Transaction do
    defstruct [
      in_count: 0,
      tx_in: [],
      out_count: 0,
      tx_out: [],
      time: nil,
      signatures: [],
      public_keys: []
    ]
  end

  defmodule Txin do
    defstruct [
      previous_output: %{
        hash: nil,
        index: 0
      }
    ]
  end

  defmodule Txout do
    defstruct [
      value: 0.0,
      address: nil
    ]
  end

  # APIs

  def newBlockchain do
    hash_digest = Const.decode(:hash_digest)
    {:ok, datetime, 0} = DateTime.from_iso8601("2018-11-20T00:00:00Z")
    genesis_block = %Block{
      header: %BlockHeader{
        previous_block_hash: <<0::size(hash_digest)>>,
        merkleRoot_hash: merkleRoot([]),
        time: datetime,
        n_bits: 0,
        nonce: 0
      },
      transactions: []
    }

    %Blockchain{
      blocks: Map.new([{hashBlockheader(genesis_block.header), genesis_block}]),
      block_count: 1,
      genesis_block: genesis_block,
      tip: genesis_block
    }
  end

  def hashOfBestBlock(blockchain), do: hashBlockheader(blockchain.tip.header)

  def hashBlockheader(header) do
    header = header.previous_block_hash <> header.merkleRoot_hash <> DateTime.to_string(header.time) <> Integer.to_string(header.n_bits) <> Integer.to_string(header.nonce)
    doubleHash(header)
  end

  def hashTransaction(tx) do
    in_count = Integer.to_string(tx.in_count)
    tx_in = transInHash(tx.tx_in)
    out_count = Integer.to_string(tx.out_count)
    tx_out = transOutHash(tx.tx_out)
    time = Time.to_string(tx.time)
    public_keys = hashPublicKeys(tx.public_keys)

    input = in_count <> tx_in <> out_count <> tx_out <> time <> public_keys
    doubleHash(input)
  end

  def blockCheck(blockchain, block) do
    cond do
      # Transaction list must be non-empty
      length(block.transactions) == 0 ->
        "Empty transaction list"
      # Block hash must satisfy nBits proof of work
      not Mining.leadingZerosMatch?(hashBlockheader(block.header), GenServer.call(Param, {:get_param, :target_difficulty_bits})) ->
        "Block hash does not meet target difficulty"
      # First transaction must be coinbase
      not transCoinbase?(Enum.at(block.transactions, 0)) ->
        "First transaction not coinbase"
      # Verify Merkle hash
      merkleRoot(block.transactions) != block.header.merkleRoot_hash ->
        "Merkle root hash incorrect"
      # Check all transactions
      # TODO
      not transVerify?(blockchain, block.transactions, 0, length(block.transactions)) ->
        "Contained invalid transactions"
      # Coinbase value = sum of block creation fee and transaction fees
      block.transactions |> Enum.at(0) |> Map.fetch!(:tx_out) |> Enum.at(0) |> Map.fetch!(:value)
        != Mining.coinbaseValueCalculate(blockchain, Enum.drop(block.transactions, 1)) ->
        "Coinbase value incorrect"

      true ->
        :ok
    end
  end

  def transactionCheck(blockchain, tx) do
    cond do
      # Neither in or out lists are empty
      length(tx.tx_in) == 0 or length(tx.tx_out) == 0 ->
        "tx_in or tx_out is empty"
      # Skip verification for coinbase transactions
      transCoinbase?(tx) ->
        :ok
      # Each input's referenced output must exist and has not already been spent(double spending)
      not transIpCheck?(blockchain, tx.tx_in, 0) ->
        "Some inputs' referenced output does not exist or is already spent"
      # Sum of input values >= sum of output values
      not transSumCheck?(blockchain, tx) ->
        "Sum of input values less than sum of output values"
      # Check signature and public key
      not transSignCheck?(blockchain, tx, 0) ->
        "Signature verification failed"

      true ->
        :ok
    end
  end

  def blockAdd(block, blockchain, wallet, mempool, mining_process \\ nil, mining_txs \\ nil) do
    {new_confirmed_block, new_confirmation_queue} =
      if :queue.len(blockchain.confirmation_queue) == Const.decode(:confirmation_count) do
        {{:value, confirmed_block}, new_queue} = :queue.out(blockchain.confirmation_queue)
        {confirmed_block, new_queue}
      else
        {nil, blockchain.confirmation_queue}
      end

    new_unspent_txout = unspentTransUpdate(block.transactions, blockchain.unspent_txout)
    new_blockchain = %{blockchain |
      blocks: Map.put(blockchain.blocks, hashBlockheader(block.header), block),
      unspent_txout: new_unspent_txout,
      confirmation_queue: :queue.in(block, new_confirmation_queue),
      block_count: blockchain.block_count + 1,
      tip: block
    }

    new_wallet =
      if new_confirmed_block != nil do
        my_addresses = wallet.unspent_addresses |> Map.keys() |> MapSet.new()
        addr_details = Enum.reduce(new_confirmed_block.transactions, Map.new(), fn(tx, result) ->
          tx_hash = hashTransaction(tx)
          {tx_addrs, _} = Enum.reduce(tx.tx_out, {Map.new(), 0}, fn(x, acc) ->
            {temp_result, index} = acc
            if MapSet.member?(my_addresses, x.address) do
              {temp_result |> Map.put(x.address, {x.value, %{ hash: tx_hash, index: index }}), index + 1}
            else
              {temp_result, index + 1}
            end
          end)
          Map.merge(result, tx_addrs)
        end)
        Wallet.update_address_detail(addr_details, wallet)
      else
        wallet
      end

    tx_hashes = Enum.reduce(block.transactions |> Enum.drop(1), MapSet.new(), fn(x, acc) -> MapSet.put(acc, hashTransaction(x)) end)
    new_mempool = Mining.unconfirmedTransClean(tx_hashes, mempool)

    if mining_process != nil and mining_txs != nil and MapSet.intersection(mining_txs, tx_hashes) |> MapSet.size() > 0 do
      IO.puts "XXX"
      Process.exit(mining_process, :kill)
      Process.send_after(self(), :initiate_mine, 1000)
    end

    {new_blockchain, new_wallet, new_mempool}
  end

  # Aux

  def merkleRoot(transactions) do
    unless length(transactions) == 0 do
      hashes = Enum.reduce(transactions, [], fn(x, acc) -> [hashTransaction(x) | acc] end)
      hashes |> Enum.reverse() |> hashlevelMerkeltree() |> Enum.at(0)
    else
      doubleHash("")
    end
  end

  def unspentTransUpdate(txs, unspent_txout) do
    Enum.reduce(txs, unspent_txout, fn(tx, result) ->
      new_unspent_txout = Enum.reduce(tx.tx_in, result, fn(x, acc) ->
        acc |> Map.delete(x.previous_output)
      end)

      tx_hash = hashTransaction(tx)
      {new_unspent_txout, _} = Enum.reduce(tx.tx_out, {new_unspent_txout, 0}, fn(x, acc) ->
        {temp_result, index} = acc
        {temp_result |> Map.put(%{ hash: tx_hash, index: index }, x), index + 1}
      end)

      new_unspent_txout
    end)
  end

  defp doubleHash(input) do
    hash_func = Const.decode(:hash_func)
    :crypto.hash(hash_func, :crypto.hash(hash_func, input))
  end

  defp hashlevelMerkeltree(hashes) when length(hashes) == 1, do: hashes

  defp hashlevelMerkeltree(hashes) do
    {new_hashes, temp, odd} =
      Enum.reduce(hashes, {[], nil, false}, fn(x, acc) ->
        {new_hashes, temp, odd} = acc
        if odd do
          {[doubleHash(temp <> x) | new_hashes], nil, false}
        else
          {new_hashes, x, true}
        end
      end)

    new_hashes = if odd, do: [doubleHash(temp <> temp) | new_hashes], else: new_hashes

    hashlevelMerkeltree(Enum.reverse(new_hashes))
  end

  defp transInHash(txin) do
    Enum.reduce(txin, "", fn(x, acc) ->
      acc <> x.previous_output.hash <> Integer.to_string(x.previous_output.index)
    end)
  end

  defp transOutHash(txout) do
    Enum.reduce(txout, "", fn(x, acc) ->
      acc <> Float.to_string(x.value) <> x.address
    end)
  end

  defp hashPublicKeys(keys) do
    Enum.reduce(keys, "", fn(x, acc) -> acc <> x end)
  end

  defp transVerify?(blockchain, txs, index, len) do
    if index == len do
      true
    else
      if transactionCheck(blockchain, Enum.at(txs, index)) == :ok, do: transVerify?(blockchain, txs, index + 1, len), else: false
    end
  end

  defp transCoinbase?(tx) do
    hash_digest = Const.decode(:hash_digest)
    length(tx.tx_in) == 1
    and Enum.at(tx.tx_in, 0).previous_output.hash == <<0::size(hash_digest)>>
    and Enum.at(tx.tx_in, 0).previous_output.index == -1
  end

  defp transIpCheck?(blockchain, txin, index) do
    if index == length(txin) do
      true
    else
      if Map.has_key?(blockchain.unspent_txout, Enum.at(txin, index).previous_output) do
        transIpCheck?(blockchain, txin, index + 1)
      else
        false
      end
    end
  end

  defp transSumCheck?(blockchain, tx) do
    total_in = Enum.reduce(tx.tx_in, 0.0, fn(x, acc) -> acc + blockchain.unspent_txout[x.previous_output].value end) |> Float.round(Const.decode(:transaction_value_precision))
    total_out = Enum.reduce(tx.tx_out, 0.0, fn(x, acc) -> acc + x.value end) |> Float.round(Const.decode(:transaction_value_precision))
    total_in >= total_out
  end

  defp transSignCheck?(blockchain, tx, index) do
    if index == length(tx.signatures) do
      true
    else
      prev_addr = blockchain.unspent_txout[Enum.at(tx.tx_in, index).previous_output].address
      pk_match? = prev_addr == :crypto.hash(:ripemd160, :crypto.hash(:sha256, Enum.at(tx.public_keys, index)))
      sig_valid? = :crypto.verify(
        :ecdsa,
        Const.decode(:hash_func),
        hashTransaction(tx),
        Enum.at(tx.signatures, index),
        [Enum.at(tx.public_keys, index), :secp256k1])

      if pk_match? and sig_valid? do
        transSignCheck?(blockchain, tx, index + 1)
      else
        false
      end
    end
  end

end
