// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "../src/Squeek.sol";

/// @dev An actual contract caller, so the token must authorize this address rather than tx.origin.
contract SqueekSpendingHarness {
    function spend(Squeek token, address owner, address recipient, uint256 amount) external returns (bool) {
        return token.transferFrom(owner, recipient, amount);
    }

    fallback() external {
        revert("ERC20 transfers must not call the recipient");
    }
}

/// @dev Complements SqueekTest with allowance transitions, recovery after rejection, and algebraic properties.
/// forge-config: default.fuzz.runs = 1024
contract SqueekEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    Squeek private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new Squeek();
        alice = makeAddr("edge alice");
        bob = makeAddr("edge bob");
        spender = makeAddr("edge spender");
    }

    function test_MaximumDirectTransferRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumDelegatedTransferPreservesInfiniteAllowanceOnFailure() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevokingInfiniteApprovalProtectsRefilledBalance() public {
        assertTrue(token.transfer(alice, SUPPLY));
        _approve(alice, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY));
        assertEq(token.allowance(alice, spender), type(uint256).max);

        _approve(alice, 0);
        vm.prank(bob);
        assertTrue(token.transfer(alice, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DowngradingInfiniteApprovalEnforcesNewLimit() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_SelfTransferCannotBypassBalanceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DelegatedSelfTransferCannotBypassBalanceCheck() public {
        assertTrue(token.approve(spender, SUPPLY + 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroAddressGuardsApplyEvenToZeroAmounts() public {
        // These pranks exercise explicit input guards; no production caller is assigned the zero address.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ContractSpenderCannotUseOwnersTransactionOrigin() public {
        SqueekSpendingHarness intermediary = new SqueekSpendingHarness();
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(intermediary), 0, 1)
        );
        vm.prank(alice, alice);
        intermediary.spend(token, alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(alice);
        assertTrue(token.approve(address(intermediary), 1));
        vm.prank(alice, alice);
        assertTrue(intermediary.spend(token, alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, address(intermediary)), 0);
    }

    function test_ContractRecipientNeedsNoCallback() public {
        SqueekSpendingHarness recipient = new SqueekSpendingHarness();
        assertTrue(token.transfer(address(recipient), 1));
        assertTrue(token.approve(spender, SUPPLY - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(recipient), SUPPLY - 1));
        assertEq(token.balanceOf(address(recipient)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceFailureCanBeRetriedAfterFunding(uint256 rawBalance, uint256 rawAmount, bool unlimited)
        public
    {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, balance + 1, SUPPLY);
        assertTrue(token.transfer(alice, balance));
        uint256 approved = unlimited ? type(uint256).max : amount;
        _approve(alice, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        // The exact same request must succeed once only its missing balance is supplied.
        assertTrue(token.transfer(alice, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidRecipientPreservesAnyAllowance(uint256 approved, uint256 rawAmount) public {
        uint256 limit = approved < SUPPLY ? approved : SUPPLY;
        uint256 amount = bound(rawAmount, 0, limit);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RepeatedRoundTripsRestoreBalances(uint256 rawAmount, uint8 rawCycles) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 cycles = bound(uint256(rawCycles), 2, 8);
        for (uint256 i; i < cycles; ++i) {
            assertTrue(token.transfer(alice, amount));
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            vm.prank(alice);
            assertTrue(token.transfer(address(this), amount));
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_SplitDelegatedTransfersEqualSingleSpend(
        uint256 rawApproved,
        uint256 rawAmount,
        uint256 rawFirst,
        bool unlimited
    ) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 first = bound(rawFirst, 0, amount);
        uint256 approved = unlimited ? type(uint256).max : bound(rawApproved, amount, type(uint256).max - 1);
        Squeek single = new Squeek();
        assertTrue(token.approve(spender, approved));
        assertTrue(single.approve(spender, approved));

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        vm.prank(spender);
        assertTrue(single.transferFrom(address(this), alice, amount));

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), unlimited ? approved : approved - amount);
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndScoped(uint256 oldAmount, uint256 newAmount) public {
        _approve(alice, oldAmount);
        vm.prank(alice);
        assertTrue(token.approve(bob, oldAmount));
        _approve(bob, oldAmount);
        _approve(alice, newAmount);
        _approve(alice, newAmount);
        assertEq(token.allowance(alice, spender), newAmount);
        assertEq(token.allowance(alice, bob), oldAmount);
        assertEq(token.allowance(bob, spender), oldAmount);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroDelegatedTransferPreservesAnyAllowance(uint256 approved, bool self) public {
        _approve(alice, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, self ? alice : bob, 0));
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(address owner, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }
}
