// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SLNToken} from "./SLNToken.sol";

contract StarPools is Ownable {
    using SafeMath for uint256;

    struct PoolInfo {
            address LPToken;      // collateral token  10**18
            address LPLimit;      // Restricted contract
            uint256 LPAmount;     // collateral amount, base LPToken token decimals
            uint256 factor;       // Mining Factor  10**9
            uint256 weight;        // LP to weight  10**9
            uint256 start;        // Starting Time
            uint256 ending;       // End Time  0=no ending  >0 = timestamps
            // uint256 fundbase;     // starting points
            bool paused;          // pool paused
    }

    PoolInfo[] public pools; // pools info
    mapping(uint256 => mapping (address => bool)) private invested;  // Invested
    mapping(uint256 => address[]) private investors;  // investors list
    mapping (uint256 => mapping (address => uint256)) public deposits;  // amount of collateral per person
    mapping (uint256 => mapping (address => uint256)) public points;    // amount of points per person
    mapping (uint256 => mapping (address => uint256)) private extracts;  // person's sln fixed , negative
    mapping (uint256 => mapping (address => uint256)) private retains;   // person's sln fixed , positive
    mapping (address => address) public referrers;      // Invitation relationship // DEBUG private

    SLNToken public profitToken;

    uint256 public totalPoints;
    uint256 private fixPoolValueAdd; // pool total value fixed, positive
    uint256 private fixPoolValueDec; // pool total value fixed, negative

    event factorReset(uint256 poolid, uint256 oldfactor, uint256 newfactor, uint256 users);
    event depositInvoked(address from, uint256 indexed poolid, address indexed account, uint256 value);
    event withdrawInvoked(address from, uint256 poolid, address account, uint256 value, address to, uint256 retain);
    event depositMoveInvoked(address from, uint256 poolid, address account, uint256 value, uint256 topoolid, address toaccount);
    event joinInvoked(address from, uint256 poolid, address account, uint256 value, uint256 points, uint256 poolValue);
    event quitInvoked(address from, uint256 poolid, address account, uint256 value, uint256 points, uint256 poolValues);
    event claimInvoked(address from, uint256 poolid, address account, address to);
    event claimMoveInvoked(address from, uint256 poolid, address account, uint256 value, uint256 topoolid, address toaccount);
    event inviter(address, address);

    constructor(
        address _profitToken
    ) public {
        profitToken = SLNToken(_profitToken);
    }

    // Pool Management mechanism

    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    function addPool(address _LPToken, address _LPLimit, uint256 _factor, uint256 _weight) 
                    external onlyOwner returns (uint256) {
        uint256 ending = now + (365 days)*10;  // 10 years
        pools.push(PoolInfo(_LPToken, _LPLimit, 0, _factor, _weight, now, ending, false));
        uint256 poolid = pools.length-1;
        // pools[poolid].fundbase = _profitnow(pools[poolid].factor*pools[poolid].weight/(10**9));
        return poolid;
    }

    function setPool(uint256 _poolid, address _LPLimit, uint256 _start, uint256 _ending,
                    bool _paused) external onlyOwner returns (uint256) {
        require(_poolid < pools.length , "pool id is not existing!");
        pools[_poolid].LPLimit = _LPLimit;
        pools[_poolid].start = _start;
        pools[_poolid].ending = _ending;  // 10 years
        pools[_poolid].paused = _paused;
        return _poolid;
    }

    function setLiveFactor(uint256 _poolid, uint256 _factor, uint256 _weight) external onlyOwner {
        address account;
        uint256 value;

        for(uint256 i = 0; i< investors[_poolid].length; i ++) {
            _quit(_poolid, investors[_poolid][i], 0);
        }
        
        emit factorReset(_poolid, pools[_poolid].factor, _factor, investors[_poolid].length);

        pools[_poolid].factor = _factor;
        pools[_poolid].weight = _weight;

        for(uint256 i = 0; i< investors[_poolid].length; i ++) {
            account = investors[_poolid][i];
            value = deposits[_poolid][account];
            _join(_poolid, account, value);
        }
    }

    // Investment mechanism
    function deposit(uint256 _poolid, address _account, uint256 _value, address _referrer) external returns (bool) {
        // Add collateral
        require(!pools[_poolid].paused && pools[_poolid].ending > now && pools[_poolid].start < now, "pool had paused or not started");
        // require((pools[_poolid].LPLimit == address(0) && _account == msg.sender) || 
        //         pools[_poolid].LPLimit == msg.sender, "limited by contract");

        // the fund pool Investor
        if(!invested[_poolid][_account]) {
            investors[_poolid].push(_account);
            invested[_poolid][_account] = true;
        }

        emit depositInvoked(msg.sender, _poolid, _account, _value);

        deposits[_poolid][_account] = deposits[_poolid][_account].add(_value);
        pools[_poolid].LPAmount = pools[_poolid].LPAmount.add(_value);

        require(IERC20(pools[_poolid].LPToken).transferFrom(msg.sender, address(this), _value),
                "transfer2 token error");

        _join(_poolid, _account, _value);
        _setInviter(_account, _referrer);
        return true;
    }

    function withdraw(uint256 _poolid, address _account, address _to) external {
        // withdraw collateral
        require(!pools[_poolid].paused, "pool had paused");
        require((pools[_poolid].LPLimit == address(0) && _account == msg.sender) || 
                pools[_poolid].LPLimit == msg.sender, "limited by contract");

        uint256 value = deposits[_poolid][_account];

        deposits[_poolid][_account] = deposits[_poolid][_account].sub(value);
        pools[_poolid].LPAmount = pools[_poolid].LPAmount.sub(value);

        require(IERC20(pools[_poolid].LPToken).transfer(_to, value),
                "transfer token error");

        emit withdrawInvoked(msg.sender, _poolid, _account, value, _to, deposits[_poolid][_account]);

        _quit(_poolid, _account, 0);
        return;
    }

    function depositMove(uint256 _poolid, address _account, uint256 _value, 
                uint256 _topoolid, address _toaccount) 
                external returns (bool)  {

        require(!pools[_poolid].paused && !pools[_topoolid].paused, "pool or topoolid had paused");
        require(pools[_poolid].LPLimit == msg.sender || pools[_topoolid].LPLimit == msg.sender, "must call from limit");
        
        if(!invested[_topoolid][_toaccount]) {
            investors[_topoolid].push(_toaccount);
            invested[_topoolid][_toaccount] = true;
        }

        pools[_poolid].LPAmount = pools[_poolid].LPAmount.sub(_value);
        deposits[_poolid][_account] = deposits[_poolid][_account].sub(_value);
        pools[_topoolid].LPAmount = pools[_topoolid].LPAmount.add(_value);
        deposits[_topoolid][_toaccount] = deposits[_topoolid][_toaccount].add(_value);

        emit depositMoveInvoked(msg.sender, _poolid, _account, _value, _topoolid, _toaccount);

        _quit(_poolid, _account, _value);
        _join(_topoolid, _toaccount, _value);
        return true;
    }

    // Mining mechanism
    function _profitnow(uint256 _points) internal view returns (uint256) {
        // Calculate the current income of the share
        uint256 PoolVal = profitToken.calcPoolValue()
                            .add(fixPoolValueAdd)
                            .sub(fixPoolValueDec);
        if(totalPoints == 0) {
            return PoolVal;
        }
        return PoolVal * _points / totalPoints;
    }

    function _join(uint256 _poolid, address _account, uint256 _value) internal returns (bool)  {
        uint256 lpDecimals = ERC20(pools[_poolid].LPToken).decimals();
        uint256 newPoints = pools[_poolid].factor * _value * pools[_poolid].weight / (10**lpDecimals);

        uint256 oldTotalPoints = totalPoints;
        points[_poolid][_account] = points[_poolid][_account].add(newPoints);
        totalPoints = totalPoints.add(newPoints);
    
        uint256 poolValue = profitToken.calcPoolValue().add(fixPoolValueAdd).sub(fixPoolValueDec);
        if(oldTotalPoints != 0) {
            uint256 fixValue = poolValue * newPoints / oldTotalPoints;
            if(fixValue <= fixPoolValueDec){
                fixPoolValueDec = fixPoolValueDec.sub(fixValue);
            }else{
                fixPoolValueAdd = fixPoolValueAdd.add(fixValue);
            }
        }

        emit joinInvoked(msg.sender, _poolid, _account, _value, newPoints, poolValue);

        uint256 extVal = _profitnow(newPoints);
        extracts[_poolid][_account] = extracts[_poolid][_account].add(extVal);
        return true;
    }
    
    function _quit(uint256 _poolid, address _account, uint256 _value) internal returns (bool) {
        uint256 thePoints = 0;
        
        if(_value == 0) {
            thePoints = points[_poolid][_account];
        }else{
            uint256 lpDecimals = ERC20(pools[_poolid].LPToken).decimals();
            thePoints = pools[_poolid].factor * _value * pools[_poolid].weight / (10**lpDecimals);
            if(thePoints > points[_poolid][_account]) {
                thePoints = points[_poolid][_account];
            }
        }

        uint256 extVal = _profitnow(thePoints);
        
        points[_poolid][_account] = points[_poolid][_account].sub(thePoints);
        totalPoints = totalPoints.sub(thePoints);
        if(extVal <= fixPoolValueAdd){
            fixPoolValueAdd = fixPoolValueAdd.sub(extVal);
        }else{
            fixPoolValueDec = fixPoolValueDec.add(extVal);
        }

        emit quitInvoked(msg.sender, _poolid, _account, extVal, thePoints, totalPoints);

        if(extracts[_poolid][_account] >= extVal) {
            extracts[_poolid][_account] = extracts[_poolid][_account].sub(extVal);
            extVal = 0;
        }else if(extracts[_poolid][_account] > 0 && extracts[_poolid][_account] < extVal) {
            extVal = extVal.sub(extracts[_poolid][_account]);
            extracts[_poolid][_account] = 0;
        }
        if(extVal > 0) {
            retains[_poolid][_account] = retains[_poolid][_account].add(extVal);
        }

        return true;
    }

    function balanceOf(uint256 _poolid, address _account) public view returns (uint256) {
        uint256 extVal = retains[_poolid][_account];
        if (points[_poolid][_account] > 0) {
            extVal = extVal + _profitnow(points[_poolid][_account]);
        }
        extVal = extVal.sub(extracts[_poolid][_account]);
        return extVal;
    }

    // claim profit or Extended contract claim profit
    function claim(uint256 _poolid, address _account, address _to) external returns (bool)  {
        require(!pools[_poolid].paused, "pool had paused");

        uint256 extVal = balanceOf(_poolid, _account);
        if(pools[_poolid].LPLimit == address(0)) {
            require(_account == msg.sender, "account not sender");
        }else{
            require(pools[_poolid].LPLimit == msg.sender, "limit call from contract");
        }

        if(extVal <= retains[_poolid][_account]){
            retains[_poolid][_account] = retains[_poolid][_account].sub(extVal);
        }else{
            extracts[_poolid][_account] = extracts[_poolid][_account].add(extVal);
        }
        require(profitToken.claim(_to, extVal), "claim call error");

        emit claimInvoked(msg.sender, _poolid, _account, _to);

        return true;
    }

    // Extended contract claim profit
    function claimMove(uint256 _poolid, address _account, uint256 _topoolid, address _toaccount) external returns (bool)  {
        require(!pools[_poolid].paused && !pools[_topoolid].paused, "pool topoolid had paused");
        require(pools[_poolid].LPLimit == msg.sender || pools[_topoolid].LPLimit == msg.sender, "must call from limit");

        uint256 extVal = balanceOf(_poolid, _account);
        if(extVal <= retains[_poolid][_account]){
            retains[_poolid][_account] = retains[_poolid][_account].sub(extVal);
        }else{
            extracts[_poolid][_account] = extracts[_poolid][_account].add(extVal);
        }

        retains[_topoolid][_toaccount] = retains[_topoolid][_toaccount].add(extVal);

        emit claimMoveInvoked(msg.sender, _poolid, _account, extVal, _topoolid, _toaccount);
        return true;
    }

    // Invitation mechanism
    function _setInviter(address _account, address _referrer) internal {
        if(_referrer == address(0)) {
            return;
        }
        if(referrers[_account] != address(0)) {
            return;
        }
        require(_account != _referrer, "Invite yourself?");

        referrers[_account] = _referrer;
        emit inviter(_account, _referrer);
        return;
    }

    // For ui display
    function annualPerShare(uint256 _poolid) external view returns (uint256) {
        uint256 value = profitToken.tokensThisWeek() * 900 / 1000;
        if(totalPoints > 0){
            value = value * 1 * pools[_poolid].factor *  pools[_poolid].weight / totalPoints;
        }
        value = value * (365 days) / (1 weeks);
        return value;
    }

}
