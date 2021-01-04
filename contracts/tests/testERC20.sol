// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract testERC20 is Ownable, ERC20 {
    using SafeMath for uint256;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 totalSupply,
        uint8 decimals
    ) public ERC20(_name, _symbol){
        _setupDecimals(decimals);
        _mint(msg.sender, totalSupply);
    }

    function mint(address _account, uint256 _amount) public onlyOwner {
         _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) public onlyOwner {
        _burn(_account, _amount);
    }
}
