// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "solmate/test/utils/DSTestPlus.sol";
import "forge-std/console2.sol";
import "../src/PYUSDImplementation.sol";

contract AssetProtectionTokenTest is DSTestPlus {

    event AddressFrozen(address indexed addr);
    event AddressUnfrozen(address indexed addr);
    event FrozenAddressWiped(address indexed addr);
    event AssetProtectionRoleSet (
        address indexed oldAssetProtectionRole,
        address indexed newAssetProtectionRole
    );
    event SupplyDecreased(address indexed from, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    PYUSDImplementation public token;
    address public freezableAddress = address(1);
    address public otherAddress = address(2);
    uint256 public amount = 100;
    uint256 public approvalAmount = 40;

    function setUp() public {
        token = new PYUSDImplementation();
    }

    function _beforeProtectableTokenTests() internal {
        // set assetProtectionRole
        token.setAssetProtectionRole(address(this));
    }

    function _beforeProtectableTokenWhenAddressFrozenTests() internal {
        // set assetProtectionRole
        _beforeProtectableTokenTests();

        // unpause token
        token.unpause();

        // give the freezableAddress some tokens
        token.increaseSupply(amount);
        token.transfer(freezableAddress, amount);

        // approve otherAddress address to take some of those tokens from freezableAddress
        hevm.prank(freezableAddress);
        token.approve(otherAddress, approvalAmount);

        // approve freezableAddress address to take some of those tokens from otherAddress
        hevm.prank(otherAddress);
        token.approve(freezableAddress, approvalAmount);

        // freeze freezableAddress
        token.freeze(freezableAddress);
    }

    function _beforeProtectableTokenWhenAddressFrozenUnfreezeTests() internal {
        // set assetProtectionRole
        _beforeProtectableTokenTests();

        // unpause token
        token.unpause();

        // freeze freezableAddress
        token.freeze(freezableAddress);
    }

    function _beforeProtectableTokenWhenWipeFrozenAddressTests() internal {
        // set assetProtectionRole
        _beforeProtectableTokenTests();

        // unpause token
        token.unpause();

        // give the freezableAddress some tokens
        token.increaseSupply(amount);
        token.transfer(freezableAddress, amount);

        // freeze freezableAddress
        token.freeze(freezableAddress);
    }

    // when the asset protection role is unset, reverts asset protection actions
    function testAssetProtectionActionsRoleUnsetRevert() public {
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.freeze(freezableAddress);
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.unfreeze(freezableAddress);
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.wipeFrozenAddress(freezableAddress);
    }

    // after setting the AssetProtectionRole, the current asset protection role is set
    function testProtectableTokenAssetProtectionRoleSet() public {
        _beforeProtectableTokenTests();
        require(token.assetProtectionRole() == address(this), "assetProtectionRole improperly set");
    }

    // freeze reverts when sender is not asset protection
    function testProtectableTokenFreezeWhenNotAssetProtectorRevert() public {
        _beforeProtectableTokenTests();
        hevm.prank(otherAddress);
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.freeze(freezableAddress);
    }

    // freeze adds the frozen address
    function testProtectableTokenFreezeAddsFrozenAddress() public {
        _beforeProtectableTokenTests();
        token.freeze(freezableAddress);
        require(token.isFrozen(freezableAddress), "freeze didn't freeze address");
    }

    // freeze emits an AddressFrozen event
    function testProtectableTokenFreezeEmitsAddressFrozen() public {
        _beforeProtectableTokenTests();
        hevm.expectEmit(true, false, false, false);
        emit AddressFrozen(freezableAddress);
        token.freeze(freezableAddress);
    }

    // when address frozen, reverts when transfer is from frozen address
    function testProtectableTokenWhenFrozenTransferFrozenFromRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(freezableAddress);
        token.transfer(otherAddress, amount);
    }

    // when address frozen, reverts when transfer is to frozen address
    function testProtectableTokenWhenFrozenTransferFrozenToRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(otherAddress);
        token.transfer(freezableAddress, amount);
    }

    // when address frozen, reverts when transferFrom is by frozen address
    function testProtectableTokenWhenFrozenTransferFromFrozenByRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(freezableAddress);
        token.transferFrom(otherAddress, otherAddress, approvalAmount);
    }

    // when address frozen, reverts when transferFrom is from frozen address
    function testProtectableTokenWhenFrozenTransferFromFrozenFromRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(otherAddress);
        token.transferFrom(freezableAddress, otherAddress, approvalAmount);
    }

    // when address frozen, reverts when transferFrom is to frozen address
    function testProtectableTokenWhenFrozenTransferFromFrozenToRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(otherAddress);
        token.transferFrom(otherAddress, freezableAddress, approvalAmount);
    }

    // when address frozen, reverts when approve is from the frozen address
    function testProtectableTokenWhenFrozenApproveFrozenFromRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(freezableAddress);
        token.approve(otherAddress, approvalAmount);
    }

    // when address frozen, reverts when approve spender is the frozen address
    function testProtectableTokenWhenFrozenApproveFrozenSpenderRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(otherAddress);
        token.approve(freezableAddress, approvalAmount);
    }

    // when address frozen, reverts when increase approval is from the frozen address
    function testProtectableTokenWhenFrozenIncreaseApprovalFrozenFromRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(freezableAddress);
        token.increaseApproval(otherAddress, approvalAmount);
    }

    // when address frozen, reverts when increase approve spender is the frozen address
    function testProtectableTokenWhenFrozenIncreaseApprovalFrozenSpenderRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(otherAddress);
        token.increaseApproval(freezableAddress, approvalAmount);
    }

    // when address frozen, reverts when decrease approval is from the frozen address
    function testProtectableTokenWhenFrozenDecreaseApprovalFrozenFromRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(freezableAddress);
        token.decreaseApproval(otherAddress, approvalAmount);
    }

    // when address frozen, reverts when decrease approval spender is the frozen address
    function testProtectableTokenWhenFrozenDecreaseApprovalFrozenSpenderRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(otherAddress);
        token.decreaseApproval(freezableAddress, approvalAmount);
    }

    // when address frozen, reverts when address is already frozen
    function testProtectableTokenWhenFrozenFreezeRevert() public {
        _beforeProtectableTokenWhenAddressFrozenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        token.freeze(freezableAddress);
    }

    // when address unfrozen, reverts when address is already unfrozen
    function testProtectableTokenWhenUnfrozenUnfreezeRevert() public {
        _beforeProtectableTokenTests();
        hevm.expectRevert(PYUSDImplementation.NotFrozen.selector);
        token.unfreeze(freezableAddress);
    }

    // when address unfrozen, reverts when sender is not asset protection
    function testProtectableTokenWhenUnfrozenNotAssetProtectorRevert() public {
        _beforeProtectableTokenWhenAddressFrozenUnfreezeTests();
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        hevm.prank(otherAddress);
        token.unfreeze(freezableAddress);
    }

    // when address unfrozen, unfreeze removes a frozen address
    function testProtectableTokenWhenUnfrozenRemovesAddress() public {
        _beforeProtectableTokenWhenAddressFrozenUnfreezeTests();
        token.unfreeze(freezableAddress);
        require(!token.isFrozen(freezableAddress), "unfreeze error");
    }

    // when address unfrozen, unfrozen address can transfer again
    function testProtectableTokenWhenUnfrozenTransfer() public {
        _beforeProtectableTokenWhenAddressFrozenUnfreezeTests();
        token.unfreeze(freezableAddress);
        token.increaseSupply(amount);
        token.transfer(freezableAddress, amount);
        require(token.balanceOf(freezableAddress) == amount, "transfer balance error");
        hevm.prank(freezableAddress);
        token.transfer(address(this), amount);
        require(token.balanceOf(address(this)) == amount, "transfer back balance error");
    }

    // when address unfrozen, emits an AddressFrozen event
    function testProtectableTokenWhenUnfrozenEmitsAddressUnfrozen() public {
        _beforeProtectableTokenWhenAddressFrozenUnfreezeTests();
        hevm.expectEmit(true, false, false, false);
        emit AddressUnfrozen(freezableAddress);
        token.unfreeze(freezableAddress);
    }

    // when calling wipeFrozenAddress, reverts when address is not frozen
    function testProtectableTokenWhenWipeFrozenAddressNotFrozenRevert() public {
        _beforeProtectableTokenTests();
        hevm.expectRevert(PYUSDImplementation.NotFrozen.selector);
        token.wipeFrozenAddress(freezableAddress);
    }

    // when calling wipeFrozenAddress after freeze and approvals, reverts when sender is not asset protection
    function testProtectableTokenWhenWipeFrozenAddressNotAssetProtectorRevert() public {
        _beforeProtectableTokenWhenWipeFrozenAddressTests();
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        hevm.prank(otherAddress);
        token.wipeFrozenAddress(freezableAddress);
    }

    // when calling wipeFrozenAddress after freeze and approvals, wipes a frozen address balance
    function testProtectableTokenWhenWipeFrozenAddressBalanceWiped() public {
        _beforeProtectableTokenWhenWipeFrozenAddressTests();
        token.wipeFrozenAddress(freezableAddress);
        require(token.isFrozen(freezableAddress), "address no longer frozen");
        require(token.balanceOf(freezableAddress) == 0, "balance wasn't wiped");
    }

    // when calling wipeFrozenAddress after freeze and approvals, emits an FrozenAddressWiped event
    function testProtectableTokenWhenWipeFrozenAddressEmitsFrozenAddressWiped() public {
        _beforeProtectableTokenWhenWipeFrozenAddressTests();
        hevm.expectEmit(true, false, false, false);
        emit FrozenAddressWiped(freezableAddress);
        hevm.expectEmit(true, false, false, false);
        emit SupplyDecreased(freezableAddress, amount);
        token.wipeFrozenAddress(freezableAddress);
        require(token.balanceOf(freezableAddress) == 0, "wipeFrozenAddress didn't wipe balance");
    }

    // when calling setAssetProtectionRole, reverts if sender is not owner or AssetProtectionRole
    function testProtectableTokenWhenSetAssetProtectionRoleNotPrivilegedSenderRevert() public {
        _beforeProtectableTokenTests();
        hevm.expectRevert(PYUSDImplementation.NotOwnerOrAssetProtector.selector);
        hevm.prank(otherAddress);
        token.setAssetProtectionRole(otherAddress);
    }

    // when calling setAssetProtectionRole, works if sender is AssetProtectionRole
    function testProtectableTokenWhenSetAssetProtectionRoleAssetProtectorCanSet() public {
        _beforeProtectableTokenTests();
        token.setAssetProtectionRole(otherAddress);
        require(token.assetProtectionRole() == otherAddress, "asset protector couldn't set role to another address");
    }

    // when calling setAssetProtectionRole, enables new AssetProtectionRole to freeze
    function testProtectableTokenWhenSetAssetProtectionRoleNewAssetProtectorCanFreeze() public {
        _beforeProtectableTokenTests();
        token.setAssetProtectionRole(otherAddress);
        hevm.prank(otherAddress);
        token.freeze(freezableAddress);
        require(token.isFrozen(freezableAddress), "new asset protector couldn't freeze address");
    }

    // when calling setAssetProtectionRole, revert if AssetProtectionRole is set to the same AssetProtectionRole
    function testProtectableTokenWhenSetAssetProtectionRoleSameAddressRevert() public {
        _beforeProtectableTokenTests();
        token.setAssetProtectionRole(otherAddress);
        hevm.expectRevert(PYUSDImplementation.SameAddress.selector);
        token.setAssetProtectionRole(otherAddress);
    }

    // when calling setAssetProtectionRole, prevents old AssetProtectionRole from freezing
    function testProtectableTokenWhenSetAssetProtectionRoleOldAssetProtectorCantFreeze() public {
        _beforeProtectableTokenTests();
        token.setAssetProtectionRole(otherAddress);
        hevm.startPrank(otherAddress);
        token.setAssetProtectionRole(address(this));
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.freeze(freezableAddress);
    }

    // when calling setAssetProtectionRole, emits a AssetProtectionRoleSet event
    function testProtectableTokenWhenSetAssetProtectionRoleEmitsAssetProtectionRoleSet() public {
        _beforeProtectableTokenTests();
        hevm.expectEmit(true, true, false, false);
        emit AssetProtectionRoleSet(address(this), otherAddress);
        token.setAssetProtectionRole(otherAddress);
    }
}