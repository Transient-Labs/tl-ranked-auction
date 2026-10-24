# Entry Point Map

> Transient Labs Ranked Auction | 26 entry points | 11 permissionless | 3 role-gated | 12 admin-only

The two contracts expose identical 13-function surfaces (ERC-721 vs ERC-1155 variant), so each block below covers the pair and cites both line numbers. Every state-changing entry point carries `nonReentrant`. Inherited OZ `Ownable` adds `transferOwnership` / `renounceOwnership` (admin-only; defined in the dependency, outside the scan).

---

## Protocol Flow Paths

### Setup (Owner)

`constructor` → `depositPrizeTokens()` (batched, ≤ NUM_TOKENS total) → `setupAuction()`  ◄── `prizeTokenIds.length` must equal NUM_TOKENS
  ├─→ `[wrong order?]` `withdrawPrizeTokens()` → re-deposit → `setupAuction()`  ◄── CONFIGURING only
  └─→ `[misconfigured?]` `resetAuction()`  ◄── only while listSize == 0

### Bidding (Bidder)

`[setup above]` → `createBid()` / `increaseBid()`  ◄── state == LIVE and openAt ≤ ts ≤ openAt+duration
  ├─→ new tail displaced → auto-refund  ◄── 1e5 gas cap; failure → pendingRefunds credit
  └─→ rank change in last 5 min → duration extended  ◄── clamped to hardEndAt (never past openAt+duration+2h)

### Settlement (Anyone)

`[bids placed]` → `[ts > openAt+duration]` → `startSettlingAuction()`  ◄── snapshots clearingPrice, pendingProceeds, nextUnallocatedRank
  → `processRanks(n)` (repeatable batches)  ◄── until processedId == tail → state = SETTLED

### Claim (Anyone — funds go to the stored bidder)

`[settled above]` → `claim(bidId)`  ◄── bid must have rank != 0 and not be claimed
  ├─→ ETH refund → `_tryRefundEth()`  ◄── failure → pendingRefunds → `rescueRefund()`
  └─→ NFT transfer → `NFT_CONTRACT.safeTransferFrom()`  ◄── failure → pendingNfts → `rescueNft()`

### Post-Settlement (Owner)

`[settled above]` → `withdrawPendingProceeds()`  ◄── capped at pendingProceeds; SETTLED only
  → `withdrawLeftOverPrizeTokens()`  ◄── only if listSize < NUM_TOKENS (underallocated)

---

## Permissionless

### `TLRankedAuction.createBid(uint32)` / `TLRankedAuction1155.createBid(uint32)` — 721:157 / 1155:161

| Aspect | Detail |
|--------|--------|
| Visibility | external, payable, nonReentrant |
| Caller | Any address (bidder) |
| Parameters | hintBidId (user-controlled — walk start point; affects gas only, not final order) |
| Call chain | → `_checkAuctionOpen()` → `_getMinBid()` → `_insertBid()` → `_findInsertionSpot()` → `_extendAuctionDuration()` → `_removeTailAndRefund()` → `_tryRefundEth()` (ETH out to displaced tail, or pendingRefunds credit) |
| State modified | nextBidId++, `_bids[bidId]`, `_bidders[bidId]`, head/tail/neighbor pointers, listSize++, duration (conditional), tail + deleted tail node (displacement), pendingRefunds (on refund failure) |
| Value flow | ETH in (msg.value = bid amount); ETH out to displaced tail bidder |
| Reentrancy guard | yes |

### `TLRankedAuction.startSettlingAuction()` / `TLRankedAuction1155.startSettlingAuction()` — 721:402 / 1155:406

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Anyone (expected: project runners) |
| Parameters | none |
| Call chain | → no external calls; pure state transition (events only) |
| State modified | state → SETTLING (or SETTLED when listSize == 0), clearingPrice, pendingProceeds, nextUnallocatedRank |
| Value flow | none |
| Reentrancy guard | yes |

### `TLRankedAuction.processRanks(uint32)` / `TLRankedAuction1155.processRanks(uint32)` — 721:428 / 1155:432

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Anyone (settlement continuation) |
| Parameters | numToProcess (user-controlled; capped to listSize − alreadyProcessed) |
| Call chain | → no external calls; walks `_bids[].next` head→tail, emits BidRanked |
| State modified | `_bids[current].rank`, nextRank, lastProcessedId, state → SETTLED at tail |
| Value flow | none |
| Reentrancy guard | yes |

### `TLRankedAuction.claim(uint32)` / `TLRankedAuction1155.claim(uint32)` — 721:476 / 1155:480

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Anyone; beneficiary is the stored `_bidders[bidId]` |
| Parameters | bidId (user-controlled) |
| Call chain | → `_tryRefundEth(bidder, refund)` → `NFT_CONTRACT.safeTransferFrom(address(this), bidder, prizeTokenIds[rank-1])` inside try/catch (1155 passes amount 1, "") |
| State modified | `storedBid.claimed = true` (before transfers); pendingRefunds[bidder] (refund failure); pendingNfts (721: token-keyed @505 / 1155: user-keyed += @509, transfer failure) |
| Value flow | ETH out (refund = amount − clearingPrice) + NFT out |
| Reentrancy guard | yes |

### `TLRankedAuction.rescueRefund(address)` / `TLRankedAuction1155.rescueRefund(address)` — 721:661 / 1155:666

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Any address with a self-keyed `pendingRefunds[msg.sender]` credit |
| Parameters | recipient (user-controlled) |
| Call chain | → `recipient.call{value: refund}("")`; reverts on failure |
| State modified | `pendingRefunds[msg.sender] = 0` before the call |
| Value flow | ETH out to caller-selected recipient |
| Reentrancy guard | yes |

### `TLRankedAuction1155.rescueNft(address,uint256)` — 1155:687

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Any address; only its self-keyed `pendingNfts[msg.sender][tokenId]` amount is read |
| Parameters | recipient (user-controlled), tokenId (user-controlled) |
| Call chain | → `NFT_CONTRACT.safeTransferFrom(address(this), recipient, tokenId, amount, "")` |
| State modified | `pendingNfts[msg.sender][tokenId] = 0` before transfer |
| Value flow | ERC-1155 units out to caller-selected recipient |
| Reentrancy guard | yes |

---

## Role-Gated

### Bidder (own bid)

#### `TLRankedAuction.increaseBid(uint32,uint32)` / `TLRankedAuction1155.increaseBid(uint32,uint32)` — 721:187 / 1155:191

| Aspect | Detail |
|--------|--------|
| Visibility | external, payable, nonReentrant |
| Access gate | `if (msg.sender != bidder) revert NotBidder()` — caller must be `_bidders[bidId]` (721:199 / 1155:203) |
| Parameters | bidId (user-controlled), hintBidId (user-controlled) |
| Call chain | → `_checkAuctionOpen()` → `_isBidInList()` → `_popBid()` → `_insertBid()` → `_extendAuctionDuration()` (only if position changed) |
| State modified | `_bids[bidId].amount` (+msg.value), list pointers (pop + reinsert), duration (conditional) |
| Value flow | ETH in |
| Reentrancy guard | yes |

### Pending-NFT owner (creditor of a failed prize transfer)

#### `TLRankedAuction.rescueNft(address,uint256)` — 721:681

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Access gate | `pendingNfts[tokenId] == msg.sender` (721:684-685) |
| Parameters | recipient (user-controlled), tokenId (user-controlled) |
| Call chain | → `NFT_CONTRACT.safeTransferFrom(address(this), recipient, tokenId)` |
| State modified | pendingNfts entry cleared (before the transfer) |
| Value flow | ERC-721 token out |
| Reentrancy guard | yes |

---

## Admin-Only

All admin functions are `onlyOwner` + `nonReentrant`. No timelock and no pause exist anywhere in the contract; every admin action is instant.

| Contract:Line | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| TLRankedAuction:580 | `depositPrizeTokens(address tokenOwner, uint256[] tokenIdsToAdd)` | tokenOwner (owner-provided — **any approving holder**), tokenIdsToAdd (owner-provided, defines rank order) | prizeTokenIds.push; NFT in via `transferFrom` (CONFIGURING only) |
| TLRankedAuction:599 | `withdrawPrizeTokens(address tokenRecipient, uint32 numToWithdraw)` | recipient (owner-provided) | prizeTokenIds.pop; NFT out (CONFIGURING only) |
| TLRankedAuction:624 | `setupAuction(uint64 openAt_, uint64 duration_)` | times (owner-provided; clamped ≥ now / ≥ 5 min) | state → LIVE, openAt, duration, hardEndAt |
| TLRankedAuction:644 | `resetAuction()` | — | state → CONFIGURING, openAt/duration/hardEndAt = 0 (only while listSize == 0) |
| TLRankedAuction:513 | `withdrawLeftOverPrizeTokens(address tokenRecipient, uint256 numToProcess)` | recipient (owner-provided), batch size (owner-provided) | nextUnallocatedRank; NFT out (SETTLED + underallocated only) |
| TLRankedAuction:551 | `withdrawPendingProceeds(uint256 amount, address payoutAddress)` | amount (owner-provided, capped), payoutAddress (owner-provided, **arbitrary**) | pendingProceeds −; ETH out (SETTLED only) |
| TLRankedAuction1155:585 | `depositPrizeTokens(address tokenOwner, uint256[] tokenIdsToAdd)` | same as 721; repeated ids allowed, `safeTransferFrom` amount 1 | prizeTokenIds.push |
| TLRankedAuction1155:604 | `withdrawPrizeTokens(address tokenRecipient, uint32 numToWithdraw)` | same as 721 | prizeTokenIds.pop; NFT out |
| TLRankedAuction1155:629 | `setupAuction(uint64, uint64)` | same as 721 | state → LIVE, openAt, duration, hardEndAt |
| TLRankedAuction1155:649 | `resetAuction()` | — | same as 721 |
| TLRankedAuction1155:517 | `withdrawLeftOverPrizeTokens(address, uint256)` | same as 721 | nextUnallocatedRank; NFT out |
| TLRankedAuction1155:555 | `withdrawPendingProceeds(uint256, address)` | same as 721 | pendingProceeds −; ETH out |

**Inherited admin (OZ Ownable, not in scan scope):** `transferOwnership(address)` (two-step accept), `renounceOwnership()` — renouncing while pendingProceeds > 0 or leftover tokens exist permanently disables those admin-only withdrawals (no alternative path exists).

---

## Initialization

No proxy pattern: all setup happens in the `constructor(address owner_, address nftContract, uint128 startBid, uint32 numTokens)` (721:141 / 1155:145) — owner and immutables are fixed at deployment, so there is no `initialize()` front-running surface. The constructor validates numTokens ∈ [2, 512], startBid ≥ 10_000 wei, and that the NFT contract has code.
