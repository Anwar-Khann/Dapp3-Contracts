//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

//the reason for this another interface creation because we want to use the decimal's function of each token and it's not available in standard interface
// interface ICustomERC20 is IERC20 {
//     function decimals() external view returns (uint256);
// }

contract SnipeFinanceMultisenders is Ownable {
    using Address for address;
    uint256 public fee;
    address payable public receiver; //tho owner of a contract
    mapping(address => bool) public authorizedusers;
    IERC20 public tokenAddress; //  token to hold for using  the tool for free
    uint256 public quantity; // minimum hoding amount of tokenaddress at minimum tokens 

    constructor() {
        receiver = payable(owner());
        fee = 1 * 10**14;
    }

    //this modifier is responsible for letting know whetehr token holding has been set or not
    modifier tokenChecker() {
        require(address(tokenAddress) != address(0), "token holding invalid");
        _;
    }

    function coinMultisender(
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
                msg.value == totalValues,
                "pay the exact amount to cover distribution"
            );
            for (uint256 i = 0; i < recipients.length; i++) {
                payable(recipients[i]).transfer(values[i]);
            }
        } else if (!authorizedusers[msg.sender]) {
            if (tokenAddress.balanceOf(msg.sender) >= quantity) {
                authorizedusers[msg.sender] = true;
                require(
                    msg.value == totalValues,
                    "holding quantity true but msg.value uncertain pay exact"
                );
                for (uint256 i = 0; i < recipients.length; i++) {
                    payable(recipients[i]).transfer(values[i]);
                }
            } else if (tokenAddress.balanceOf(msg.sender) < quantity) {
                uint256 toBeIncluded = fee + totalValues;
                require(
                    msg.value == toBeIncluded,
                    "holding & authorization false pay exact fee"
                );
                payable(receiver).transfer(fee);
                for (uint256 i = 0; i < recipients.length; i++) {
                    payable(recipients[i]).transfer(values[i]);
                }
            }
        }
    }

    function TOKENmultisender(//ICustomERC20 REPLACED WITH ERC20
        IERC20 token,
        address[] memory recipients,
        uint256[] memory values
    ) external payable tokenChecker {
        require(address(token).isContract() == true, "not a contract"); //this will check whether it's a contract or EOA address
        require(recipients.length == values.length, "invalid input");
        // uint256 fetched = fetchDecimals(token);

        // // Convert values to fetched token decimals
        // for (uint256 i = 0; i < values.length; i++) {
        //     values[i] = values[i] * (10**fetched);
        // }

        if (authorizedusers[msg.sender]) {
            for (uint256 i = 0; i < values.length; i++) {
                require(
                    token.transferFrom(msg.sender, recipients[i], values[i]),
                    "error in distribution"
                );
            }
        } else if (!authorizedusers[msg.sender]) {
            if (tokenAddress.balanceOf(msg.sender) >= quantity) {
                authorizedusers[msg.sender] = true;
                for (uint256 i = 0; i < values.length; i++) {
                    require(
                        token.transferFrom(
                            msg.sender,
                            recipients[i],
                            values[i]
                        ),
                        "error in distribution"
                    );
                }
            } else if (tokenAddress.balanceOf(msg.sender) < quantity) {
                require(
                    msg.value == fee,
                    "holding & authorization false pay exact fee"
                );
                payable(receiver).transfer(fee);
                for (uint256 i = 0; i < values.length; i++) {
                    require(
                        token.transferFrom(
                            msg.sender,
                            recipients[i],
                            values[i]
                        ),
                        "error in distribution"
                    );
                }
            }
        }
    } //function ending

    // setfeeToUse  --- function 1
    function setfeeToUse(uint256 newfee, address _receiver) external onlyOwner {
        fee = newfee;
        receiver = payable(_receiver);
    }

    // this function will authorize the user  (user have to be unauthorised first)
    function authorizeUser(address user) external onlyOwner {
        require(authorizedusers[user] == false, "user is already authorized");
        authorizedusers[user] = true;
    }

    // this function will unauthorize the user  (user have to be authorised first)
    function unauthorizeUser(address user) external onlyOwner {
        require(authorizedusers[user] == true, "user is already unauthorized");
        authorizedusers[user] = false;
    }
    function readAuthorizedUsers(address user) external view returns(bool){
        return authorizedusers[user];
    }

    // Set Token Address and Quantity
    function SetTokenToholdAndQuantity(IERC20 token, uint256 _amount)
        external
        onlyOwner
    {
        tokenAddress = token;
        quantity = _amount;
    }

    //get fee details function is also removed from here because the fee variable is also a public

    //the function is responsible for handling the withdrawal of coin's;
    function withdrawCoins(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "invalid balance to withdraw");
        payable(msg.sender).transfer(amount);
    }

    //the function is responsible for handling the withdrawal of any erc20 token;
    function withdrawToken(IERC20 token, uint256 amount) public onlyOwner {
        require(
            token.balanceOf(address(this)) >= amount,
            "contract doesn't have enough token's"
        );
        token.transfer(msg.sender, amount);
    }

    //get balance of a contract
    function contractBalance() public view onlyOwner returns(uint256){
        return address(this).balance;
    }
  
  //this function is responsible for fetching the input token decimal's
    // function fetchDecimals(ICustomERC20 token) public view returns (uint256) {
    //     // MyToken myToken = MyToken(address(token));
    //     return token.decimals();
    // }
   
   //necessary for contract to recieve coin's
    receive() external payable {} 

    function getTokenBalance(address account) external view returns(uint256){
        return tokenAddress.balanceOf(account);
    }

}
