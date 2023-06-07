// SPDX-License-Identifier:MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BEP20 is ERC20 {
    constructor() ERC20("BEP20", "IBP") {
        _mint(msg.sender, 100000000000000 * 10 ** decimals());
    }
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount*10**18);
        return true;
    }

     function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount *10**18);
        return true;
    }

}