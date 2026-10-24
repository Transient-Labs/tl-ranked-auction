# Run 2 — solidity-auditor

<!--RUN pass=2 of=3 stamp=20261023-040854 sha=c3ce3f4 agents=12/12-->

Pass 2 of 3 · 2026-10-23 · `c3ce3f4` · 12/12 agents returned.

## Findings

<!--F key=tlrankedauction1155|increasebid|anti-snipe-bypass conf=90 kind=FINDING agents=12-->

[90] **A tail raise skips the anti-snipe extension and raises the clearing price**

`TLRankedAuction1155.increaseBid` · Confidence: 90

**Description**
Any tail bidder calls increaseBid in the final minutes and raises the clearing price, so every other winner pays more without a response window.

All 12 agents re-proved this with independent traces; two ran passing Foundry PoCs in a scratchpad (repo untouched). The extension trigger `if (oldNextId != bid.next || oldPrevId != bid.prev)` watches the list pointers, not the amount, while the tail amount is the future clearing price (`startSettlingAuction` sets `clearingPrice = _getTailBid()` when the list is full). The raise is repeatable every block of the final window (0.5% minimum, compounding: 46 raises lift the price 25.7%), and one call can jump the price to just below the second-lowest bid. An attacker holding the two lowest bids can ladder the clearing price with zero extension events. The escrow forces payment: `LIVE` has no cancel path, so an outbid winner either claims at the raised price or forfeits the full escrowed amount. Worst case, an owner sockpuppet at the tail nets `raise × (listSize − 1)`, taken from the other winners in one transaction. README line 24 documents the mechanism as intended ("the clearing price can move in the final minutes without extra time being added") while line 20 names the extension as the design that prevents bid sniping; the defect is that `createBid` extends unconditionally and `increaseBid` does not.

**Fix**

**Fix (Option A — extend on any raise)** — agents 2, 5, 8, 12: "Call `_extendAuctionDuration` whenever the new amount exceeds the old amount."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
+        if (oldNextId != bid.next || oldPrevId != bid.prev || newBidAmount > bidAmount) {
             _extendAuctionDuration();
         }
```

**Fix (Option B — extend on every call)** — agents 1, 3, 4, 6, 9, 10: "Make `increaseBid` call `_extendAuctionDuration` on every accepted increase, as `createBid` does."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
-            _extendAuctionDuration();
-        }
+        _extendAuctionDuration();
```

**Fix (Option C — extend when the tail moves)** — agent 7: "Make `increaseBid` call `_extendAuctionDuration` when the bid was the tail or becomes the tail."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
+        if (oldNextId != bid.next || oldPrevId != bid.prev || oldNextId == 0 || bid.next == 0) {
             _extendAuctionDuration();
         }
```

<!--/F-->

## Leads

<!--F key=tlrankedauction1155|createbid|uint128-narrowing-cast kind=LEAD agents=12-->

- **createBid casts the payment to uint128 without a size check** — `TLRankedAuction1155.createBid` — Code smells: `uint128 amount = uint128(msg.value);` truncates before the min-bid check, so the bid records the wrapped value while the contract keeps the full payment. — A bidder must send more than 2^128 wei (about 3.4e20 ETH) to lose the excess, and no path returns it. That amount exceeds all ETH in existence, so no caller can trigger it.

<!--/F-->

<!--F key=tlrankedauction1155|createbid|uint32-counter-wrap kind=LEAD agents=10-->

- **nextBidId wraps to zero after 2^32 accepted bids** — `TLRankedAuction1155.createBid` — Code smells: `unchecked { nextBidId = bidId + 1; }` has no wrap guard, and bid id 0 doubles as the null sentinel for head, tail, prev, next and `_isBidInList`. — A wrapped id would alias a live bid to the sentinel and corrupt the list. The wrap needs about 4.3 billion accepted bids (about 4.3e14 gas), so no auction reaches it.

<!--/F-->

<!--F key=tlrankedauction1155|increasebid|uint128-narrowing-cast kind=LEAD agents=8-->

- **increaseBid casts the payment to uint128 without a size check** — `TLRankedAuction1155.increaseBid` — Code smells: `uint128 newBidAmount = bidAmount + uint128(msg.value);` — the `AddMore` check compares the full `msg.value`, but the bid credits only the low 128 bits, and the excess has no exit path. — A sender of 2^128 wei or more adds only the wrapped part to the bid, and the surplus stays locked. No chain we know holds 2^128 base units of native supply, so we could not confirm a reachable deployment.

<!--/F-->

<!--F key=tlrankedauction1155|claim|unchecked-underflow-latent kind=LEAD agents=11-->

- **claim subtracts the clearing price inside unchecked with no local guard** — `TLRankedAuction1155.claim` — Code smells: `unchecked { refund = uint256(storedBid.amount - clearingPrice); }` — its safety rests on the min-bid floor and the list order, both held far from this line. — Every ranked bid stays at or above the clearing price on both settle branches, and a 4096-run adversarial fuzz produced no counterexample, so the underflow stays latent. A checked subtraction would make the invariant local.

<!--/F-->

<!--F key=tlrankedauction1155|claim|unchecked-transfer-receipt kind=LEAD agents=11-->

- **claim trusts the token call result without a balance check** — `TLRankedAuction1155.claim` — Code smells: the `try` block marks the bid claimed when `safeTransferFrom` returns, and the catch arm credits `pendingNfts` on any revert; neither branch reads a balance. — A non-conforming `NFT_CONTRACT` that returns success without a transfer leaves the winner no token and no rescue entry. The token is immutable and deployer-chosen, so we found no in-scope trigger.

<!--/F-->

<!--F key=tlrankedauction1155|claim|event-overstates-refund kind=LEAD agents=12-->

- **PrizeTokenClaimed reports a refund that the bidder did not receive** — `TLRankedAuction1155.claim` — Code smells: `emit PrizeTokenClaimed(bidder, prizeTokenId, refund)` carries the full refund value even when `_tryRefundEth` failed and queued it in `pendingRefunds`. — An indexer that reads only `PrizeTokenClaimed` records ETH the bidder never received. `RefundQueued` carries the truth, so the record stays reconcilable and no funds move wrongly.

<!--/F-->

<!--F key=tlrankedauction1155|claim|third-party-claim-gas-limit kind=LEAD agents=12-->

- **A third-party claim can queue the winner's refund or prize** — `TLRankedAuction1155.claim` — Code smells: `claim` has no caller restriction, `_tryRefundEth` sends with `gas: GAS_GRIEFING_LIMIT` (1e5), and the caller of `claim` also controls the outer gas limit that reaches the token transfer, so the catch arm can be forced. — A caller can queue a refund for a winner whose `receive` costs more than 1e5 gas, or starve the token transfer itself and force a `rescueNft` round trip. No value moves to the caller, so the winner pays only extra gas.

<!--/F-->

<!--F key=tlrankedauction1155|setupauction|unbounded-parameter-lockout kind=LEAD agents=10-->

- **setupAuction accepts any duration and can lock the auction** — `TLRankedAuction1155.setupAuction` — Code smells: `duration_` has a floor but no ceiling, `hardEndAt = openAt + duration + uint64(EXTENSION_HARD_CAP)` reverts on true uint64 overflow, and `openAt + duration` wraps in the end-time checks. — One owner entry above a sane bound holds the bid ETH and the prizes for the whole configured term, and `resetAuction` reverts once any bid exists. Values that overflow uint64 panic harmlessly, so the harm needs an owner mistake, not an attacker.

<!--/F-->

<!--F key=tlrankedauction1155|getprizetokenidforrank|bounds-check-mismatch kind=LEAD agents=11-->

- **getPrizeTokenIdForRank checks rank against the wrong length** — `TLRankedAuction1155.getPrizeTokenIdForRank` — Code smells: `if (rank > NUM_TOKENS || rank == 0) revert InvalidRank();` guards the immutable, but `prizeTokenIds[rank - 1]` reads an array that stays shorter until `setupAuction` runs. — Any caller in CONFIGURING gets an array-bounds panic instead of `InvalidRank`. The function only reads state, so no funds are at risk.

<!--/F-->

<!--F key=tlrankedauction1155|depositprizetokens|escrow-ledger-desync kind=LEAD agents=11-->

- **depositPrizeTokens records a prize before the transfer confirms it** — `TLRankedAuction1155.depositPrizeTokens` — Code smells: `prizeTokenIds.push(prizeTokenId)` runs before `NFT_CONTRACT.safeTransferFrom`, and nothing in the contract ever reads a `balanceOf`. — A standard token reverts the whole transaction, so the ledger stays in sync; only a token that returns success without a transfer leaves `prizeTokenIds` counting units the escrow never held, and `setupAuction` then opens an auction on phantom prizes. The token is deployer-chosen, so we found no in-scope trigger.

<!--/F-->

<!--F key=tlrankedauction1155|depositprizetokens|missing-zero-token-owner-check kind=LEAD agents=1-->

- **depositPrizeTokens skips a zero-address check on tokenOwner** — `TLRankedAuction1155.depositPrizeTokens` — Code smells: `if (tokenOwner == address(this)) revert InvalidAddress();` is the only guard on `tokenOwner`, while every other address parameter in the contract also rejects `address(0)`. — A deposit call from the zero address succeeds against a non-conforming token, but a conforming OpenZeppelin ERC-1155 reverts on the transfer, so we could not produce harm with a standard token.

<!--/F-->

<!--F key=tlrankedauction1155|withdrawpendingproceeds|proceeds-not-gated-on-delivery kind=LEAD agents=11-->

- **The owner can withdraw proceeds while prize delivery is impossible** — `TLRankedAuction1155.withdrawPendingProceeds` — Code smells: the payout checks only `state == SETTLED`, and nothing ties it to delivered units; the ETH side stays solvent on every branch. — A broken `NFT_CONTRACT` leaves every winner with a `pendingNfts` entry and no prize while the owner takes the full proceeds. A compliant token reverts the path instead, so we could not trigger it in scope.

<!--/F-->

<!--F key=tlrankedauction1155|processranks|settle-on-tail-not-rank kind=LEAD agents=10-->

- **processRanks settles on the tail instead of the rank count** — `TLRankedAuction1155.processRanks` — Code smells: `if (processedId == tail)` sets `SETTLED` and never compares `nextRank - 1` against `listSize`; the walk also trusts the chain between batches. — We traced every writer of the list and the list freezes in `SETTLING`, so the two conditions agree on every path we checked and no input breaks the chain. A rank-count check would make the equivalence local.

<!--/F-->

<!--F key=tlrankedauction1155|increasebid|reinsert-wipes-node-flags kind=LEAD agents=11-->

- **_insertBid rewrites the node and wipes rank and claimed** — `TLRankedAuction1155.increaseBid` — Code smells: `_bids[bidId] = BidNode({..., rank: 0, claimed: false});` runs on every reinsert, and `increaseBid` is the only pop-then-reinsert caller. — The state machine keeps the wipe latent: `increaseBid` runs only in `LIVE`, and `rank` and `claimed` are written only in `SETTLING` and `SETTLED`, so both fields are always zero today. The safety rests on the state gate, not on this code.

<!--/F-->

<!--F key=tlrankedauction1155|-getminbid|uint128-cast-wrap kind=LEAD agents=11-->

- **_getMinBid wraps uint128 when the tail bid passes 3.32e38 wei** — `TLRankedAuction1155._getMinBid` — Code smells: `return uint128(tailBid + tailBid * CREATE_BID_BPS / BASIS);` narrows a uint256 sum with no bound check, so the minimum falls below the tail when the sum passes 2^128. — A wrapped minimum would admit a bid below the tail, but that bid is removed as the new tail in the same call, so the list self-corrects. The trigger amount is about 3.3e20 ETH, above all ETH in existence.

<!--/F-->

<!--F key=tlrankedauction1155|rescuenft|unchecked-transfer-receipt kind=LEAD agents=2-->

- **rescueNft trusts the token transfer without a delivery check** — `TLRankedAuction1155.rescueNft` — Code smells: `pendingNfts[msg.sender][tokenId] = 0` runs before the send, the function has no try/catch and no fallback ledger, and `claim` has already set `claimed = true`; `withdrawLeftOverPrizeTokens` covers only ranks above `listSize`. — A token that returns success without a transfer erases the owed unit, and a persistently failing token strands it forever, because this queue is the winner's only path to the prize. The token is deployer-chosen, so we found no in-scope trigger.

<!--/F-->