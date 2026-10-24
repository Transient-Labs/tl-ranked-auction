# Invariant Map

> Transient Labs Ranked Auction | 40 guards | 19 inferred (14 single-contract · 1 cross-contract · 4 economic) | 1 not enforced on-chain

`TLRankedAuction` (ERC-721) and `TLRankedAuction1155` are logic clones; every entry cites the 721 variant first and the 1155 line second. All storage-variable write sites below were enumerated by grep across both files.

---

## 1. Enforced Guards (Reference)

Per-call preconditions. Heading IDs below (`G-N`) are anchor targets from x-ray.md attack surfaces.

#### G-1
`if (numTokens < 2) revert TooFewTokens()` · `TLRankedAuction.sol:142; TLRankedAuction1155.sol:146` · Establishes at least two immutable prize slots for ranked-auction semantics.

#### G-2
`if (numTokens > MAX_TOKENS) revert TooManyTokens()` · `TLRankedAuction.sol:143; TLRankedAuction1155.sol:147` · Caps looped ranking and token-transfer work at 512 slots.

#### G-3
`if (startBid < BASIS) revert InvalidStartBid()` · `TLRankedAuction.sol:144; TLRankedAuction1155.sol:148` · Keeps BPS-derived minimum increments nonzero at the immutable price floor.

#### G-4
`if (nftContract.code.length == 0) revert InvalidNftContract()` · `TLRankedAuction.sol:145; TLRankedAuction1155.sol:149` · Prevents fixing the immutable prize dependency to a codeless address.

#### G-5
`if (amount < minBid) revert BidMore()` · `TLRankedAuction.sol:164; TLRankedAuction1155.sol:168` · Enforces the storage-derived floor at the only new-bid amount creation path.

#### G-6
`if (!_isBidInList(bidId)) revert InvalidBid()` · `TLRankedAuction.sol:192; TLRankedAuction1155.sol:196` · Prevents mutation of removed or nonexistent bid nodes.

#### G-7
`if (msg.sender != bidder) revert NotBidder()` · `TLRankedAuction.sol:199; TLRankedAuction1155.sol:203` · Binds increases to the address stored for the bid node.

#### G-8
`if (msg.value < _getMinBidIncrease(bidAmount)) revert AddMore()` · `TLRankedAuction.sol:205; TLRankedAuction1155.sol:209` · Requires economically meaningful upward movement of a stored bid.

#### G-9
`if (state != AuctionState.LIVE) revert NotAllowed()` · `TLRankedAuction.sol:230; TLRankedAuction1155.sol:234` · Freezes bid-list mutation outside the LIVE lifecycle phase.

#### G-10
`if (block.timestamp < uint256(openAt)) revert BiddingNotOpen()` · `TLRankedAuction.sol:231; TLRankedAuction1155.sol:235` · Prevents bids before the stored opening time.

#### G-11
`if (block.timestamp > endTime) revert BiddingEnded()` · `TLRankedAuction.sol:233; TLRankedAuction1155.sol:237` · Prevents list mutation after the stored auction deadline.

#### G-12
`revert InvariantBroken()` · `TLRankedAuction.sol:329; TLRankedAuction1155.sol:333` · Fails closed if a bounded list walk cannot find a valid insertion edge.

#### G-13
`if (state != AuctionState.LIVE) revert NotAllowed()` · `TLRankedAuction.sol:403; TLRankedAuction1155.sol:407` · Allows settlement snapshotting only from LIVE.

#### G-14
`if (block.timestamp <= uint256(endTime)) revert AuctionNotEnded()` · `TLRankedAuction.sol:405; TLRankedAuction1155.sol:409` · Prevents fixing the clearing price while the bidding window remains open.

#### G-15
`if (state != AuctionState.SETTLING) revert NotAllowed()` · `TLRankedAuction.sol:429; TLRankedAuction1155.sol:433` · Confines rank assignment to the settlement phase.

#### G-16
`if (numToProcess == 0) revert ProcessAtLeastOne()` · `TLRankedAuction.sol:440; TLRankedAuction1155.sol:444` · Rejects a no-op rank batch after capping against stored progress.

#### G-17
`if (lastProcessedId != 0 && _bids[lastProcessedId].rank != (nextRank - 1)) revert InvariantBroken()` · `TLRankedAuction.sol:443; TLRankedAuction1155.sol:447` · Protects consistency between the rank counter and batch-resume pointer.

#### G-18
`if (current == 0) revert InvariantBroken()` · `TLRankedAuction.sol:451; TLRankedAuction1155.sol:455` · Fails closed if the rank walk ends before stored remaining work is consumed.

#### G-19
`if (state != AuctionState.SETTLED) revert NotAllowed()` · `TLRankedAuction.sol:477; TLRankedAuction1155.sol:481` · Prevents claims before every winning bid has a final rank.

#### G-20
`if (storedBid.rank == 0) revert InvalidBid()` · `TLRankedAuction.sol:484; TLRankedAuction1155.sol:488` · Restricts prize claims to ranked bid records.

#### G-21
`if (storedBid.claimed) revert BidClaimed()` · `TLRankedAuction.sol:485; TLRankedAuction1155.sol:489` · Enforces the per-bid one-shot payout latch.

#### G-22
`if (state != AuctionState.SETTLED) revert NotAllowed()` · `TLRankedAuction.sol:518; TLRankedAuction1155.sol:522` · Delays leftover-prize withdrawal until allocation is final.

#### G-23
`if (listSize == NUM_TOKENS) revert NothingToWithdraw()` · `TLRankedAuction.sol:519; TLRankedAuction1155.sol:523` · Keeps the owner path away from fully allocated winner prizes.

#### G-24
`if (numToProcess == 0) revert ProcessAtLeastOne()` · `TLRankedAuction.sol:532; TLRankedAuction1155.sol:536` · Rejects a no-op leftover withdrawal after storage-derived capping.

#### G-25
`if (state != AuctionState.SETTLED) revert NotAllowed()` · `TLRankedAuction.sol:552; TLRankedAuction1155.sol:556` · Prevents proceeds withdrawal before the clearing-price liability snapshot is final.

#### G-26
`if (amountToWithdraw == 0) revert NothingToWithdraw()` · `TLRankedAuction.sol:557; TLRankedAuction1155.sol:561` · Requires a positive withdrawal after capping to stored pending proceeds.

#### G-27
`if (state != AuctionState.CONFIGURING) revert NotAllowed()` · `TLRankedAuction.sol:581; TLRankedAuction1155.sol:586` · Restricts prize deposits to the pre-bid configuration phase.

#### G-28
`if (prizeTokenIds.length + tokenIdsToAdd.length > NUM_TOKENS) revert TooManyTokens()` · `TLRankedAuction.sol:582; TLRankedAuction1155.sol:587` · Preserves the global prize-array upper bound.

#### G-29
`if (tokenOwner == address(this)) revert InvalidAddress()` · `TLRankedAuction.sol:583; TLRankedAuction1155.sol:588` · Prevents self-to-self deposit bookkeeping without new escrow.

#### G-30
`if (state != AuctionState.CONFIGURING) revert NotAllowed()` · `TLRankedAuction.sol:600; TLRankedAuction1155.sol:605` · Restricts prize removal to the pre-bid configuration phase.

#### G-31
`if (state != AuctionState.CONFIGURING) revert NotAllowed()` · `TLRankedAuction.sol:625; TLRankedAuction1155.sol:630` · Allows LIVE activation only from CONFIGURING.

#### G-32
`if (prizeTokenIds.length != NUM_TOKENS) revert DepositAllPrizeTokens()` · `TLRankedAuction.sol:626; TLRankedAuction1155.sol:631` · Requires a complete rank-to-prize array before bidding starts.

#### G-33
`if (state != AuctionState.LIVE) revert NotAllowed()` · `TLRankedAuction.sol:645; TLRankedAuction1155.sol:650` · Restricts configuration rollback to the LIVE phase.

#### G-34
`if (listSize > 0) revert BidsHaveBeenPlaced()` · `TLRankedAuction.sol:646; TLRankedAuction1155.sol:651` · Prevents reversing the lifecycle after any bid value enters.

#### G-35
`if (refund == 0) revert NothingToWithdraw()` · `TLRankedAuction.sol:664; TLRankedAuction1155.sol:669` · Restricts pull refunds to callers with a stored ETH credit.

#### G-36
`if (pendingNftOwner == address(0)) revert NothingToWithdraw()` · `TLRankedAuction.sol:684` · Requires an ERC-721 rescue credit to exist.

#### G-37
`if (pendingNftOwner != msg.sender) revert NotAllowed()` · `TLRankedAuction.sol:685` · Binds ERC-721 rescue authority to the recorded failed-transfer creditor.

#### G-38
`if (amount == 0) revert NothingToWithdraw()` · `TLRankedAuction1155.sol:690` · Restricts ERC-1155 rescue to the caller's nonzero self-keyed credit.

#### G-39
`if (operator != address(this) || from == address(this)) revert NotAllowed()` · `TLRankedAuction1155.sol:714` · Admits only self-initiated ERC-1155 deposits and rejects self-loop receipts.

#### G-40
`revert NotAllowed()` · `TLRankedAuction1155.sol:725` · Rejects all batch receipts because no accounting path supports them.

---

## 2. Inferred Invariants (Single-Contract)

Inferred invariants derive from structural analysis of the source. Extraction methods: **Δ-pair** (equal-and-opposite storage deltas in one function), **guard-lift** (per-call guard promoted to a global property after enumerating every write site), **state-machine edge**, **temporal predicate**, **NatSpec-stated property**.

---

#### I-1

`StateMachine` · On-chain: **Yes**

> The auction lifecycle is one-way once value enters: CONFIGURING → LIVE → SETTLING → SETTLED, with the only reverse edge (LIVE → CONFIGURING) requiring listSize == 0. No path leaves SETTLED.

**Derivation** — edge: `state = AuctionState.LIVE` @ `TLRankedAuction.sol:628` guarded by `state == CONFIGURING` @625; `state = SETTLING|SETTLED` @408,415 guarded by `state == LIVE` @403; `state = SETTLED` @468 guarded by `state == SETTLING` @429; `state = CONFIGURING` @648 guarded by `state == LIVE ∧ listSize == 0` @645-646. All `state` write sites enumerated via grep: exactly 5 per contract (setupAuction:628, startSettlingAuction:408/415, processRanks:468, resetAuction:648); 1155 mirror @633, 412/419, 472, 653.

**If violated** — post-settlement list mutation, double settlement, or prize re-allocation after payouts began.

---

#### I-2

`Conservation` · On-chain: **Yes**

> Every wei the contract holds is accounted: contract ETH balance ≥ pendingProceeds + Σ unclaimed claim-refunds + Σ pendingRefunds, with equality absent forced ETH (selfdestruct).

**Derivation** — Δ-pairs: createBid `Δ(bid amount) = +msg.value` with `Δ(balance) = +msg.value` @157-180; increaseBid same @187-226; `_removeTailAndRefund`: `Δ(balance) = −oldTail.amount` **or** `Δ(pendingRefunds[bidder]) = +oldTail.amount` @365-390 + 831-837; claim: `Δ(balance) = −refund` or `Δ(pendingRefunds) += refund`, always paired with `claimed = true` @476-508; withdrawPendingProceeds `Δ(pendingProceeds) = −amountToWithdraw = Δ(balance)` @551-569. No `receive`/`fallback` exists, so ETH enters only via the two payable functions. pendingRefunds write sites (grep-verified): `_tryRefundEth:834` (+) and `rescueRefund:667` (clear-before-send). 1155 mirror @863-869, 672.

**If violated** — insolvency: claims or refunds overdraw balance; owner withdrawal strands bidder refunds.

---

#### I-3

`Bound` · On-chain: **Yes**

> listSize ≤ NUM_TOKENS at the end of every transaction — the winning set can never exceed the prize count.

**Derivation** — guard-lift: `_removeTailAndRefund` guard `if (listSize <= NUM_TOKENS) return` @367; write sites of listSize (grep-verified): `_insertBid` ++ @286, `_popBid` -- @360, `_removeTailAndRefund` -- @383. The only caller able to exceed the bound (createBid: insert @171 then conditional removal @177) ends with the removal; `_popBid` is only reached paired with a re-insert (net 0) or on a shrinking path. 1155 mirror @290, 364, 387, guard @371.

**If violated** — more ranked bids than prize slots: `prizeTokenIds[rank-1]` would index out of bounds or bids would win without payment slots.

---

#### I-4

`Bound` · On-chain: **Yes**

> Every in-list bid amount ≥ START_BID, and after settlement every ranked amount ≥ clearingPrice — the precondition that keeps the unchecked `refund = uint256(storedBid.amount - clearingPrice)` safe.

**Derivation** — guard-lift: min-bid guards G-5/G-8 at the only amount writers: `_insertBid` @273 (createBid ≥ `_getMinBid()` ≥ START_BID; increaseBid strictly larger via `newBidAmount = bidAmount + uint128(msg.value)` @208); clearingPrice write sites (grep-verified): startSettlingAuction only — either START_BID (≤ every amount) or `_getTailBid()` @416 (≤ every in-list amount by sortedness). The list is frozen in SETTLING/SETTLED by G-9/G-15, so the snapshot and claims see the same amounts. Unchecked subtraction @493-496; 1155 mirror @497-500, 277, 212, 420.

**If violated** — uint256 underflow in the unchecked subtraction → refund ≈ 2^256 → balance-drain attempt on every claim.

---

#### I-5

`Ratio` · On-chain: **Yes**

> At SETTLED entry, pendingProceeds == listSize × clearingPrice; afterwards it is non-increasing (only withdrawPendingProceeds decrements, capped at the stored value).

**Derivation** — ratio: `pendingProceeds = uint256(listSize) * uint256(clearingPrice)` @418, snapshotted atomically with clearingPrice @416 and nextUnallocatedRank @419; write sites (grep-verified): the settlement site and `pendingProceeds -= amountToWithdraw` @561 with cap @556. 1155 mirror @422, 565, 560. Snapshot ordering: clearingPrice and listSize are read before any of the three writes, in the same function body with no intervening external call.

**If violated** — owner over-payment beyond winners' clearing-price portions, or proceeds under-counted.

---

#### I-6

`Temporal` · On-chain: **Yes**

> The bidding window can never extend past the hard cap: openAt + duration ≤ hardEndAt throughout LIVE.

**Derivation** — temporal: duration write sites (grep-verified): setupAuction @635-637 (duration ≥ EXTENSION_TIME; hardEndAt = openAt + duration + 2h, written only here and zeroed in resetAuction @650-651), `_extendAuctionDuration` @254 with clamp `newEnd = desiredEndTime > hardEndAt ? hardEndAt : desiredEndTime` @248 and no-op return `if (newEnd <= endTime) return` @251. 1155 mirror @641-642, 258, 252, 655-656.

**If violated** — indefinite anti-snipe extension loop = settlement DoS and permanently escrowed bids.

---

#### I-7

`StateMachine` · On-chain: **Yes**

> Displacement is one-shot per bid id: a bid removed as the displaced tail is deleted (node + bidder mapping) and its full amount leaves escrow accounting in the same transaction — as an ETH refund or a pendingRefunds credit. The id is never re-minted (nextBidId is monotonic).

**Derivation** — edge: `delete _bids[oldTailId]; delete _bidders[oldTailId]` @380-381 paired with `_tryRefundEth(oldTailBidder, uint256(oldTail.amount))` @387; nextBidId write site (grep-verified): createBid @167-170 only. Re-insertion of a *live* id (increaseBid pop/reinsert @215-218) preserves the bidder binding (G-7). 1155 mirror @384-385, 391, 171-174, 219-222.

**If violated** — double refunds, resurrection of deleted nodes, or silent loss of displaced bidders' ETH.

---

#### I-8

`StateMachine` · On-chain: **Yes**

> Each bid pays out at most once: `claimed` flips false → true inside claim with no reverse path; combined with rank uniqueness, each prize slot pays exactly one bid.

**Derivation** — edge: `if (storedBid.claimed) revert BidClaimed(); storedBid.claimed = true` @485-488 before any transfer. claimed write sites (grep-verified): `_insertBid` (false, @273) and claim (true, @488). Rank uniqueness: nextRank monotonic @452-455, each node ranked once by the head→tail walk. 1155 mirror @489-492, 277, 456-459.

**If violated** — double-claim of the NFT and the refund.

---

#### I-9

`Conservation` · On-chain: **Yes**

> Prize allocation is a strict partition: prizeTokenIds indices 0..listSize-1 belong to bids of rank index+1 (claim); indices listSize..NUM_TOKENS-1 belong to the owner (withdrawLeftOverPrizeTokens). No index is reachable from both paths.

**Derivation** — guard-lift/Δ-pair: claim reads `prizeTokenIds[storedBid.rank - 1]` @494 with rank ∈ [1, listSize] (I-12); the owner path reads `prizeTokenIds[rank - 1]` with rank ≥ nextUnallocatedRank = listSize + 1, set atomically at settlement @419 (or 1 in the empty branch @410), capped by `remaining = NUM_TOKENS - alreadyProcessed` @526-528; G-23 blocks the owner path entirely when listSize == NUM_TOKENS. Both counters derive from the same frozen listSize snapshot. 1155 mirror @498, 423/414, 530-532, 523.

**If violated** — the same NFT paid both to a winner and to the owner, or a winner's token stolen via the owner path.

---

#### I-10

`StateMachine` · On-chain: **Yes**

> Failed auto-payouts never brick funds: every ETH/NFT delivery failure is recoverable permissionlessly by the owed party, with no admin action.

**Derivation** — NatSpec/spec: README:34 — "If for some reason the ETH refund or NFT transfer fails, it does NOT brick the contract. The ETH and NFTs can be recovered by the rightful bidder and do not rely on any admin action/trust." Structural scan confirms: `_tryRefundEth` failure → `pendingRefunds[to] += refund` @833-835 → `rescueRefund` (permissionless, self-keyed @661-676); claim NFT failure → `pendingNfts[prizeTokenId] = bidder` @505 → `rescueNft` (creditor-gated @681-694). 1155 mirror @865-867, 666-681, 509, 687-699.

**If violated** — failed transfers would permanently strand bidder ETH/NFTs (brick-by-receiver).

---

#### I-11

`Bound` (ordering) · On-chain: **Yes**

> Final list order — hence rank assignment — is independent of the caller-supplied hint: the walk deterministically finds the unique sorted insertion spot (after the last bid with amount ≥ the new amount), and equal-amount bids resolve first-come-first-ranked.

**Derivation** — order analysis: `_findInsertionSpot` walk-down terminates at `next == 0 || amount > _bids[next].amount` @312-313, returning the last node ≥ the new amount; walk-up terminates at `prev == 0 || amount <= _bids[prev].amount` @321-322, returning the first node ≥ it — the same landing spot in a sorted list; `revert InvariantBroken()` @329 fails closed on exhaustion; the hint @302-305 only selects the start point. Equal amounts: both directions insert below existing equal-amount nodes (strict `>` in the new-head case @298), so earlier equal bids keep higher rank. 1155 mirror @316-317, 325-326, 333, 302-305, 302.

**If violated** — crafted hints could buy rank priority among equal bids or misorder the list, corrupting rank→prize fairness.

---

#### I-12

`StateMachine` · On-chain: **Yes**

> Ranks are contiguous 1..listSize, assigned strictly in head→tail order; state reaches SETTLED only when the walk lands on the tail.

**Derivation** — edge: processRanks starts at `lastProcessedId == 0 ? head : _bids[lastProcessedId].next` @446, assigns `rank = nextRank` monotonically @452-455, resume consistency guard @443, `if (processedId == tail) state = SETTLED` @466-468. Counter write sites (grep-verified): nextRank and lastProcessedId are written only in processRanks. 1155 mirror @450, 456-459, 447, 470-472.

**If violated** — non-contiguous or duplicate ranks → wrong prizeTokenIds index at claim, or premature SETTLED with unranked bids.

---

#### I-13

`Conservation` · On-chain: **No**

> ERC-721 variant: a pending-NFT rescue credit is never overwritten or misattributed.

**Derivation** — write-site enumeration: the claim catch path executes `pendingNfts[prizeTokenId] = bidder` @ `TLRankedAuction.sol:505` **unconditionally** — a second failed claim of the same tokenId would overwrite the first creditor's entry. The property holds only because prizeTokenIds cannot contain duplicate ids for ERC-721, which is enforced by the *external* token's uniqueness (each deposit `transferFrom` @591 succeeds only once per id), not by any in-contract guard. Clear site: `pendingNfts[tokenId] = address(0)` @688. Within the scope files alone, the invariant is not enforced.

**If violated** — a legitimate winner's rescue right is silently reassigned; the NFT becomes claimable by another address.

---

#### I-14

`Conservation` · On-chain: **Yes**

> ERC-1155 variant: pending-NFT credits are per-(user, tokenId) amounts, incremented once per failed claim and cleared once per rescue — duplicate token ids across ranks cannot collide.

**Derivation** — write sites (grep-verified): `pendingNfts[bidder][prizeTokenId] += 1` @ `TLRankedAuction1155.sol:509`; `pendingNfts[msg.sender][tokenId] = 0` @693 after `uint256 amount = pendingNfts[msg.sender][tokenId]` @689; the rescue sends exactly `amount` units @696. No path writes another user's bucket. (Commit c3ce3f4 states the re-keying rationale: "keyed by user since the same token id can be won by multiple bidders".)

**If violated** — over- or under-delivery of rescue units for repeated token ids.

---

**Categories:**
- **Conservation**: storage variables change by equal-and-opposite amounts in the same function body (Δ(A) = +x, Δ(B) = −x → A + B = const), or credits mirror held value.
- **Bound**: a guard on a storage variable lifted to a global property across every write site (G-5/G-8 → every amount ≥ floor; listSize ≤ NUM_TOKENS).
- **Ratio**: a storage variable defined as a formula of others (pendingProceeds = listSize × clearingPrice).
- **StateMachine**: discrete transitions with guards preventing reversal (lifecycle, claimed latch, displacement one-shot).
- **Temporal**: a condition depending on block.timestamp or a stored duration/deadline (hardEndAt clamp).

---

## 3. Inferred Invariants (Cross-Contract)

---

#### X-1

On-chain: **Yes**

> TLRankedAuction1155 assumes every ERC-1155 unit it holds entered through its own depositPrizeTokens flow; unsolicited receipts revert rather than silently resting in the contract unaccounted.

**Caller side** — `TLRankedAuction1155.sol:596` — depositPrizeTokens initiates `NFT_CONTRACT.safeTransferFrom(tokenOwner, address(this), prizeTokenId, 1, "")` with operator = address(this), immediately after pushing the id @593, so accounting and receipt are atomic per iteration.

**Callee side** — `TLRankedAuction1155.sol:708-726` — onERC1155Received accepts only `operator == address(this) && from != address(this)` @714; onERC1155BatchReceived always reverts @719-726. Any transfer not initiated by depositPrizeTokens reverts inside the token's safe-transfer check, so held units always correspond to prizeTokenIds entries (or pending rescues).

**If violated** — dusted/unaccounted units would sit in the contract with no reclaim path (no admin sweep exists), or internal accounting would drift from real holdings.

---

## 4. Economic Invariants

---

#### E-1

On-chain: **Yes**

> Uniform pricing holds net-of-refunds: every winner pays exactly clearingPrice (bid − refund), and aggregate winner payments == pendingProceeds == listSize × clearingPrice.

**Follows from** — I-5 + I-4 + I-2

**If violated** — winners over/underpay the uniform price; proceeds misaccount against payouts.

---

#### E-2

On-chain: **Yes**

> The owner's proceeds withdrawal is always fully covered: even before any claim, balance ≥ pendingProceeds + Σ unclaimed refunds + Σ pendingRefunds — an owner withdrawal cannot strand a single winner's refund or NFT.

**Follows from** — I-2 + I-5 (forced ETH via selfdestruct only widens the inequality; no receive/fallback exists to donate normally)

**If violated** — insolvent auction: claims would fail after the owner withdrawal.

---

#### E-3

On-chain: **Yes**

> Displacement is refund-complete: no bid can exit the list without its full amount leaving bid escrow accounting in the same transaction (immediate ETH refund or pendingRefunds credit) — displaced bidders never fund the winners' discount.

**Follows from** — I-7 + I-2

**If violated** — displaced bidders' ETH silently converts to owner proceeds.

---

#### E-4

On-chain: **Yes**

> In a fully allocated list, the tail (minimum winning) amount never decreases during LIVE — the clearing price can only ratchet upward via bounded steps (new bids ≥ 1.025 × tail @799; increases ≥ 1.005 × own amount @805).

**Follows from** — I-11 + I-3 + I-7 (displacement removes only the current minimum; insertions land strictly above it; increases only add)

**If violated** — clearing-price manipulation between the settlement snapshot and claims, or rank-order corruption.
