pragma solidity ^0.4.19;

import 'zeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import "./RangeProofVerifier.sol";
import "./alt_bn128.sol";

contract CoinMixer {
    using alt_bn128 for alt_bn128.G1Point;

    mapping (address => alt_bn128.G1Point) public deposits;
    event DepositToMixer(address indexed _address, uint256 _amount);
    event TransferByMixer(address indexed _address, uint256 _X, uint256 _Y);
    event WithdrawFromMixer(address indexed _address, uint256 _amount);
    RangeProofVerifier public verifier;

    uint256 public constant m = 4;
    uint256 public constant n = 2;

    ERC20 public token;

    alt_bn128.G1Point public peddersenBaseG;
    alt_bn128.G1Point public peddersenBaseH;

    function CoinMixer(
        uint256[4] coords, // [peddersenBaseG_x, peddersenBaseG_y, peddersenBaseH_x, peddersenBaseH_y]
        RangeProofVerifier _verifier,
        ERC20 _token) {
        require(_verifier.n() == n);
        require(_verifier.m() == m);
        verifier = _verifier;
        token = _token;
        peddersenBaseG = alt_bn128.G1Point(coords[0], coords[1]);
        peddersenBaseH = alt_bn128.G1Point(coords[2], coords[3]);
    }

    function deposit(uint256 value) external returns (bool) {
        require(deposits[msg.sender].eq(alt_bn128.G1Point(0, 0))); //TODO: move to lib
        require(token.transferFrom(msg.sender, this, value));
        deposits[msg.sender] = peddersenBaseG.mul(value);
        DepositToMixer(msg.sender, value);
        return true;
    }

    function withdraw(uint256 value, uint256 secret) external returns (bool) {
        require(peddersenBaseG.mul(value).add(peddersenBaseH.mul(secret)).eq(deposits[msg.sender]));
        assert(token.transfer(msg.sender, value));
        WithdrawFromMixer(msg.sender, value);
        return true;
    }

    function transfer(
        address address1,
        uint256 hiddenValue1_x,
        uint256 hiddenValue1_y,
        address address2,
        uint256 hiddenValue2_x,
        uint256 hiddenValue2_y
    ) external {
        alt_bn128.G1Point memory hiddenValue1 = alt_bn128.G1Point(hiddenValue1_x, hiddenValue1_y);
        alt_bn128.G1Point memory hiddenValue2 = alt_bn128.G1Point(hiddenValue2_x, hiddenValue2_y);
        require(hiddenValue1.add(hiddenValue2).eq(deposits[msg.sender]));
        deposits[msg.sender] = alt_bn128.G1Point(0, 0);
        deposits[address1] = hiddenValue1;
        deposits[address2] = hiddenValue2;
    }

    function transferWithProofs(
        address[2] addresses,
        uint256[20] coords, // [input_x, input_y, A_x, A_y, S_x, S_y, commits[0]_x, commits[0]_y, commits[1]_x, commits[1]_y]
        uint256[10] scalars, // [tauX, mu, t, a, b]
        uint256[2*2*n] ls_coords, // 2 * n
        uint256[2*2*n] rs_coords  // 2 * n
    ) external {
        uint256[10] memory scratchForCoords;
        uint256[5] memory scratchForScalars;
        uint256[2*n] memory scratchForLs;
        uint256[2*n] memory scratchForRs;
        for (uint8 i = 0; i < 2; i++) {
            uint8 j = 0;
            // bool success = false;
            for (j = 0; j < scratchForCoords.length; j++) {
                scratchForCoords[j] = coords[i*10 + j];
            }
            for (j = 0; j < scratchForScalars.length; j++) {
                scratchForScalars[j] = scalars[i*5 + j];
            }
            for (j = 0; j < scratchForLs.length; j++) {
                scratchForLs[j] = ls_coords[i*2*n + j];
            }
            for (j = 0; j < scratchForRs.length; j++) {
                scratchForRs[j] = rs_coords[i*2*n + j];
            }
            require(verifier.verify(scratchForCoords, scratchForScalars, scratchForLs, scratchForRs));
        }
        alt_bn128.G1Point memory hiddenValue0 = alt_bn128.G1Point(coords[0], coords[1]);
        alt_bn128.G1Point memory hiddenValue1 = alt_bn128.G1Point(coords[10], coords[11]);
        require(hiddenValue0.add(hiddenValue1).eq(deposits[msg.sender]));
        deposits[msg.sender] = alt_bn128.G1Point(0, 0);
        deposits[addresses[0]] = hiddenValue0;
        TransferByMixer(addresses[0], hiddenValue0.X, hiddenValue0.Y);
        deposits[addresses[1]] = hiddenValue1;
        TransferByMixer(addresses[1], hiddenValue1.X, hiddenValue1.Y);
    }
}
