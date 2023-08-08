// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "solmate/test/utils/DSTestPlus.sol";
import "forge-std/console2.sol";
import "../src/PYUSDImplementation.sol";

contract AssetProtectionTokenTest is DSTestPlus {

    event AddressFrozen(address indexed addr);

    PYUSDImplementation public token;
    address freezableAddress = address(1);
    address otherAddress = address(2);
    uint256 amount = 100;
    uint256 approvalAmount = 40;

    function setUp() public {
        token = new PYUSDImplementation();
    }

    function _beforeProtectableTokenTests() internal {
        // set assetProtectionRole
        token.setAssetProtectionRole(address(this));
    }

    function _beforeProtectableFreezeWhenFrozenTokenTests() internal {
        // set assetProtectionRole
        token.setAssetProtectionRole(address(this));

        // fund contract owner with tokens
        token.increaseSupply(amount);

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

    // when the asset protection role is unset, reverts asset protection actions
    function testAssetProtectionActionsRoleUnsetRevert() public {
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.freeze(freezableAddress);
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.unfreeze(freezableAddress);
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.wipeFrozenAddress(freezableAddress);
    }

    // as an asset protectable token, after setting the AssetProtectionRole, the current asset protection role is set
    function testProtectableTokenAssetProtectionRoleSet() public {
        _beforeProtectableTokenTests();
        require(token.assetProtectionRole() == address(this), "assetProtectionRole improperly set");
    }

    // as an asset protectable token, freeze reverts when sender is not asset protection
    function testProtectableTokenFreezeRevertWhenNotAssetProtector() public {
        _beforeProtectableTokenTests();
        hevm.prank(otherAddress);
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.freeze(freezableAddress);
    }

    // as an asset protectable token, freeze adds the frozen address
    function testProtectableTokenFreezeAddsFrozenAddress() public {
        _beforeProtectableTokenTests();
        token.freeze(freezableAddress);
        require(token.isFrozen(freezableAddress), "freeze didn't freeze address");
    }

    // as an asset protectable token, freeze emits an AddressFrozen event
    function testProtectableTokenFreezeEmitsAddressFrozen() public {
        _beforeProtectableTokenTests();
        hevm.expectEmit(true, false, false, false);
        emit AddressFrozen(freezableAddress);
        token.freeze(freezableAddress);
    }

    // as an asset protectable token, freeze when frozen reverts when transfer is from frozen address
    function testProtectableTokenWhenFrozenTransferFrozenFromRevert() public {
        _beforeProtectableFreezeWhenFrozenTokenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(freezableAddress);
        token.transfer(otherAddress, amount);
    }

    // as an asset protectable token, freeze when frozen reverts when transfer is to frozen address
    function testProtectableTokenWhenFrozenTransferFrozenToRevert() public {
        _beforeProtectableFreezeWhenFrozenTokenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        token.transfer(freezableAddress, amount);
    }

    // as an asset protectable token, freeze when frozen reverts when transferFrom is by frozen address
    function testProtectableTokenWhenFrozenTransferFromFrozenFromRevert() public {
        _beforeProtectableFreezeWhenFrozenTokenTests();
        hevm.expectRevert(PYUSDImplementation.Frozen.selector);
        hevm.prank(freezableAddress);
        token.transferFrom(otherAddress, otherAddress, approvalAmount);
    }
}