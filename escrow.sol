// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract escrow {
    address immutable owner;
    uint96 public fee;
    uint256 public dealNumber;
    struct Deal {
        address seller;
        uint96 valueSeller;
        address buyer;
        uint96 valueBuyer;
        address token;
        string messageSeller;
        string messageBuyer;
        bool completed;
    }
    mapping(address=>uint) public ownerFunds;
    mapping(uint256 => Deal) public deals;
    mapping(address => uint256[]) private activeDeals;
    mapping(address => uint256[]) private completedDeals;
    mapping(address => bool) public allowedTokens;

    event NewDeal(
        uint256 dealNumber,  
        uint256 dealValue,  
        address seller, 
        string message
    );

    event NewDealWithToken(
        uint256 dealNumber, 
        uint256 dealValue, 
        address seller,
        address token,
        string message
    );

    event Abort(uint256 dealNumber, uint256 dealValue, address seller);
    event Purchase(uint256 dealNumber, address buyer, string message);
    event DealComplete(uint256 dealNumber);

    

    constructor() {
        owner = msg.sender;
    }

    function createDeal(address _buyer, string calldata _message) external payable {
        require(msg.value >= 0.001 ether, "minimum 0.001ETH");
        unchecked {
            ++dealNumber;
        }
        Deal storage newDeal = deals[dealNumber];
        newDeal.valueSeller = uint96(msg.value);
        newDeal.seller = msg.sender;
        newDeal.messageSeller = _message;
        if(_buyer!=address(0)){
            require(_buyer != msg.sender, "no sense");
            newDeal.buyer = _buyer;
        }
        activeDeals[msg.sender].push(dealNumber);
        emit NewDeal(dealNumber, msg.value, msg.sender, _message);
    } 
    
    function createDeal(address _buyer, address _token, uint96 _amount, string calldata _message) external {
        require(allowedTokens[_token], "unknown token");
        (, bytes memory response) = address(_token).staticcall(
            abi.encodeWithSignature("decimals()")
        ); 
        require(_amount/10**abi.decode(response, (uint))>=1, "minimum 1 token");
        transferFromERC20(_token, msg.sender, address(this), _amount);
        unchecked {
            ++dealNumber;
        }
        Deal storage newDeal = deals[dealNumber];
        newDeal.valueSeller = _amount;
        newDeal.seller = msg.sender;
        newDeal.messageSeller = _message;
        newDeal.token = _token;
        if(_buyer!=address(0)){
            require(_buyer != msg.sender, "no sense");
            newDeal.buyer = _buyer;
        }
        activeDeals[msg.sender].push(dealNumber);
        emit NewDealWithToken(dealNumber, _amount, msg.sender, _token, _message);
    }  

    function abort(uint256 _dealNumber) external {
        Deal storage abortDeal = deals[_dealNumber];
        require(abortDeal.valueBuyer == 0, "Locked from buyer!");
        require(abortDeal.seller == msg.sender, "No have right to abort!");
        uint96 amount = abortDeal.valueSeller;
        delete abortDeal.valueSeller; 
        delete abortDeal.seller;
        delete abortDeal.messageSeller;
        if(abortDeal.buyer != address(0)){
            delete abortDeal.buyer;
        }
        removeFromActive(_dealNumber, msg.sender);
        if(abortDeal.token == address(0)){
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success);
        } else {
            transferERC20(abortDeal.token, msg.sender, amount);
        }
        emit Abort(_dealNumber, amount, msg.sender); 
    } 
    
    function confirmPurchase(uint256 _dealNumber, string calldata _message) external payable {
        Deal storage dealForPurchase = deals[_dealNumber];
        require(dealForPurchase.valueBuyer == 0, "don't do it twice");
        
        //we just multiply valueSeller by 2 here
        uint x = dealForPurchase.valueSeller;
        uint96 amount;
        assembly{
            amount := shl(1, x)
        } 

        require(amount != 0, "Wrong value!"); 
        if(dealForPurchase.token == address(0)){
            require(msg.value == amount, "Wrong value!");   
        } else {
            transferFromERC20(dealForPurchase.token, msg.sender, address(this), amount);
        }
        dealForPurchase.valueBuyer = amount;
        if(dealForPurchase.buyer != address(0)){
            require(dealForPurchase.buyer == msg.sender, "you are not buyer");
        } else {
            require(dealForPurchase.seller != msg.sender, "no sense");
            dealForPurchase.buyer = msg.sender;
        }
        dealForPurchase.messageBuyer = _message;
        activeDeals[msg.sender].push(_dealNumber);
        emit Purchase(_dealNumber, msg.sender, _message);
    }
    
    function confirmReceipt(uint256 _dealNumber) external {
        Deal storage dealForComplete = deals[_dealNumber];
        require(dealForComplete.buyer == msg.sender, "You are not a buyer!");
        require(!dealForComplete.completed, "already completed");
        dealForComplete.completed=true;
        uint96 amountB = dealForComplete.valueBuyer;
        uint96 amountS = dealForComplete.valueSeller;
        uint256 amountOwner;
        removeFromActive(_dealNumber, msg.sender);
        removeFromActive(_dealNumber, dealForComplete.seller); 
        completedDeals[msg.sender].push(_dealNumber);
        completedDeals[dealForComplete.seller].push(_dealNumber);   
        unchecked {
            if(fee!=0) {
                amountS >= 10 ether
                ? amountOwner = (amountS * fee) / 2000  // >10ETH  if (fee=10) 0.5%
                : amountOwner = (amountS * fee) / 1000; // <10ETH  if (fee=10) 1%
            }
            if(dealForComplete.token == address(0)){
                (bool success, ) = dealForComplete.seller.call{value: amountB - (amountOwner / 2)}("");
                require(success);
                (bool success1, ) = msg.sender.call{value: amountS - (amountOwner / 2)}("");
                require(success1);
                ownerFunds[address(0)] += amountOwner;
            } else {
                transferERC20(dealForComplete.token, dealForComplete.seller, amountB - (amountOwner / 2));
                transferERC20(dealForComplete.token, msg.sender, amountS - (amountOwner / 2));
                ownerFunds[dealForComplete.token] += amountOwner;
            }
        }
        emit DealComplete(_dealNumber);
    }

    function withdraw(address _token) external {
        require(msg.sender == owner, "You are not an owner!");
        uint256 amount = ownerFunds[_token];
        delete ownerFunds[_token];
        if(_token == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success);
        } else {
            transferERC20(_token, msg.sender, amount);
        }
    }

//////////////PRIVATE //////////////////////////
    function transferERC20(address _token, address _to, uint _amount) private {
        (bool success, bytes memory response) = address(_token).call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                _to,
                _amount)
        );
        require(success && (response.length == 0 || abi.decode(response, (bool))), "Failed send funds");
    }    

    function transferFromERC20(address _token, address _from, address _to, uint _amount) private {
        (bool success, bytes memory response) = address(_token).call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                _from,
                _to,
                _amount)
        );
        require(success && (response.length == 0 || abi.decode(response, (bool))), "Failed send funds");
    } 

    function removeFromActive(uint _dealNumber, address _target) private {
        uint length = activeDeals[_target].length;
        for(uint i; i<length;) {
            if (activeDeals[_target][i] == _dealNumber){
                delete activeDeals[_target][i];
                break;
            }
            unchecked {
                ++i;
            }
        }
    }  
//////////////SETTER ///////////////////////////
    function setFee(uint96 _fee) external {
        require(msg.sender == owner, "You are not an owner!");
        require(_fee < 11);
        fee = _fee;
    }

    function setAllowedToken(address _token) external {
        require(msg.sender == owner, "You are not an owner!");
        require(_token!=address(0));
        bool isAllowed = allowedTokens[_token];
        allowedTokens[_token] = !isAllowed;
    }
//////////////GETTER ///////////////////////////
    function getActiveDeals(address _adr) external view returns (uint[] memory) {
        return activeDeals[_adr];
    }

    function getCompletedDeals(address _adr) external view returns (uint[] memory) {
        return completedDeals[_adr];
    }
}
