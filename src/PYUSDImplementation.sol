// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Upgraded to OpenZeppelin v4.9.0
import "openzeppelin/access/Ownable2StepUpgradeable.sol";
import "openzeppelin/utils/math/SafeMathUpgradeable.sol";
import "openzeppelin/security/PausableUpgradeable.sol";
import "solady/tokens/ERC20.sol";

/**
 * @title PYUSDImplementation
 * @dev this contract is a Pausable ERC20 token with Burn and Mint
 * controlled by a central SupplyController. By implementing PYUSDImplementation
 * this contract also includes external methods for setting
 * a new implementation contract for the Proxy.
 * NOTE: The storage defined here will actually be held in the Proxy
 * contract and all calls to this contract should be made through
 * the proxy, including admin actions done as owner or supplyController.
 * Any call to transfer against this contract should fail
 * with insufficient funds since no tokens will be issued there.
 */
contract PYUSDImplementation is ERC20, PausableUpgradeable, Ownable2StepUpgradeable {

    /**
     * MATH
     */

    using SafeMathUpgradeable for uint256;

    /**
     * DATA
     */

    // ASSET PROTECTION DATA
    address public assetProtectionRole;
    mapping(address => bool) internal _frozen;

    // SUPPLY CONTROL DATA
    address public supplyController;

    // OWNER DATA
    address public proposedOwner;

    // DELEGATED TRANSFER DATA
    address public betaDelegateWhitelister;
    mapping(address => bool) internal _betaDelegateWhitelist;
    mapping(address => uint256) internal _nextSeqs;
    // EIP191 header for EIP712 prefix
    string constant internal _EIP191_HEADER = "\x19\x01";
    // Hash of the EIP712 Domain Separator Schema
    bytes32 constant internal _EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH = keccak256(
        "EIP712Domain(string name,address verifyingContract)"
    );
    bytes32 constant internal _EIP712_DELEGATED_TRANSFER_SCHEMA_HASH = keccak256(
        "BetaDelegatedTransfer(address to,uint256 value,uint256 fee,uint256 seq,uint256 deadline)"
    );
    // Hash of the EIP712 Domain Separator data
    // solhint-disable-next-line var-name-mixedcase
    bytes32 public EIP712_DOMAIN_HASH;

    /**
     * EVENTS
     */

    // OWNABLE EVENTS
    event OwnershipTransferDisregarded(
        address indexed oldProposedOwner
    );

    // ASSET PROTECTION EVENTS
    event AddressFrozen(address indexed addr);
    event AddressUnfrozen(address indexed addr);
    event FrozenAddressWiped(address indexed addr);
    event AssetProtectionRoleSet (
        address indexed oldAssetProtectionRole,
        address indexed newAssetProtectionRole
    );

    // SUPPLY CONTROL EVENTS
    event SupplyIncreased(address indexed to, uint256 value);
    event SupplyDecreased(address indexed from, uint256 value);
    event SupplyControllerSet(
        address indexed oldSupplyController,
        address indexed newSupplyController
    );

    // DELEGATED TRANSFER EVENTS
    event BetaDelegatedTransfer(
        address indexed from, address indexed to, uint256 value, uint256 seq, uint256 fee
    );
    event BetaDelegateWhitelisterSet(
        address indexed oldWhitelister,
        address indexed newWhitelister
    );
    event BetaDelegateWhitelisted(address indexed newDelegate);
    event BetaDelegateUnwhitelisted(address indexed oldDelegate);

    /**
     * ERRORS
     */

    error NotBetaDelegateWhitelister();
    error NotOwnerOrSupplyController();
    error NotOwnerOrAssetProtector();
    error NotOwnerOrProposedOwner();
    error NotWhitelistedDelegate();
    error NotOwnerOrWhitelister();
    error NotSupplyController();
    error ErrorDerivingSender();
    error TransactionExpired();
    error NotAssetProtector();
    error InsufficientFunds();
    error NoProposedOwner();
    error LengthMismatch();
    error NotWhitelisted();
    error IncorrectSeq();
    error SigIncorrect();
    error Whitelisted();
    error SameAddress();
    error ZeroAddress();
    error ZeroValues();
    error SigLength();
    error NotFrozen();
    error Frozen();

    /**
     * FUNCTIONALITY
     */

    // INITIALIZATION FUNCTIONALITY

    /**
     * @dev sets 0 initials tokens, the owner, and the supplyController.
     * this serves as the constructor for the proxy but compiles to the
     * memory model of the Implementation contract.
     */
    function initialize() public initializer {
        assetProtectionRole = address(0);
        supplyController = msg.sender;
        _initializeDomainSeparator();
        __Ownable2Step_init();
        __Pausable_init();
    }

    /**
     * The constructor is used here to ensure that the implementation
     * contract is initialized. An uncontrolled implementation
     * contract might lead to misleading state
     * for users who accidentally interact with it.
     */
    constructor() payable {
        initialize();
        pause();
    }

    /**
     * @dev To be called when upgrading the contract using upgradeAndCall to add delegated transfers
     */
    function _initializeDomainSeparator() private onlyInitializing {
        // hash the name context with the contract address
        EIP712_DOMAIN_HASH = keccak256(abi.encodePacked(// solium-disable-line
                _EIP712_DOMAIN_SEPARATOR_SCHEMA_HASH,
                keccak256(bytes(name())),
                bytes32(uint256(uint160(address(this))))
            ));
    }

    // ERC20 BASIC FUNCTIONALITY

    /**
    * @dev Token Name
    */
    function name() public pure override returns (string memory) { return "PayPal USD"; }

    /**
    * @dev Token Symbol
    */
    function symbol() public pure override returns (string memory) { return "PYUSD"; }

    /**
    * @dev Token Decimals
    */
    function decimals() public pure override returns (uint8) { return 6; }

    /**
    * @dev Transfer token to a specified address from msg.sender
    * Note: the use of Safemath ensures that _value is nonnegative.
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint256 _value) public override whenNotPaused returns (bool) {
        if (_to == address(0)) { revert ZeroAddress(); }
        if (_frozen[_to] || _frozen[msg.sender]) { revert Frozen(); }
        return super.transfer(_to, _value);
    }

    // ERC20 FUNCTIONALITY

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public override whenNotPaused returns (bool) {
        if (_to == address(0)) { revert ZeroAddress(); }
        if (_frozen[_to] || _frozen[_from] || _frozen[msg.sender]) { revert Frozen(); }
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
     * Beware that changing an allowance with this method brings the risk that someone may use both the old
     * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
     * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     * @param _spender The address which will spend the funds.
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value) public override whenNotPaused returns (bool) {
        if (_frozen[_spender] || _frozen[msg.sender]) { revert Frozen(); }
        return super.approve(_spender, _value);
    }

    /**
     * @dev Increase the amount of tokens that an owner allowed to a spender.
     *
     * To increment allowed value is better to use this function to avoid 2 calls (and wait until the first transaction
     * is mined) instead of approve.
     * @param _spender The address which will spend the funds.
     * @param _addedValue The amount of tokens to increase the allowance by.
     */
    function increaseApproval(address _spender, uint _addedValue) public whenNotPaused returns (bool) {
        if (_frozen[_spender] || _frozen[msg.sender]) { revert Frozen(); }
        return increaseAllowance(_spender, _addedValue);
    }

    /**
     * @dev Decrease the amount of tokens that an owner allowed to a spender.
     *
     * To decrement allowed value is better to use this function to avoid 2 calls (and wait until the first transaction
     * is mined) instead of approve.
     * @param _spender The address which will spend the funds.
     * @param _subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseApproval(address _spender, uint _subtractedValue) public whenNotPaused returns (bool) {
        if (_frozen[_spender] || _frozen[msg.sender]) { revert Frozen(); }
        uint oldValue = allowance(msg.sender, _spender);
        if (_subtractedValue > oldValue) {
            _approve(msg.sender, _spender, 0);
        } else {
            return decreaseAllowance(_spender, _subtractedValue);
        }
        return true;
    }

    // OWNER FUNCTIONALITY
    
    /**
     * @dev Allows the current owner or proposed owner to cancel transferring control of the contract to a proposedOwner
     */
    function disregardProposedOwner() public {
        if (msg.sender != proposedOwner || msg.sender != owner()) { revert NotOwnerOrProposedOwner(); }
        if (proposedOwner == address(0)) { revert NoProposedOwner(); }
        address _oldProposedOwner = proposedOwner;
        proposedOwner = address(0);
        transferOwnership(address(0));
        emit OwnershipTransferDisregarded(_oldProposedOwner);
    }

    /**
     * @dev Reclaim all PYUSD at the contract address.
     * This sends the PYUSD tokens that this contract add holding to the owner.
     * Note: this is not affected by freeze constraints.
     */
    function reclaimPYUSD() external onlyOwner {
        _transfer(address(this), owner(), balanceOf(address(this)));
    }

    // PAUSABILITY FUNCTIONALITY

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() public onlyOwner whenNotPaused { _pause(); }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() public onlyOwner whenPaused { _unpause(); }

    // ASSET PROTECTION FUNCTIONALITY

    /**
     * @dev Sets a new asset protection role address.
     * @param _newAssetProtectionRole The new address allowed to freeze/unfreeze addresses and seize their tokens.
     */
    function setAssetProtectionRole(address _newAssetProtectionRole) public {
        address assetProtector = assetProtectionRole;
        if (msg.sender != assetProtector && msg.sender != owner()) { revert NotOwnerOrAssetProtector(); }
        if (assetProtector == _newAssetProtectionRole) { revert SameAddress(); }
        emit AssetProtectionRoleSet(assetProtector, _newAssetProtectionRole);
        assetProtectionRole = _newAssetProtectionRole;
    }

    modifier onlyAssetProtectionRole() {
        if (msg.sender != assetProtectionRole) { revert NotAssetProtector(); }
        _;
    }

    /**
     * @dev Freezes an address balance from being transferred.
     * @param _addr The new address to freeze.
     */
    function freeze(address _addr) public onlyAssetProtectionRole {
        if (_frozen[_addr]) { revert Frozen(); }
        _frozen[_addr] = true;
        emit AddressFrozen(_addr);
    }

    /**
     * @dev Unfreezes an address balance allowing transfer.
     * @param _addr The new address to unfreeze.
     */
    function unfreeze(address _addr) public onlyAssetProtectionRole {
        if (!_frozen[_addr]) { revert NotFrozen(); }
        _frozen[_addr] = false;
        emit AddressUnfrozen(_addr);
    }

    /**
     * @dev Wipes the balance of a frozen address, and burns the tokens.
     * @param _addr The new frozen address to wipe.
     */
    function wipeFrozenAddress(address _addr) public onlyAssetProtectionRole {
        if (!_frozen[_addr]) { revert NotFrozen(); }
        uint256 balance = balanceOf(_addr);
        _burn(_addr, balance);
        emit FrozenAddressWiped(_addr);
        emit SupplyDecreased(_addr, balance);
    }

    /**
    * @dev Gets whether the address is currently frozen.
    * @param _addr The address to check if frozen.
    * @return A bool representing whether the given address is frozen.
    */
    function isFrozen(address _addr) public view returns (bool) {
        return _frozen[_addr];
    }

    // SUPPLY CONTROL FUNCTIONALITY

    /**
     * @dev Sets a new supply controller address.
     * @param _newSupplyController The address allowed to burn/mint tokens to control supply.
     */
    function setSupplyController(address _newSupplyController) public {
        address _supplyController = supplyController;
        if (msg.sender != _supplyController || msg.sender != owner()) { revert NotOwnerOrSupplyController(); }
        if (_newSupplyController == address(0)) { revert ZeroAddress(); }
        if (_newSupplyController == _supplyController) { revert SameAddress(); }
        emit SupplyControllerSet(_supplyController, _newSupplyController);
        supplyController = _newSupplyController;
    }

    modifier onlySupplyController() {
        if (msg.sender != supplyController) { revert NotSupplyController(); }
        _;
    }

    /**
     * @dev Increases the total supply by minting the specified number of tokens to the supply controller account.
     * @param _value The number of tokens to add.
     * @return success A boolean that indicates if the operation was successful.
     */
    function increaseSupply(uint256 _value) public onlySupplyController returns (bool success) {
        _mint(supplyController, _value);
        emit SupplyIncreased(supplyController, _value);
        success = true;
    }

    /**
     * @dev Decreases the total supply by burning the specified number of tokens from the supply controller account.
     * @param _value The number of tokens to remove.
     * @return success A boolean that indicates if the operation was successful.
     */
    function decreaseSupply(uint256 _value) public onlySupplyController returns (bool success) {
        _burn(supplyController, _value);
        emit SupplyDecreased(supplyController, _value);
        success = true;
    }

    // DELEGATED TRANSFER FUNCTIONALITY

    /**
     * @dev returns the next seq for a target address.
     * The transactor must submit nextSeqOf(transactor) in the next transaction for it to be valid.
     * Note: that the seq context is specific to this smart contract.
     * @param target The target address.
     * @return the seq.
     */
    //
    function nextSeqOf(address target) public view returns (uint256) {
        return _nextSeqs[target];
    }

    /**
     * @dev Performs a transfer on behalf of the from address, identified by its signature on the delegatedTransfer msg.
     * Splits a signature byte array into r,s,v for convenience.
     * @param sig the signature of the delgatedTransfer msg.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @param fee an optional ERC20 fee paid to the executor of betaDelegatedTransfer by the from address.
     * @param seq a sequencing number included by the from address specific to this contract to protect from replays.
     * @param deadline a block number after which the pre-signed transaction has expired.
     * @return A boolean that indicates if the operation was successful.
     */
    function betaDelegatedTransfer(
        bytes memory sig,
        address to,
        uint256 value,
        uint256 fee,
        uint256 seq,
        uint256 deadline
    ) public returns (bool) {
        if (sig.length != 65) { revert SigLength(); }
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        _betaDelegatedTransfer(r, s, v, to, value, fee, seq, deadline);
        return true;
    }

    /**
     * @dev Performs a transfer on behalf of the from address, identified by its signature on the betaDelegatedTransfer msg.
     * Note: both the delegate and transactor sign in the fees. The transactor, however,
     * has no control over the gas price, and therefore no control over the transaction time.
     * Beta prefix chosen to avoid a name clash with an emerging standard in ERC865 or elsewhere.
     * Internal to the contract - see betaDelegatedTransfer and betaDelegatedTransferBatch.
     * @param r the r signature of the delgatedTransfer msg.
     * @param s the s signature of the delgatedTransfer msg.
     * @param v the v signature of the delgatedTransfer msg.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @param fee an optional ERC20 fee paid to the delegate of betaDelegatedTransfer by the from address.
     * @param seq a sequencing number included by the from address specific to this contract to protect from replays.
     * @param deadline a block number after which the pre-signed transaction has expired.
     * @return A boolean that indicates if the operation was successful.
     */
    function _betaDelegatedTransfer(
        bytes32 r,
        bytes32 s,
        uint8 v,
        address to,
        uint256 value,
        uint256 fee,
        uint256 seq,
        uint256 deadline
    ) internal whenNotPaused returns (bool) {
        if (!_betaDelegateWhitelist[msg.sender]) { revert NotWhitelistedDelegate(); }
        if (value == 0 && fee == 0) { revert ZeroValues(); }
        if (block.number > deadline) { revert TransactionExpired(); }
        // prevent sig malleability from ecrecover()
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) { revert SigIncorrect(); }
        if (v != 27 && v != 28) { revert SigIncorrect(); }

        // EIP712 scheme: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md
        bytes32 delegatedTransferHash = keccak256(abi.encodePacked(// solium-disable-line
                _EIP712_DELEGATED_TRANSFER_SCHEMA_HASH, bytes32(uint256(uint160(to))), value, fee, seq, deadline
            ));
        bytes32 hash = keccak256(abi.encodePacked(_EIP191_HEADER, EIP712_DOMAIN_HASH, delegatedTransferHash));
        address _from = ecrecover(hash, v, r, s);

        if (_from == address(0)) { revert ErrorDerivingSender(); }
        if (to == address(0)) { revert ZeroAddress(); }
        if (_frozen[to] || _frozen[_from] || _frozen[msg.sender]) { revert Frozen(); }
        if (value.add(fee) > balanceOf(_from)) { revert InsufficientFunds(); }
        if (_nextSeqs[_from] != seq) { revert IncorrectSeq(); }

        _nextSeqs[_from] = _nextSeqs[_from].add(1);
        if (fee != 0) {
            _transfer(_from, msg.sender, fee);
            _transfer(_from, to, value);
        } else {
            _transfer(_from, to, value);
        }

        emit BetaDelegatedTransfer(_from, to, value, seq, fee);
        return true;
    }

    /**
     * @dev Performs an atomic batch of transfers on behalf of the from addresses, identified by their signatures.
     * Lack of nested array support in arguments requires all arguments to be passed as equal size arrays where
     * delegated transfer number i is the combination of all arguments at index i
     * @param r the r signatures of the delgatedTransfer msg.
     * @param s the s signatures of the delgatedTransfer msg.
     * @param v the v signatures of the delgatedTransfer msg.
     * @param to The addresses to transfer to.
     * @param value The amounts to be transferred.
     * @param fee optional ERC20 fees paid to the delegate of betaDelegatedTransfer by the from address.
     * @param seq sequencing numbers included by the from address specific to this contract to protect from replays.
     * @param deadline block numbers after which the pre-signed transactions have expired.
     * @return A boolean that indicates if the operation was successful.
     */
    function betaDelegatedTransferBatch(
        bytes32[] memory r,
        bytes32[] memory s,
        uint8[] memory v,
        address[] memory to,
        uint256[] memory value,
        uint256[] memory fee,
        uint256[] memory seq,
        uint256[] memory deadline
    ) public returns (bool) {
        if (r.length != s.length || r.length != v.length || r.length != to.length || r.length != value.length) { revert LengthMismatch(); }
        if (r.length != fee.length || r.length != seq.length || r.length != deadline.length) { revert LengthMismatch(); }
        
        for (uint i = 0; i < r.length; i++) {
            _betaDelegatedTransfer(r[i], s[i], v[i], to[i], value[i], fee[i], seq[i], deadline[i]);
        }
        return true;
    }

    /**
    * @dev Gets whether the address is currently whitelisted for betaDelegateTransfer.
    * @param _addr The address to check if whitelisted.
    * @return A bool representing whether the given address is whitelisted.
    */
    function isWhitelistedBetaDelegate(address _addr) public view returns (bool) {
        return _betaDelegateWhitelist[_addr];
    }

    /**
     * @dev Sets a new betaDelegate whitelister.
     * @param _newWhitelister The address allowed to whitelist betaDelegates.
     */
    function setBetaDelegateWhitelister(address _newWhitelister) public {
        address whitelister = betaDelegateWhitelister;
        if (msg.sender != whitelister && msg.sender != owner()) { revert NotOwnerOrWhitelister(); }
        if (whitelister == _newWhitelister) { revert SameAddress(); }
        betaDelegateWhitelister = _newWhitelister;
        emit BetaDelegateWhitelisterSet(whitelister, _newWhitelister);
    }

    modifier onlyBetaDelegateWhitelister() {
        if (msg.sender != betaDelegateWhitelister) { revert NotBetaDelegateWhitelister(); }
        _;
    }

    /**
     * @dev Whitelists an address to allow calling BetaDelegatedTransfer.
     * @param _addr The new address to whitelist.
     */
    function whitelistBetaDelegate(address _addr) public onlyBetaDelegateWhitelister {
        if (_betaDelegateWhitelist[_addr]) { revert Whitelisted(); }
        _betaDelegateWhitelist[_addr] = true;
        emit BetaDelegateWhitelisted(_addr);
    }

    /**
     * @dev Unwhitelists an address to disallow calling BetaDelegatedTransfer.
     * @param _addr The new address to whitelist.
     */
    function unwhitelistBetaDelegate(address _addr) public onlyBetaDelegateWhitelister {
        if (!_betaDelegateWhitelist[_addr]) { revert NotWhitelisted(); }
        _betaDelegateWhitelist[_addr] = false;
        emit BetaDelegateUnwhitelisted(_addr);
    }
}
