# Common Commands
Let's make our life easy here.

## Step One
Always run `source .env` to ensure variables from your .env file are available in your shell session.

## Deploy
```
forge create src/TLRankedAuction.sol:TLRankedAuction --ledger --rpc-url <rpc-url> --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY --chain <chain> --constructor-args <owner address> <nft contract> <start bid (wei)> <num tokens>
```

## Setting up the auction
Depositing prize tokens
```
cast send --rpc-url <blockchain> --ledger <auction contract> "depositPrizeTokens(address,uint256[])" <token owner> "[<token ids>]"
```

Withdrawing prize tokens (if deposited out of order)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "withdrawPrizeTokens(address,uint256)" <token recipient> <num to withdraw>
```

Setup auction (moves to LIVE)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "setupAuction(uint64,uint64)" <open at timestamp> <duration seconds>
```

Reset auction (only if no bids)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "resetAuction()"
```

## Bidding
Create bid
```
cast send --rpc-url <blockchain> --ledger --value <bid amount wei> <auction contract> "createBid(uint32)" <hint bid id>
```

Increase bid
```
cast send --rpc-url <blockchain> --ledger --value <additional wei> <auction contract> "increaseBid(uint32,uint32)" <bid id> <hint bid id>
```

## Settling the auction
Start settling (after auction end)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "startSettlingAuction()"
```

Process ranks (batch)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "processRanks(uint32)" <num to process>
```

Claim prize + refund for bid
```
cast send --rpc-url <blockchain> --ledger <auction contract> "claim(uint32)" <bid id>
```

Withdraw leftover prize tokens (owner)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "withdrawLeftOverPrizeTokens(address,uint256)" <token recipient> <num to process>
```

Withdraw pending proceeds (owner)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "withdrawPendingProceeds(uint256,address)" <amount wei> <payout address>
```

## Reclaim
Rescue refund (if auto-refund failed)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "rescueRefund(address)" <recipient>
```

Rescue NFT (if transfer failed on claim)
```
cast send --rpc-url <blockchain> --ledger <auction contract> "rescueNft(address,uint256)" <recipient> <token id>
```

## Read-only helpers
Auction info
```
cast call --rpc-url <blockchain> <auction contract> "getAuctionInfo()(uint8,uint64,uint64,uint64,uint128,uint32,uint32,uint32)"
```

Minimum bid
```
cast call --rpc-url <blockchain> <auction contract> "getMinBid()(uint128)"
```

Minimum bid increase
```
cast call --rpc-url <blockchain> <auction contract> "getMinBidIncrease(uint128)(uint128)" <current bid amount wei>
```

Tail bid
```
cast call --rpc-url <blockchain> <auction contract> "getTailBid()(uint128)"
```

Head bid
```
cast call --rpc-url <blockchain> <auction contract> "getHeadBid()(uint128)"
```

Bid detail
```
cast call --rpc-url <blockchain> <auction contract> "getDetailedBid(uint32)((uint32,address,uint128,uint32,uint32,uint32,bool))" <bid id>
```

Paginated bids
```
cast call --rpc-url <blockchain> <auction contract> "getBids(uint32,uint32)((uint32,address,uint128,uint32,uint32,uint32,bool)[],uint32)" <start bid id> <limit>
```

Prize token for rank
```
cast call --rpc-url <blockchain> <auction contract> "getPrizeTokenIdForRank(uint32)(uint256)" <rank>
```
