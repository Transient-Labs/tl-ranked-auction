# X-Ray Report

> Transient Labs Ranked Auction | 1057 nSLOC | c3ce3f4 (`erc-1155-variant`) | Foundry | 24/10/26

---

## 1. Protocol Overview

**What it does:** A fully on-chain ranked (multi-unit, uniform-price) auction: bidders compete for rank slots on an escrowed batch of 2–512 NFTs, everyone above the clearing price wins, and all winners pay the lowest winning bid.

- **Users**: Bidders compete for ranked prize slots; the owner/operator escrows prizes, configures the auction, and receives proceeds.
- **Core flow**: escrow NFTs → configure → ranked bidding with displacement refunds → permissionless settlement → per-bid claim of NFT + refund.
- **Key mechanism**: a sorted doubly-linked list of bids capped at NUM_TOKENS entries with hint-based insertion; the tail is simultaneously the minimum-bid reference and the clearing price at settlement.
- **Token model**: prize NFTs only (ERC-721 in `TLRankedAuction`, ERC-1155 with repeated ids allowed in `TLRankedAuction1155`); ETH is the only bid asset; no protocol token.
- **Admin model**: single OZ `Ownable` owner; no timelock, multisig, or pause; the contract is single-use (no restart from SETTLED).

For a visual overview, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Ranked Auction Core | TLRankedAuction (520), TLRankedAuction1155 (537) | 1057 | On-chain ranked uniform-price auction: escrow, linked-list bidding, settlement, claims. The two contracts are ~97% logic clones differing in token standard, transfer calls, and pendingNfts keying. |

### How It Fits Together

The core trick: bids live in a sorted (descending) doubly-linked list that is trimmed back to NUM_TOKENS entries on every insert, so the tail bid is always the minimum winning bid — the anti-dust floor during bidding and the uniform clearing price at settlement.

### Auction lifecycle (owner)

```
Owner → TLRankedAuction.constructor()          *immutables fixed: NFT_CONTRACT, START_BID, NUM_TOKENS (721:141-149)*
      → TLRankedAuction.depositPrizeTokens()   *prizeTokenIds[] = rank order; NFT_CONTRACT.transferFrom per id (721:591)*
      → TLRankedAuction.setupAuction()          *CONFIGURING → LIVE; openAt/duration/hardEndAt set (721:624-640)*
        └─ [mistake?] → TLRankedAuction.resetAuction()  *back to CONFIGURING, only while listSize == 0 (721:644-654)*
```

### Bid creation with tail displacement

```
Bidder → TLRankedAuction.createBid{value}(hintBidId)   (721:157)
        ├─ _checkAuctionOpen()                          *LIVE + openAt ≤ ts ≤ openAt+duration (721:229-234)*
        ├─ _insertBid() → _findInsertionSpot(hint)       *bounded ↑/↓ walk; revert InvariantBroken on exhaustion (721:294-330)*
        ├─ _extendAuctionDuration()                     *only if < 5 min remain; clamped to hardEndAt (721:238-256)*
        └─ _removeTailAndRefund()                        *only if listSize > NUM_TOKENS (721:365-390)*
             ├─ delete _bids[oldTailId] / _bidders[oldTailId]   *displacement is final for that bid id*
             └─ _tryRefundEth(bidder, amount)            *1e5 gas cap; failure → pendingRefunds[bidder] += amount (721:831-837)*
```

### Settlement snapshot and ranking (permissionless)

```
Anyone → TLRankedAuction.startSettlingAuction()          (721:402)  *[ts > end]*
        *atomic snapshot: clearingPrice = tail (full) | START_BID (underallocated/empty);
         pendingProceeds = listSize × clearingPrice; nextUnallocatedRank = listSize+1 (721:403-423)*
      → TLRankedAuction.processRanks(n)                   (721:428)  *repeatable batches; rank = nextRank++;
                                                            resume check + terminator check both revert InvariantBroken;
                                                            state → SETTLED when processedId == tail (721:466-469)*
```

### Claim with fallback buckets

```
Anyone → TLRankedAuction.claim(bidId)                     (721:476)  *[SETTLED] funds go to the stored bidder*
        ├─ storedBid.claimed = true                       *marked before any transfer (721:488)*
        ├─ refund = storedBid.amount - clearingPrice      *unchecked subtraction (721:495) — safe iff I-4 holds*
        ├─ _tryRefundEth(bidder, refund)                 *failure → pendingRefunds → rescueRefund() (721:661)*
        └─ NFT_CONTRACT.safeTransferFrom(this, bidder, prizeTokenIds[rank-1])   (721:500)
             └─ catch → pendingNfts[prizeTokenId] = bidder *rescueNft() by that bidder later (721:681)*
```

---

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **On-chain ranked auction / NFT marketplace mechanism** (multi-unit uniform-price auction with ETH escrow).

No DeFi venue type from the standard profiles matches: there is no lending, AMM, vault, stable, perp, staking, bridge, or governance surface, and no oracle. The relevant lenses are escrow accounting (I-2 family), adversarial list ordering, ERC-721/1155 transfer semantics, and single-admin operations.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| Owner / Operator | Trusted (deployer-set, no timelock/multisig/pause) | 6 instant functions: escrow prizes from **any approving holder** in owner-chosen rank order, withdraw pre-bid, start/reset (pre-bids), and post-settlement withdraw proceeds to an **arbitrary payoutAddress** and leftover tokens to any recipient. Inherited `renounceOwnership()` permanently strands those withdrawals. |
| Bidder | Bounded (only acts on own ETH and own bids) | createBid / increaseBid (own bid only, 721:199); claim for any bidId but funds flow only to the stored bidder; rescueRefund / rescueNft only for credits owed to msg.sender. |
| Settler (anyone) | Bounded (can only advance the state machine) | startSettlingAuction (after end time), processRanks (batched, resume-checked) — no value routing. |
| NFT contract | External (immutable address; behavior may change if the token is a proxy) | Receives escrow transfers, executes prize delivery; claim wraps it in try/catch, deposit/withdraw paths propagate its reverts. |

**Adversary Ranking** (ordered by threat level, adjusted by git evidence):

1. **Griefing bidder** — the cheapest attacker class against auctions: list churn, gas-capped refund abuse, and dust-bid games are the live attack surface (dust is priced out by the 2.5%/0.5% steps).
2. **Compromised owner** — every operational action is instant (payout routing, prize order, escrow-from-any-approver); a single key, no timelock signal in code or history.
3. **Bid sniper / MEV searcher** — targets the last-5-minute extension window and the position-change-only trigger (README:24 documents clearing-price drift without extension).
4. **Malicious or non-standard NFT contract** — all prize delivery trusts NFT_CONTRACT transfer semantics and receiver hooks on bidders.
5. **Approval phisher** — `depositPrizeTokens` can escrow from any holder that approved the auction (documented admin workflow, 721:577).

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **Owner ↔ all users** — no delay mechanism at all: proceeds to arbitrary payoutAddress (721:551-565), leftover tokens to any recipient (721:513), escrow from any approving holder (721:580) are all instant; renounceOwnership strands proceeds/leftovers permanently. *Git signal: access-control code touched in 4 of 5 source commits — elevated risk.*
- **Auction ↔ NFT contract** — address immutable and code-length-checked at deploy (721:145), but token behavior can still change post-deploy if the token is a proxy; transfers are validated only by claim's try/catch, nowhere else.
- **Auction ↔ ETH recipients** — refund path gas-capped at 1e5 (721:832) with a pull fallback; owner payouts and rescueRefund use uncapped calls and revert on failure.
- **Bidder ↔ ranked list** — a bidder's rank (prize and price) depends on list order, which must be hint-independent (I-11) and is frozen once settlement starts.
- **No pause exists** — the lifecycle state machine is the only stopping mechanism, and it cannot be triggered early (G-14 requires the end time to pass); once LIVE, the owner cannot halt bidding or reclaim escrowed NFTs before settlement.

### Key Attack Surfaces

- **`claim()` unchecked refund subtraction** &nbsp;&#91;[I-4](invariants.md#i-4), [I-2](invariants.md#i-2)&#93; — `refund = uint256(storedBid.amount - clearingPrice)` sits in `unchecked` (721:493-496 / 1155:497-500); safe only while every ranked amount ≥ clearingPrice — worth re-walking I-4's write-site enumeration (amounts created only ≥ `_getMinBid()`, increased only upward, list frozen at settlement).

- **Settlement snapshot immutability** &nbsp;&#91;[I-1](invariants.md#i-1), [I-5](invariants.md#i-5), [G-14](invariants.md#g-14)&#93; — clearingPrice, pendingProceeds, and nextUnallocatedRank are fixed atomically at LIVE→SETTLING (721:403-423); worth confirming no LIVE mutation path can survive into SETTLING (both bid functions gate through `_checkAuctionOpen`).

- **Sorted linked-list integrity under adversarial hints** &nbsp;&#91;[I-11](invariants.md#i-11), [G-12](invariants.md#g-12), [I-3](invariants.md#i-3)&#93; — `_findInsertionSpot` bounded walks plus two `InvariantBroken` safety nets (721:329, 443, 451); worth checking equal-amount tie-breaking and stale-hint fallback keep order deterministic and FCFS.

- **Displacement refund conservation** &nbsp;&#91;[I-7](invariants.md#i-7), [I-2](invariants.md#i-2), [E-3](invariants.md#e-3)&#93; — `_removeTailAndRefund` deletes the node then refunds the full amount with a 1e5 gas cap (721:365-390); worth tracing both refund sinks (direct ETH vs pendingRefunds) for double-credit or loss.

- **Rank/prize allocation partition** &nbsp;&#91;[I-9](invariants.md#i-9), [I-12](invariants.md#i-12)&#93; — claim reads `prizeTokenIds[rank-1]` (721:494) while the owner path starts at nextUnallocatedRank (721:417-419); worth confirming the two counters can never overlap across partial processRanks/withdraw batches (resume guard 721:443).

- **Owner operational powers without timelock or pause** &nbsp;&#91;[I-9](invariants.md#i-9)&#93; — instant: arbitrary payoutAddress for proceeds (721:551-565), arbitrary leftover recipient (721:513), escrow from any approving tokenOwner (721:580, documented intent), owner-chosen rank→prize order at deposit; inherited `renounceOwnership` would strand proceeds/leftovers permanently.

- **Failed-payout fallback buckets** &nbsp;&#91;[I-10](invariants.md#i-10), [I-13](invariants.md#i-13), [I-14](invariants.md#i-14)&#93; — 721 keys `pendingNfts` by tokenId with an unconditional overwrite on transfer failure (721:505); 1155 re-keys per-user with `+=` (1155:509) — worth confirming which guarantee makes the 721 single-creditor mapping sound (external ERC-721 uniqueness, per I-13).

- **Gas-capped auto-refund path** &nbsp;&#91;[I-10](invariants.md#i-10), [E-3](invariants.md#e-3)&#93; — `_tryRefundEth` gives recipients 1e5 gas (721:832) and diverts failures to pull-based pendingRefunds; worth checking the griefing cost balance and that every diverged credit stays reclaimable (rescueRefund 721:661).

- **Anti-snipe extension window** &nbsp;&#91;[I-6](invariants.md#i-6)&#93; — extension fires only on position change, clamped to hardEndAt (721:238-256, 637); README:24 documents the clearing price moving in the final minutes without extension — worth confirming snipe-window math and the +2h cap arithmetic.

- **ERC-1155 receiver gating** &nbsp;&#91;[X-1](invariants.md#x-1)&#93; — onERC1155Received accepts only operator == address(this) (1155:714) and batch receipts always revert (1155:719-726); worth confirming no deposit/rescue path bypasses the operator check — the 721 variant has no receiver and deposits via raw `transferFrom` by design (721:591).

- **Dust-bid economics and BPS floor** &nbsp;&#91;[G-5](invariants.md#g-5), [G-8](invariants.md#g-8), [I-4](invariants.md#i-4)&#93; — 2.5%/0.5% steps with integer floor (721:799, 805); START_BID ≥ 10^4 keeps increments ≥ 1 wei; worth checking behavior at the under/fully-allocated boundary (721:792-801).

### Protocol-Type Concerns

**As an auction/escrow mechanism:**
- BPS arithmetic floors: `_getMinBid` = tail + tail×250/10000 and `_getMinBidIncrease` = amount×50/10000 (721:799, 805) — worth confirming boundary behavior exactly at listSize == NUM_TOKENS, where the min bid jumps from START_BID to tail×1.025.
- `uint128` truncation of msg.value (721:162) is unreachable in practice (2^128 wei exceeds total ETH supply) — no viable truncation path.
- `uint64` time math: setupAuction's `hardEndAt = openAt + duration + 2h` (721:637) uses checked arithmetic — an oversized `duration_` reverts setup rather than wrapping.
- List walks are SLOAD-only loops bounded by listSize ≤ 512 (721:310-325) — worst-case insertion is O(N) but gas-capped.

### Temporal Risk Profile

**Deployment & Initialization:**
- Constructor-validated immutables (owner, NFT code-length, startBid, numTokens — 721:141-149) leave no `initialize()` front-run surface; single-tx deployment.
- Empty-state edges are explicitly handled: first bid (721:298), zero-bid settlement branch (721:407-413), underallocated leftovers (721:519) — mitigated by explicit branches plus tests.

**Market Stress:**
- Gas spikes could stall permissionless settlement; `processRanks` and `withdrawLeftOverPrizeTokens` batching keeps per-tx cost bounded (≤ 512 iterations) — partially mitigated.
- The +2h extension hard cap (721:637) bounds end-game snipe congestion; no oracle or liquidation cascade exists.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **NFT_CONTRACT (ERC-721 / ERC-1155)** — via `depositPrizeTokens` (721:591 raw transferFrom / 1155:596 safeTransferFrom amount 1), `claim` (safeTransferFrom, try/catch), `withdrawLeftOverPrizeTokens`, `rescueNft`
> - Assumes: standard transfer semantics; ERC-721 id uniqueness (underwrites I-13); receivers accept safe transfers or revert
> - Validates: code-length at deploy only; nothing at call time (claim catches, deposit/withdraw propagate reverts)
> - Mutability: address immutable; token behavior can change post-deploy if the token is a proxy
> - On failure: claim → pendingNfts rescue path; deposit/withdraw loops → whole-tx revert

> **Raw ETH calls** — via `_tryRefundEth` (gas 1e5, 721:832), `rescueRefund` (721:670), `withdrawPendingProceeds` (721:565)
> - Assumes: refund recipients' fallbacks fit 1e5 gas or fail cleanly
> - Validates: bool success only
> - On failure: refunds → pendingRefunds credit (fail-open to a pull path); owner/rescue payouts → revert (fail-closed)

**Token Assumptions** *(unvalidated only)*:
- ERC-721 (721 variant): assumes unique ownership per id — this is the sole guarantee behind the tokenId-keyed single-creditor `pendingNfts` mapping (I-13); the contract itself never checks id uniqueness.
- Claim recipients: must implement `onERC721Received` / accept ERC-1155; hooks fire inside `nonReentrant`, and the 1155 receiver rejects anything not self-operated (X-1).

**Shared State Exposure:** none — no external pools, oracles, or governance; the contract shares no mutable state with other protocols.

---

## 3. Invariants

> ### 📋 Full invariant map: **[invariants.md](invariants.md)**
>
> A dedicated reference file contains the complete invariant analysis — do not look here for the catalog.
>
> - **40 Enforced Guards** (`G-1` … `G-40`) — per-call preconditions with `Check` / `Location` / `Purpose`
> - **14 Single-Contract Invariants** (`I-1` … `I-14`) — Conservation, Bound, Ratio, StateMachine, Temporal
> - **1 Cross-Contract Invariant** (`X-1`) — the 1155 receiver-gating assumption
> - **4 Economic Invariants** (`E-1` … `E-4`) — higher-order properties deriving from `I-N` + `X-N`
>
> Every inferred block cites a concrete Δ-pair, guard-lift + write-sites, state edge, temporal predicate, or NatSpec quote. The **On-chain=No** blocks are the high-signal ones — there is **1** (I-13: the 721 `pendingNfts` overwrite, safe only via an external ERC-721 uniqueness guarantee). Attack-surface bullets above cross-link directly into the relevant blocks.

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` — substantive: mechanism, min-bid rules, extension semantics, state machine, data-structure rationale, key parameters, gas/coverage tables (721-only) |
| NatSpec | ~2 contract-level blocks + per-function `@notice`/`@dev` on nearly all functions | Good coverage of intent; `@dev` notes explain *why* (e.g., transferFrom choice at 721:590, proceeds-withdrawal safety at 721:549-550) |
| Spec/Whitepaper | README serves as spec (per spec) | No separate whitepaper; state-machine/attack-vector diagrams referenced as images (`public/`) |
| Inline Comments | Adequate | Safety nets and intent annotated at tricky spots (InvariantBroken sites, extension clamp, receiver gating); zero TODO/FIXME markers |

A prior contract review exists (`audits/TL Ranked Auction Contract Review - Final.pdf`); its findings were folded in via commit 3850b06 — not re-ingested here.

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 23 | File scan (always reliable) |
| Test functions | 228 | File scan (always reliable) |
| Line coverage | 99.34% (606/610) | `forge coverage`; 33 executed tests passed |
| Branch coverage | 95.65% (176/184) | `forge coverage` |

Test presence is reported from enumeration independently of the 33 tests selected and executed by `forge coverage`.

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 228 test functions | File-scan aggregate across the detected test corpus |
| Fork | 7 | Fork-test signals detected by enumeration |
| Stateless Fuzz | 26 | Foundry fuzz-test functions detected by enumeration |
| Stateful Fuzz (Foundry) | 0 | none |
| Stateful Fuzz (Echidna) | 0 | none |
| Stateful Fuzz (Medusa) | 0 | none |
| Formal Verification (Certora / Halmos / HEVM) | 0 | none |

### Gaps

- **No stateful/invariant fuzzing** — highest-impact gap: the linked-list ordering (I-11), allocation partition (I-9), and escrow conservation (I-2) are exactly the properties stateful fuzzing checks, and the contract already ships `InvariantBroken` assertions that double as invariant oracle points.
- **No formal verification** — the settlement arithmetic (I-4/I-5) is small enough for Certora/Halmos-style proofs.
- README:85-93 reports historical 721 coverage; the current run measured 99.66% for the 721 contract and 99.00% for the 1155 contract.

---

## 6. Developer & Git History

> Repo shape: normal_dev — 7 commits over 288 days; 5 touch source. Analyzed branch: `erc-1155-variant` at `c3ce3f4`.

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| Marco Peyfuss | 6 | +1730 | 99.2% |
| Marco ◹◺ | 1 | +14 | 0.8% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 2 | Effectively single-developer (99.2% of source lines) |
| Merge commits | 0 of 7 (0%) | Linear history — no peer-review signal |
| Repo age | 2026-01-05 → 2026-10-20 | 288 days |
| Recent source activity (30d) | 1 commit | Late burst: the entire 870-line ERC-1155 variant landed 2026-10-20 |
| Test co-change rate | 80% | 4 of 5 source commits also modified tests (co-modification, not coverage) |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| src/TLRankedAuction.sol | 3 | Primary contract — all audit-relevant churn |
| src/Counter.sol | 2 | Foundry scaffold, since removed from src |
| src/TLRankedAuction1155.sol | 1 | Added wholesale in the latest commit |

### Security-Relevant Commits

**Score** = weighted sum of fix-like signals (message keywords, diff patterns, change shape). 10+ warrants a manual diff.

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| c3ce3f4 | 2026-10-20 | ERC-1155 variant (storage re-key, safeTransferFrom conversions, ERC1155Holder) | 13 | Token-transfer + accounting changes across 4 security domains, 870 lines, with tests |
| 13af92d | 2026-01-13 | contract written & tested | 13 | Initial 808-line implementation with guards + tests |
| 3850b06 | 2026-01-28 | Update based on preliminary audit findings | 9 | Access-control tightening after a preliminary review |
| 66c3758 | 2026-01-14 | docs update + slither static analysis; clarified transferFrom usage | 5 | Static-analysis pass; raw transferFrom intent documented |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| access_control | 4 | TLRankedAuction.sol, TLRankedAuction1155.sol |
| fund_flows | 4 | same |
| oracle_price | 4 | same (heuristic label — no actual oracle code exists) |
| state_machines | 4 | same |

### Security Observations

- **Single-developer dominance** — Marco Peyfuss authored 99.2% of source lines; no second-reviewer signal anywhere in history.
- **No merge commits** — 0 of 7; linear history suggests no formal peer review.
- **Preliminary audit folded in** — 3850b06 (83 lines, access-control tightening) followed a preliminary review; `audits/` holds a final review PDF — worth requesting those findings to diff against current code.
- **Late, large addition** — the entire 1155 variant (870 lines, fix-score 13) is the only commit in the last 30 days; it has the least review exposure of any code in the repo.
- **Static analysis pass** — 66c3758 ran slither with nothing to address; documented the raw `transferFrom` deposit choice in dev comments.
- **Removed scaffold** — Counter.sol (2 modifications) was deleted; no dead code remains in scope.

### Cross-Reference Synthesis

- **TLRankedAuction.sol tops both churn (3 mods) and attack-surface density** — surfaces 1-9 all cite it → highest-leverage review file; the 1155 clone inherits everything except receiver gating and pendingNfts keying.
- **c3ce3f4's `pendingNfts` re-keying ↔ I-13/I-14** — the commit message ("keyed by user since the same token id can be won by multiple bidders") names exactly the I-13 overwrite gap left in the 721 variant → confirm the 721 single-creditor mapping is acceptable for unique-id tokens.
- **3850b06's access-control tightening ↔ admin surface** — a prior review already touched owner gates; the remaining instant admin powers (arbitrary payout, escrow-from-any-approver) are the live follow-up question.

---

## X-Ray Verdict

**ADEQUATE** — 228 detected test functions including 26 stateless fuzz tests, 99.34% executed line coverage, and clear intent-level docs, but no stateful invariant fuzzing or formal verification for the linked-list/settlement invariants, and admin powers are instant with no timelock or pause.

**Structural facts:**
1. 1057 nSLOC across 2 logic-clone contracts (~97% duplicated surface) differing in token standard, transfer calls, and pendingNfts keying.
2. 26 scanned entry points total — 11 permissionless, 3 caller-restricted, and 12 owner-only — every state-changing path carries `nonReentrant`; no pause or timelock exists.
3. Enumeration detects 23 test files, 228 test functions, and 26 stateless fuzz tests; the coverage run passed 33 selected tests and measured 99.34% lines / 95.65% branches.
4. One developer authored 99.2% of source; the entire 1155 variant arrived in the single most recent commit, 3 days before this analysis.
5. A prior contract review exists (audits/ + commit 3850b06); zero TODO/FIXME markers and no forked dependencies.
