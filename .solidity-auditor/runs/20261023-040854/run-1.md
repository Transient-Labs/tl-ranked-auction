# Run 1 — solidity-auditor

<!--RUN pass=1 of=3 stamp=20261023-040854 sha=c3ce3f4 agents=12/12-->

Pass 1 of 3 · 2026-10-23 · `c3ce3f4` · 12/12 agents returned.

## Findings

<!--F key=tlrankedauction1155|increasebid|anti-snipe-bypass conf=90 kind=FINDING agents=3-->

[90] **A tail raise skips the anti-snipe extension and raises the clearing price**

`TLRankedAuction1155.increaseBid` · Confidence: 90

**Description**
Any tail bidder calls increaseBid in the final minutes, so the clearing price rises and every other winner pays more without a response window.

Three agents traced the full path with concrete values: the extension trigger `if (oldNextId != bid.next || oldPrevId != bid.prev)` watches the list pointers, not the amount, and the tail amount is the future clearing price (`startSettlingAuction` sets `clearingPrice = _getTailBid()` when the list is full). A raise up to an exact tie with the second-lowest bid keeps the position, so the auction ends on schedule and every winner's refund shrinks by the raise, which the owner collects as proceeds. README.md documents this behavior as a design note: "the clearing price can move in the final minutes without extra time being added."

**Fix**

**Fix (Option A — extend on any increase)** — agent 2: "In `increaseBid`, call `_extendAuctionDuration` whenever the new amount exceeds the old amount, not only when the pointers change."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
+        if (oldNextId != bid.next || oldPrevId != bid.prev || newBidAmount > bidAmount) {
             _extendAuctionDuration();
         }
```

**Fix (Option B — extend on every call)** — agent 4: "Make `increaseBid` call `_extendAuctionDuration` on every call, the same as `createBid`."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
-            _extendAuctionDuration();
-        }
+        _extendAuctionDuration();
```

**Fix (Option C — extend when the tail moves)** — agent 10: "Make `increaseBid` also call `_extendAuctionDuration` when the bid was the tail or becomes the tail."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
+        if (oldNextId != bid.next || oldPrevId != bid.prev || oldNextId == 0 || bid.next == 0) {
             _extendAuctionDuration();
         }
```

<!--/F-->

## Leads

<!--F key=tlrankedauction1155|createbid|uint128-narrowing-cast kind=LEAD agents=5-->

- **The bid functions cast msg.value to uint128 without a check** — `TLRankedAuction1155.createBid` — Code smells: `uint128 amount = uint128(msg.value);` truncates the payment, `uint128 newBidAmount = bidAmount + uint128(msg.value);` truncates the increase, and every outflow pays only the recorded amount. — A bidder who sends more than 2^128 wei records a smaller bid and the contract keeps the surplus. That value exceeds the ETH supply many times over, so no input reaches this path.

<!--/F-->

<!--F key=tlrankedauction1155|createbid|uint32-counter-wrap kind=LEAD agents=1-->

- **nextBidId wraps to zero after 2^32 accepted bids** — `TLRankedAuction1155.createBid` — Code smells: `unchecked { nextBidId = bidId + 1; }` wraps after 4,294,967,295 accepted creates, and bid id 0 is the null sentinel for head, tail, prev and next. — A caller needs about 4.3 billion accepted bids before the counter wraps, so we could not reach the state that aliases a real bid to the sentinel.

<!--/F-->

<!--F key=tlrankedauction1155|claim|unchecked-underflow-latent kind=LEAD agents=4-->

- **claim subtracts the clearing price inside unchecked with no local guard** — `TLRankedAuction1155.claim` — Code smells: `unchecked { refund = uint256(storedBid.amount - clearingPrice); }` carries no bound check; its safety rests on invariants spread across `_getMinBid`, the sorted list and `startSettlingAuction`. — Every ranked bid stays at or above the clearing price, so we found no input that makes the subtraction wrap. A checked subtraction would make the safety local to the line.

<!--/F-->

<!--F key=tlrankedauction1155|claim|unchecked-transfer-receipt kind=LEAD agents=3-->

- **claim trusts the token call result without a balance check** — `TLRankedAuction1155.claim` — Code smells: `try NFT_CONTRACT.safeTransferFrom(...) catch { pendingNfts[bidder][prizeTokenId] += 1; }` assumes a revert means no unit moved, and the success branch assumes success means the unit arrived; neither reads a balance. — A token that reverts after it moves the unit credits a second unit, and a token that returns success without a transfer keeps the winner's unit. Both paths need a misbehaving NFT_CONTRACT that the deployer chooses, so we found no in-scope trigger.

<!--/F-->

<!--F key=tlrankedauction1155|claim|event-overstates-refund kind=LEAD agents=1-->

- **PrizeTokenClaimed reports a refund that the bidder did not receive** — `TLRankedAuction1155.claim` — Code smells: claim emits `PrizeTokenClaimed(bidder, prizeTokenId, refund)` even when `_tryRefundEth` failed and queued the refund in `pendingRefunds`. — An indexer that reads the event records a payment the bidder never received in that transaction. `RefundQueued` is also emitted, so the record stays reconcilable and no funds move wrongly.

<!--/F-->

<!--F key=tlrankedauction1155|claim|third-party-claim-gas-limit kind=LEAD agents=1-->

- **The refund gas cap makes a third-party claim queue the refund** — `TLRankedAuction1155.claim` — Code smells: claim checks no caller, `_tryRefundEth` sends with `gas: GAS_GRIEFING_LIMIT` (1e5), and a failed send queues `pendingRefunds`. — A contract-wallet winner whose refund fails under the 1e5 gas cap must call `rescueRefund` a second time. No value moves to the caller, so the winner only spends extra gas.

<!--/F-->

<!--F key=tlrankedauction1155|setupauction|unbounded-parameter-lockout kind=LEAD agents=2-->

- **setupAuction accepts any duration and can lock the auction** — `TLRankedAuction1155.setupAuction` — Code smells: `duration_` is clamped only from below (`if (duration_ < EXTENSION_TIME)`) and `hardEndAt = openAt + duration + uint64(EXTENSION_HARD_CAP)` adds uint64 values with no upper bound. — One owner entry above a sane bound ends the auction past any date the chain reaches, so bids and prizes stay locked with no recovery path. We found no path where another actor picks `duration_`.

<!--/F-->

<!--F key=tlrankedauction1155|getprizetokenidforrank|bounds-check-mismatch kind=LEAD agents=2-->

- **getPrizeTokenIdForRank checks rank against the wrong length** — `TLRankedAuction1155.getPrizeTokenIdForRank` — Code smells: the guard reads `if (rank > NUM_TOKENS || rank == 0) revert InvalidRank();` but the array read is `prizeTokenIds[rank - 1]`, whose length stays below `NUM_TOKENS` until `setupAuction` runs. — Any caller gets a Panic instead of `InvalidRank` during CONFIGURING when rank exceeds the deposited count. The function only reads state, so no funds are at risk.

<!--/F-->

<!--F key=tlrankedauction1155|depositprizetokens|escrow-ledger-desync kind=LEAD agents=2-->

- **depositPrizeTokens records a prize before the transfer confirms** — `TLRankedAuction1155.depositPrizeTokens` — Code smells: `prizeTokenIds.push(prizeTokenId)` runs before `NFT_CONTRACT.safeTransferFrom`, nothing reads a balance to confirm the unit arrived, and `setupAuction` checks only the array length. — A token contract that reports success without a transfer leaves ranks with nothing in escrow. The NFT contract is immutable and chosen at deploy, so we found no in-scope trigger.

<!--/F-->

<!--F key=tlrankedauction1155|withdrawpendingproceeds|proceeds-not-gated-on-delivery kind=LEAD agents=1-->

- **The owner can withdraw proceeds while prize delivery is impossible** — `TLRankedAuction1155.withdrawPendingProceeds` — Code smells: claim catches every transfer revert and credits `pendingNfts`, while `withdrawPendingProceeds` pays the owner with no check that prize delivery works. — An NFT_CONTRACT that stops transfers leaves winners with refunds and no tokens, while the owner still takes the proceeds. A compliant token reverts the whole path instead, so we could not trigger this.

<!--/F-->

<!--F key=tlrankedauction1155|processranks|settle-on-tail-not-rank kind=LEAD agents=1-->

- **processRanks settles on the tail instead of the rank count** — `TLRankedAuction1155.processRanks` — Code smells: `state = AuctionState.SETTLED` fires when `processedId == tail` and never checks `nextRank == listSize + 1`; the walk also trusts the whole chain between batches. — We traced every writer of the list and found no path that breaks the chain, so we did not verify any impact from the missing rank check.

<!--/F-->

<!--F key=tlrankedauction1155|increasebid|reinsert-wipes-node-flags kind=LEAD agents=1-->

- **_insertBid rewrites the node and wipes rank and claimed** — `TLRankedAuction1155.increaseBid` — Code smells: `_bids[bidId] = BidNode({amount: amount, next: nextId, prev: prevId, rank: 0, claimed: false});` runs inside the pop-and-reinsert pair of `increaseBid`. — The state machine keeps ranking and bidding apart, so no live bid carries `rank` into `increaseBid` today. The safety rests on the state machine, not on this code.

<!--/F-->

<!--F key=tlrankedauction1155|-getminbid|uint128-cast-wrap kind=LEAD agents=1-->

- **_getMinBid wraps uint128 when the tail bid passes 3.32e38 wei** — `TLRankedAuction1155._getMinBid` — Code smells: `return uint128(tailBid + tailBid * CREATE_BID_BPS / BASIS);` — the uint256 sum passes `type(uint128).max` when the tail bid exceeds about 3.32e38 wei and the cast wraps. — The wrapped minimum sits far below the tail, but a bid that small is removed as the new tail in the same call. The trigger amount exceeds all ETH supply, so we found no reachable impact.

<!--/F-->
