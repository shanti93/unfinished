defmodule BitcoinSimulator.BitcoinCore do

  alias BitcoinSimulator.BitcoinCore.{Blockchain, Mining, Network, RawTransaction, Wallet}

  # Block Chain

  def newBlockchain, do: Blockchain.newBlockchain()

  def hashOfBestBlock(blockchain), do: Blockchain.hashOfBestBlock(blockchain)

  def hashBlockheader(header), do: Blockchain.hashBlockheader(header)

  def hashTransaction(tx), do: Blockchain.hashTransaction(tx)

  def blockCheck(blockchain, block), do: Blockchain.blockCheck(blockchain, block)

  def transactionCheck(blockchain, tx), do: Blockchain.transactionCheck(blockchain, tx)

  def blockAdd(block, blockchain, wallet, mempool, mining_process \\ nil, mining_txs \\ nil) do
    Blockchain.blockAdd(block, blockchain, wallet, mempool, mining_process, mining_txs)
  end

  # Mining

  def newMempool, do: Mining.newMempool()

  def findTopUnconfirmedTrans(mempool), do: Mining.findTopUnconfirmedTrans(mempool)

  def blockTemplate(prev_hash, txs), do: Mining.blockTemplate(prev_hash, txs)

  def doMine(block, coinbase_addr, self_id), do: Mining.doMine(block, coinbase_addr, self_id)

  def unconfirmedTransAdd(mempool, tx, tx_hash), do: Mining.unconfirmedTransAdd(mempool, tx, tx_hash)

  def coinbaseValueCalculate(blockchain, txs), do: Mining.coinbaseValueCalculate(blockchain, txs)

  # Network

  def newMessageRecord, do: %Network.MessageRecord{}

  def findInitialNeighbors(id), do: Network.findInitialNeighbors(id)

  def get_initial_blockchain(neighbors), do: Network.get_initial_blockchain(neighbors)

  def exchange_neighbors(neighbors), do: Network.exchange_neighbors(neighbors)

  def mix_neighbors(neighbors, self_id), do: Network.mix_neighbors(neighbors, self_id)

  def message_seen?(record, type, hash), do: Network.message_seen?(record, type, hash)

  def saw_message(record, type, hash), do: Network.saw_message(record, type, hash)

  def clean_message_record(record), do: Network.clean_message_record(record)

  def broadcast_message(type, message, neighbors, sender), do: Network.broadcast_message(type, message, neighbors, sender)

  # Raw Transaction

  def create_raw_transaction(in_addresses, out_addresses, out_values, change_address, change_value) do
    RawTransaction.create_raw_transaction(in_addresses, out_addresses, out_values, change_address, change_value)
  end

  def create_coinbase_transaction(out_addresses, out_values), do: RawTransaction.create_coinbase_transaction(out_addresses, out_values)

  # Wallet

  def get_new_wallet, do: Wallet.get_new_wallet()

  def get_new_address(wallet), do: Wallet.get_new_address(wallet)

  def combine_unspent_addresses(wallet, target_value), do: Wallet.combine_unspent_addresses(wallet, target_value)

  def spend_address(wallet, address), do: Wallet.spend_address(wallet, address)

  def import_address(wallet, address), do: Wallet.import_address(wallet, address)

end
