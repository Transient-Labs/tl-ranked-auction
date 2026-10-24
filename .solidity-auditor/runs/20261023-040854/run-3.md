# Run 3 — solidity-auditor

<!--RUN pass=3 of=3 stamp=20261023-040854 sha=c3ce3f4 agents=12/12-->

Pass 3 of 3 · 2026-10-23 · `c3ce3f4` · 12/12 agents returned (7 relaunched after a transient credit-limit failure at launch; the relaunches all completed).

## Findings

<!--F key=tlrankedauction1155|increasebid|anti-snipe-bypass conf=90 kind=FINDING agents=12-->

[90] **A tail raise skips the anti-snipe extension and raises the clearing price**

`TLRankedAuction1155.increaseBid` · Confidence: 90

**Description**
Any tail bidder raises the clearing price in the final minutes through increaseBid, so every other winner pays more without the promised response window.

All 12 agents re-proved the path this pass, with two passing Foundry PoCs in scratchpads (repo untouched). The extension trigger `if (oldNextId != bid.next || oldPrevId != bid.prev)` watches the list pointers, not the amount, while the tail amount is the future clearing price: `startSettlingAuction` sets `clearingPrice = _getTailBid()` when the list is full. A position-preserving raise — any raise up to an exact tie with the second-lowest bid — skips the extension and ends the auction on schedule, so every winner's refund shrinks by the raise. The same money through `createBid` opens the 5-minute window unconditionally and must also pay 2.5% above the tail, where the raise pays only 0.5%.

Escalations proven across the passes: the raise is repeatable every block of the final window (0.5% steps compound; 46 raises lift the clearing price 25.7%); one call can jump the price to just below the second-lowest bid; a bidder who holds the two lowest bids can ladder the clearing price with zero extension events; the last permitted raise lands at `block.timestamp == endTime`, which `_checkAuctionOpen` still accepts; and `LIVE` has no cancel path, so an outbid winner either claims at the raised price or forfeits the whole escrow. Worst case an owner sockpuppet at the tail nets `raise × (listSize − 1)` from the other winners, because the tail row returns to the owner through `pendingProceeds`.

README line 24 documents the mechanism as intended ("the clearing price can move in the final minutes without extra time being added") while line 64 says the extension exists to "Prevent bid sniping near the end" — the code implements the weaker statement. The identical gate sits in the ERC-721 sibling `src/TLRankedAuction.sol` (`increaseBid`, line 221, verified word-for-word); that file is outside this scan's scope.

**Fix**

**Fix (Option A — extend on any raise)** — "Call `_extendAuctionDuration` whenever the new amount exceeds the old amount."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
+        if (oldNextId != bid.next || oldPrevId != bid.prev || newBidAmount > bidAmount) {
             _extendAuctionDuration();
         }
```

**Fix (Option B — extend on every call)** — "Make `increaseBid` call `_extendAuctionDuration` on every accepted increase, as `createBid` does."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
-            _extendAuctionDuration();
-        }
+        _extendAuctionDuration();
```

**Fix (Option C — extend when the tail moves)** — "Make `increaseBid` call `_extendAuctionDuration` when the bid was the tail or becomes the tail."

```diff
-        if (oldNextId != bid.next || oldPrevId != bid.prev) {
+        if (oldNextId != bid.next || oldPrevId != bid.prev || oldNextId == 0 || bid.next == 0) {
             _extendAuctionDuration();
         }
```

<!--/F-->

## Leads

<!--F key=tlrankedauction1155|createbid|uint128-narrowing-cast kind=LEAD agents=11-->

- **createBid casts the payment to uint128 without a size check** — `TLRankedAuction1155.createBid` — Code smells: `uint128 amount = uint128(msg.value);` truncates before the min-bid check, so the bid records the wrapped value while the contract keeps the full payment, and `withdrawPendingProceeds` and every refund are capped at recorded values. — A bidder must send more than 2^128 wei (about 3.4e20 ETH) to lose the excess, and no path returns it. That amount exceeds all ETH in existence, so no caller can trigger it.

<!--/F-->

<!--F key=tlrankedauction1155|createbid|uint32-counter-wrap kind=LEAD agents=11-->

- **nextBidId wraps to zero after 2^32 accepted bids** — `TLRankedAuction1155.createBid` — Code smells: `unchecked { nextBidId = bidId + 1; }` has no wrap guard; at the wrap the new id is 0, `_insertBid` then writes `head = 0` or `_bids[prevId].next = 0`, so the list loses nodes while `listSize` still counts them. — A wrapped id aliases the null sentinel for head, tail, prev, next and `_isBidInList`, and the gas cost of 4.3 billion accepted bids blocks the wrap in practice.

<!--/F-->

<!--F key=tlrankedauction1155|increasebid|uint128-narrowing-cast kind=LEAD agents=11-->

- **increaseBid casts the payment to uint128 without a size check** — `TLRankedAuction1155.increaseBid` — Code smells: `uint128 newBidAmount = bidAmount + uint128(msg.value);` — the `AddMore` check compares the full `msg.value`, but the bid credits only the low 128 bits, and the excess has no exit path. — A sender of 2^128 wei or more adds only the wrapped part to the bid, and the surplus stays locked. No chain we know holds 2^128 base units of native supply, so we could not confirm a reachable deployment.

<!--/F-->

<!--F key=tlrankedauction1155|claim|unchecked-underflow-latent kind=LEAD agents=12-->

- **claim subtracts the clearing price inside unchecked with no local guard** — `TLRankedAuction1155.claim` — Code smells: `unchecked { refund = uint256(storedBid.amount - clearingPrice); }` — a wrap would queue a refund near 2^128 into the bidder's single `pendingRefunds` key, and `rescueRefund` would then revert `WithdrawalFailed` forever. — Every ranked bid stays at or above the clearing price on both settle branches, and a 4096-run adversarial fuzz produced no counterexample, so the underflow stays latent. A checked subtraction would make the invariant local.

<!--/F-->

<!--F key=tlrankedauction1155|claim|unchecked-transfer-receipt kind=LEAD agents=11-->

- **claim trusts the token call result without a balance check** — `TLRankedAuction1155.claim` — Code smells: `try NFT_CONTRACT.safeTransferFrom(...)` — the OZ `IERC1155` interface declares the function with no return value, so the success branch proves only that the call did not revert; `claimed = true` runs first and no balance is read. — A non-conforming `NFT_CONTRACT` that returns success without a transfer leaves the winner no token and no rescue entry. The token is immutable and deployer-chosen, so we found no in-scope trigger.

<!--/F-->

<!--F key=tlrankedauction1155|claim|event-overstates-refund kind=LEAD agents=11-->

- **PrizeTokenClaimed reports a refund that the bidder did not receive** — `TLRankedAuction1155.claim` — Code smells: `emit PrizeTokenClaimed(bidder, prizeTokenId, refund)` carries the full refund value even when `_tryRefundEth` failed and queued it in `pendingRefunds`, and no event separates a paid refund from a queued one. — An indexer that reads only `PrizeTokenClaimed` records ETH the bidder never received. `RefundQueued` carries the truth, so the record stays reconcilable and no funds move wrongly.

<!--/F-->

<!--F key=tlrankedauction1155|claim|third-party-claim-gas-limit kind=LEAD agents=11-->

- **A third-party claim can queue the winner's refund or prize** — `TLRankedAuction1155.claim` — Code smells: `claim` has no caller restriction, `_tryRefundEth` sends with `gas: GAS_GRIEFING_LIMIT` (1e5), and the caller of `claim` also controls the outer gas limit that reaches the token transfer, so the catch arm can be forced. — A caller can queue a refund for a winner whose `receive` costs more than 1e5 gas, or starve the token transfer itself and force a `rescueNft` round trip. No value moves to the caller, so the winner pays only extra gas.

<!--/F-->

<!--F key=tlrankedauction1155|setupauction|unbounded-parameter-lockout kind=LEAD agents=11-->

- **setupAuction accepts any duration and can lock the auction** — `TLRankedAuction1155.setupAuction` — Code smells: `duration_` has a floor but no ceiling; `hardEndAt = openAt + duration + uint64(EXTENSION_HARD_CAP)` reverts on true uint64 overflow, so overflow values never reach `LIVE`. — One owner entry above a sane but valid duration holds the bid ETH and the prizes for the whole configured term, and `resetAuction` reverts once any bid exists, because the contract offers no bid cancellation. The harm needs an owner mistake, not an attacker.

<!--/F-->

<!--F key=tlrankedauction1155|getprizetokenidforrank|bounds-check-mismatch kind=LEAD agents=11-->

- **getPrizeTokenIdForRank checks rank against the wrong length** — `TLRankedAuction1155.getPrizeTokenIdForRank` — Code smells: `if (rank > NUM_TOKENS || rank == 0) revert InvalidRank();` guards the immutable, but `prizeTokenIds[rank - 1]` reads an array that stays shorter until `setupAuction` runs, and array bounds stay checked inside `unchecked`. — Any caller in CONFIGURING gets an out-of-bounds panic instead of `InvalidRank`. The function only reads state, so no funds are at risk.

<!--/F-->

<!--F key=tlrankedauction1155|depositprizetokens|escrow-ledger-desync kind=LEAD agents=11-->

- **depositPrizeTokens records a prize before the transfer confirms it** — `TLRankedAuction1155.depositPrizeTokens` — Code smells: `prizeTokenIds.push(prizeTokenId)` runs before `NFT_CONTRACT.safeTransferFrom`, nothing in the contract ever reads a `balanceOf`, and `setupAuction` checks only the array length. — A standard token reverts the whole transaction, so the ledger stays in sync; only a token that returns success without a transfer leaves `prizeTokenIds` counting units the escrow never held, and `setupAuction` then opens an auction on phantom prizes. The token is deployer-chosen, so we found no in-scope trigger.

<!--/F-->

<!--F key=tlrankedauction1155|depositprizetokens|missing-zero-token-owner-check kind=LEAD agents=9-->

- **depositPrizeTokens skips a zero-address check on tokenOwner** — `TLRankedAuction1155.depositPrizeTokens` — Code smells: `if (tokenOwner == address(this)) revert InvalidAddress();` is the only guard on `tokenOwner`, while every other address parameter in the contract also rejects `address(0)`. — A deposit call from the zero address succeeds only against a non-conforming token; a conforming OpenZeppelin ERC-1155 reverts the transfer first, so we could not produce harm with a standard token.

<!--/F-->

<!--F key=tlrankedauction1155|withdrawpendingproceeds|proceeds-not-gated-on-delivery kind=LEAD agents=11-->

- **The owner can withdraw proceeds while prize delivery is impossible** — `TLRankedAuction1155.withdrawPendingProceeds` — Code smells: the payout checks only `state == SETTLED`, and nothing ties it to delivered units; the ETH side stays solvent on every branch, so the owner cannot overdraw. — A broken `NFT_CONTRACT` leaves every winner with a `pendingNfts` entry and no prize while the owner takes the full proceeds. A compliant token reverts the path instead, so we could not trigger it in scope.

<!--/F-->

<!--F key=tlrankedauction1155|processranks|settle-on-tail-not-rank kind=LEAD agents=10-->

- **processRanks settles on the tail instead of the rank count** — `TLRankedAuction1155.processRanks` — Code smells: `if (processedId == tail)` sets `SETTLED` and never compares `nextRank - 1` against `listSize`; the walk also trusts the chain between batches, and the batch cap keeps it honest today. — We traced every writer of the list and the list freezes in `SETTLING`, so the two conditions agree on every path we checked and no input breaks the chain. A rank-count check would make the equivalence local.

<!--/F-->

<!--F key=tlrankedauction1155|increasebid|reinsert-wipes-node-flags kind=LEAD agents=11-->

- **_insertBid rewrites the node and wipes rank and claimed** — `TLRankedAuction1155.increaseBid` — Code smells: `_bids[bidId] = BidNode({..., rank: 0, claimed: false});` runs on every reinsert, and `increaseBid` is the only pop-then-reinsert caller. — The state machine keeps the wipe latent: `increaseBid` runs only in `LIVE`, and `rank` and `claimed` are written only in `SETTLING` and `SETTLED`, so both fields are always zero today. The safety rests on the state gate, not on this code.

<!--/F-->

<!--F key=tlrankedauction1155|-getminbid|uint128-cast-wrap kind=LEAD agents=11-->

- **_getMinBid wraps uint128 when the tail bid passes 3.32e38 wei** — `TLRankedAuction1155._getMinBid` — Code smells: `return uint128(tailBid + tailBid * CREATE_BID_BPS / BASIS);` narrows a uint256 sum with no bound check, so the minimum falls below the tail when the sum passes 2^128. — A wrapped minimum would admit a bid below the tail, but that bid is removed as the new tail in the same call, so the list self-corrects. The trigger amount is about 3.3e20 ETH, above all ETH in existence.

<!--/F-->

<!--F key=tlrankedauction1155|rescuenft|unchecked-transfer-receipt kind=LEAD agents=10-->

- **rescueNft trusts the token transfer without a delivery check** — `TLRankedAuction1155.rescueNft` — Code smells: `pendingNfts[msg.sender][tokenId] = 0` runs before the send, the function has no try/catch and no fallback ledger, and `claim` has already set `claimed = true`; `withdrawLeftOverPrizeTokens` covers only ranks above `listSize`. — A token that returns success without a transfer erases the owed unit, and a persistently failing token strands it forever, because this queue is the winner's only path to the prize. The token is deployer-chosen, so we found no in-scope trigger.

<!--/F-->

<!--F key=tlrankedauction1155|onerc1155batchreceived|supports-interface-lie kind=LEAD agents=1-->

- **The holder advertises ERC-1155Receiver but always reverts batch receives** — `TLRankedAuction1155.onERC1155BatchReceived` — Code smells: `supportsInterface` inherits true for `IERC1155Receiver` (0x4e2312e0) from `ERC1155Holder`, while the overridden `onERC1155BatchReceived` is `pure` and always reverts `NotAllowed()`. — A caller that checks ERC-165 before a batch send gets a green light and the transfer still reverts. The revert is atomic, so no funds move and the harm stays a coordination cost.

<!--/F-->

<!--F key=tlrankedauction1155|getbids|view-ghost-row kind=LEAD agents=1-->

- **getBids returns one zeroed row for a removed or unused bid id** — `TLRankedAuction1155.getBids` — Code smells: the loop starts at any `startBidId`; a removed-tail id (deleted node, zero bidder, zero amount) or a never-used id fills one zeroed `BidView`, counts `numReturned = 1`, then stops at `next = 0`. — An indexer that pages with a stale id reads a row that reports a null bidder and a zero amount, and no row signals that no bid exists. The function reads state only, so no funds are at risk.

<!--/F-->

<!--F key=tlrankedauction1155|withdrawleftoverprizetokens|unchecked-transfer-receipt kind=LEAD agents=1-->

- **withdrawLeftOverPrizeTokens burns a rank with no delivery check** — `TLRankedAuction1155.withdrawLeftOverPrizeTokens` — Code smells: the loop advances `nextUnallocatedRank` and emits `PrizeTokenWithdrawn` around a raw `safeTransferFrom` with no try/catch and no balance check, and a consumed rank never returns. — A token that reports success without a transfer strands the unit in the contract with no path out, because the rank cursor already passed it. The caller is the owner, so a lying token harms the owner's own withdrawal.

<!--/F-->

<!--F key=tlrankedauction1155|withdrawprizetokens|unchecked-transfer-receipt kind=LEAD agents=1-->

- **withdrawPrizeTokens pops each prize id before the transfer** — `TLRankedAuction1155.withdrawPrizeTokens` — Code smells: the loop pops `prizeTokenIds` before the raw `safeTransferFrom`, with no delivery check. — A token that reports success without a transfer destroys the escrow record and keeps the unit in the contract. The function runs only in CONFIGURING and only the owner calls it, so the owner takes the loss.

<!--/F-->