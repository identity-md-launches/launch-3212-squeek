// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "../src/Squeek.sol";

/// @dev All token holders in this model are tracked; the model does not read token balances
/// or allowances to decide what a successful operation should do.
contract SqueekHandler is Test {
    Squeek private immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Squeek token_) {
        token = token_;
        actors[0] = makeAddr("actor zero");
        actors[1] = makeAddr("actor one");
        actors[2] = makeAddr("actor two");
        actors[3] = makeAddr("actor three");
        expectedBalance[actors[0]] = 1_000_000_000 * 1e18;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool unlimited) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = unlimited ? type(uint256).max : bound(rawAmount, 0, 1_000_000_000 * 1e18);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        uint256 amount = bound(rawAmount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function rejectOverdraw(uint256 fromSeed, uint256 toSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        if (approved == type(uint256).max) return;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }
}

contract SqueekInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    Squeek private token;
    SqueekHandler private handler;

    function setUp() public {
        token = new Squeek();
        handler = new SqueekHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = SqueekHandler.move.selector;
        selectors[1] = SqueekHandler.approve.selector;
        selectors[2] = SqueekHandler.spend.selector;
        selectors[3] = SqueekHandler.rejectOverdraw.selector;
        selectors[4] = SqueekHandler.rejectOverAllowance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
            sum += token.balanceOf(actor);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
