// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Logarithm.sol";
import "./TransferHelper.sol";

// This is common token interface, get balance of owner's token by ERC20/ERC721.
interface ICommonToken {
    function balanceOf(address owner) external returns(uint256);
}

interface IPancakeRouter02 {
   
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (
        uint amountToken,
        uint amountETH,
        uint liquidity
    );
}

interface IPancakeFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;

    function INIT_CODE_PAIR_HASH() external view returns (bytes32);
}

contract WNULS {
    string public name     = "Wrapped NULS";
    string public symbol   = "WNULS";
    uint8  public decimals = 18;

    event  Approval(address indexed src, address indexed guy, uint wad);
    event  Transfer(address indexed src, address indexed dst, uint wad);
    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);

    mapping (address => uint)                       public  balanceOf;
    mapping (address => mapping (address => uint))  public  allowance;


    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    function withdraw(uint wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != type(uint).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}

interface IPancakePair {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

// This contract is extended from ERC20
contract InscriptionV2 is ERC20, ReentrancyGuard {
    using Logarithm for int256;
    uint256 public cap;                 // Max amount
    uint256 public limitPerMint;        // Limitaion of each mint
    uint256 public inscriptionId;       // Inscription Id
    uint256 public maxMintSize;         // max mint size, that means the max mint quantity is: maxMintSize * limitPerMint
    uint256 public freezeTime;          // The frozen time (interval) between two mints is a fixed number of seconds. You can mint, but you will need to pay an additional mint fee, and this fee will be double for each mint.
    address public onlyContractAddress; // Only addresses that hold these assets can mint
    uint256 public onlyMinQuantity;     // Only addresses that the quantity of assets hold more than this amount can mint
    uint256 public baseFee;             // base fee of the second mint after frozen interval. The first mint after frozen time is free.
    uint256 public fundingCommission;   // commission rate of fund raising, 100 means 1%
    uint256 public crowdFundingRate;    // rate of crowdfunding
    address payable public crowdfundingAddress; // receiving fee of crowdfunding
    address payable public inscriptionFactory;
    uint256 public percent;    
    mapping(address => uint256) public lastMintTimestamp;   // record the last mint timestamp of account
    mapping(address => uint256) public lastMintFee;           // record the last mint fee
    address public swapAddress;
    address public wnuls = address(0x888279a0df02189078e3E68fbD93D35183E1Fc69);   
    address public pairAddress;
    address public routerAddress = address(0xcC81d3B057c16DFfe778D2d342CfF40d33bD69A7); //router address

    uint public flag = 0;

    constructor(
        string memory _name,            // token name
        string memory _tick,            // token tick, same as symbol. must be 4 characters.
        uint256 _cap,                   // Max amount
        uint256 _limitPerMint,          // Limitaion of each mint
        uint256 _inscriptionId,         // Inscription Id
        uint256 _maxMintSize,           // max mint size, that means the max mint quantity is: maxMintSize * limitPerMint. This is only availabe for non-frozen time token.
        uint256 _freezeTime,            // The frozen time (interval) between two mints is a fixed number of seconds. You can mint, but you will need to pay an additional mint fee, and this fee will be double for each mint.
        address _onlyContractAddress,   // Only addresses that hold these assets can mint
        uint256 _onlyMinQuantity,       // Only addresses that the quantity of assets hold more than this amount can mint
        uint256 _baseFee,               // base fee of the second mint after frozen interval. The first mint after frozen time is free.
        uint256 _fundingCommission,     // commission rate of fund raising, 100 means 1%
        uint256 _crowdFundingRate,      // rate of crowdfunding
        address payable _crowdFundingAddress,   // receiving fee of crowdfunding
        address payable _inscriptionFactory,
        uint256 _percent,
        address _swapAddress
    ) ERC20(_name, _tick) {
        require(_cap >= _limitPerMint, "Limit per mint exceed cap");
        cap = _cap;
        limitPerMint = _limitPerMint;
        inscriptionId = _inscriptionId;
        maxMintSize = _maxMintSize;
        freezeTime = _freezeTime;
        onlyContractAddress = _onlyContractAddress;
        onlyMinQuantity = _onlyMinQuantity;
        baseFee = _baseFee;
        fundingCommission = _fundingCommission;
        crowdFundingRate = _crowdFundingRate;
        percent = _percent; 
        crowdfundingAddress = _crowdFundingAddress;
        inscriptionFactory = _inscriptionFactory;
        swapAddress = _swapAddress;
    }

    
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if(crowdFundingRate > 0 && percent > 0 ) {
            require(flag == 0, "token is locking");
        }
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if(crowdFundingRate > 0 && percent > 0 ) {
            require(flag == 0, "token is locking");
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

   

    function mint(address _to) payable public nonReentrant {
        require(msg.sender == tx.origin, "only EOA");
        require(msg.sender == _to, "only self mint");
        // Check if the quantity after mint will exceed the cap
        require(totalSupply() + limitPerMint <= cap, "Touched cap");
        // Check if the assets in the msg.sender is satisfied
        require(onlyContractAddress == address(0x0) || ICommonToken(onlyContractAddress).balanceOf(msg.sender) >= onlyMinQuantity, "You don't have required assets");

        if(lastMintTimestamp[msg.sender] + freezeTime > block.timestamp) {
            // The min extra tip is double of last mint fee
            lastMintFee[msg.sender] = lastMintFee[msg.sender] == 0 ? baseFee : lastMintFee[msg.sender] * 2;
            // Transfer the fee to the crowdfunding address
            if(crowdFundingRate > 0) {
                // Check if the tip is high than the min extra fee
                require(msg.value >= crowdFundingRate + lastMintFee[msg.sender], "Send some NULS as fee and crowdfunding");
                _dispatchFunding(crowdFundingRate);
            }
            // double check the tip
            require(msg.value >= crowdFundingRate + lastMintFee[msg.sender], "Insufficient mint fee");
            // Transfer the tip to InscriptionFactory smart contract
            if(msg.value - crowdFundingRate > 0) TransferHelper.safeTransferETH(inscriptionFactory, msg.value - crowdFundingRate);
        } else {
            // Transfer the fee to the crowdfunding address
            if(crowdFundingRate > 0) {
                require(msg.value >= crowdFundingRate, "Send some NULS as crowdfunding");
                _dispatchFunding(msg.value);
            }
            
            // Out of frozen time, free mint. Reset the timestamp and mint times.
            lastMintFee[msg.sender] = 0;
            lastMintTimestamp[msg.sender] = block.timestamp;
        }
        uint256 totalPercent = 100;
        uint256 remainingPercent =  totalPercent - uint256(percent);
        uint256 lastMintNum = limitPerMint * remainingPercent/totalPercent;
        // Do mint
        _mint(_to, lastMintNum);
        if(totalSupply() == cap){
            flag = 0;
        }
    }

    // batch mint is only available for non-frozen-time tokens
    function batchMint(address _to, uint256 _num) payable public nonReentrant {
        require(msg.sender == tx.origin, "only EOA");
        require(msg.sender == _to, "only self mint");
        require(_num <= maxMintSize, "exceed max mint size");
        require(totalSupply() + _num * limitPerMint <= cap, "Touch cap");
        require(freezeTime == 0, "Batch mint only for non-frozen token");
        require(onlyContractAddress == address(0x0) || ICommonToken(onlyContractAddress).balanceOf(msg.sender) >= onlyMinQuantity, "You don't have required assets");
        if(crowdFundingRate > 0) {
            require(msg.value >= crowdFundingRate * _num, "Crowdfunding NULS not enough");
            _dispatchFunding(msg.value);
            // IPancakeRouter01(_contractAddress).addLiquidityETH(address(this),10,10,10,msg.sender(),10);
        }
        for(uint256 i = 0; i < _num; i++)
        {   
             uint256 totalPercent = 100;
             uint256 remainingPercent =  totalPercent - uint256(percent);
             uint256 lastMintNum = limitPerMint * remainingPercent/totalPercent;
             _mint(_to, lastMintNum);
        }
    }

    function getMintFee(address _addr) public view returns(uint256 mintedTimes, uint256 nextMintFee) {
        if(lastMintTimestamp[_addr] + freezeTime > block.timestamp) {
            int256 scale = 1e18;
            int256 halfScale = 5e17;
            // times = log_2(lastMintFee / baseFee) + 1 (if lastMintFee > 0)
            nextMintFee = lastMintFee[_addr] == 0 ? baseFee : lastMintFee[_addr] * 2;
            mintedTimes = uint256((Logarithm.log2(int256(nextMintFee / baseFee) * scale, scale, halfScale) + 1) / scale) + 1;
        }
    }

     
    function getPercent( ) public view returns(uint256 currentPercent) {
        currentPercent = percent;
    }

    function getSwpFactoryAddress( ) public view returns(address currentSwapFactoryAddress) {
        currentSwapFactoryAddress = swapAddress;
    }

    function getPairAddress( ) public view returns(address currentPairAddress) {
        currentPairAddress =pairAddress ;
    }

    //    
    function _dispatchFunding(uint256 _amount) private {
        uint256 commission = _amount * fundingCommission / 10000;
        uint256  remainingAmount =  _amount - commission;
        if(commission > 0) TransferHelper.safeTransferETH(inscriptionFactory, commission);   
        if(percent > 0){
            if(IPancakeFactory(swapAddress).getPair(address(this),wnuls) == address(0)){
                address pair =  IPancakeFactory(swapAddress).createPair(address(this),wnuls);
                pairAddress = pair;
                uint256 lastAmount = limitPerMint*percent/100;
                _mint(address(this), lastAmount);
                uint _deadline= block.timestamp + 300;
                ERC20(address(this)).approve(address(routerAddress),0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                IPancakeRouter02(address(routerAddress)).addLiquidityETH{value: remainingAmount}(address(this),lastAmount,lastAmount,remainingAmount,address(this),_deadline);
                uint lpAmount = IPancakePair(pair).balanceOf(address(this));
                IPancakePair(pair).transfer(address(0x0000000000000000000000000000000000000000),lpAmount);
                IPancakePair(pair).sync();
                flag = 1;
            }else{
                 //
                WNULS(wnuls).deposit{value: remainingAmount}();
                WNULS(wnuls).transfer(pairAddress,remainingAmount);
                uint256 lastAmount = limitPerMint*percent/100;
                _mint(pairAddress, lastAmount);
                IPancakePair(pairAddress).sync();
            }
        }else{
                TransferHelper.safeTransferETH(crowdfundingAddress, remainingAmount); 
        }            
    }


}
