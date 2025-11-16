// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TicketSale
 * @dev INKY Tombola ticket sale contract with token-based participation
 * 
 * CONTRACT OVERVIEW:
 * - Users buy tickets using INKY tokens with a fixed ticket price
 * - Ticket purchases automatically burn the paid tokens
 * - Participation is gated by minimum token balance requirements
 * - Users can buy more tickets based on their token balance (tier system)
 * - Owner can distribute bounty prizes to winners with automatic burn mechanism
 * - Multi-round system with participant tracking per round
 * 
 * KEY FEATURES:
 * - Automatic token burning on ticket purchase
 * - Tier-based ticket allocation based on token holdings
 * - Bounty distribution with burn cap
 * - Paginated participant data retrieval
 * - Comprehensive stats tracking per round
 */
contract TicketSale is Ownable {
    // Token contract interface
    IERC20 public inkyToken;
    
    // Ticket configuration
    uint256 public ticketPrice;
    address public constant burnAddress = 0x000000000000000000000000000000000000dEaD; 

    // Round management
    uint256 public currentRoundId;
    address public constant bountyWallet = 0x20dd4f9857A737E4b762bB8857499e22CdA70Edc; 

    // Bounty configuration
    uint256 public maxBountyAmountINKY;
    
    // Round tracking mappings
    mapping(uint256 => mapping(address => uint256)) public ticketsBought;
    mapping(uint256 => address[]) public participantsPerRound;
    mapping(uint256 => uint256) public totalTicketsPerRound;
    mapping(uint256 => uint256) public totalCostPerRound;
    uint256 public burnedTotalINKY;
    
    // Participation requirements
    uint256 public minBalanceToParticipate;
    
    // Tier system for ticket allocation
    struct Threshold {
        uint256 balance;
        uint256 maxTickets;
    }
    Threshold[] public thresholds;

    // Optimized data structures for frontend integration
    struct ParticipantData {
        address wallet;
        uint256 tickets;
    }
    
    struct RoundStats {
        uint256 currentRoundId;
        uint256 totalParticipants;
        uint256 totalTickets;
        uint256 roundBurned;
        uint256 allTimeBurned;
        uint256 poolBalance;
        uint256 maxBounty;
        uint256 ticketPrice;
        uint256 minBalanceToParticipate;
    }
    
    struct UserStats {
        uint256 inkyBalance;
        uint256 maxTicketsAllowed;
        uint256 ticketsBought;
        bool isEligible;
    }

    // Events
    event TicketsPurchased(address indexed buyer, uint256 amount, uint256 totalCost, uint256 roundId); 
    event ThresholdUpdated(uint256 index, uint256 balance, uint256 maxTickets); 
    event NewRoundStarted(uint256 newRoundId); 
    event MinBalanceUpdated(uint256 newMinBalance); 
    event MaxBountyUpdated(uint256 newMaxBounty);
    event BountyTransferred(uint256 roundId, address indexed winner, uint256 prizeAmount, uint256 burnAmount); 

    /**
     * @dev Initializes the contract with configuration parameters
     * @param _inkyToken Address of the INKY token contract
     * @param _ticketPrice Price per ticket in INKY tokens
     * @param _initialMinBalance Minimum token balance required to participate
     * @param _initialMaxBounty Maximum bounty amount that can be distributed
     */
    constructor(
        address _inkyToken, 
        uint256 _ticketPrice, 
        uint256 _initialMinBalance, 
        uint256 _initialMaxBounty
    ) Ownable(msg.sender) {
        inkyToken = IERC20(_inkyToken); 
        ticketPrice = _ticketPrice; 
        minBalanceToParticipate = _initialMinBalance;
        currentRoundId = 1;
        maxBountyAmountINKY = _initialMaxBounty;

        // Initialize tier thresholds (balance in INKY tokens)
        thresholds.push(Threshold({balance: 100000, maxTickets: 1}));
        thresholds.push(Threshold({balance: 300000, maxTickets: 2}));
        thresholds.push(Threshold({balance: 500000, maxTickets: 3}));
        thresholds.push(Threshold({balance: 700000, maxTickets: 4}));
        thresholds.push(Threshold({balance: 1000000, maxTickets: 5}));
        thresholds.push(Threshold({balance: 2000000, maxTickets: 6}));
        thresholds.push(Threshold({balance: type(uint256).max, maxTickets: 7}));
    }

    /**
     * @dev Updates the maximum bounty amount
     * @param _newMaxBounty New maximum bounty in INKY tokens
     */
    function setMaxBounty(uint256 _newMaxBounty) external onlyOwner {
        maxBountyAmountINKY = _newMaxBounty;
        emit MaxBountyUpdated(_newMaxBounty);
    }

    /**
     * @dev Updates the minimum balance requirement
     * @param _newMinBalance New minimum balance in INKY tokens
     */
    function setMinBalance(uint256 _newMinBalance) external onlyOwner {
        minBalanceToParticipate = _newMinBalance; 
        emit MinBalanceUpdated(_newMinBalance); 
    }

    /**
     * @dev Allows users to purchase tickets for the current round
     * @param _amount Number of tickets to purchase
     * Requirements:
     * - User must have sufficient INKY token balance
     * - User must meet minimum balance requirements
     * - User cannot exceed their tier-based ticket limit
     * - Contract must have sufficient token allowance
     */
    function buyTickets(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than zero"); 
        
        // Check minimum balance requirement
        uint256 userBalance = inkyToken.balanceOf(msg.sender) / (10 ** 18);
        require(userBalance >= minBalanceToParticipate, "Balance too low to participate"); 

        // Check tier-based ticket limits
        uint256 maxAllowed = getMaxTicketsAllowed(msg.sender); 
        require(_amount <= maxAllowed, "Cannot buy more than max allowed"); 

        // Calculate and process payment
        uint256 totalCost = _amount * ticketPrice * (10 ** 18); 
        require(
            inkyToken.allowance(msg.sender, address(this)) >= totalCost, 
            "Approve INKY first"
        );
        
        // Transfer tokens to burn address
        bool success = inkyToken.transferFrom(msg.sender, burnAddress, totalCost); 
        require(success, "Token transfer failed"); 
        
        // Add user to participants list if first purchase this round
        if (ticketsBought[currentRoundId][msg.sender] == 0) { 
            participantsPerRound[currentRoundId].push(msg.sender); 
        }

        // Update round statistics
        ticketsBought[currentRoundId][msg.sender] += _amount; 
        totalTicketsPerRound[currentRoundId] += _amount; 
        totalCostPerRound[currentRoundId] += totalCost; 
        burnedTotalINKY += totalCost; 
        
        emit TicketsPurchased(msg.sender, _amount, totalCost, currentRoundId); 
    }

    /**
     * @dev Advances to the next round (owner only)
     */
    function startNewRound() external onlyOwner {
        currentRoundId += 1; 
        emit NewRoundStarted(currentRoundId); 
    }

    /**
     * @dev Distributes bounty to winner with burn mechanism
     * @param winner Address of the winner to receive the prize
     * Process:
     * - Transfers up to maxBountyAmountINKY to winner
     * - Burns any remaining balance in bounty wallet
     */
    function transferBountyToWinner(address winner) external onlyOwner {
        uint256 totalBountyWei = inkyToken.balanceOf(bountyWallet);
        require(totalBountyWei > 0, "Bounty wallet empty"); 

        uint256 maxBountyWei = maxBountyAmountINKY * (10 ** 18); 

        // Calculate prize and burn amounts
        uint256 prizeToWinnerWei = (totalBountyWei < maxBountyWei) ? totalBountyWei : maxBountyWei;
        uint256 burnAmountWei = totalBountyWei - prizeToWinnerWei;
        
        bool sent;

        // Transfer prize to winner
        if (prizeToWinnerWei > 0) {
            sent = inkyToken.transferFrom(bountyWallet, winner, prizeToWinnerWei);
            require(sent, "Prize transfer failed");
        }

        // Burn excess tokens
        if (burnAmountWei > 0) {
            sent = inkyToken.transferFrom(bountyWallet, burnAddress, burnAmountWei);
            require(sent, "Burn transfer failed");
            burnedTotalINKY += burnAmountWei;
        }

        // Emit event with human-readable amounts
        uint256 prizeAmountINKY = prizeToWinnerWei / (10 ** 18);
        uint256 burnAmountINKY = burnAmountWei / (10 ** 18);
        
        emit BountyTransferred(currentRoundId, winner, prizeAmountINKY, burnAmountINKY); 
    }

    // ===================== FRONTEND OPTIMIZED FUNCTIONS =====================

    /**
     * @dev Returns paginated participant data for frontend display
     * @param _roundId Round ID to query
     * @param _page Page number (1-indexed)
     * @param _pageSize Number of participants per page
     * @return Array of ParticipantData for the requested page
     */
    function getParticipantsPage(
        uint256 _roundId, 
        uint256 _page, 
        uint256 _pageSize
    ) external view returns (ParticipantData[] memory) {
        address[] memory allParticipants = participantsPerRound[_roundId];
        uint256 totalParticipants = allParticipants.length;
        
        if (totalParticipants == 0) {
            return new ParticipantData[](0);
        }
        
        // Calculate pagination bounds
        uint256 start = (_page - 1) * _pageSize;
        uint256 end = start + _pageSize;
        if (end > totalParticipants) {
            end = totalParticipants;
        }
        if (start >= totalParticipants) {
            return new ParticipantData[](0);
        }
        
        // Build page data
        ParticipantData[] memory pageData = new ParticipantData[](end - start);
        
        for (uint256 i = start; i < end; i++) {
            address participant = allParticipants[i];
            pageData[i - start] = ParticipantData({
                wallet: participant,
                tickets: ticketsBought[_roundId][participant]
            });
        }
        
        return pageData;
    }

    /**
     * @dev Returns comprehensive round statistics in a single call
     * @param _roundId Round ID to query
     * @return RoundStats struct containing all round-related data
     */
    function getRoundStats(uint256 _roundId) external view returns (RoundStats memory) {
        return RoundStats({
            currentRoundId: currentRoundId,
            totalParticipants: participantsPerRound[_roundId].length,
            totalTickets: totalTicketsPerRound[_roundId],
            roundBurned: totalCostPerRound[_roundId],
            allTimeBurned: burnedTotalINKY,
            poolBalance: inkyToken.balanceOf(bountyWallet),
            maxBounty: maxBountyAmountINKY * (10 ** 18),
            ticketPrice: ticketPrice,
            minBalanceToParticipate: minBalanceToParticipate
        });
    }

    /**
     * @dev Returns comprehensive user statistics in a single call
     * @param _roundId Round ID to query
     * @param _user User address to query
     * @return UserStats struct containing all user-related data
     */
    function getUserStats(
        uint256 _roundId, 
        address _user
    ) external view returns (UserStats memory) {
        uint256 balanceWei = inkyToken.balanceOf(_user);
        uint256 balanceNormalized = balanceWei / (10 ** 18);
        uint256 maxAllowed = getMaxTicketsAllowed(_user);
        uint256 tickets = ticketsBought[_roundId][_user];
        bool eligible = balanceNormalized >= minBalanceToParticipate && maxAllowed > 0;
        
        return UserStats({
            inkyBalance: balanceWei,
            maxTicketsAllowed: maxAllowed,
            ticketsBought: tickets,
            isEligible: eligible
        });
    }

    /**
     * @dev Calculates maximum tickets allowed for a user based on tier system
     * @param _user User address to check
     * @return Number of additional tickets user can purchase
     */
    function getMaxTicketsAllowed(address _user) public view returns (uint256) {
        uint256 balanceRaw = inkyToken.balanceOf(_user); 
        uint256 balance = balanceRaw / (10 ** 18); 

        if (balance < minBalanceToParticipate) { 
            return 0; 
        }

        // Find appropriate tier
        uint256 allowed = 0; 
        for (uint256 i = 0; i < thresholds.length; i++) { 
            if (balance <= thresholds[i].balance) { 
                allowed = thresholds[i].maxTickets; 
                break; 
            }
        }

        // Subtract already purchased tickets
        if (allowed <= ticketsBought[currentRoundId][_user]) return 0; 
        return allowed - ticketsBought[currentRoundId][_user]; 
    }

    /**
     * @dev Updates ticket price (owner only)
     * @param _newPrice New ticket price in INKY tokens
     */
    function setTicketPrice(uint256 _newPrice) external onlyOwner {
        ticketPrice = _newPrice; 
    }

    /**
     * @dev Updates tier threshold (owner only)
     * @param _index Index of threshold to update
     * @param _balance New balance requirement for tier
     * @param _maxTickets New maximum tickets for tier
     */
    function setThreshold(
        uint256 _index, 
        uint256 _balance, 
        uint256 _maxTickets
    ) external onlyOwner {
        require(_index < thresholds.length, "Invalid index"); 
        thresholds[_index] = Threshold({balance: _balance, maxTickets: _maxTickets}); 
        emit ThresholdUpdated(_index, _balance, _maxTickets);
    }
}