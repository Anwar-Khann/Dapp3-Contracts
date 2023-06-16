//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISnipeFinanceMultisenders {
    function readAuthorizedUsers(address user) external view returns(bool);
    function getTokenBalance(address account) external view returns(uint256);

}