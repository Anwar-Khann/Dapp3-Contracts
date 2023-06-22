// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "IPancakeRouter02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICUSTOM is IERC20 {
    function decimals() external view returns (uint256);
}

// import "SwapBot/IChainlinkAggregator.sol";

contract Swap {
    IPancakeRouter02 public instance;
    // IChainlinkAggregator public priceAggregator;
    struct Order {
        uint256 desired;
        uint256 spend;
        address spent;
        address getToken;
        address owner;
    }
    mapping(address => Order) public Registery;

    constructor(address routerAddress) {
        instance = IPancakeRouter02(routerAddress);
        // priceAggregator = IChainlinkAggregator(aggregatorAddress);
    }
//  ["0x55a7f2DE1e9FE58bA6493132160b8fF1F1388741", "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"]
    //pancake router testnet =0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;
    //pancake factory = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3

    function setOrder(uint256 desired, uint256 spend,address spent,address getToken) public // address spent

    {
        ICUSTOM spender = ICUSTOM(spent);
        ICUSTOM recieve = ICUSTOM(getToken);
        uint256 decimalsforrecieve = recieve.decimals();
        uint256 decForSpend = spender.decimals();
        uint256 toReceieve = desired * (10**decimalsforrecieve);
        uint256 toBeSpent = spend * (10**decForSpend);

        Registery[msg.sender] = Order(toReceieve, toBeSpent,spent,getToken,msg.sender);
    }
  //again updated check
   
   function check() public view returns (bool) {
    
    
    Order storage order = Registery[msg.sender];
    require(msg.sender == order.owner, "you don't have order listed");
    address[] memory path = new address[](2);
    path[0] = order.spent;
    path[1] = order.getToken;
    
    uint256[] memory amounts = instance.getAmountsOut(order.spend, path);
    uint256 amountOut = amounts[1]; // The desired output amount is at index 1
    
    return amountOut >= order.desired;
}

    
    // updated check
    // function check(address[] memory path) public view returns (bool) {
    //     uint256 desiredAmount = Registery[msg.sender].desired;
    //     uint256 amountIn = Registery[msg.sender].spend;
    //     address[] path = [Registery[msg.sender].spend,Registery[msg.sender].getToken];
    //     uint256[] memory amounts = instance.getAmountsOut(amountIn, path);
    //     uint256 amountOut = amounts[path.length - 1];

    //     return amountOut == desiredAmount;
    // }

    // function check(uint256 amountIn, address[] memory path) public view returns(bool){
    //     //this function will check whether our desired output amount reached
    //     amountIn = Registery[msg.sender].spend;
    //     instance.getAmountsOut(amountIn, path);
    //     // uint256 amountOut = amounts[path.length - 1];

    //     // return amountOut == desiredAmount;
    
        

    // }

    function swapTokens(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMin
    ) public {
        uint256[] memory amounts = instance.getAmountsOut(amountIn, path);
        uint256 amountOut = amounts[path.length - 1];

        require(amountOut >= amountOutMin, "Insufficient output amount");

        // Approve the router to spend the input token
        // ...

        // Call the swap function
        instance.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
    }
}
