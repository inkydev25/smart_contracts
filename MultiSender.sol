// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title MultiSender
 * @dev A gas-efficient contract for batch sending native currency and ERC20 tokens
 * 
 * CONTRACT OVERVIEW:
 * - Allows batch transfers of native NXRA to multiple recipients in one transaction
 * - Allows batch transfers of ERC20 tokens to multiple recipients in one transaction  
 * - Supports ERC20 permit for tokenless approvals via signatures
 * - Includes safety checks and error handling for failed transfers
 * - Optimized for gas efficiency with minimal storage operations
 * 
 * KEY FEATURES:
 * - Single transaction for multiple transfers (saves gas and time)
 * - Support for both native currency and ERC20 tokens
 * - ERC2612 permit support for meta-transactions
 * - Comprehensive error handling and event logging
 * - Reentrancy protection through minimal state changes
 */
contract MultiSender {
    // Events
    event MultiSentNative(address indexed sender, uint256 total);
    event MultiSentERC20(address indexed token, address indexed sender, uint256 total);

    // Custom errors for gas efficiency
    error LengthMismatch();
    error TransferFailed();

    /**
     * @dev Batch sends native currency (ETH/MATIC) to multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to send (in wei)
     * Requirements:
     * - recipients and amounts arrays must have same length
     * - Total msg.value must equal sum of all amounts
     * - Each transfer must succeed
     */
    function multisendNative(address[] calldata recipients, uint256[] calldata amounts) external payable {
        if (recipients.length != amounts.length) revert LengthMismatch();

        uint256 total = _sum(amounts);
        require(total == msg.value, "Value mismatch");

        for (uint i = 0; i < recipients.length; i++) {
            (bool ok, ) = recipients[i].call{value: amounts[i]}("");
            if (!ok) revert TransferFailed();
        }
        emit MultiSentNative(msg.sender, total);
    }

    /**
     * @dev Batch sends ERC20 tokens to multiple recipients
     * @param token Address of the ERC20 token contract
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to transfer
     * Requirements:
     * - recipients and amounts arrays must have same length
     * - Caller must have sufficient allowance for total amount
     * - Each transferFrom must succeed
     */
    function multisendERC20(address token, address[] calldata recipients, uint256[] calldata amounts) external {
        if (recipients.length != amounts.length) revert LengthMismatch();

        uint256 total = _sum(amounts);

        for (uint i = 0; i < recipients.length; i++) {
            _safeTransferFrom(token, msg.sender, recipients[i], amounts[i]);
        }
        emit MultiSentERC20(token, msg.sender, total);
    }

    /**
     * @dev Batch sends ERC20 tokens using permit for tokenless approval
     * @param token Address of the ERC20 token contract
     * @param recipients Array of recipient addresses  
     * @param amounts Array of amounts to transfer
     * @param value Approval amount for permit
     * @param deadline Expiration time for permit signature
     * @param v Recovery byte of the signature
     * @param r R value of the signature
     * @param s S value of the signature
     * Process:
     * 1. Execute permit to approve this contract to spend tokens
     * 2. Perform batch transfers using the new allowance
     */
    function multisendERC20WithPermit(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Execute permit approval via low-level call
        (bool ok, ) = token.call(
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                msg.sender,
                address(this),
                value,
                deadline,
                v, r, s
            )
        );
        require(ok, "Permit failed");

        if (recipients.length != amounts.length) revert LengthMismatch();

        uint256 total = _sum(amounts);

        for (uint i = 0; i < recipients.length; i++) {
            _safeTransferFrom(token, msg.sender, recipients[i], amounts[i]);
        }

        emit MultiSentERC20(token, msg.sender, total);
    }

    /**
     * @dev Internal function for safe ERC20 transferFrom with return value check
     * @param token ERC20 token address
     * @param from Source address
     * @param to Destination address  
     * @param value Amount to transfer
     * Requirements:
     * - transferFrom call must succeed
     * - If return data exists, it must be true
     */
    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, value)
        );
        require(success, "ERC20 transferFrom failed");
        if (data.length > 0) require(abi.decode(data, (bool)), "ERC20 transferFrom returned false");
    }

    /**
     * @dev Internal function to calculate sum of uint256 array
     * @param arr Array of uint256 values to sum
     * @return total Sum of all array elements
     */
    function _sum(uint256[] calldata arr) internal pure returns (uint256 total) {
        for (uint i = 0; i < arr.length; i++) total += arr[i];
    }

    /**
     * @dev Receive function to accept native currency
     */
    receive() external payable {}

    /**
     * @dev Fallback function to accept native currency  
     */
    fallback() external payable {}
}