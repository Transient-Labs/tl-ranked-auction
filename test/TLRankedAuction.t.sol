// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std-1.11.0/Test.sol";
import {Strings} from "@openzeppelin-contracts-5.5.0/utils/Strings.sol";
import {TLRankedAuction, Ownable} from "src/TLRankedAuction.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

/// @dev Test the internal bid insertion and tail deletion functions.
///      This is main for sanity checking the internal bid insertion logic and the underlying data structure.
///      The main logic can be tested with 10 tokens easily.
contract TLRankedAuctionBidDataStructureTest is Test, TLRankedAuction {
    address public bob = address(0xb0b);
    address public sal = address(0x5a1);

    // inputs don't matter here at all except for the number of tokens
    // using the vm address as the "nft contract" to just get past the code size challenge
    constructor() TLRankedAuction(address(0xbeef), address(vm), 1 ether, 10) {}

    function _assertInvariants(
        uint32 bidId,
        uint32 expectedListSize,
        uint32 expectedHead,
        uint32 expectedTail,
        uint32 expectedNext,
        uint32 expectedPrev,
        uint128 expectedAmount,
        address expectedBidder
    ) internal view {
        BidView memory bid = getDetailedBid(bidId);
        assertEq(listSize, expectedListSize, "List size invariant broken");
        assertEq(head, expectedHead, "Head invariant broken");
        assertEq(tail, expectedTail, "Tail invariant broken");
        assertEq(bid.next, expectedNext, "Next invariant broken");
        assertEq(bid.prev, expectedPrev, "Prev invariant broken");
        assertEq(bid.amount, expectedAmount, "Bid amount invariant broken");
        assertEq(bid.bidder, expectedBidder, "Bidder invariant broken");
        if (bid.prev != 0) {
            BidView memory prevBid = getDetailedBid(bid.prev);
            assertGe(prevBid.amount, bid.amount, "Previous bid not gte to inserted bid");
            assertEq(prevBid.next, bidId, "Previous bid not linked to inserted bid");
        } else if (_isBidInList(bidId)) {
            // inserted bid is the new head if it's valid in the list (accounts for popped bids)
            assertEq(bidId, head, "Inserted bid is the head but isn't recorded as the head");
        }
        if (bid.next != 0) {
            BidView memory nextBid = getDetailedBid(bid.next);
            assertGe(bid.amount, nextBid.amount, "Inserted bid not gte to next bid");
            assertEq(nextBid.prev, bidId, "Next bid not linked to back inserted bid");
        } else if (_isBidInList(bidId)) {
            // inserted bid is the new tail if it's valid in the list (accounts for popped bids)
            assertEq(bidId, tail, "Inserted bid is the tail but isn't recorded as the tail");
        }
    }

    function test_dataStructure() public {
        // bob submits first bid
        _insertBid(0, 1, bob, 10 ether);
        _assertInvariants(1, 1, 1, 1, 0, 0, 10 ether, bob);
        // list: 1

        // sal submits next bid
        _insertBid(1, 2, sal, 9 ether);
        _assertInvariants(2, 2, 1, 2, 0, 1, 9 ether, sal);
        // list: 1 -> 2

        // sal submits another bid tied with his last one, but it should become the new tail
        _insertBid(0, 3, sal, 9 ether);
        _assertInvariants(3, 3, 1, 3, 0, 2, 9 ether, sal);
        // list: 1 -> 2 -> 3

        // if we try to remove the tail here, nothing changes
        _removeTailAndRefund();
        _assertInvariants(3, 3, 1, 3, 0, 2, 9 ether, sal);

        // bob submits another bid tied with sal's last one, but it should become the new tail
        _insertBid(3, 4, bob, 9 ether);
        _assertInvariants(4, 4, 1, 4, 0, 3, 9 ether, bob);
        // list: 1 -> 2 -> 3 -> 4

        // bob submits a new low bid, but hints that it should be second
        _insertBid(1, 5, bob, 8 ether);
        _assertInvariants(5, 5, 1, 5, 0, 4, 8 ether, bob);
        // list: 1 -> 2 -> 3 -> 4 -> 5

        // sal submits a tie with the head but it should be second, along with a bad hint of 0
        _insertBid(0, 6, sal, 10 ether);
        _assertInvariants(6, 6, 1, 5, 2, 1, 10 ether, sal);
        // list: 1 -> 6 -> 2 -> 3 -> 4 -> 5

        // bob sees this and submits a new head, but with a hint of the current head (even though a hint of 0 is better)
        _insertBid(1, 7, bob, 11 ether);
        _assertInvariants(7, 7, 7, 5, 1, 0, 11 ether, bob);
        // list: 7 -> 1 -> 6 -> 2 -> 3 -> 4 -> 5

        // bob wants to add a low ball bid, cause why not
        _insertBid(5, 8, bob, 1 ether);
        _assertInvariants(8, 8, 7, 8, 0, 5, 1 ether, bob);
        // list: 7 -> 1 -> 6 -> 2 -> 3 -> 4 -> 5 -> 8

        // sal wants to copy bob with a 8 eth bid, cause why not, and submits the tail as a hint which should walk up
        _insertBid(8, 9, sal, 8 ether);
        _assertInvariants(9, 9, 7, 8, 8, 5, 8 ether, sal);
        // list: 7 -> 1 -> 6 -> 2 -> 3 -> 4 -> 5 -> 9 -> 8

        // bob wants to add another low ball 1 eth bid, cause why not, and with a totally invalid hint
        _insertBid(3000, 10, bob, 1 ether);
        _assertInvariants(10, 10, 7, 10, 0, 8, 1 ether, bob);
        // list: 7 -> 1 -> 6 -> 2 -> 3 -> 4 -> 5 -> 9 -> 8 -> 10

        // sal wants to copy bob with that low ball bid, but with a stale hint
        _insertBid(2, 11, sal, 1 ether);
        _assertInvariants(11, 11, 7, 11, 0, 10, 1 ether, sal);
        // list: 7 -> 1 -> 6 -> 2 -> 3 -> 4 -> 5 -> 9 -> 8 -> 10 -> 11

        // and now we want to try removing the tail because in the real thing that's what would happen.
        vm.deal(address(this), 1000 ether); // just so it doesn't revert
        _removeTailAndRefund();
        _assertInvariants(10, 10, 7, 10, 0, 8, 1 ether, bob);
        // list: 7 -> 1 -> 6 -> 2 -> 3 -> 4 -> 5 -> 9 -> 8 -> 10

        // sal wants to kick bob's low ball hint with a walk up hint
        _insertBid(10, 12, sal, 10 ether);
        _assertInvariants(12, 11, 7, 10, 2, 6, 10 ether, sal);
        // list: 7 -> 1 -> 6 -> 12 -> 2 -> 3 -> 4 -> 5 -> 9 -> 8 -> 10

        // and now we want to try removing the tail because in the real thing that's what would happen.
        _removeTailAndRefund();
        _assertInvariants(12, 10, 7, 8, 2, 6, 10 ether, sal);
        // list: 7 -> 1 -> 6 -> 12 -> 2 -> 3 -> 4 -> 5 -> 9 -> 8

        // pop bid number 3
        _popBid(3);
        _assertInvariants(3, 9, 7, 8, 0, 0, 9 ether, sal);
        // list: 7 -> 1 -> 6 -> 12 -> 2 -> 4 -> 5 -> 9 -> 8

        // insert bid 3 again, but with a higher bid value (sal increased bid to 10 ether)
        _insertBid(6, 3, sal, 10 ether);
        _assertInvariants(3, 10, 7, 8, 2, 12, 10 ether, sal);
        // list: 7 -> 1 -> 6 -> 12 -> 3 -> 2 -> 4 -> 5 -> 9 -> 8

        // pop the tail
        _popBid(8);
        _assertInvariants(8, 9, 7, 9, 0, 0, 1 ether, bob);
        // list: 7 -> 1 -> 6 -> 12 -> 3 -> 2 -> 4 -> 5 -> 9

        // increase the bid for 8 to 10.5 ether
        _insertBid(7, 8, bob, 10.5 ether);
        _assertInvariants(8, 10, 7, 9, 1, 7, 10.5 ether, bob);
        // list: 7 -> 8 -> 1 -> 6 -> 12 -> 3 -> 2 -> 4 -> 5 -> 9

        // pop the head
        _popBid(7);
        _assertInvariants(7, 9, 8, 9, 0, 0, 11 ether, bob);
        // list: 8 -> 1 -> 6 -> 12 -> 3 -> 2 -> 4 -> 5 -> 9

        // increase the bid for 7 to 12 ether
        _insertBid(0, 7, bob, 12 ether);
        _assertInvariants(7, 10, 7, 9, 8, 0, 12 ether, bob);
        // list: 7 -> 8 -> 1 -> 6 -> 12 -> 3 -> 2 -> 4 -> 5 -> 9
    }
}

/// @dev Full integration test
contract TLRankedAuctionTest is Test {
    using Strings for uint256;

    bool public revertOnReceive;
    TLRankedAuction public ra;
    MockERC721 public nft;
    address public nftCollector = address(0xbeef);

    receive() external payable {
        if (revertOnReceive) revert();
    }

    function _deployContracts(uint128 startBid, uint32 numTokens) internal {
        nft = new MockERC721();
        ra = new TLRankedAuction(address(this), address(nft), startBid, numTokens);
    }

    function _setupAuction(uint256 numTokens, uint64 openAt, uint64 duration) internal {
        // mint nfts
        nft.mint(nftCollector, numTokens); // no need to batch here

        // grant approval
        vm.prank(nftCollector);
        nft.setApprovalForAll(address(ra), true);

        // batch token deposits into batches of 50 to simulate real world
        uint256 startTokenId = 0; // always 0 at the start of this function
        uint256 numDeposited = 0;
        while (numDeposited < numTokens) {
            uint256 numLeftToDeposit = numTokens - numDeposited;
            uint256 numToDeposit = numLeftToDeposit > 50 ? 50 : numLeftToDeposit;
            numDeposited += numToDeposit;
            uint256[] memory tokenIds = new uint256[](numToDeposit);
            for (uint256 i = startTokenId; i < startTokenId + numToDeposit; ++i) {
                tokenIds[i - startTokenId] = i;
            }
            startTokenId = tokenIds[tokenIds.length - 1] + 1;
            ra.depositPrizeTokens(nftCollector, tokenIds);
        }

        // setup auction
        ra.setupAuction(openAt, duration);

        // invariant check
        if (openAt > block.timestamp) {
            assertEq(ra.openAt(), openAt);
        } else {
            assertEq(ra.openAt(), uint64(block.timestamp));
        }
        if (duration > ra.EXTENSION_TIME()) {
            assertEq(ra.duration(), duration);
        } else {
            assertEq(ra.duration(), uint64(ra.EXTENSION_TIME()));
        }
        assertEq(uint8(ra.state()), uint8(TLRankedAuction.AuctionState.LIVE));
    }

    function _assertInvariants(
        uint32 insertedBidId,
        uint32 expectedListSize,
        uint32 expectedNext,
        uint32 expectedPrev,
        uint128 expectedAmount,
        address expectedBidder
    ) internal view {
        TLRankedAuction.BidView memory bid = ra.getDetailedBid(insertedBidId);
        uint32 head = ra.head();
        uint32 tail = ra.tail();
        uint32 listSize = ra.listSize();
        assertEq(listSize, expectedListSize, "List size invariant broken");
        assertEq(bid.next, expectedNext, "Next invariant broken");
        assertEq(bid.prev, expectedPrev, "Prev invariant broken");
        assertEq(bid.amount, expectedAmount, "Bid amount invariant broken");
        assertEq(bid.bidder, expectedBidder, "Bidder invariant broken");
        if (bid.prev != 0) {
            TLRankedAuction.BidView memory prevBid = ra.getDetailedBid(bid.prev);
            assertGe(prevBid.amount, bid.amount, "Previous bid not gte to inserted bid");
            assertEq(prevBid.next, insertedBidId, "Previous bid not linked to inserted bid");
        } else {
            // inserted bid is the new head
            assertEq(insertedBidId, head, "Inserted bid is the head but isn't recorded as the head");
        }
        if (bid.next != 0) {
            TLRankedAuction.BidView memory nextBid = ra.getDetailedBid(bid.next);
            assertGe(bid.amount, nextBid.amount, "Inserted bid not gte to next bid");
            assertEq(nextBid.prev, insertedBidId, "Next bid not linked to back inserted bid");
        } else {
            // inserted bid is the new tail
            assertEq(insertedBidId, tail, "Inserted bid is the tail but isn't recorded as the tail");
        }
    }

    /// Test constructor errors
    function test_constructor_errors() public {
        vm.expectRevert(TLRankedAuction.TooFewTokens.selector);
        new TLRankedAuction(address(this), address(1), 0, 0);

        vm.expectRevert(TLRankedAuction.TooFewTokens.selector);
        new TLRankedAuction(address(this), address(1), 0, 1);

        vm.expectRevert(TLRankedAuction.TooManyTokens.selector);
        new TLRankedAuction(address(this), address(1), 0, 1024);

        vm.expectRevert(TLRankedAuction.InvalidStartBid.selector);
        new TLRankedAuction(address(this), address(1), 500, 256);

        vm.expectRevert(TLRankedAuction.InvalidNftContract.selector);
        new TLRankedAuction(address(this), address(1), 1 ether, 2);
    }

    /// Test setting up the auction
    /// - access control
    /// - errors
    /// - events
    /// - successful state transition
    function test_auction_setup_access_control(address hacker) public {
        vm.assume(hacker != address(this));
        _deployContracts(1 ether, 50);
        nft.mint(nftCollector, 50);

        uint256[] memory tokenIds = new uint256[](50);
        for (uint256 i = 0; i < 50; ++i) {
            tokenIds[i] = i;
        }

        // try setting up auction as hacker
        vm.startPrank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        ra.depositPrizeTokens(nftCollector, tokenIds);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        ra.withdrawPrizeTokens(nftCollector, 1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        ra.setupAuction(0, 5 minutes);

        vm.stopPrank();
    }

    function test_auction_setup() public {
        _deployContracts(1 ether, 50);
        nft.mint(nftCollector, 50);

        uint256[] memory tokenIds = new uint256[](50);
        for (uint256 i = 0; i < 50; ++i) {
            tokenIds[i] = i;
        }

        // deposit tokens fails without approval granted
        vm.expectRevert();
        ra.depositPrizeTokens(nftCollector, tokenIds);

        // grant approval
        vm.prank(nftCollector);
        nft.setApprovalForAll(address(ra), true);

        // deposit tokens
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            vm.expectEmit(true, false, false, false);
            emit TLRankedAuction.PrizeTokenEscrowed(tokenIds[i]);
        }
        ra.depositPrizeTokens(nftCollector, tokenIds);

        // try depositing again
        vm.expectRevert(TLRankedAuction.TooManyTokens.selector);
        ra.depositPrizeTokens(nftCollector, tokenIds);

        // try withdrawing to zero address
        vm.expectRevert(TLRankedAuction.InvalidAddress.selector);
        ra.withdrawPrizeTokens(address(0), 50);

        // withdraw some
        for (uint256 i = 50; i > 45; --i) {
            vm.expectEmit(true, true, false, false);
            emit TLRankedAuction.PrizeTokenWithdrawn(nftCollector, i - 1);
        }
        ra.withdrawPrizeTokens(nftCollector, 5);

        // try depositing too many
        vm.expectRevert(TLRankedAuction.TooManyTokens.selector);
        ra.depositPrizeTokens(nftCollector, tokenIds);

        // try depositing some that are already in the contract
        uint256[] memory newTokenIds = new uint256[](5);
        newTokenIds[0] = 0;
        newTokenIds[1] = 1;
        newTokenIds[2] = 2;
        newTokenIds[3] = 3;
        newTokenIds[4] = 4;
        vm.expectRevert(TLRankedAuction.InvalidAddress.selector);
        ra.depositPrizeTokens(address(ra), newTokenIds);

        // try setting up auction early
        vm.expectRevert(TLRankedAuction.DepositAllPrizeTokens.selector);
        ra.setupAuction(0, 0);

        // withdraw the rest
        for (uint256 i = 45; i > 0; --i) {
            vm.expectEmit(true, true, false, false);
            emit TLRankedAuction.PrizeTokenWithdrawn(nftCollector, i - 1);
        }
        ra.withdrawPrizeTokens(nftCollector, 50); // function takes care of situations where the user wants too many withdrawn

        // try to setup auction
        vm.expectRevert(TLRankedAuction.DepositAllPrizeTokens.selector);
        ra.setupAuction(0, 0);

        // deposit all
        ra.depositPrizeTokens(nftCollector, tokenIds);
        for (uint256 i = 0; i < 50; ++i) {
            assertEq(ra.prizeTokenIds(i), tokenIds[i]);
        }

        // setup auction
        vm.expectEmit(false, false, false, true);
        emit TLRankedAuction.AuctionConfigured(uint64(block.timestamp), uint64(ra.EXTENSION_TIME()));
        ra.setupAuction(0, 0);
        assertEq(ra.openAt(), uint64(block.timestamp));
        assertEq(ra.duration(), uint64(ra.EXTENSION_TIME()));
        assertEq(uint8(ra.state()), uint8(TLRankedAuction.AuctionState.LIVE));

        // try depositing again
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.depositPrizeTokens(nftCollector, tokenIds);

        // try removing again
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.withdrawPrizeTokens(nftCollector, 50);

        // try withdrawing leftover ones
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.withdrawLeftOverPrizeTokens(nftCollector, 50);

        // try setting up auction again
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.setupAuction(0, 0);
    }

    function test_auction_reset(address hacker) public {
        vm.assume(hacker != address(this));

        _deployContracts(1 ether, 2);

        // cannot reset while not live
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.resetAuction();

        // setup
        _setupAuction(2, uint64(block.timestamp), 1 hours);

        // non-owner cannot reset
        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        ra.resetAuction();

        // reset succeeds with no bids
        vm.expectEmit(false, false, false, true);
        emit TLRankedAuction.AuctionReset();
        ra.resetAuction();
        assertEq(uint8(ra.state()), uint8(TLRankedAuction.AuctionState.CONFIGURING));
        assertEq(ra.openAt(), 0);
        assertEq(ra.duration(), 0);
        assertEq(ra.hardEndAt(), 0);

        // withdraw tokens
        ra.withdrawPrizeTokens(nftCollector, 2);

        // cannot reset when bids have been placed
        _setupAuction(2, uint64(block.timestamp), 1 hours);
        vm.deal(address(0xbeef), 10 ether);
        vm.prank(address(0xbeef));
        ra.createBid{value: 1 ether}(0);
        vm.expectRevert(TLRankedAuction.BidsHaveBeenPlaced.selector);
        ra.resetAuction();
    }

    /// Test bidding
    /// - errors
    /// - events
    /// - invariants
    function test_createBid_errors(address bidder) public {
        vm.deal(bidder, 100 ether);
        _deployContracts(1 ether, 2);

        // try when not configured
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.createBid(0);

        _setupAuction(2, uint64(block.timestamp + 1 hours), 24 hours);

        // try bidding before it opens
        vm.expectRevert(TLRankedAuction.BiddingNotOpen.selector);
        vm.prank(bidder);
        ra.createBid{value: 1 ether}(0);

        // warp to open time
        vm.warp(block.timestamp + 1 hours);

        // try bidding less than the starting bid
        vm.expectRevert(TLRankedAuction.BidMore.selector);
        vm.prank(bidder);
        ra.createBid{value: 0.1 ether}(0);

        // successful bid
        uint32 bidId = ra.nextBidId();
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidCreated(bidder, bidId, 1.1 ether);
        vm.prank(bidder);
        ra.createBid{value: 1.1 ether}(0);

        // a second successful bidder
        bidId = ra.nextBidId();
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidCreated(bidder, bidId, 1.2 ether);
        vm.prank(bidder);
        ra.createBid{value: 1.2 ether}(1);

        // try bidding too little now that the list is full
        vm.expectRevert(TLRankedAuction.BidMore.selector);
        vm.prank(bidder);
        ra.createBid{value: 1.1 ether}(0); // tail bid value

        // warp to the end of the auction
        vm.warp(block.timestamp + 25 hours);

        // try bidding
        vm.expectRevert(TLRankedAuction.BiddingEnded.selector);
        vm.prank(bidder);
        ra.createBid{value: 5 ether}(0);
    }

    function test_createBid(uint16 numTokens, uint128 startBid) public {
        if (numTokens < 2) numTokens = 2;
        if (numTokens > 512) numTokens = 512;
        if (startBid < 10_000) startBid = 10_000;
        if (startBid > 100 ether) startBid = 100 ether;

        address[] memory bidders = new address[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            address b = makeAddr(i.toString());
            bidders[i] = b;
            vm.deal(b, 300 ether);
        }

        // setup auction
        _deployContracts(startBid, numTokens);
        _setupAuction(numTokens, 0, 24 hours);

        // fill up the bids via walk down (worse case scenario)
        // all bids will be the start bid, so they'll become the tail
        for (uint256 i = 0; i < numTokens; ++i) {
            address b = bidders[i];
            uint32 id = ra.nextBidId();
            vm.expectEmit(true, true, false, true);
            emit TLRankedAuction.BidCreated(b, id, startBid);
            vm.prank(b);
            ra.createBid{value: startBid}(0);
            _assertInvariants(id, uint32(i + 1), 0, id - 1, startBid, b);
        }

        // add a new head bid
        uint32 tailBidId = ra.tail();
        uint32 bidId = ra.nextBidId();
        address bidder = bidders[0];
        uint128 amount = startBid + startBid * 500 / 10_000;
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidRemoved(bidders[numTokens - 1], numTokens, startBid);
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidCreated(bidder, bidId, amount);
        vm.prank(bidder);
        ra.createBid{value: amount}(tailBidId);
        _assertInvariants(bidId, numTokens, 1, 0, amount, bidder);

        // add a second highest bid, walking from the tail up (worst case scenario)
        uint32 headBidId = ra.head();
        tailBidId = ra.tail();
        bidId = ra.nextBidId();
        bidder = bidders[1];
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidRemoved(bidders[numTokens - 2], numTokens - 1, startBid);
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidCreated(bidder, bidId, amount);
        vm.prank(bidder);
        ra.createBid{value: amount}(tailBidId);
        _assertInvariants(bidId, numTokens, numTokens == 2 ? 0 : 1, headBidId, amount, bidder);

        // warp to the last five minutes
        vm.warp(block.timestamp + 24 hours - 4 minutes);

        // extend auction with a crazy new head
        uint64 newDuration = ra.duration()
            + uint64(ra.EXTENSION_TIME() - (uint256(ra.openAt()) + uint256(ra.duration()) - block.timestamp));
        headBidId = ra.head();
        bidId = ra.nextBidId();
        bidder = bidders[0];
        vm.deal(bidder, 200 ether);
        amount = uint128(200 ether);
        vm.expectEmit(false, false, false, true);
        emit TLRankedAuction.AuctionExtended(newDuration);
        vm.prank(bidder);
        ra.createBid{value: amount}(tailBidId);
        _assertInvariants(bidId, numTokens, headBidId, 0, amount, bidder);

        // extend auction to the hard cap
        // NOTE: do this by always bidding at endAt - 1 to maximize extension per iteration.
        vm.deal(bidder, 10_000 ether); // ensure bidder never runs out during the loop

        uint256 maxIters = 2048; // safety guard
        for (uint256 i = 0; i < maxIters; ++i) {
            uint256 endAt = uint256(ra.openAt()) + uint256(ra.duration());
            uint256 hardEndAt = uint256(ra.hardEndAt());
            if (endAt >= hardEndAt) break;

            // warp to the last second of the auction to force an extension
            vm.warp(endAt - 1);

            uint256 expectedEndAt = block.timestamp + uint256(ra.EXTENSION_TIME());
            if (expectedEndAt > hardEndAt) expectedEndAt = hardEndAt;
            uint64 expectedDuration = uint64(expectedEndAt - uint256(ra.openAt()));

            vm.expectEmit(false, false, false, true);
            emit TLRankedAuction.AuctionExtended(expectedDuration);

            uint128 bidAmount = ra.getMinBid();
            uint32 hint = ra.tail();
            vm.prank(bidder);
            ra.createBid{value: bidAmount}(hint);

            assertEq(uint256(ra.openAt()) + uint256(ra.duration()), expectedEndAt, "endAt mismatch after extension");
        }

        assertEq(uint256(ra.openAt()) + uint256(ra.duration()), uint256(ra.hardEndAt()), "hard end not reached");
        
        // finito
    }

    /// Test increase bid errors
    function test_increaseBid_errors(address bidder) public {
        vm.assume(bidder != address(0));
        vm.assume(bidder != address(this));
        vm.deal(address(this), 1 ether);
        vm.deal(bidder, 100 ether);
        _deployContracts(1 ether, 2);

        // try when not configured
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.increaseBid(1, 0);

        _setupAuction(2, uint64(block.timestamp + 1 hours), 24 hours);

        // try bidding before it opens
        vm.expectRevert(TLRankedAuction.BiddingNotOpen.selector);
        vm.prank(bidder);
        ra.increaseBid{value: 1 ether}(1, 0);

        // warp to open time
        vm.warp(block.timestamp + 1 hours);

        // try increasing an invalid bid
        vm.expectRevert(TLRankedAuction.InvalidBid.selector);
        vm.prank(bidder);
        ra.increaseBid(1, 0);

        // successful bid
        uint32 bidId = ra.nextBidId();
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidCreated(bidder, bidId, 1 ether);
        vm.prank(bidder);
        ra.createBid{value: 1 ether}(0);

        // try increase bid for someone else
        vm.expectRevert(TLRankedAuction.NotBidder.selector);
        ra.increaseBid{value: 1 ether}(bidId, 0);

        // try increasing too little
        vm.expectRevert(TLRankedAuction.AddMore.selector);
        vm.prank(bidder);
        ra.increaseBid{value: 0}(bidId, 0);

        // warp to the end of the auction
        vm.warp(block.timestamp + 25 hours);

        // try increasing
        vm.expectRevert(TLRankedAuction.BiddingEnded.selector);
        vm.prank(bidder);
        ra.increaseBid{value: 5 ether}(bidId, 0);
    }

    /// Test increasing bids
    function test_increaseBid(uint16 numTokens, uint128 startBid) public {
        if (numTokens < 3) numTokens = 3;
        if (numTokens > 512) numTokens = 512;
        if (startBid < 10_000) startBid = 10_000;
        if (startBid > 100 ether) startBid = 100 ether;

        address[] memory bidders = new address[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            address b = makeAddr(i.toString());
            bidders[i] = b;
            vm.deal(b, 300 ether);
        }

        // setup auction
        _deployContracts(startBid, numTokens);
        _setupAuction(numTokens, 0, 24 hours);

        // fill up the bids via walk down a single hop (best case scenario)
        // all bids will be the start bid, so they'll become the tail
        for (uint256 i = 0; i < numTokens; ++i) {
            address b = bidders[i];
            uint32 id = ra.nextBidId();
            vm.expectEmit(true, true, false, true);
            emit TLRankedAuction.BidCreated(b, id, startBid);
            vm.prank(b);
            ra.createBid{value: startBid}(id - 1);
            _assertInvariants(id, uint32(i + 1), 0, id - 1, startBid, b);
        }

        // increase the bid of the head
        address bidder = bidders[0];
        uint32 bidId = ra.head();
        uint128 minBidIncrease = ra.getMinBidIncrease(startBid);
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidIncreased(bidder, bidId, startBid + minBidIncrease);
        vm.prank(bidder);
        ra.increaseBid{value: minBidIncrease}(bidId, 0);
        _assertInvariants(bidId, numTokens, 2, 0, startBid + minBidIncrease, bidder);

        // increase the bid of the tail to now be the second bid
        bidder = bidders[numTokens - 1];
        bidId = ra.tail();
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.BidIncreased(bidder, bidId, startBid + minBidIncrease);
        vm.prank(bidder);
        ra.increaseBid{value: minBidIncrease}(bidId, bidId); // hint same id to test pop + insertion logic
        _assertInvariants(bidId, numTokens, 2, 1, startBid + minBidIncrease, bidder);

        // warp to near the end of the auction
        vm.warp(block.timestamp + 24 hours - 3 minutes);

        // increase a middle bid and extend the auction
        bidder = bidders[1];
        bidId = 2;
        uint64 newDuration = ra.duration()
            + uint64(ra.EXTENSION_TIME() - (uint256(ra.openAt()) + uint256(ra.duration()) - block.timestamp));
        vm.expectEmit(false, false, false, true);
        emit TLRankedAuction.AuctionExtended(newDuration);
        vm.prank(bidder);
        ra.increaseBid{value: 2*minBidIncrease}(bidId, 0); // new head
        _assertInvariants(bidId, numTokens, 1, 0, startBid + 2*minBidIncrease, bidder);

        // finito

    }

    /// Test settling an auction with 0 bids
    function test_settle_auction_no_bids() public {
        _deployContracts(1 ether, 10);
        _setupAuction(10, 0, 0);
        vm.warp(block.timestamp + 1 hours);

        // no bids came in, should be able to go straight to settled
        vm.expectEmit(false, false, false, true);
        emit TLRankedAuction.AuctionSettling(1 ether);
        vm.expectEmit(false, false, false, false);
        emit TLRankedAuction.AuctionSettled();
        ra.startSettlingAuction();

        // check the state transition
        assertEq(uint8(ra.state()), uint8(TLRankedAuction.AuctionState.SETTLED));
        assertEq(ra.clearingPrice(), 1 ether);
        assertEq(ra.nextUnallocatedRank(), 1);

        // make sure processing ranks and claim functions fail
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.processRanks(10);
        vm.expectRevert(TLRankedAuction.InvalidBid.selector);
        ra.claim(1);

        // try withdrawing nfts to zero address
        vm.expectRevert(TLRankedAuction.InvalidAddress.selector);
        ra.withdrawLeftOverPrizeTokens(address(0), 5);

        // try withdrawing zero
        vm.expectRevert(TLRankedAuction.ProcessAtLeastOne.selector);
        ra.withdrawLeftOverPrizeTokens(nftCollector, 0);

        // withdraw left over nfts
        for (uint256 i = 0; i < 5; ++i) {
            vm.expectEmit(true, true, false, false);
            emit TLRankedAuction.PrizeTokenWithdrawn(nftCollector, i);
        }
        ra.withdrawLeftOverPrizeTokens(nftCollector, 5);

        for (uint256 i = 5; i < 10; ++i) {
            vm.expectEmit(true, true, false, false);
            emit TLRankedAuction.PrizeTokenWithdrawn(nftCollector, i);
        }
        ra.withdrawLeftOverPrizeTokens(nftCollector, 10); // try to withdraw more to test clamping path

        assertEq(ra.nextUnallocatedRank(), 11);

        // withdrawing pending proceeds fails
        vm.expectRevert(TLRankedAuction.NothingToWithdraw.selector);
        ra.withdrawPendingProceeds(1 ether, nftCollector);
    }

    /// Test settling an auction with less bids than num tokens
    function test_settle_underallocated_auction() public {
        _deployContracts(1 ether, 50);
        
        // try settling auction before auction is live
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.startSettlingAuction();

        _setupAuction(50, 0, 0);

        address bidder = address(0xb0b);
        vm.deal(bidder, 11 ether);

        // bidder bids 10 times
        vm.startPrank(bidder);
        ra.createBid{value: 2 ether}(0);
        ra.createBid{value: 1 ether}(1);
        ra.createBid{value: 1 ether}(2);
        ra.createBid{value: 1 ether}(3);
        ra.createBid{value: 1 ether}(4);
        ra.createBid{value: 1 ether}(5);
        ra.createBid{value: 1 ether}(6);
        ra.createBid{value: 1 ether}(7);
        ra.createBid{value: 1 ether}(8);
        ra.createBid{value: 1 ether}(9);
        vm.stopPrank();

        // try settling auction before it ends
        vm.expectRevert(TLRankedAuction.AuctionNotEnded.selector);
        ra.startSettlingAuction();

        // auction ends
        vm.warp(block.timestamp + 10 minutes);

        // start settling
        vm.expectEmit(false, false, false, true);
        emit TLRankedAuction.AuctionSettling(1 ether);
        ra.startSettlingAuction();

        assertEq(uint8(ra.state()), uint8(TLRankedAuction.AuctionState.SETTLING));
        assertEq(ra.clearingPrice(), 1 ether);
        assertEq(ra.nextUnallocatedRank(), 11);
        assertEq(ra.nextRank(), 1);
        assertEq(ra.pendingProceeds(), 10 ether);

        // try processing 0
        vm.expectRevert(TLRankedAuction.ProcessAtLeastOne.selector);
        ra.processRanks(0);

        // try withdrawing proceeds
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.withdrawPendingProceeds(10 ether, address(this));

        // try claiming
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.claim(1);

        // process ranks in two batches
        uint32 nextRank = ra.nextRank();
        for (uint256 i = 0; i < 5; i++) {
            vm.expectEmit(true, false, false, true);
            emit TLRankedAuction.BidRanked(uint32(i + 1), uint32(nextRank + i));
        }
        ra.processRanks(5);

        assertEq(ra.lastProcessedId(), 5);
        assertEq(ra.nextRank(), 6);

        for (uint256 i = 5; i < 10; ++i) {
            vm.expectEmit(true, false, false, true);
            emit TLRankedAuction.BidRanked(uint32(i + 1), uint32(nextRank + i));
        }
        vm.expectEmit(false, false, false, false);
        emit TLRankedAuction.AuctionSettled();
        ra.processRanks(10); // try processing more and get limited

        assertEq(uint8(ra.state()), uint8(TLRankedAuction.AuctionState.SETTLED));

        // try processing again and fail
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.processRanks(10);

        // assert next rank is 11
        assertEq(ra.nextRank(), 11, "next rank invariant broken");
        assertEq(ra.nextUnallocatedRank(), 11, "next unallocated rank invariant broken");

        // bidder can claim
        vm.prank(bidder);
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.PrizeTokenClaimed(bidder, 0, 1 ether);
        ra.claim(1);

        // anyone can claim for the bidder
        for (uint256 i = 2; i < 11; ++i) {
            vm.expectEmit(true, true, false, true);
            emit TLRankedAuction.PrizeTokenClaimed(bidder, i - 1, 0);
            ra.claim(uint32(i));
        }

        // try claiming invalid bid
        vm.expectRevert(TLRankedAuction.InvalidBid.selector);
        ra.claim(30);

        // try claiming bid again
        vm.expectRevert(TLRankedAuction.BidClaimed.selector);
        ra.claim(1);

        // try withdrawing proceeds to a reverting address
        revertOnReceive = true;
        vm.expectRevert(TLRankedAuction.WithdrawalFailed.selector);
        ra.withdrawPendingProceeds(1 ether, address(this));
        revertOnReceive = false;

        // proceeds can be withdrawn
        vm.expectRevert(TLRankedAuction.InvalidAddress.selector);
        ra.withdrawPendingProceeds(1 ether, address(0));

        ra.withdrawPendingProceeds(1 ether, address(this));
        assertEq(ra.pendingProceeds(), 9 ether);
        ra.withdrawPendingProceeds(10 ether, address(this));
        assertEq(ra.pendingProceeds(), 0 ether);

        // try withdrawing proceeds again
        vm.expectRevert(TLRankedAuction.NothingToWithdraw.selector);
        ra.withdrawPendingProceeds(1 ether, address(this));

        // remaining 40 nfts can be withdrawn
        for (uint256 i = 10; i < 50; ++i) {
            vm.expectEmit(true, true, false, false);
            emit TLRankedAuction.PrizeTokenWithdrawn(nftCollector, i);
        }
        ra.withdrawLeftOverPrizeTokens(nftCollector, 40);

        // check nft owners
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(nft.ownerOf(i), bidder);
        }
        for (uint256 i = 10; i < 50; ++i) {
            assertEq(nft.ownerOf(i), nftCollector);
        }

        // bidder is returned their 1 ETH refund
        assertEq(bidder.balance, 1 ether);

        // balance of the auction contract is 0 at the end
        assertEq(address(ra).balance, 0);
        assertEq(nft.balanceOf(address(ra)), 0);
    }

    /// Test settling an auction with a fully allocated auction
    function test_settle_fully_allocated_auction() public {
        _deployContracts(1 ether, 10);
        _setupAuction(10, 0, 0);

        address bidder = address(0xb0b);
        vm.deal(bidder, 11 ether);

        // bidder bids 10 times
        vm.startPrank(bidder);
        ra.createBid{value: 2 ether}(0);
        ra.createBid{value: 1 ether}(1);
        ra.createBid{value: 1 ether}(2);
        ra.createBid{value: 1 ether}(3);
        ra.createBid{value: 1 ether}(4);
        ra.createBid{value: 1 ether}(5);
        ra.createBid{value: 1 ether}(6);
        ra.createBid{value: 1 ether}(7);
        ra.createBid{value: 1 ether}(8);
        ra.createBid{value: 1 ether}(9);
        vm.stopPrank();

        // auction ends
        vm.warp(block.timestamp + 10 minutes);

        // start settling
        vm.expectEmit(false, false, false, true);
        emit TLRankedAuction.AuctionSettling(1 ether);
        ra.startSettlingAuction();

        assertEq(uint8(ra.state()), uint8(TLRankedAuction.AuctionState.SETTLING));
        assertEq(ra.clearingPrice(), 1 ether);
        assertEq(ra.nextUnallocatedRank(), 11);
        assertEq(ra.nextRank(), 1);
        assertEq(ra.pendingProceeds(), 10 ether);

        // try processing 0
        vm.expectRevert(TLRankedAuction.ProcessAtLeastOne.selector);
        ra.processRanks(0);

        // try withdrawing proceeds
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.withdrawPendingProceeds(10 ether, address(this));

        // process ranks in two batches
        uint32 nextRank = ra.nextRank();
        for (uint256 i = 0; i < 5; i++) {
            vm.expectEmit(true, false, false, true);
            emit TLRankedAuction.BidRanked(uint32(i + 1), uint32(nextRank + i));
        }
        ra.processRanks(5);

        assertEq(ra.lastProcessedId(), 5);
        assertEq(ra.nextRank(), 6);

        for (uint256 i = 5; i < 10; ++i) {
            vm.expectEmit(true, false, false, true);
            emit TLRankedAuction.BidRanked(uint32(i + 1), uint32(nextRank + i));
        }
        vm.expectEmit(false, false, false, false);
        emit TLRankedAuction.AuctionSettled();
        ra.processRanks(10); // try processing more and get limited

        assertEq(uint8(ra.state()), uint8(TLRankedAuction.AuctionState.SETTLED));

        // assert next rank is 11
        assertEq(ra.nextRank(), 11, "next rank invariant broken");
        assertEq(ra.nextUnallocatedRank(), 11, "next unallocated rank invariant broken");

        // try processing again and fail
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        ra.processRanks(10);

        // bidder can claim
        vm.prank(bidder);
        vm.expectEmit(true, true, false, true);
        emit TLRankedAuction.PrizeTokenClaimed(bidder, 0, 1 ether);
        ra.claim(1);

        // anyone can claim for the bidder
        for (uint256 i = 2; i < 11; ++i) {
            vm.expectEmit(true, true, false, true);
            emit TLRankedAuction.PrizeTokenClaimed(bidder, i - 1, 0);
            ra.claim(uint32(i));
        }

        // try claiming invalid bid
        vm.expectRevert(TLRankedAuction.InvalidBid.selector);
        ra.claim(30);

        // try claiming bid again
        vm.expectRevert(TLRankedAuction.BidClaimed.selector);
        ra.claim(1);

        // can't withdraw left over tokens
        vm.expectRevert(TLRankedAuction.NothingToWithdraw.selector);
        ra.withdrawLeftOverPrizeTokens(nftCollector, 10);

        // proceeds can be withdrawn
        vm.expectRevert(TLRankedAuction.InvalidAddress.selector);
        ra.withdrawPendingProceeds(1 ether, address(0));

        ra.withdrawPendingProceeds(1 ether, address(this));
        assertEq(ra.pendingProceeds(), 9 ether);
        ra.withdrawPendingProceeds(10 ether, address(this));
        assertEq(ra.pendingProceeds(), 0 ether);

        // try withdrawing proceeds again
        vm.expectRevert(TLRankedAuction.NothingToWithdraw.selector);
        ra.withdrawPendingProceeds(1 ether, address(this));

        // check nft owner
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(nft.ownerOf(i), bidder);
        }

        // bidder is returned their 1 ETH refund
        assertEq(bidder.balance, 1 ether);

        // balance of the auction contract is 0 at the end
        assertEq(address(ra).balance, 0);
        assertEq(nft.balanceOf(address(ra)), 0);
    }

    /// Test reverting eth and nft transfer
    function test_reverting_bidders() public {
        _deployContracts(1 ether, 2);
        _setupAuction(2, 0, 0);

        vm.deal(address(this), 100 ether);

        // try withdrawing with nothing to withdraw
        vm.expectRevert(TLRankedAuction.NothingToWithdraw.selector);
        ra.rescueRefund(address(this));

        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 2 ether}(0);

        // revert on receive to simulate any type of revert
        revertOnReceive = true;

        // bid again
        ra.createBid{value: 1.5 ether}(2);

        // make sure it went through
        assertEq(ra.listSize(), 2);
        assertEq(ra.pendingRefunds(address(this)), 1 ether);
        assertEq(ra.tail(), 3);
        assertEq(ra.getTailBid(), 1.5 ether);

        // try withdrawing to the zero address
        vm.expectRevert(TLRankedAuction.InvalidAddress.selector);
        ra.rescueRefund(address(0));

        // try withrawing
        vm.expectRevert(TLRankedAuction.WithdrawalFailed.selector);
        ra.rescueRefund(address(this));

        // withdraw the funds to a different wallet
        ra.rescueRefund(nftCollector);
        assertEq(nftCollector.balance, 1 ether);

        // settle the auction
        vm.warp(block.timestamp + 10 minutes);
        ra.startSettlingAuction();
        assertEq(ra.clearingPrice(), 1.5 ether);
        assertEq(ra.pendingProceeds(), 3 ether);
        ra.processRanks(2);

        // claim
        ra.claim(2);
        ra.claim(3);
        assertEq(ra.pendingNfts(0), address(this));
        assertEq(ra.pendingNfts(1), address(this));
        assertEq(ra.pendingRefunds(address(this)), 0.5 ether);

        TLRankedAuction.BidView memory bv = ra.getDetailedBid(2);
        assertTrue(bv.claimed);

        // retreive refund
        revertOnReceive = false;
        ra.rescueRefund(address(this));
        assertEq(ra.pendingRefunds(address(this)), 0);
        vm.expectRevert(TLRankedAuction.NothingToWithdraw.selector);
        ra.rescueRefund(address(this));

        // retreive the nfts
        vm.expectRevert(TLRankedAuction.InvalidAddress.selector);
        ra.rescueNft(address(0), 0);
        vm.expectRevert(TLRankedAuction.NotAllowed.selector);
        vm.prank(nftCollector);
        ra.rescueNft(nftCollector, 0);
        ra.rescueNft(nftCollector, 0);
        ra.rescueNft(nftCollector, 1);
        assertEq(nft.ownerOf(0), nftCollector);
        assertEq(nft.ownerOf(1), nftCollector);
        vm.expectRevert(TLRankedAuction.NothingToWithdraw.selector);
        ra.rescueNft(nftCollector, 0);

        assertEq(ra.pendingNfts(0), address(0));
        assertEq(ra.pendingNfts(1), address(0));

        // withdraw proceeds
        ra.withdrawPendingProceeds(address(ra).balance, address(this));

        // final checks
        assertEq(nft.balanceOf(address(ra)), 0);
        assertEq(address(ra).balance, 0);
    }

    function test_helper_functions() public {
        _deployContracts(1 ether, 2);
        _setupAuction(2, 0, 0);

        // min bid should be the start bid
        uint128 minBid = ra.getMinBid();
        assertEq(minBid, 1 ether);

        vm.deal(address(this), 100 ether);

        ra.createBid{value: 1.5 ether}(0);

        // list not full, min bid should still by the start bid
        minBid = ra.getMinBid();
        assertEq(minBid, 1 ether);

        ra.createBid{value: 1 ether}(1);

        // list full, min bid should be 5% more than the tail test_bid
        uint128 tailBid = ra.getTailBid();
        minBid = ra.getMinBid();
        assertEq(minBid, tailBid + tailBid * ra.CREATE_BID_BPS() / ra.BASIS());

        ra.createBid{value: 1.25 ether}(1);

        // get prize token for rank
        vm.expectRevert(TLRankedAuction.InvalidRank.selector);
        ra.getPrizeTokenIdForRank(0);
        vm.expectRevert(TLRankedAuction.InvalidRank.selector);
        ra.getPrizeTokenIdForRank(3);
        uint256 tokenId = ra.getPrizeTokenIdForRank(1);
        assertEq(tokenId, 0);
        tokenId = ra.getPrizeTokenIdForRank(2);
        assertEq(tokenId, 1);

        // get auction info
        (,,,,, uint32 listSize, uint32 head, uint32 tail) = ra.getAuctionInfo();
        assertEq(listSize, 2);
        assertEq(head, 1);
        assertEq(tail, 3);

        // get head and tail bid
        assertEq(ra.getHeadBid(), 1.5 ether);
        assertEq(ra.getTailBid(), 1.25 ether);
    }

    function test_get_bids_array() public {
        _deployContracts(1 ether, 10);
        _setupAuction(10, 0, 0);

        vm.deal(address(this), 20 ether);

        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);
        ra.createBid{value: 1 ether}(0);

        TLRankedAuction.BidView[] memory bids = new TLRankedAuction.BidView[](10);
        uint32 numReturned;
        (bids, numReturned) = ra.getBids(1, 10);

        assertEq(bids.length, 10);
        assertEq(numReturned, 10);
        assertEq(bids[0].bidId, 1);

        // get half starting at the head
        (bids, numReturned) = ra.getBids(0, 5);

        assertEq(bids.length, 5);
        assertEq(numReturned, 5);
        assertEq(bids[0].bidId, 1);
    }
}
