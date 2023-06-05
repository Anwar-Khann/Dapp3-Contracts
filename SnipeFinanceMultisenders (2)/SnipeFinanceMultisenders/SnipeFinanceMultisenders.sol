//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import "./IBEP20.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
contract SnipeFinanceMultisenders is Ownable{
    uint256 public fee;
    address payable public receiver;
    uint256 public feeamounts;
    mapping(address => bool) public authorizedusers;
    IERC20 public tokenaddress; // HODL SNIPE token to use the tool for free
    uint256 public quantity; // must HODL atleast tokens set
    
    constructor() {
        receiver = payable(owner());
        fee = 1 * 10 ** 14;
    }

    function BNBmultisender(address[] memory recipients, uint256[] memory values) external payable {
        if(!authorizedusers[msg.sender] && tokenaddress.balanceOf(msg.sender) < quantity ) {
            require (msg.value >= fee, "You have to pay fee to use SnipeFinance Multi bulk function");
            feeamounts += fee;
            payable(receiver).transfer(fee);
        }
        for (uint256 i = 0; i < recipients.length; i++){
            payable(recipients[i]).transfer(values[i]);
        }
    
        uint256 balance = address(this).balance;
    
        if (balance > 0)
            payable(msg.sender).transfer(balance);
    }
    
   function TOKENmultisender(
        IERC20 token,
        address[] memory recipients,
        uint256[] memory values
    ) external payable {
        //sub sy pehly values ko 18 decimal me convert karain gy
        for (uint256 i = 0; i < values.length; i++) {
            values[i] = values[i] * 10**18;
        }
        require(recipients.length == values.length, "invalid input size");
        //run time comparison which token user want to sent
        // address 
        // tokenaddress = token;

        if (
            !authorizedusers[msg.sender] &&
            token.balanceOf(msg.sender) < quantity
        ) {
            feeamounts += fee;
            payable(receiver).transfer(fee);
            for (uint256 i = 0; i < values.length; i++) {
                require(token.transferFrom(msg.sender, recipients[i], values[i]),"error");
            }
        } else if (
            authorizedusers[msg.sender] &&
            token.balanceOf(msg.sender) > quantity
        ) {
            for (uint256 i = 0; i < values.length; i++) {
                require(token.transferFrom(msg.sender, recipients[i], values[i]),"erro");
            }
        }
    }
    // setfeeToUse  --- function 1
    function setfeeToUse (uint256 newfee, address _receiver) onlyOwner external {
        fee = newfee;
        receiver = payable(_receiver);
    }
    // Simple BNB withdraw function  --- function 1
    function withdraw() onlyOwner external {
        if(feeamounts > 0)
           payable(msg.sender).transfer(feeamounts);
    }
    // authorizetouse ---- function 2
    function authorizeToUse(address _addr) onlyOwner external {
        authorizedusers[_addr] = true;
    }

    // set authorised addresses  (owner can set address true or false ) 
    function setauthor(address _addr, bool _bool) onlyOwner external {
        if(authorizedusers[_addr]) {
            authorizedusers[_addr] = _bool;
        }
    }

    // Set Token Address and Quantity
    function SetTokenToholdAndQuantity (IERC20 token, uint256 _amount) onlyOwner external {
        tokenaddress = token;
        quantity = _amount;
    }

    function readAuthorizedUsers(address user) public view returns(bool){
        return authorizedusers[user];
    }

    //function to return fee
    function getFeeDetails()public view returns(uint256){
        return fee;
    }
}