/*
INKYCONTRACT - INKYCOIN ($INKY)

Description:
-----------
INKYCONTRACT is an ERC20 token with a total supply of 500,000,000 INKY, designed for community engagement and utility within the Nexera ecosystem. 

Key Features:
-------------
1. **Token Distribution**
   - Treasury: 35%
   - Liquidity: 30%
   - Team: 5% immediate + 20% vesting over 2 years
   - Airdrop: 10%
   - Bounty: initially 0%, receives bounty fees from transfers

2. **Team Vesting**
   - Linear vesting over 2 years for the team allocation.
   - Claimable by the team wallet only.
   - Event `TeamTokensClaimed` emitted upon claim.

3. **Bounty Mechanism**
   - Transfer tax configurable in basis points (default 1%).
   - Custom whitelist possible for DEXs, bridges, or other contracts.
   - Event `BountyPercentUpdated` emitted on changes.

4. **Airdrop**
   - Flexible, owner-controlled airdrop with per-address amount.
   - Each address can receive tokens only once.
   - Event `AirdropSent` emitted for transparency.

5. **Treasury Management**
   - Owner can send tokens from treasury with `sendFromTreasury`.
   - Transparent and trackable.

6. **Security & Best Practices**
   - Uses OpenZeppelin ERC20 and Ownable standards.
   - Immutable total supply, no unlimited minting.
   - Exemption system for transfers to prevent tax on specific addresses.
   - Fully compatible with Nexera Explorer, DEXs, and community tooling.

Purpose:
--------
Designed for community engagement, rewards, and ecosystem development on Nexera. Supports flexible token distribution while maintaining team vesting and bounty mechanisms. Transparent and auditable on-chain with event logging.

*/



// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract INKYCONTRACT is ERC20, Ownable {
    address public treasuryWallet;
    address public liquidityWallet;
    address public teamWallet;
    address public airdropWallet;
    address public bountyWallet;

    // Bounty tax in basis points (100 = 1%)
    uint256 public bountyPercentBasisPoints = 100; // Default 1%

    // Whitelisted addresses exempt from bounty
    mapping(address => bool) public bountyExempt;

    // Team vesting parameters
    uint256 public teamVestingStart;
    uint256 public teamVestingDuration = 2 * 365 days; // 2 years
    uint256 public teamTotalVesting;
    uint256 public teamClaimed;

    // Airdrop tracking
    mapping(address => bool) public hasClaimedAirdrop;

    // Classic burn address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Events
    event BountyPercentUpdated(uint256 newPercent);
    event TeamTokensClaimed(uint256 amount, uint256 timestamp);
    event AirdropSent(address indexed recipient, uint256 amount);
    event AddressWhitelisted(address indexed addr, bool status);

    constructor(
        address _treasuryWallet,
        address _liquidityWallet,
        address _teamWallet,
        address _airdropWallet,
        address _bountyWallet
    ) ERC20("INKYCOIN", "tINKY") Ownable(msg.sender) {
        treasuryWallet = _treasuryWallet;
        liquidityWallet = _liquidityWallet;
        teamWallet = _teamWallet;
        airdropWallet = _airdropWallet;
        bountyWallet = _bountyWallet;

        uint256 totalSupply = 500_000_000 * 10 ** decimals();

        // 5% immediate team allocation
        uint256 teamImmediate = totalSupply * 5 / 100;
        _mint(teamWallet, teamImmediate);

        // 20% team vesting over 2 years
        teamTotalVesting = totalSupply * 20 / 100;
        _mint(address(this), teamTotalVesting);

        // 30% liquidity
        _mint(liquidityWallet, totalSupply * 30 / 100);
        // 35% treasury
        _mint(treasuryWallet, totalSupply * 35 / 100);
        // 10% airdrop
        _mint(airdropWallet, totalSupply * 10 / 100);
        // 0% bounty initial
        _mint(bountyWallet, 0);

        teamVestingStart = block.timestamp; // Vesting starts now
    }

    // ---------------------- BOUNTY SECTION ----------------------

    // Update bounty percentage (basis points, 100 = 1%)
    function setBountyPercent(uint256 _bountyBasisPoints) external onlyOwner {
        require(_bountyBasisPoints <= 1000, "Max 10%");
        bountyPercentBasisPoints = _bountyBasisPoints;
        emit BountyPercentUpdated(_bountyBasisPoints);
    }

    // Add or remove addresses from bounty exemption list
    function setBountyExempt(address account, bool exempt) external onlyOwner {
        bountyExempt[account] = exempt;
        emit AddressWhitelisted(account, exempt);
    }

    // Check if sender/recipient are exempt from bounty
    function _isExempt(address sender, address recipient) internal view returns (bool) {
        return (
            sender == treasuryWallet ||
            sender == liquidityWallet ||
            sender == teamWallet ||
            sender == bountyWallet ||
            sender == airdropWallet ||
            recipient == BURN_ADDRESS ||
            bountyExempt[sender] ||
            bountyExempt[recipient]
        );
    }

    // Custom transfer with bounty
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (_isExempt(msg.sender, recipient)) {
            super._transfer(msg.sender, recipient, amount);
        } else {
            uint256 bountyAmount = amount * bountyPercentBasisPoints / 10000;
            uint256 sendAmount = amount - bountyAmount;

            super._transfer(msg.sender, bountyWallet, bountyAmount);
            super._transfer(msg.sender, recipient, sendAmount);
        }
        return true;
    }

    // transferFrom with bounty as well
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (_isExempt(sender, recipient)) {
            super._transfer(sender, recipient, amount);
        } else {
            uint256 bountyAmount = amount * bountyPercentBasisPoints / 10000;
            uint256 sendAmount = amount - bountyAmount;

            super._transfer(sender, bountyWallet, bountyAmount);
            super._transfer(sender, recipient, sendAmount);
        }

        uint256 currentAllowance = allowance(sender, msg.sender);
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);

        return true;
    }

    // ---------------------- AIRDROP SECTION ----------------------

    /**
     * Flexible airdrop: the owner defines the list of recipients and
     * the amount per user (entered without decimals, converted inside).
     * Each address can receive tokens only once.
     */
    function airdrop(address[] calldata recipients, uint256 amountPerUserNoDecimals) external onlyOwner {
        require(amountPerUserNoDecimals > 0, "Invalid amount");

        uint256 amountPerUser = amountPerUserNoDecimals * 10 ** decimals();
        uint256 totalRequired = recipients.length * amountPerUser;
        require(balanceOf(airdropWallet) >= totalRequired, "Not enough airdrop balance");

        for (uint256 i = 0; i < recipients.length; i++) {
            address user = recipients[i];
            if (!hasClaimedAirdrop[user]) {
                hasClaimedAirdrop[user] = true;
                _transfer(airdropWallet, user, amountPerUser);
                emit AirdropSent(user, amountPerUser);
            }
        }
    }

    // ---------------------- TREASURY SECTION ----------------------

    // Transfer tokens from treasury to a specific address (only owner)
    function sendFromTreasury(address recipient, uint256 amountTokensNoDecimals) public onlyOwner {
        uint256 amount = amountTokensNoDecimals * 10 ** decimals();
        uint256 treasuryBalance = balanceOf(treasuryWallet);
        require(amount <= treasuryBalance, "Amount too high");
        _transfer(treasuryWallet, recipient, amount);
    }

    // ---------------------- TEAM VESTING SECTION ----------------------

    function claimTeamTokens() public {
        require(msg.sender == teamWallet, "Only team wallet can claim");

        uint256 elapsed = block.timestamp - teamVestingStart;
        if (elapsed > teamVestingDuration) {
            elapsed = teamVestingDuration;
        }

        uint256 claimable = (teamTotalVesting * elapsed / teamVestingDuration) - teamClaimed;
        require(claimable > 0, "No tokens to claim yet");

        teamClaimed += claimable;
        _transfer(address(this), teamWallet, claimable);

        emit TeamTokensClaimed(claimable, block.timestamp);
    }
}