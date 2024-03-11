// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract escrow {
    address owner;
    uint96 public fee;
    uint public dealNumber;
    uint public ownerFunds;
    mapping (uint=>Deal) public deals;
   
    event NewDeal(uint dealNumber, uint dealValue, address seller, string message);
    event Abort(uint dealNumber, uint dealValue, address seller);
    event Purchase(uint dealNumber, address buyer, string message);
    event DealComplete(uint dealNumber);

    struct  Deal  {
        address seller;
        uint96 valueSeller;
        address buyer;
        uint96 valueBuyer;
        string messageSeller;
        string messageBuyer;
    }

    constructor (uint96 _fee) {
        owner=msg.sender;
        fee=_fee;
    }
    
    function createDeal (string calldata _message) external payable {
        require (msg.value>=0.001 ether, "minimum 0.001ETH");
        unchecked {
            dealNumber++;
        }
        Deal storage newDeal = deals[dealNumber];
        newDeal.valueSeller = uint96(msg.value);
        newDeal.seller = msg.sender;
        newDeal.messageSeller = _message;
        emit NewDeal(dealNumber, msg.value, msg.sender, _message);
    }

    function abort (uint _dealNumber) external  {
        Deal storage abortDeal = deals[_dealNumber];
        require (abortDeal.valueBuyer==0, "Locked from buyer!");
        require (abortDeal.seller==msg.sender, "No have right to abort!");
        uint96 amount = abortDeal.valueSeller;
        unchecked {
            abortDeal.valueSeller -= amount;
        }
        payable(msg.sender).transfer(amount);
        emit Abort(_dealNumber, amount, msg.sender);
        }

    function confirmPurchase (uint _dealNumber, string calldata _message) external payable {
        Deal storage dealForPurchase = deals[_dealNumber];
        require (msg.value == 2 * dealForPurchase.valueSeller, "Wrong value!");
        require (dealForPurchase.valueBuyer==0, "don't do it twice!");
        require (msg.value!=0, "Wrong value!");
        dealForPurchase.valueBuyer = uint96(msg.value);
        dealForPurchase.buyer = msg.sender;
        dealForPurchase.messageBuyer = _message;
        emit Purchase(_dealNumber, msg.sender, _message);
    }

    function confirmReceipt (uint _dealNumber) external  {
        Deal storage dealForComplete = deals[_dealNumber];
        require(dealForComplete.buyer == msg.sender, "You are not a buyer!");
        uint96 amountB = dealForComplete.valueBuyer;
        uint96 amountS = dealForComplete.valueSeller;
        uint amountOwner;
        unchecked {
            amountS>=10 ether
            ? amountOwner = amountS*fee/2000  // >10ETH Fee - 0.5%
            : amountOwner = amountS*fee/1000; // <10ETH Fee - 1% 
            dealForComplete.valueBuyer -= amountB;
            dealForComplete.valueSeller -= amountS;
            payable(dealForComplete.seller).transfer(amountB -(amountOwner/2));
            payable(msg.sender).transfer(amountS-(amountOwner/2));
            ownerFunds += amountOwner;
        }
        emit DealComplete(_dealNumber);
    }

    function withdraw() external  {
        require (msg.sender==owner, "You are not an owner!");
        uint amount = ownerFunds;
        unchecked{
            ownerFunds -= amount;
        }
        payable(msg.sender).transfer(amount);
    }
}
