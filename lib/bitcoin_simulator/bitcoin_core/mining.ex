defmodule BitcoinSimulator.BitcoinCore.Mining do
  use Timex

  alias BitcoinSimulator.BitcoinCore.Blockchain
  alias BitcoinSimulator.Simulation.Param
  alias BitcoinSimulator.Const

  defmodule MemPool do
    defstruct [
      unconfirmed_txs: Map.new()
    ]
  end

  # APIs

  def newMempool, do: %MemPool{}

  def findTopUnconfirmedTrans(mempool) do
    transactions = Map.values(mempool.unconfirmed_txs)
    max_transaction_per_block = Const.decode(:max_transaction_per_block)
    sorted_txs = unconfirmedTransSort(transactions)
    Enum.take(sorted_txs, max_transaction_per_block)
  end

  def blockTemplate(prev_hash, txs) do
    %Blockchain.Block{
      header: %Blockchain.BlockHeader{
        previous_block_hash: prev_hash,
        merkleRoot_hash: Blockchain.merkleRoot(txs),
        n_bits: GenServer.call(Param, {:get_param, :target_difficulty_bits}),
      },
      transactions: txs
    }
  end

  def doMine(block, coinbase_addr, self_id) do
    Process.flag(:priority, :low)
    mined_block_header = miningHelper(block.header, 0)
    mined_block = %{block | header: mined_block_header}
    GenServer.cast({:via, Registry, {BitcoinSimulator.Registry, "peer_#{self_id}"}}, {:block_mined, mined_block, coinbase_addr})
  end

  def unconfirmedTransAdd(mempool, tx, tx_hash) do
    new_unconfirmed_txs = Map.put(mempool.unconfirmed_txs, tx_hash, tx)
    %{mempool | unconfirmed_txs: new_unconfirmed_txs}
  end

  def coinbaseValueCalculate(blockchain, txs) do
    fee = Enum.reduce(txs, 0.0, fn(x, acc) -> acc + transFeeCalculate(blockchain, x) end)
    (fee + Const.decode(:block_reward)) |> Float.round(Const.decode(:transaction_value_precision))
  end

  # Aux

  def leadingZerosMatch?(hash, difficulty) do
    remain = Const.decode(:hash_digest) - difficulty
    <<n::size(difficulty), _::size(remain)>> = hash
    n == 0
  end

  def unconfirmedTransClean(tx_hashes, mempool) do
    new_unconfirmed_txs = Enum.reduce(MapSet.to_list(tx_hashes), mempool.unconfirmed_txs, fn(x, acc) -> Map.delete(acc, x) end)
    %{mempool | unconfirmed_txs: new_unconfirmed_txs}
  end

  defp unconfirmedTransSort(txs), do: Enum.sort(txs, fn(a, b) -> Timex.compare(a.time, b.time) == -1 end)

  defp miningHelper(header, nonce) do
    filled_header = %{header | time: Timex.now(), nonce: nonce}
    hash = Blockchain.hashBlockheader(filled_header)
    if leadingZerosMatch?(hash, GenServer.call(Param, {:get_param, :target_difficulty_bits})), do: filled_header, else: miningHelper(header, nonce + 1)
  end

  defp transFeeCalculate(blockchain, tx) do
    total_in = Enum.reduce(tx.tx_in, 0.0, fn(x, acc) -> acc + blockchain.unspent_txout[x.previous_output].value end) |> Float.round(Const.decode(:transaction_value_precision))
    total_out = Enum.reduce(tx.tx_out, 0.0, fn(x, acc) -> acc + x.value end) |> Float.round(Const.decode(:transaction_value_precision))
    (total_in - total_out) |> Float.round(Const.decode(:transaction_value_precision))
  end

end
