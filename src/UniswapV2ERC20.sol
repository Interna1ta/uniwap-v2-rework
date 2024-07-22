// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "solady/src/tokens/ERC20.sol";

contract UniswapV2ERC20 is ERC20 {
    string private s_name;
    string private s_symbol;

    constructor() {
        s_name = "Pair Token";
        s_symbol = "PAIR";
    }

    function name() public view virtual override returns (string memory) {
        return s_name;
    }

    function symbol() public view virtual override returns (string memory) {
        return s_symbol;
    }
}