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
        uint256 amount = unlimited ? type(uint256).max : bound(rawAmount, 0, type(uint256).max - 1);
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
        // Make an unlimited approval finite first so every invocation actually attempts a rejection.
        if (approved == type(uint256).max) {
            approved = type(uint256).max - 1;
            vm.prank(owner);
            assertTrue(token.approve(spender, approved));
            expectedAllowance[owner][spender] = approved;
        }
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function moveAll(uint256 fromSeed, uint256 toSeed) public {
        address from = _fundedActor(fromSeed);
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function roundTrip(uint256 fromSeed, uint256 offsetSeed, uint256 rawAmount) public {
        address from = _fundedActor(fromSeed);
        // Choose a different actor so even a one-wei round trip exercises both balance slots.
        uint256 fromIndex;
        while (actors[fromIndex] != from) ++fromIndex;
        address to = actors[(fromIndex + 1 + offsetSeed % (actors.length - 1)) % actors.length];
        uint256 amount = bound(rawAmount, 1, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), expectedBalance[from] - amount);
        assertEq(token.balanceOf(to), expectedBalance[to] + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        // Ghost balances intentionally stay unchanged: the pair of calls must be an exact inverse.
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
    }

    function rejectSpendOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 rawExcess,
        bool unlimited
    ) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(rawExcess, 1, type(uint256).max - balance);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // The invariant compares all allowances to the unchanged ghost after the failed spend.
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 operation) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        if (operation % 3 == 0) {
            uint256 amount = bound(rawAmount, 0, expectedBalance[owner]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (operation % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), rawAmount);
        } else {
            uint256 approved = expectedAllowance[owner][spender];
            uint256 available = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
            uint256 amount = bound(rawAmount, 0, available);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[(start + i) % actors.length];
            if (expectedBalance[actor] != 0) return actor;
        }
        revert("model lost the entire fixed supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
contract SqueekInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    Squeek private token;
    SqueekHandler private handler;

    function setUp() public {
        token = new Squeek();
        handler = new SqueekHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = SqueekHandler.move.selector;
        selectors[1] = SqueekHandler.approve.selector;
        selectors[2] = SqueekHandler.spend.selector;
        selectors[3] = SqueekHandler.rejectOverdraw.selector;
        selectors[4] = SqueekHandler.rejectOverAllowance.selector;
        selectors[5] = SqueekHandler.revoke.selector;
        selectors[6] = SqueekHandler.moveAll.selector;
        selectors[7] = SqueekHandler.roundTrip.selector;
        selectors[8] = SqueekHandler.rejectSpendOverBalance.selector;
        selectors[9] = SqueekHandler.rejectZeroAddress.selector;
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
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
        }
    }

    function invariant_MetadataNeverChanges() public view {
        assertEq(token.name(), "Squeek");
        assertEq(token.symbol(), "SQK");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev Every holder must still be able to transfer its entire balance after every random sequence.
    function afterInvariant() public {
        address recipient = makeAddr("invariant consolidation recipient");
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 amount = handler.expectedBalance(actor);
            vm.prank(actor);
            assertTrue(token.transfer(recipient, amount));
            assertEq(token.balanceOf(actor), 0);
        }
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        invariant_AllowancesMatchModel();
    }
}
