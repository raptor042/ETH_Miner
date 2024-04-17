// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

contract Bank {
    address public owner;

    address public admin;

    event Transfer(address indexed user, uint256 amount);

    constructor() {
        owner = msg.sender;
    }
    
    receive() external payable {}

    modifier onlyOwner {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    modifier onlyAdmin {
        require(msg.sender == admin, "Only admin can call this function.");
        _;
    }

    function setAdmin(address _admin) public onlyOwner {
        require(_admin != address(0), "Do not pass a zero address.");

        admin = _admin;
    }

    function transfer(address user, uint256 amount) public onlyAdmin {
        require(address(this).balance > amount, "Insufficent funds.");

        (bool os, ) = payable(user).call{value: amount}("");
        require(os);

        emit Transfer(user, amount);
    }
}