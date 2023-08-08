// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "solmate/test/utils/DSTestPlus.sol";
import "forge-std/console2.sol";
import "../src/PYUSDImplementation.sol";

contract AssetProtectionTokenTest is DSTestPlus {

    PYUSDImplementation public token;

    function setUp() public {
        token = new PYUSDImplementation();
    }

    function _beforeProtectableTokenTests() internal {
        hevm.prank(address(this));
        token.setAssetProtectionRole(msg.sender);
    }

    function testAssetProtectionActionsRoleUnsetRevert() public {
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.freeze(address(1));
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.unfreeze(address(1));
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.wipeFrozenAddress(address(1));
    }

    function testProtectableTokenAssetProtectionRoleSet() public {
        _beforeProtectableTokenTests();
        require(token.assetProtectionRole() == msg.sender, "assetProtectionRole improperly set");
    }

    function testProtectableTokenFreezeRevertWhenNotAssetProtector() public {
        _beforeProtectableTokenTests();
        hevm.prank(address(1));
        hevm.expectRevert(PYUSDImplementation.NotAssetProtector.selector);
        token.freeze(address(2));
    }

    function testProtectableTokenFreezeAddsFrozenAddress() public {
        _beforeProtectableTokenTests();
        console2.log(msg.sender);
        console2.log(token.assetProtectionRole());
        token.freeze(address(1));
        require(token.isFrozen(address(1)), "freeze didn't freeze address");
    }
}