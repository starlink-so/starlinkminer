
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;
// import {Console} from "./libs/DebugLogs.sol";

contract DebugLogs {
    event DebugLogUint(string, uint);
    function log(string memory s, uint256 x) internal {
        emit DebugLogUint(s, x);
    }    
    
    event DebugLogUint9(string, uint);
    function log9(string memory s, uint256 x) internal {
        emit DebugLogUint9(s, x);
    }

    event DebugLogUint18(string, uint);
    function log18(string memory s, uint256 x) internal {
        emit DebugLogUint18(s, x);
    }
    
    event DebugLogInt(string, int);
    function log(string memory s , int x) internal {
        emit DebugLogInt(s, x);
    }
    
    event DebugLogBytes(string, bytes);
    function log(string memory s , bytes memory x) internal {
        emit DebugLogBytes(s, x);
    }
    
    event DebugLogBytes32(string, bytes32);
    function log(string memory s , bytes32 x) internal {
        emit DebugLogBytes32(s, x);
    }

    event DebugLogAddress(string, address);
    function log(string memory s , address x) internal {
        emit DebugLogAddress(s, x);
    }

    event DebugLogBool(string, bool);
    function log(string memory s , bool x) internal {
        emit DebugLogBool(s, x);
    }
}