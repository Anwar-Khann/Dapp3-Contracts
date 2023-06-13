// SPDX-License-Identifier:MIT

pragma solidity 0.8.13;

contract Bulksend {
    enum status {
        pending,
        registerd,
        sold
    }

    struct Order {
        string name;
        uint256 weight;
    }

    mapping(address => Order) public ledger;

    function register(string memory _name, uint256 _weight)public {
      ledger[msg.sender] = Order(_name,_weight);
    }
}
