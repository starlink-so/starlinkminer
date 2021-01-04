
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StarPools} from "./StarPools.sol";

pragma experimental ABIEncoderV2;

// Word Management Contract
contract WordFund is ERC721, Ownable {
    using SafeMath for uint256;
    
    address public poolAddress;
    uint256 public poolId;
    uint256 public relatedPoolId;

    function setPoolAddress(address _poolAddress) public onlyOwner {
        poolAddress = _poolAddress;
    }

    function setRelatedPoolId(uint256 _poolId, uint256 _relatedPoolId) public onlyOwner {
        poolId = _poolId;
        relatedPoolId = _relatedPoolId;
    }

    // Word Data
    struct worddata{
        address owner;              // The leader in the bidding
        uint256 collateral;         // amount of collateral
        uint256 biddingPeriod;      // last bidding time point 24h 
        uint256 positionLocking;    // holding ntf locking 15d
        string word; // word 
        string pic;
        string ext;
    }

    worddata[] public words;  // Word Data List
    
    uint256 public biddingLockingPeriod = (4 hours);
    uint256 public positionLockingPeriod = (15 days);

    constructor() public ERC721('GOOG-Token', 'GOOG') {
    }

    function wordsLength() public view returns (uint256) {
        return words.length;
    }

    event addWord(address from, uint256 wordid, string word);
    event biddingWord(address indexed from, uint256 indexed wordid, uint256 indexed poolid, uint256 value, 
                        address lastholder, uint256 lastvalue, uint256 lasttime);
    event harvestWord(address from, uint256 wordid, uint256 holdtimes);
    event releaseWord(address from, uint256 wordid, uint256 value, uint256 holdtime);
    event setWordData(address from, uint256 wordid, string pic, string ext);

    event claimInvoked(address from, uint256 poolid, uint256 wordid, address to);

    function lowAmount() public view returns (uint256) {
        uint256 weight;
        (,,,,weight,,,) = StarPools(poolAddress).pools(poolId);
        return 100*(10**18)*(10**9)/weight;
    }

    function addWords(string[] memory wordlist) public onlyOwner returns (uint256) {
        uint256 wordid = 0;
        for(uint256 i = 0; i < wordlist.length; i ++) {
            wordid = words.length;
            words.push(worddata(address(0), lowAmount(),0,0, wordlist[i],"",""));
            _mint(address(this), wordid);
            emit addWord(msg.sender, wordid, wordlist[i]);
        }
        return words.length;
    }

    function setData(uint256 _wordid, string memory _pic, string memory _ext) public {
        // set word info data
        require(ownerOf(_wordid) == msg.sender, "only owner can do");
        words[_wordid].pic = _pic;
        words[_wordid].ext = _ext;
        emit setWordData(msg.sender, _wordid, _pic, _ext);
    }

    function getPoolLPToken(uint256 _poolid) internal view returns (address) {
        address LPToken;
        (LPToken,,,,,,,) = StarPools(poolAddress).pools(_poolid);
        return LPToken;
    }

    function _depositMovePool(uint256 _poolId, uint256 _wordid, uint256 _collateral, uint256 _relatedPoolId, address _relatedaccount) internal returns (bool) {
        require(StarPools(poolAddress).depositMove(_poolId, address(_wordid), _collateral,
                                             _relatedPoolId, _relatedaccount),
                                             "collateral move error");
        require(StarPools(poolAddress).claimMove(_poolId, address(_wordid), _relatedPoolId, _relatedaccount),
                                             "profit move error");
        return true;
    }

    function bidding(uint256 _wordid, uint256 _poolid, uint256 _value, address _referrer) public returns (uint256) {
        require(_value > words[_wordid].collateral, "collateral Less than required");
        require(ownerOf(_wordid) == address(this), "held by somebody");
        require(words[_wordid].biddingPeriod == 0 || now - words[_wordid].biddingPeriod < biddingLockingPeriod,
                "not in bidding period");        

        address LPAddress = getPoolLPToken(poolId);

        // if there is the original owner, refund
        if(words[_wordid].owner != address(0)) {
            _depositMovePool(poolId, _wordid, words[_wordid].collateral,
                            relatedPoolId, words[_wordid].owner);
        }

        // purchase
        if(_poolid == poolId) {
            // purchase from wallet
            require(IERC20(LPAddress).transferFrom(msg.sender, address(this), _value),
                    "transfer token error");
            require(IERC20(LPAddress).approve(poolAddress, _value),
                    "approve token error");
            require(StarPools(poolAddress).deposit(poolId, address(_wordid), _value, _referrer), 
                    "deposit token error");
        }else if(_poolid == relatedPoolId) {
            // purchase from related pool
            require(StarPools(poolAddress).depositMove(relatedPoolId, msg.sender, _value, poolId, address(_wordid)),
                    "collateral move error");
        }else{
            require(false, "no match pool for pay");
        }

        emit biddingWord(msg.sender, _wordid, _poolid, _value, 
                        words[_wordid].owner, words[_wordid].collateral, words[_wordid].biddingPeriod);

        // define word ownership
        words[_wordid].owner = msg.sender;
        words[_wordid].collateral = _value;
        words[_wordid].biddingPeriod = now;
        words[_wordid].positionLocking = 0;
        return _value;
    }

    function harvest(uint256 _wordid) public {
        require(words[_wordid].owner == msg.sender, "not bidding winner");
        require(ownerOf(_wordid) == address(this), "held by someone");
        require(now - words[_wordid].biddingPeriod > biddingLockingPeriod, // 86400 = 60*60*24
                "not in bidding period ending");   

        emit harvestWord(msg.sender, _wordid, now - words[_wordid].biddingPeriod);

        _transfer(address(this), msg.sender, _wordid);

        words[_wordid].positionLocking = words[_wordid].biddingPeriod + biddingLockingPeriod;
    }

    function _ishold(uint256 _wordid) internal view returns (bool) {
        if(ownerOf(_wordid) == msg.sender) {
            // in position Locking time
            require(now - words[_wordid].positionLocking > positionLockingPeriod, "in position Locking time");  // 1296000 = 60*60*24*15
        }else if(ownerOf(_wordid) == address(this)) {
            // bidder success but not hold ntf token
            require(words[_wordid].owner == msg.sender, "only bidder can do");
            require(words[_wordid].positionLocking == 0 && now - words[_wordid].biddingPeriod > (positionLockingPeriod + biddingLockingPeriod),  // 1382400 = 60*60*24*16
                    "long over biddingPeriod time");
        }else{
            require(false, "have nothing");
        }
        return true;
    }

    function release(uint256 _wordid) public {
        _ishold(_wordid);

        if(ownerOf(_wordid) == msg.sender) {
            _transfer(msg.sender, address(this), _wordid);
        }

        _depositMovePool(poolId, _wordid, words[_wordid].collateral,
                            relatedPoolId, msg.sender);

        emit releaseWord(msg.sender, _wordid, words[_wordid].collateral, 
                        now-words[_wordid].positionLocking);

        // make ntf token as newer
        words[_wordid].owner = address(0);
        words[_wordid].collateral = lowAmount();
        words[_wordid].biddingPeriod = 0;
        words[_wordid].positionLocking = 0;
    }

    function claim(uint256 _wordid, address _to) public returns (bool){
        require(ownerOf(_wordid) == msg.sender || 
                (ownerOf(_wordid) == address(this) && words[_wordid].owner == msg.sender),  "not allowed");

        require(StarPools(poolAddress).claim(poolId, address(_wordid), _to), 
                    "claim token error");

        emit claimInvoked(msg.sender, poolId, _wordid, _to);
        return true;
    }
}
