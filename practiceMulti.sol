// SPDX-License-Identifier:MIT

pragma solidity 0.8.13;

contract Bulksend {
    function sendTo(address payable contrac)payable public{
      address reciever = address(contrac);
      payable(reciever).transfer(msg.value);
    }

   
}


    

  