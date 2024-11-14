// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/InitializableOwnable.sol";

contract DOODGasDistributor is InitializableOwnable {
    address public bot;
    uint256 public maxAmount;
    bool public paused;
    
    mapping(bytes32 => bool) public processedExternalIds;
    
    event Distribution(address indexed to, uint256 amount, bytes32 indexed externalId);
    event MaxAmountUpdated(uint256 newMaxAmount);
    event BotUpdated(address newBot);
    event Paused(bool isPaused);
    
    modifier onlyBot() {
        require(msg.sender == bot, "Only bot");
        _;
    }
    
    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    
    constructor(address _owner, address _bot, uint256 _maxAmount) {
        initOwner(_owner);
        bot = _bot;
        maxAmount = _maxAmount;
    }
    
    function distribute(address to, uint256 amount, bytes32 externalId) 
        external 
        onlyBot 
        notPaused 
    {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than 0");
        require(!processedExternalIds[externalId], "ExternalId already processed");
        
        processedExternalIds[externalId] = true;
        
        uint256 distributionAmount = amount > maxAmount ? maxAmount : amount;
        
        (bool success, ) = to.call{value: distributionAmount}("");
        require(success, "Transfer failed");
        
        emit Distribution(to, distributionAmount, externalId);
    }
    
    function setMaxAmount(uint256 _maxAmount) external {
        require(msg.sender == bot || msg.sender == _OWNER_, "Only bot or owner");
        maxAmount = _maxAmount;
        emit MaxAmountUpdated(_maxAmount);
    }
    
    function setBot(address _bot) external onlyOwner {
        require(_bot != address(0), "Invalid bot address");
        bot = _bot;
        emit BotUpdated(_bot);
    }
    
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }
    
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        
        (bool success, ) = _OWNER_.call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    receive() external payable {}
}
