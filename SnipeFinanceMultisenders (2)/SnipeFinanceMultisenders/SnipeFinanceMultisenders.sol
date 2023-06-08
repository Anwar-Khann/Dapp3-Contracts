//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract SnipeFinanceMultisenders is Ownable {
    using Address for address;
    uint256 public fee;
    address payable public receiver;
    uint256 public feeamounts;
    mapping(address => bool) public authorizedusers;
    IERC20 public tokenaddress; // HODL SNIPE token to use the tool for free
    uint256 public quantity; // must HODL at least tokens set

    constructor() {
        receiver = payable(owner());
        fee = 1 * 10**14;
    }

    modifier tokenChecker() {
        require(address(tokenaddress) != address(0), "set token holding first");
        _;
    }

    function BNBmultisender(
        address[] memory recipients,
        uint256[] memory values
    ) external payable tokenChecker {
        // sum up values
        require(recipients.length == values.length, "invalid input");
        uint256 totalValues;
        for (uint256 i; i < values.length; i++) {
            totalValues += values[i];
        }

        if (authorizedusers[msg.sender]) {
            require(
                msg.value >= totalValues,
                "user authorized but msg.value is invalid to cover fund's for user's"
            );
            for (uint256 i = 0; i < recipients.length; i++) {
                payable(recipients[i]).transfer(values[i]);
            }
        } else if (!authorizedusers[msg.sender]) {
            if (tokenaddress.balanceOf(msg.sender) >= quantity) {
                authorizedusers[msg.sender] = true;
                require(
                    msg.value >= totalValues,
                    "user authorized because of high quantity but msg.value low"
                );
                for (uint256 i = 0; i < recipients.length; i++) {
                    payable(recipients[i]).transfer(values[i]);
                }
            } else if (tokenaddress.balanceOf(msg.sender) < quantity) {
                uint256 toBeIncluded = fee + totalValues;
                require(
                    msg.value >= toBeIncluded,
                    "neither authorized and don't have enough token balance"
                );
                payable(receiver).transfer(fee);
                for (uint256 i = 0; i < recipients.length; i++) {
                    payable(recipients[i]).transfer(values[i]);
                }
            }
        }
        uint256 balance = address(this).balance;
        if (address(this).balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    }

    function TOKENmultisender(
        IERC20 token,
        address[] memory recipients,
        uint256[] memory values
    ) external payable tokenChecker {
        require(address(token).isContract() == true, "not a contract");//this will check whether it's a contract or EOA address
        require(recipients.length == values.length, "invalid input");
        //sub sy pehly values ko 18 decimal me convert karain gy
        for (uint256 i = 0; i < values.length; i++) {
            values[i] = values[i] * 10**18;
        }

        if (authorizedusers[msg.sender]) {
            for (uint256 i = 0; i < values.length; i++) {
                require(
                    token.transferFrom(msg.sender, recipients[i], values[i])
                );
            }
        } else if (!authorizedusers[msg.sender]) {
            if (tokenaddress.balanceOf(msg.sender) >= quantity) {
                authorizedusers[msg.sender] = true;
                for (uint256 i = 0; i < values.length; i++) {
                    require(
                        token.transferFrom(msg.sender, recipients[i], values[i])
                    );
                }
            } else if (tokenaddress.balanceOf(msg.sender) < quantity) {
                require(msg.value >= fee, "not authorized and low msg.value");
                payable(receiver).transfer(fee);
                for (uint256 i = 0; i < values.length; i++) {
                    require(
                        token.transferFrom(msg.sender, recipients[i], values[i])
                    );
                }
            }
        }
        uint256 balance = address(this).balance;
        if (address(this).balance > 0) {
            payable(msg.sender).transfer(balance);
        }
    } //function ending

    // setfeeToUse  --- function 1
    function setfeeToUse(uint256 newfee, address _receiver) external onlyOwner {
        fee = newfee;
        receiver = payable(_receiver);
    }

    // Simple BNB withdraw function  --- function 1
    function withdraw() external onlyOwner {
        if (feeamounts > 0) payable(msg.sender).transfer(feeamounts);
    }

    // authorizetouse ---- function 2
    function authorizeToUse(address _addr) external onlyOwner {
        authorizedusers[_addr] = true;
    }

    // set authorised addresses  (owner can set address true or false )
    function setauthor(address _addr, bool _bool) external onlyOwner {
        if (authorizedusers[_addr]) {
            authorizedusers[_addr] = _bool;
        }
    }

    // Set Token Address and Quantity
    function SetTokenToholdAndQuantity(IERC20 token, uint256 _amount)
        external
        onlyOwner
    {
        tokenaddress = token;
        quantity = _amount;
    }

    function readAuthorizedUsers(address user) public view returns (bool) {
        return authorizedusers[user];
    }

    //function to return fee
    function getFeeDetails() public view returns (uint256) {
        return fee;
    }

   
}
