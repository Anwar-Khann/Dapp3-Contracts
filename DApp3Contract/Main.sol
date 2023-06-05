// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./IPinkLock.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./FullMath.sol";
import "./ISnipeFinanceMultisenders.sol";

contract Contract is IPinkLock, Pausable, Ownable {
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    // new code 10/jan
    uint256 public lockFee;
    uint256 public vestFee;
    address public receiver;
    uint256 public feeamounts;

    struct Lock {
        uint256 id;
        address token;
        address owner;
        uint256 amount;
        uint256 lockDate;
        uint256 tgeDate; // TGE date for vesting locks, unlock date for normal locks
        uint256 tgeBps; // In bips. Is 0 for normal locks
        uint256 cycle; // Is 0 for normal locks
        uint256 cycleBps; // In bips. Is 0 for normal locks
        uint256 unlockedAmount;
        string description;
    }
    // new code start
    struct BNBLock {
        uint256 id;
        address owner;
        uint256 amount;
        uint256 lockDate;
        uint256 tgeDate; // TGE date for vesting locks, unlock date for normal locks
        uint256 tgeBps; // In bips. Is 0 for normal locks
        uint256 cycle; // Is 0 for normal locks
        uint256 cycleBps; // In bips. Is 0 for normal locks
        uint256 unlockedAmount;
        string description;
    }
    // uint256 BNBLockId = 0;
    // mapping(uint256 => BNBLock) private BNBData;
    // new code end

    struct CumulativeLockInfo {
        address token;
        address factory;
        uint256 amount;
    }

    // ID padding from PinkLock v1, as there is a lack of a pausing mechanism
    // as of now the lastest id from v1 is about 22K, so this is probably a safe padding value.
    uint256 private constant ID_PADDING = 1_000_000;

    Lock[] private _locks;
    // new code 16/Jan
    BNBLock[] private _BNBlocks;
    mapping(address => EnumerableSet.UintSet) private _userLpLockIds;
    mapping(address => EnumerableSet.UintSet) private _userNormalLockIds;
    // new code 16/Jan
    mapping(address => EnumerableSet.UintSet) private _userBnbLockIds;

    EnumerableSet.AddressSet private _lpLockedTokens;
    EnumerableSet.AddressSet private _normalLockedTokens;
    mapping(address => CumulativeLockInfo) public cumulativeLockInfo;
    mapping(address => EnumerableSet.UintSet) private _tokenToLockIds;
    // new code 16/Jan
    mapping(string => EnumerableSet.UintSet) private _bnbToLockIds;

    event LockAdded(
        uint256 indexed id,
        address token,
        address owner,
        uint256 amount,
        uint256 unlockDate
    );
    // new code
    event LockBNBAdded(
        uint256 indexed id,
        address owner,
        uint256 amount,
        uint256 unlockDate
    );
    event LockUpdated(
        uint256 indexed id,
        address token,
        address owner,
        uint256 newAmount,
        uint256 newUnlockDate
    );

    // new code 19/Jan
    event LockUpdatedBNB(
        uint256 indexed id,
        address owner,
        uint256 newAmount,
        uint256 newUnlockDate
    );

    event LockRemoved(
        uint256 indexed id,
        address token,
        address owner,
        uint256 amount,
        uint256 unlockedAt
    );
    // new code
    event LockBNBRemoved(
        uint256 indexed id,
        address owner,
        uint256 amount,
        uint256 unlockedAt
    );
    event LockVested(
        uint256 indexed id,
        address token,
        address owner,
        uint256 amount,
        uint256 total,
        uint256 timestamp
    );
    event LockVestedBNB(
        uint256 indexed id,
        address owner,
        uint256 amount,
        uint256 total,
        uint256 timestamp
    );

    event LockDescriptionChanged(uint256 lockId);
    event LockOwnerChanged(uint256 lockId, address owner, address newOwner);

    modifier validLock(uint256 lockId) {
        _getActualIndex(lockId);
        _;
    }
    // new code 16/Jan
    modifier validLockBNB(uint256 lockId) {
        _getActualIndexBNB(lockId);
        _;
    }
    ISnipeFinanceMultisenders public snipefinancemultisenders;

    constructor(address _snipefinancemultisenders) {
        snipefinancemultisenders = ISnipeFinanceMultisenders(
            _snipefinancemultisenders
        );
        lockFee = 0.001 ether;
        vestFee = 0.002 ether;
    }

    function setSnipeFinanceContract(address contractAddress)
        external
        onlyOwner
    {
        require(contractAddress != address(0), "Invalid address");
        snipefinancemultisenders = ISnipeFinanceMultisenders(contractAddress);
    }

    // new code
    function lock(
        address owner,
        address token,
        bool isLpToken,
        uint256 amount,
        uint256 unlockDate,
        string memory description
    ) external payable override returns (uint256 id) {
        require(token != address(0), "Invalid token");
        require(amount > 0, "Amount should be greater than 0");
        require(unlockDate > block.timestamp, "Please set a valid Unlock Date");
        if (snipefinancemultisenders.readAuthorizedUsers(msg.sender) == false) {
            require(msg.value >= lockFee, "You have to pay fee for locking"); //TAKE FEE IF NOT AUTHORIZED
            feeamounts += lockFee;
            payable(receiver).transfer(lockFee);
        }

        id = _createLock(
            owner,
            token,
            isLpToken,
            amount,
            unlockDate,
            0,
            0,
            0,
            description
        );
        _safeTransferFromEnsureExactAmount(
            token,
            msg.sender,
            address(this),
            amount
        );
        emit LockAdded(id, token, owner, amount, unlockDate);
        return id;
    }

    // new code 16/Jan
    function LockBNB(
        address owner,
        uint256 amount,
        uint256 unlockDate,
        string memory description
    ) external payable returns (uint256 id) {
        require(unlockDate > block.timestamp, "Please set a valid Unlock Date");
        require(amount > 0, "Amount should be greater than 0");
        if (snipefinancemultisenders.readAuthorizedUsers(msg.sender) == false) {
            require(
                msg.value >= lockFee + amount,
                "You have to pay fee for vesting"
            ); //TAKE FEE IF NOT AUTHORIZED
            feeamounts += lockFee;
            payable(receiver).transfer(lockFee);
        } else {
            require(msg.value >= amount, "Insufficient amount to lock");
        }

        id = _createLockBNB(owner, amount,block.timestamp + unlockDate, 0, 0, 0, description);
        emit LockBNBAdded(id, owner, amount, unlockDate);
        return id;
    }

    // new code 16/Jan
    function unlockBNB(uint256 lockId) external payable {
        require(lockId > 0, "invalid lock id");
        BNBLock storage userLock = _BNBlocks[_getActualIndexBNB(lockId)];
        require(block.timestamp > userLock.tgeDate, "It is not time to unlock");
        require(
            userLock.owner == msg.sender,
            "You are not the owner of this lock"
        );
        require(userLock.unlockedAmount == 0, "Nothing to unlock");

        // new code 16/Jan
        _userBnbLockIds[msg.sender].remove(userLock.id);
        uint256 unlockAmount = userLock.amount;
        userLock.unlockedAmount = unlockAmount;
        _bnbToLockIds["BNB"].remove(userLock.id);

        (bool success, ) = (msg.sender).call{value: unlockAmount}("");
        require(success, "tranfer failed");

        emit LockBNBRemoved(
            userLock.id,
            userLock.owner,
            unlockAmount,
            block.timestamp
        );
    }

    // new code
    function VestingLockBNB(
        address owner,
        uint256 amount,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) external payable returns (uint256 id) {
        require(amount > 0, "Amount should be greater than 0");
        require(tgeDate > block.timestamp, "Please set a valid TGE date");
        require(cycle > 0, "Invalid cycle");
        require(tgeBps > 0 && tgeBps < 10_000, "Invalid bips for TGE");
        require(cycleBps > 0 && cycleBps < 10_000, "Invalid bips for cycle");
        require(
            tgeBps + cycleBps <= 10_000,
            "Sum of TGE bps and cycle should be less than 10000"
        );
        if (snipefinancemultisenders.readAuthorizedUsers(msg.sender) == false) {
            require(
                msg.value >= vestFee + amount,
                "You have to pay fee for vesting"
            ); //TAKE FEE IF NOT AUTHORIZED
            feeamounts += vestFee;
            payable(receiver).transfer(vestFee);
        } else {
            require(msg.value >= amount, "Insufficient amount to lock");
        }

        id = _createLockBNB(
            owner,
            amount,
            tgeDate,
            tgeBps,
            cycle,
            cycleBps,
            description
        );
        emit LockBNBAdded(id, owner, amount, tgeDate);
        return id;
    }

    // new code
    function VestingUnLockBNB(uint256 lockId) external validLockBNB(lockId) {
        BNBLock storage userLock = _BNBlocks[_getActualIndexBNB(lockId)];
        require(
            userLock.owner == msg.sender,
            "You are not the owner of this lock"
        );

        _vestingUnlockBNB(userLock);
    }

    function vestingLock(
        address owner,
        address token,
        bool isLpToken,
        uint256 amount,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) external payable override returns (uint256 id) {
        require(tgeDate > block.timestamp, "TGE date should be in the future");
        require(cycle > 0, "Invalid cycle");
        require(tgeBps > 0 && tgeBps < 10_000, "Invalid bips for TGE");
        require(cycleBps > 0 && cycleBps < 10_000, "Invalid bips for cycle");
        require(
            tgeBps + cycleBps <= 10_000,
            "Sum of TGE bps and cycle should be less than 10000"
        );
        require(amount > 0, "Amount should be greater than 0");
        if (snipefinancemultisenders.readAuthorizedUsers(msg.sender) == false) {
            require(msg.value >= lockFee, "You have to pay fee for locking"); //TAKE FEE IF NOT AUTHORIZED
            feeamounts += lockFee;
            payable(receiver).transfer(lockFee);
        }
        id = _createLock(
            owner,
            token,
            isLpToken,
            amount,
            tgeDate,
            tgeBps,
            cycle,
            cycleBps,
            description
        );
        _safeTransferFromEnsureExactAmount(
            token,
            msg.sender,
            address(this),
            amount
        );
        emit LockAdded(id, token, owner, amount, tgeDate);
        return id;
    }

    function multipleVestingLock(
        address[] calldata owners,
        uint256[] calldata amounts,
        address token,
        bool isLpToken,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) external override returns (uint256[] memory) {
        require(owners.length == amounts.length, "Length mismatched");
        require(tgeDate > block.timestamp, "TGE date should be in the future");
        require(cycle > 0, "Invalid cycle");
        require(tgeBps > 0 && tgeBps < 10_000, "Invalid bips for TGE");
        require(cycleBps > 0 && cycleBps < 10_000, "Invalid bips for cycle");
        require(
            tgeBps + cycleBps <= 10_000,
            "Sum of TGE bps and cycle should be less than 10000"
        );
        return
            _multipleVestingLock(
                owners,
                amounts,
                token,
                isLpToken,
                [tgeDate, tgeBps, cycle, cycleBps],
                description
            );
    }

    function _multipleVestingLock(
        address[] calldata owners,
        uint256[] calldata amounts,
        address token,
        bool isLpToken,
        uint256[4] memory vestingSettings, // avoid stack too deep
        string memory description
    ) internal returns (uint256[] memory) {
        uint256 sumAmount = _sumAmount(amounts);
        uint256 count = owners.length;
        uint256[] memory ids = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            ids[i] = _createLock(
                owners[i],
                token,
                isLpToken,
                amounts[i],
                vestingSettings[0], // TGE date
                vestingSettings[1], // TGE bps
                vestingSettings[2], // cycle
                vestingSettings[3], // cycle bps
                description
            );
            emit LockAdded(
                ids[i],
                token,
                owners[i],
                amounts[i],
                vestingSettings[0] // TGE date
            );
        }
        _safeTransferFromEnsureExactAmount(
            token,
            msg.sender,
            address(this),
            sumAmount
        );
        return ids;
    }

    function _sumAmount(uint256[] calldata amounts)
        internal
        pure
        returns (uint256)
    {
        uint256 sum = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] == 0) {
                revert("Amount cant be zero");
            }
            sum += amounts[i];
        }
        return sum;
    }

    // new code
    function checkValidLPToken(address token)
        public
        view
        returns (bool success)
    {
        // address possibleFactoryAddress;
        try IUniswapV2Pair(token).factory() returns (address factory) {
            // possibleFactoryAddress = factory;
            if (factory != address(0)) {
                success = true;
            }
        } catch {
            // revert("This token is not a LP token");
            // return address(0);
            success = false;
        }
        return success;
    }

    function _createLock(
        address owner,
        address token,
        bool isLpToken,
        uint256 amount,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) internal returns (uint256 id) {
        if (isLpToken) {
            address possibleFactoryAddress = _parseFactoryAddress(token);
            id = _lockLpToken(
                owner,
                token,
                possibleFactoryAddress,
                amount,
                tgeDate,
                tgeBps,
                cycle,
                cycleBps,
                description
            );
        } else {
            id = _lockNormalToken(
                owner,
                token,
                amount,
                tgeDate,
                tgeBps,
                cycle,
                cycleBps,
                description
            );
        }
        return id;
    }

    // new code 16/Jan
    function _createLockBNB(
        address owner,
        uint256 amount,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) internal returns (uint256 id) {
        id = _registerLockBNB(
            owner,
            amount,
            tgeDate,
            tgeBps,
            cycle,
            cycleBps,
            description
        );
        _userBnbLockIds[owner].add(id);
        // _normalLockedTokens.add(token);

        _bnbToLockIds["BNB"].add(id);
    }

    // new code
    function setLockFee(uint256 _newFee) external onlyOwner {
        require(_newFee > 0, "invalid value for fee");
        lockFee = _newFee;
    }

    // new code
    function setVestFee(uint256 _newFee) external onlyOwner {
        require(_newFee > 0, "invalid value for fee");
        vestFee = _newFee;
    }

    function _lockLpToken(
        address owner,
        address token,
        address factory,
        uint256 amount,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) private returns (uint256 id) {
        id = _registerLock(
            owner,
            token,
            amount,
            tgeDate,
            tgeBps,
            cycle,
            cycleBps,
            description
        );
        _userLpLockIds[owner].add(id);
        _lpLockedTokens.add(token);

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[token];
        if (tokenInfo.token == address(0)) {
            tokenInfo.token = token;
            tokenInfo.factory = factory;
        }
        tokenInfo.amount = tokenInfo.amount + amount;

        _tokenToLockIds[token].add(id);
    }

    function _lockNormalToken(
        address owner,
        address token,
        uint256 amount,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) private returns (uint256 id) {
        id = _registerLock(
            owner,
            token,
            amount,
            tgeDate,
            tgeBps,
            cycle,
            cycleBps,
            description
        );
        _userNormalLockIds[owner].add(id);
        _normalLockedTokens.add(token);

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[token];
        if (tokenInfo.token == address(0)) {
            tokenInfo.token = token;
            tokenInfo.factory = address(0);
        }
        tokenInfo.amount = tokenInfo.amount + amount;

        _tokenToLockIds[token].add(id);
    }

    function _registerLock(
        address owner,
        address token,
        uint256 amount,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) private whenNotPaused returns (uint256 id) {
        id = _locks.length + ID_PADDING;
        Lock memory newLock = Lock({
            id: id,
            token: token,
            owner: owner,
            amount: amount,
            lockDate: block.timestamp,
            tgeDate: tgeDate,
            tgeBps: tgeBps,
            cycle: cycle,
            cycleBps: cycleBps,
            unlockedAmount: 0,
            description: description
        });
        _locks.push(newLock);
    }

    // new code 16/Jan
    function _registerLockBNB(
        address owner,
        uint256 amount,
        uint256 tgeDate,
        uint256 tgeBps,
        uint256 cycle,
        uint256 cycleBps,
        string memory description
    ) private whenNotPaused returns (uint256 id) {
        id = _BNBlocks.length + ID_PADDING;
        BNBLock memory newLock = BNBLock({
            id: id,
            owner: owner,
            amount: amount,
            lockDate: block.timestamp,
            tgeDate: tgeDate,
            tgeBps: tgeBps,
            cycle: cycle,
            cycleBps: cycleBps,
            unlockedAmount: 0,
            description: description
        });
        _BNBlocks.push(newLock);
    }

    function unlock(uint256 lockId) external override validLock(lockId) {
        Lock storage userLock = _locks[_getActualIndex(lockId)];
        require(
            userLock.owner == msg.sender,
            "You are not the owner of this lock"
        );

        if (userLock.tgeBps > 0) {
            _vestingUnlock(userLock);
        } else {
            _normalUnlock(userLock);
        }
    }

    function _normalUnlock(Lock storage userLock) internal {
        require(
            block.timestamp >= userLock.tgeDate,
            "It is not time to unlock"
        );
        require(userLock.unlockedAmount == 0, "Nothing to unlock");

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[
            userLock.token
        ];

        bool isLpToken = tokenInfo.factory != address(0);

        if (isLpToken) {
            _userLpLockIds[msg.sender].remove(userLock.id);
        } else {
            _userNormalLockIds[msg.sender].remove(userLock.id);
        }

        uint256 unlockAmount = userLock.amount;

        if (tokenInfo.amount <= unlockAmount) {
            tokenInfo.amount = 0;
        } else {
            tokenInfo.amount = tokenInfo.amount - unlockAmount;
        }

        if (tokenInfo.amount == 0) {
            if (isLpToken) {
                _lpLockedTokens.remove(userLock.token);
            } else {
                _normalLockedTokens.remove(userLock.token);
            }
        }
        userLock.unlockedAmount = unlockAmount;

        _tokenToLockIds[userLock.token].remove(userLock.id);

        IERC20(userLock.token).safeTransfer(msg.sender, unlockAmount);

        emit LockRemoved(
            userLock.id,
            userLock.token,
            msg.sender,
            unlockAmount,
            block.timestamp
        );
    }

    function _vestingUnlock(Lock storage userLock) internal {
        uint256 withdrawable = _withdrawableTokens(userLock);
        uint256 newTotalUnlockAmount = userLock.unlockedAmount + withdrawable;
        require(
            withdrawable > 0 && newTotalUnlockAmount <= userLock.amount,
            "Nothing to unlock"
        );

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[
            userLock.token
        ];
        bool isLpToken = tokenInfo.factory != address(0);

        if (newTotalUnlockAmount == userLock.amount) {
            if (isLpToken) {
                _userLpLockIds[msg.sender].remove(userLock.id);
            } else {
                _userNormalLockIds[msg.sender].remove(userLock.id);
            }
            _tokenToLockIds[userLock.token].remove(userLock.id);
            emit LockRemoved(
                userLock.id,
                userLock.token,
                msg.sender,
                newTotalUnlockAmount,
                block.timestamp
            );
        }

        if (tokenInfo.amount <= withdrawable) {
            tokenInfo.amount = 0;
        } else {
            tokenInfo.amount = tokenInfo.amount - withdrawable;
        }

        if (tokenInfo.amount == 0) {
            if (isLpToken) {
                _lpLockedTokens.remove(userLock.token);
            } else {
                _normalLockedTokens.remove(userLock.token);
            }
        }
        userLock.unlockedAmount = newTotalUnlockAmount;

        IERC20(userLock.token).safeTransfer(userLock.owner, withdrawable);

        emit LockVested(
            userLock.id,
            userLock.token,
            msg.sender,
            withdrawable,
            userLock.amount,
            block.timestamp
        );
    }

    // new code
    function _vestingUnlockBNB(BNBLock storage userLock) internal {
        uint256 withdrawable = _withdrawableTokensBNB(userLock);
        uint256 newTotalUnlockAmount = userLock.unlockedAmount + withdrawable;
        require(
            withdrawable > 0 && newTotalUnlockAmount <= userLock.amount,
            "Nothing to unlock"
        );

        if (newTotalUnlockAmount == userLock.amount) {
            // new code 18/Jan
            _userBnbLockIds[msg.sender].remove(userLock.id);
            _bnbToLockIds["BNB"].remove(userLock.id);

            emit LockBNBRemoved(
                userLock.id,
                userLock.owner,
                newTotalUnlockAmount,
                block.timestamp
            );
        }

        userLock.unlockedAmount = newTotalUnlockAmount;

        // IERC20(userLock.token).safeTransfer(userLock.owner, withdrawable);
        (bool success, ) = (userLock.owner).call{value: withdrawable}("");
        require(success);

        emit LockVestedBNB(
            userLock.id,
            msg.sender,
            withdrawable,
            userLock.amount,
            block.timestamp
        );
    }

    function withdrawableTokens(uint256 lockId)
        external
        view
        returns (uint256)
    {
        Lock memory userLock = getLockById(lockId);
        return _withdrawableTokens(userLock);
    }

    function _withdrawableTokens(Lock memory userLock)
        internal
        view
        returns (uint256)
    {
        if (userLock.amount == 0) return 0;
        if (userLock.unlockedAmount >= userLock.amount) return 0;
        if (block.timestamp < userLock.tgeDate) return 0;
        if (userLock.cycle == 0) return 0;

        uint256 tgeReleaseAmount = (userLock.amount * userLock.tgeBps) / 10_000;
        uint256 cycleReleaseAmount = FullMath.mulDiv(
            userLock.amount,
            userLock.cycleBps,
            10_000
        );
        uint256 currentTotal = 0;
        if (block.timestamp >= userLock.tgeDate) {
            currentTotal =
                (((block.timestamp - userLock.tgeDate) / userLock.cycle) *
                    cycleReleaseAmount) +
                tgeReleaseAmount; // Truncation is expected here
        }
        uint256 withdrawable = 0;
        if (currentTotal > userLock.amount) {
            withdrawable = userLock.amount - userLock.unlockedAmount;
        } else {
            withdrawable = currentTotal - userLock.unlockedAmount;
        }
        return withdrawable;
    }

    // new code
    function withdrawableTokensBNB(uint256 lockId)
        external
        view
        returns (uint256)
    {
        BNBLock memory userLock = getLockByIdBNB(lockId);
        // BNBLock memory userLock = BNBData[lockId];
        return _withdrawableTokensBNB(userLock);
    }

    // new  code
    function _withdrawableTokensBNB(BNBLock memory userLock)
        internal
        view
        returns (uint256)
    {
        if (userLock.amount == 0) return 0;
        if (userLock.unlockedAmount >= userLock.amount) return 0;
        if (block.timestamp < userLock.tgeDate) return 0;
        if (userLock.cycle == 0) return 0;

        uint256 tgeReleaseAmount = (userLock.amount * userLock.tgeBps) / 10_000;
        uint256 cycleReleaseAmount = FullMath.mulDiv(
            userLock.amount,
            userLock.cycleBps,
            10_000
        );
        uint256 currentTotal = 0;
        if (block.timestamp >= userLock.tgeDate) {
            currentTotal =
                (((block.timestamp - userLock.tgeDate) / userLock.cycle) *
                    cycleReleaseAmount) +
                tgeReleaseAmount; // Truncation is expected here
        }
        uint256 withdrawable = 0;
        if (currentTotal > userLock.amount) {
            withdrawable = userLock.amount - userLock.unlockedAmount;
        } else {
            withdrawable = currentTotal - userLock.unlockedAmount;
        }
        return withdrawable;
    }

    function editLock(
        uint256 lockId,
        uint256 newAmount,
        uint256 newUnlockDate
    ) external payable override validLock(lockId) {
        Lock storage userLock = _locks[_getActualIndex(lockId)];
        require(
            userLock.owner == msg.sender,
            "You are not the owner of this lock"
        );
        require(userLock.unlockedAmount == 0, "Lock was unlocked");
        //new code 23/Jan
        if (newUnlockDate > 0 || newAmount > 0) {
            if (
                snipefinancemultisenders.readAuthorizedUsers(msg.sender) ==
                false
            ) {
                require(msg.value >= lockFee, "Fee require for Lock Edit");
                (bool success, ) = payable(receiver).call{value: lockFee}("");
                require(success, "editLock: fee transfer failed");
            }
        }

        if (newUnlockDate > 0) {
            require(
                newUnlockDate >= userLock.tgeDate &&
                    newUnlockDate > block.timestamp,
                "New unlock time should not be before old unlock time or current time"
            );
            userLock.tgeDate = newUnlockDate;
        }

        if (newAmount > 0) {
            require(
                newAmount >= userLock.amount,
                "New amount should not be less than current amount"
            );

            uint256 diff = newAmount - userLock.amount;

            if (diff > 0) {
                userLock.amount = newAmount;
                CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[
                    userLock.token
                ];
                tokenInfo.amount = tokenInfo.amount + diff;
                _safeTransferFromEnsureExactAmount(
                    userLock.token,
                    msg.sender,
                    address(this),
                    diff
                );
            }
        }

        emit LockUpdated(
            userLock.id,
            userLock.token,
            userLock.owner,
            userLock.amount,
            userLock.tgeDate
        );
    }

    // new code
    function editLockBNB(
        uint256 lockId,
        uint256 newAmount,
        uint256 newUnlockDate
    ) external payable validLockBNB(lockId) {
        BNBLock storage userLock = _BNBlocks[_getActualIndexBNB(lockId)];
        require(
            userLock.owner == msg.sender,
            "You are not the owner of this lock"
        );
        require(userLock.unlockedAmount == 0, "Lock was unlocked");
        // new code 23/Jan
        if (newUnlockDate > 0 || newAmount > 0) {
            if (
                snipefinancemultisenders.readAuthorizedUsers(msg.sender) ==
                false
            ) {
                require(msg.value >= lockFee, "Fee require for Lock Edit");
                (bool success, ) = payable(receiver).call{value: lockFee}("");
                require(success, "editLockBNB: fee transfer failed");
            }
        }

        if (newUnlockDate > 0) {
            require(
                newUnlockDate >= userLock.tgeDate &&
                    newUnlockDate > block.timestamp,
                "New unlock time should not be before old unlock time or current time"
            );
            userLock.tgeDate = newUnlockDate;
        }

        if (newAmount > 0) {
            require(
                newAmount >= userLock.amount,
                "New amount should not be less than current amount"
            );

            uint256 diff = newAmount - userLock.amount;

            if (diff > 0) {
                userLock.amount = newAmount;
                // CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[
                //     userLock.token
                // ];
                // tokenInfo.amount = tokenInfo.amount + diff;

                // (bool success, ) = payable(receiver).call{value: diff}("");
                require(msg.value >= diff, "should pay diff");
                // _safeTransferFromEnsureExactAmount(
                //     userLock.token,
                //     msg.sender,
                //     address(this),
                //     diff
                // );
            }
        }

        // emit LockUpdatedBNB(
        //     userLock.id,
        //     userLock.owner,
        //     userLock.amount,
        //     userLock.tgeDate
        // );
    }

    function editLockDescription(uint256 lockId, string memory description)
        external
        validLock(lockId)
    {
        Lock storage userLock = _locks[_getActualIndex(lockId)];
        require(
            userLock.owner == msg.sender,
            "You are not the owner of this lock"
        );
        userLock.description = description;
        emit LockDescriptionChanged(lockId);
    }

    function transferLockOwnership(uint256 lockId, address newOwner)
        public
        validLock(lockId)
    {
        Lock storage userLock = _locks[_getActualIndex(lockId)];
        address currentOwner = userLock.owner;
        require(
            currentOwner == msg.sender,
            "You are not the owner of this lock"
        );

        userLock.owner = newOwner;

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[
            userLock.token
        ];

        bool isLpToken = tokenInfo.factory != address(0);

        if (isLpToken) {
            _userLpLockIds[currentOwner].remove(lockId);
            _userLpLockIds[newOwner].add(lockId);
        } else {
            _userNormalLockIds[currentOwner].remove(lockId);
            _userNormalLockIds[newOwner].add(lockId);
        }

        emit LockOwnerChanged(lockId, currentOwner, newOwner);
    }

    // new code 17/Jan
    function transferLockOwnershipBNB(uint256 lockId, address newOwner)
        public
        validLockBNB(lockId)
    {
        BNBLock storage userLock = _BNBlocks[_getActualIndexBNB(lockId)];
        address currentOwner = userLock.owner;
        require(
            currentOwner == msg.sender,
            "You are not the owner of this lock"
        );

        userLock.owner = newOwner;

        _userBnbLockIds[currentOwner].remove(lockId);
        _userBnbLockIds[newOwner].add(lockId);

        emit LockOwnerChanged(lockId, currentOwner, newOwner);
    }

    function renounceLockOwnership(uint256 lockId) external {
        transferLockOwnership(lockId, address(0));
    }

    // new code 19/Jan
    function renounceLockOwnershipBNB(uint256 lockId) external {
        transferLockOwnershipBNB(lockId, address(0));
    }

    function _safeTransferFromEnsureExactAmount(
        address token,
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        uint256 oldRecipientBalance = IERC20(token).balanceOf(recipient);
        IERC20(token).safeTransferFrom(sender, recipient, amount);
        uint256 newRecipientBalance = IERC20(token).balanceOf(recipient);
        require(
            newRecipientBalance - oldRecipientBalance == amount,
            "Not enough token was transfered"
        );
    }

    function getTotalLockCount() external view returns (uint256) {
        // Returns total lock count, regardless of whether it has been unlocked or not
        return _locks.length;
    }

    // new code 19/Jan
    function getTotalLockCountBNB() external view returns (uint256) {
        // Returns total lock count, regardless of whether it has been unlocked or not
        return _BNBlocks.length;
    }

    function getLockAt(uint256 index) external view returns (Lock memory) {
        return _locks[index];
    }

    function getBNBLockAt(uint256 index)
        external
        view
        returns (BNBLock memory)
    {
        return _BNBlocks[index];
    }

    function getLockById(uint256 lockId) public view returns (Lock memory) {
        return _locks[_getActualIndex(lockId)];
    }

    // new code 17/Jan
    function getLockByIdBNB(uint256 lockId)
        public
        view
        returns (BNBLock memory)
    {
        return _BNBlocks[_getActualIndexBNB(lockId)];
    }

    function allLpTokenLockedCount() public view returns (uint256) {
        return _lpLockedTokens.length();
    }

    function allNormalTokenLockedCount() public view returns (uint256) {
        return _normalLockedTokens.length();
    }

    function getCumulativeLpTokenLockInfoAt(uint256 index)
        external
        view
        returns (CumulativeLockInfo memory)
    {
        return cumulativeLockInfo[_lpLockedTokens.at(index)];
    }

    function getCumulativeNormalTokenLockInfoAt(uint256 index)
        external
        view
        returns (CumulativeLockInfo memory)
    {
        return cumulativeLockInfo[_normalLockedTokens.at(index)];
    }

    function getCumulativeLpTokenLockInfo(uint256 start, uint256 end)
        external
        view
        returns (CumulativeLockInfo[] memory)
    {
        if (end >= _lpLockedTokens.length()) {
            end = _lpLockedTokens.length() - 1;
        }
        uint256 length = end - start + 1;
        CumulativeLockInfo[] memory lockInfo = new CumulativeLockInfo[](length);
        uint256 currentIndex = 0;
        for (uint256 i = start; i <= end; i++) {
            lockInfo[currentIndex] = cumulativeLockInfo[_lpLockedTokens.at(i)];
            currentIndex++;
        }
        return lockInfo;
    }

    function getCumulativeNormalTokenLockInfo(uint256 start, uint256 end)
        external
        view
        returns (CumulativeLockInfo[] memory)
    {
        if (end >= _normalLockedTokens.length()) {
            end = _normalLockedTokens.length() - 1;
        }
        uint256 length = end - start + 1;
        CumulativeLockInfo[] memory lockInfo = new CumulativeLockInfo[](length);
        uint256 currentIndex = 0;
        for (uint256 i = start; i <= end; i++) {
            lockInfo[currentIndex] = cumulativeLockInfo[
                _normalLockedTokens.at(i)
            ];
            currentIndex++;
        }
        return lockInfo;
    }

    function totalTokenLockedCount() external view returns (uint256) {
        return allLpTokenLockedCount() + allNormalTokenLockedCount();
    }

    function lpLockCountForUser(address user) public view returns (uint256) {
        return _userLpLockIds[user].length();
    }

    function lpLocksForUser(address user)
        external
        view
        returns (Lock[] memory)
    {
        uint256 length = _userLpLockIds[user].length();
        Lock[] memory userLocks = new Lock[](length);
        for (uint256 i = 0; i < length; i++) {
            userLocks[i] = getLockById(_userLpLockIds[user].at(i));
        }
        return userLocks;
    }

    function lpLockForUserAtIndex(address user, uint256 index)
        external
        view
        returns (Lock memory)
    {
        require(lpLockCountForUser(user) > index, "Invalid index");
        return getLockById(_userLpLockIds[user].at(index));
    }

    function normalLockCountForUser(address user)
        public
        view
        returns (uint256)
    {
        return _userNormalLockIds[user].length();
    }

    // new code 17/Jan
    function BNBLockCountForUser(address user) public view returns (uint256) {
        return _userBnbLockIds[user].length();
    }

    function normalLocksForUser(address user)
        external
        view
        returns (Lock[] memory)
    {
        uint256 length = _userNormalLockIds[user].length();
        Lock[] memory userLocks = new Lock[](length);

        for (uint256 i = 0; i < length; i++) {
            userLocks[i] = getLockById(_userNormalLockIds[user].at(i));
        }
        return userLocks;
    }

    // new code 17/Jan
    function BNBLocksForUser(address user)
        external
        view
        returns (BNBLock[] memory)
    {
        uint256 length = _userBnbLockIds[user].length();
        BNBLock[] memory userLocks = new BNBLock[](length);

        for (uint256 i = 0; i < length; i++) {
            userLocks[i] = getLockByIdBNB(_userBnbLockIds[user].at(i));
        }
        return userLocks;
    }

    function normalLockForUserAtIndex(address user, uint256 index)
        external
        view
        returns (Lock memory)
    {
        require(normalLockCountForUser(user) > index, "Invalid index");
        return getLockById(_userNormalLockIds[user].at(index));
    }

    // new code 17/Jan
    function BNBLockForUserAtIndex(address user, uint256 index)
        external
        view
        returns (BNBLock memory)
    {
        require(BNBLockCountForUser(user) > index, "Invalid index");
        return getLockByIdBNB(_userBnbLockIds[user].at(index));
    }

    function totalLockCountForUser(address user)
        external
        view
        returns (uint256)
    {
        return normalLockCountForUser(user) + lpLockCountForUser(user);
    }

    function totalLockCountForToken(address token)
        external
        view
        returns (uint256)
    {
        return _tokenToLockIds[token].length();
    }

    // new code 18/Jan
    function totalLockCountForBNB() external view returns (uint256) {
        return _bnbToLockIds["BNB"].length();
    }

    function getLocksForToken(
        address token,
        uint256 start,
        uint256 end
    ) public view returns (Lock[] memory) {
        if (end >= _tokenToLockIds[token].length()) {
            end = _tokenToLockIds[token].length() - 1;
        }
        uint256 length = end - start + 1;
        Lock[] memory locks = new Lock[](length);
        uint256 currentIndex = 0;
        for (uint256 i = start; i <= end; i++) {
            locks[currentIndex] = getLockById(_tokenToLockIds[token].at(i));
            currentIndex++;
        }
        return locks;
    }

    // new code 18/Jan
    function getLocksForBNB(uint256 start, uint256 end)
        public
        view
        returns (BNBLock[] memory)
    {
        if (end >= _bnbToLockIds["BNB"].length()) {
            end = _bnbToLockIds["BNB"].length() - 1;
        }
        uint256 length = end - start + 1;
        BNBLock[] memory locks = new BNBLock[](length);
        uint256 currentIndex = 0;
        for (uint256 i = start; i <= end; i++) {
            locks[currentIndex] = getLockByIdBNB(_bnbToLockIds["BNB"].at(i));
            currentIndex++;
        }
        return locks;
    }

    function _getActualIndex(uint256 lockId) internal view returns (uint256) {
        if (lockId < ID_PADDING) {
            revert("Invalid lock id");
        }
        uint256 actualIndex = lockId - ID_PADDING;
        require(actualIndex < _locks.length, "Invalid lock id");
        return actualIndex;
    }

    // new code 17/Jan
    function _getActualIndexBNB(uint256 lockId)
        internal
        view
        returns (uint256)
    {
        if (lockId < ID_PADDING) {
            revert("Invalid lock id");
        }
        uint256 actualIndex = lockId - ID_PADDING;
        require(actualIndex < _BNBlocks.length, "Invalid lock id");
        return actualIndex;
    }

    function _parseFactoryAddress(address token)
        internal
        view
        returns (address)
    {
        address possibleFactoryAddress;
        try IUniswapV2Pair(token).factory() returns (address factory) {
            possibleFactoryAddress = factory;
        } catch {
            revert("This token is not a LP token");
        }
        require(
            possibleFactoryAddress != address(0) &&
                _isValidLpToken(token, possibleFactoryAddress),
            "This token is not a LP token."
        );
        return possibleFactoryAddress;
    }

    function _isValidLpToken(address token, address factory)
        private
        view
        returns (bool)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(token);
        address factoryPair = IUniswapV2Factory(factory).getPair(
            pair.token0(),
            pair.token1()
        );
        return factoryPair == token;
    }

    function setReceiver(address _receiver) external onlyOwner {
        // require(_receiver != address(this), "Contract can not be receiver");
        // require(_receiver != address(0), "Address 0 can't be the reciver");
        receiver = _receiver;
    }
}
