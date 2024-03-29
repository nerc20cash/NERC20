// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./InscriptionV2.sol";
import "./TransferHelper.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IFactory {
    struct Token {
        string tick;            // same as symbol in ERC20
        string name;            // full name of token
        uint256 cap;            // Hard cap of token
        uint256 limitPerMint;   // Limitation per mint
        uint256 maxMintSize;    // // max mint size, that means the max mint quantity is: maxMintSize * limitPerMint
        uint256 inscriptionId;  // Inscription id
        uint256 freezeTime;
        address onlyContractAddress;
        uint256 onlyMinQuantity;
        uint256 crowdFundingRate;
        address crowdfundingAddress;
        address minter;         // The minter of this token
        address addr;           // Contract address of inscribed token 
        uint256 timestamp;      // Inscribe timestamp
        uint256 percent;
        address swapAddress; 
    }
    function getInscriptionAmount() external view returns(uint256);
    function getIncriptionIdByTick(string memory _tick) external view returns(uint256);
    function getIncriptionById(uint256 _id) external view returns(Token memory, uint256);
}

contract InscriptionFactoryV2 is Ownable{
    using Counters for Counters.Counter;
    Counters.Counter private _inscriptionNumbers;

    uint8 public maxTickSize = 8;                 // tick(symbol) length is 4.
    uint8 public maxNameSize = 20;                // max name length is 50.
    uint256 public baseFee = 1000000000000000000;    // Will charge 1 NULS  as extra min tip from the second time of mint in the frozen period. And this tip will be double for each mint.
    uint256 public inscriptionFee = 10000000000000000000; // Will charge 10 NULS as inscription fee
    uint256 public fundingCommission = 100;       // commission rate of fund raising, 100 means 1%
    uint256 public maxFrozenTime = 86400;
    address public swapFactoryAddress = address(0x6af6Ef18f9d263577722462DA962cdf279299Fd7);         // The max frozen time is 1 day

    mapping(uint256 => Token) private inscriptions; // key is inscription id, value is token data
    mapping(string => uint256) private ticks;       // Key is tick, value is inscription id
    address public factoryV1;                       // The address of factory v1
    bool public launched = false;                   // Whether the factory is launched

    event DeployInscription(
        uint256 indexed id, 
        string tick, 
        string name, 
        uint256 cap, 
        uint256 limitPerMint, 
        address inscriptionAddress, 
        uint256 timestamp
    );

    struct Token {
        string tick;            // same as symbol in ERC20
        string name;            // full name of token
        uint256 cap;            // Hard cap of token
        uint256 limitPerMint;   // Limitation per mint
        uint256 maxMintSize;    // // max mint size, that means the max mint quantity is: maxMintSize * limitPerMint
        uint256 inscriptionId;  // Inscription id
        uint256 freezeTime;
        address onlyContractAddress;
        uint256 onlyMinQuantity;
        uint256 crowdFundingRate;
        address crowdfundingAddress;
        address minter;         // The minter of this token
        address addr;           // Contract address of inscribed token 
        uint256 timestamp;      // Inscribe timestamp
        uint256 percent;
        address swapAddress; 
    }

    

    constructor(address _factoryV1) {
        factoryV1 = _factoryV1;
        // The inscription id will be from 1, not zero.
        _inscriptionNumbers.increment();
    }

    // Let this contract accept NULS as tip
    receive() external payable {}
    
    function deploy(
        string memory _tick,
        string memory _name,
        uint256 _cap,
        uint256 _limitPerMint,
        uint256 _maxMintSize, // The max lots of each mint
        uint256 _freezeTime, // Freeze seconds between two mint, during this freezing period, the mint fee will be increased 
        address _onlyContractAddress, // Only the holder of this asset can mint, optional
        uint256 _onlyMinQuantity, // The min quantity of asset for mint, optional
        uint256 _crowdFundingRate,
        address _crowdFundingAddress,
        uint256 _percent
        // address _swapAddress
    ) payable external returns (address _inscriptionAddress) {
        require(launched, "Factory is not launched");
        address _swapAddress = swapFactoryAddress;
        require(_percent >=0 || _percent <= 100 , "_percent should be 0-100");
        require(strlen(_tick) <= maxTickSize || strlen(_tick) >=4, "Tick lenght should be 4");
        require(strlen(_name) <= maxNameSize, "Name lenght should be less than 20");
        require(_cap >= _limitPerMint, "Limit per mint exceed cap");
        require(_limitPerMint % 100 == 0, "100 not divisible by  _limitPerMint");
        require(_cap % _limitPerMint == 0, "Limit per not divisible by _cap");
        if (_onlyContractAddress != address(0)) {
            require(_onlyMinQuantity > 0, "Only min quantity should be greater than zero");
        } else {
            require(_onlyMinQuantity == 0, "Only min quantity should be zero");
        }
        require(_freezeTime <= maxFrozenTime, "Freeze time exceed max frozen time");
        if (_maxMintSize > 1) {
            require(_freezeTime == 0, "Freeze time should be zero when max mint size is greater than 1");
        }
        if (_crowdFundingRate > 0 || _crowdFundingAddress != address(0)) {
            require(_crowdFundingAddress != address(0), "Crowd funding address should not be zero");
            require(_crowdFundingRate > 0, "Crowd funding rate should be greater than zero");
        }
        
        _tick = toLower(_tick);
        require(this.getIncriptionIdByTick(_tick) == 0, "tick is existed");
        // require(IFactory(factoryV1).getIncriptionIdByTick(_tick) == 0, "tick is existed in factory v1");

        require(msg.value >= inscriptionFee, "Insufficient inscription fee");

        // Create inscription contract
        bytes memory bytecode = type(InscriptionV2).creationCode;
        uint256 _id = _inscriptionNumbers.current();
		bytecode = abi.encodePacked(bytecode, abi.encode(
            _name, 
            _tick, 
            _cap, 
            _limitPerMint, 
            _id, 
            _maxMintSize,
            _freezeTime,
            _onlyContractAddress,
            _onlyMinQuantity,
            baseFee,
            fundingCommission,
            _crowdFundingRate,
            _crowdFundingAddress,
            address(this),
             _percent,
            _swapAddress
        ));
		bytes32 salt = keccak256(abi.encodePacked(_id));
		assembly ("memory-safe") {
			_inscriptionAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
			if iszero(extcodesize(_inscriptionAddress)) {
				revert(0, 0)
			}
		}
        inscriptions[_id] = Token(
            _tick, 
            _name, 
            _cap, 
            _limitPerMint, 
            _maxMintSize,
            _id,
            _freezeTime,
            _onlyContractAddress,
            _onlyMinQuantity,
            _crowdFundingRate,
            _crowdFundingAddress,
            msg.sender,
            _inscriptionAddress, 
            block.timestamp,
            _percent,
            _swapAddress
        );
        ticks[_tick] = _id;

        _inscriptionNumbers.increment();
        emit DeployInscription(_id, _tick, _name, _cap, _limitPerMint, _inscriptionAddress, block.timestamp);
    }

    function getInscriptionAmount() external view returns(uint256) {
        return _inscriptionNumbers.current() - 1;
    }

    function getIncriptionIdByTick(string memory _tick) external view returns(uint256) {
        return ticks[toLower(_tick)];
    }

    function getIncriptionById(uint256 _id) external view returns(Token memory, uint256) {
        Token memory token = inscriptions[_id];
        return (inscriptions[_id], InscriptionV2(token.addr).totalSupply());
    }

    function getIncriptionByTick(string memory _tick) external view returns(Token memory, uint256) {
        Token memory token = inscriptions[this.getIncriptionIdByTick(_tick)];
        return (inscriptions[this.getIncriptionIdByTick(_tick)], InscriptionV2(token.addr).totalSupply());
    }

    function getInscriptionAmountByType(uint256 _type) external view returns(uint256) {
        require(_type < 3, "type is 0-2");
        uint256 totalInscription = this.getInscriptionAmount();
        uint256 count = 0;
        for(uint256 i = 1; i <= totalInscription; i++) {
            (Token memory _token, uint256 _totalSupply) = this.getIncriptionById(i);
            if(_type == 1 && _totalSupply == _token.cap) continue;
            else if(_type == 2 && _totalSupply < _token.cap) continue;
            else count++;
        }
        return count;
    }



    
    // Fetch inscription data by page no, page size, type and search keyword
    function getIncriptions(
        uint256 _pageNo, 
        uint256 _pageSize, 
        uint256 _type, // 0- all, 1- in-process, 2- ended
        string memory _searchBy
    ) external view returns(
        Token[] memory inscriptions_, 
        uint256[] memory totalSupplies_
    ) {
        // if _searchBy is not empty, the _pageNo and _pageSize should be set to 1
        require(_type < 3, "type is 0-2");
        uint256 totalInscription = this.getInscriptionAmount();
        uint256 pages = (totalInscription - 1) / _pageSize + 1;
        require(_pageNo > 0 && _pageSize > 0 && pages > 0 && _pageNo <= pages, "Params wrong");

        inscriptions_ = new Token[](_pageSize);
        totalSupplies_ = new uint256[](_pageSize);

        Token[] memory _inscriptions = new Token[](totalInscription);
        uint256[] memory _totalSupplies = new uint256[](totalInscription);

        uint256 index = 0;
        for(uint256 i = 1; i <= totalInscription; i++) {
            (Token memory _token, uint256 _totalSupply) = this.getIncriptionById(i);
            if(_type == 1 && _totalSupply == _token.cap) continue;
            else if(_type == 2 && _totalSupply < _token.cap) continue;
            else if(!compareStrings(_searchBy, "") && !compareStrings(toLower(_searchBy), _token.tick)) continue;
            else {
                _inscriptions[index] = _token;
                _totalSupplies[index] = _totalSupply;
                index++;
            }
        }

        for(uint256 i = 0; i < _pageSize; i++) {
            uint256 id = (_pageNo - 1) * _pageSize + i;
            if(id < index) {
                inscriptions_[i] = _inscriptions[id];
                totalSupplies_[i] = _totalSupplies[id];
            }
        }
    }

    // Withdraw the NULS tip from the contract
    function withdraw(address payable _to, uint256 _amount) external onlyOwner {
        require(_amount <= payable(address(this)).balance);
        TransferHelper.safeTransferETH(_to, _amount);
    }

    // Update base fee
    function updateBaseFee(uint256 _fee) external onlyOwner {
        baseFee = _fee;
    }

    // Update Launched
    function updateLaunched(bool flag) external onlyOwner {
       launched = flag;
    }

    function updateInscriptionFee(uint256 _inscriptionFee) external onlyOwner {
        inscriptionFee = _inscriptionFee;
    }


    // Update funding commission
    function updateFundingCommission(uint256 _rate) external onlyOwner {
        require(_rate >0 || _rate <= 2000 , "_rate should be 1-2000");
        fundingCommission = _rate;
    }

    // Update character's length of tick
    function updateTickSize(uint8 _size) external onlyOwner {
        maxTickSize = _size;
    }

    // migrate v1 inscription to v2
    function migrateV1Inscriptions() external onlyOwner {
        require(launched == false, "Already migrated");
        uint256 totalInscription = IFactory(factoryV1).getInscriptionAmount();
        for(uint256 i = 1; i <= totalInscription; i++) {
            (IFactory.Token memory _token, ) = IFactory(factoryV1).getIncriptionById(i);
            uint256 _id = _inscriptionNumbers.current();
            inscriptions[_id] = Token(
                _token.tick, 
                _token.name, 
                _token.cap, 
                _token.limitPerMint, 
                _token.maxMintSize,
                _token.inscriptionId,
                _token.freezeTime,
                _token.onlyContractAddress,
                _token.onlyMinQuantity,
                _token.crowdFundingRate,
                _token.crowdfundingAddress,
                _token.minter,
                _token.addr,
                _token.timestamp,
                _token.percent,
                _token.swapAddress
            );
            ticks[_token.tick] = _id;

            _inscriptionNumbers.increment();
        }
        launched = true;
    }

    function strlen(string memory s) internal pure returns (uint256) {
        uint256 len;
        uint256 i = 0;
        uint256 bytelength = bytes(s).length;

        for (len = 0; i < bytelength; len++) {
            bytes1 b = bytes(s)[i];
            if (b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
        }
        return len;
    }

    function toLower(string memory str) internal pure returns (string memory) {
		bytes memory bStr = bytes(str);
		bytes memory bLower = new bytes(bStr.length);
		for (uint i = 0; i < bStr.length; i++) {
			if (uint8(bStr[i]) >= 65 && uint8(bStr[i]) <= 90) {
				bLower[i] = bytes1(uint8(bStr[i]) + 32);
			} else {
				bLower[i] = bStr[i];
			}
		}
		return string(bLower);
	}

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function compareStrings(string memory a, string memory b) public pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }






}
