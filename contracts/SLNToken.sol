// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20, ERC20, ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/ERC20Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SLNToken is ERC20Pausable, Ownable {
    using SafeMath for uint256;

    uint256 private timeBegin;
    uint256 private poolVal;
    uint256 private teamVal;
    address private teamAddress;
    address private poolAddress;

    mapping (address => bool) private blockedlist;

    event claimValue(address, address, uint256);

    modifier onlyPooler() {
        require(msg.sender == poolAddress, "only call by pool");
        _;
    }

    constructor(
            address _premint,
            address _foundation,
            address _team
        ) public ERC20('SLN-Token', 'SLN') {

        timeBegin = now;
        teamAddress = _team;

        // 初始挖
        uint256 totalVal = (1*10**8)*(10**18);

        _mint(address(this), totalVal*8635/10000); // 86.8%% for  8635%% = 7850%% pool and 785%% team mint
        _mint(_premint, totalVal*150/10000);     // 150%% for pool premint
        _mint(teamAddress, totalVal*15/10000);   // 15%% for team premint
        _mint(_foundation, totalVal*1200/10000); // 1200%% for foundation

        require(totalVal == totalSupply());
    }

    function setTeamAddress(address _teamAddress) external onlyOwner {
        require(_teamAddress != address(0), "zero address is not allowed!");
        teamAddress = _teamAddress;
    }
    
    function setPoolAddress(address _poolAddress) external onlyOwner {
        poolAddress = _poolAddress;
        _approve(address(this), poolAddress, totalSupply()*835/1000);
    }

    function _makeSum(uint256 _first, uint256 _weekindex) internal pure returns (uint256) {
        uint256 downRatio = 80;
        uint256 flatRatio = 6;
        uint256 value = 0;
        if(_weekindex == 0) {
            value = 0;
        }else if(_weekindex <= 12){
            value = _first * (100 ** _weekindex - downRatio ** _weekindex)/ (100 ** _weekindex) * 100 / (100-downRatio);
        }else{
            value = _first * 4656402615 / (10**9); // 4656402615 = _makeSum(1, 12)
            // value = _first * (100 ** _count - downRatio ** _count)/ (100 ** _count) * 100 / (100-downRatio);
            value = value + _first * (_weekindex - 12) * flatRatio / 100;
        }
        return value;
    }

    function _makeLastWeek(uint256 _first, uint256 _weekindex) internal pure returns (uint256) {
        require(_weekindex > 0, "_weekindex == 0 ??");
        uint256 downRatio = 80;
        uint256 flatRatio = 6;
        if(_weekindex <= 12){
            return _first * downRatio ** (_weekindex-1) / (100 ** (_weekindex-1));
        }
        return _first * flatRatio / 100;
    }

    function tokensThisWeek() external view returns (uint256) {
        uint256 aweeks = (now - timeBegin) / (1 weeks);
        uint256 pFirstVal = totalSupply() * 5 / 100;  // firstVal = totalSupply * 5% 
        uint256 aweeklast = _makeLastWeek(pFirstVal, aweeks + 1);
        return aweeklast;
    }

    // Calculate mining output
    function _calcMintValue() internal view returns (uint256) {

        uint256 aweeks = (now - timeBegin) / (1 weeks);
        uint256 asecends = (now - timeBegin - aweeks * 1 weeks);
        uint256 pFirstVal = totalSupply() * 5 / 100;  // firstVal = totalSupply * 5% 
        // Weekly income
        uint256 aweekval = _makeSum(pFirstVal, aweeks);
        uint256 aweeklast = _makeLastWeek(pFirstVal, aweeks + 1);
        uint256 asecval = aweeklast * asecends / (1 weeks);
        return aweekval + asecval;
    }

    function calcPoolValue() public view returns (uint256) {
        // Calculate mining output for miner
        return _calcMintValue() * 7850 / 8635;
    }

    function claim(address _to, uint256 _value) external onlyPooler returns (bool) {
        // obtain income from the mining pool
        require(_value <= calcPoolValue().sub(poolVal), "not enough tokens");
        poolVal = poolVal.add(_value);
        _transfer(address(this), _to, _value);
        emit claimValue(msg.sender, _to, _value);
        teamClaim();
        return true;
    }

    function teamClaim() public {
        // obtain team income from the mining pool
        uint256 curval =  _calcMintValue() * 785 / 8635;
        uint256 value = curval.sub(teamVal);
        if(value == 0){
            return;
        }
        teamVal = teamVal.add(value);
        _transfer(address(this), teamAddress, value);
        emit claimValue(msg.sender, teamAddress, value);
    }

    function setBlockedlist(address _address, bool _blocked) external onlyOwner {
        require(blockedlist[_address] != _blocked);
        blockedlist[_address] = _blocked;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        require(!blockedlist[from] && !blockedlist[to], 'address blocked');
    }
}
