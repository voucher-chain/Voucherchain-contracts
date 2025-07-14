// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/VoucherChain.sol";

/**
 * @title VoucherChain Multi-Token Treasury Deployment Script
 * @dev Script to deploy the VoucherChain contract as a treasury for multiple tokens
 */
contract DeployScript is Script {
    // Configuration constants
    uint256 constant MINTING_FEE = 200; // 2% minting fee
    uint256 constant REDEMPTION_FEE = 100; // 1% redemption fee
    uint256 constant DEFAULT_EXPIRY_DAYS = 90; // 90 days default expiry

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get token addresses from environment
        string memory tokenAddressesStr = "";
        try vm.envString("TOKEN_ADDRESSES") returns (string memory val) {
            tokenAddressesStr = val;
        } catch {
            console2.log("TOKEN_ADDRESSES not set in environment");
            console2.log("Please set TOKEN_ADDRESSES environment variable");
            console2.log("Example: export TOKEN_ADDRESSES=0x123,0x456,0x789");
            return;
        }
        // Split by comma and use vm.envAddress for each
        string[] memory parts = split(tokenAddressesStr, ",");
        address[] memory tokenAddresses = new address[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            tokenAddresses[i] = parseAddr(parts[i]);
        }

        // Use deployer as treasury for initial deployment
        address treasury = deployer;

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the VoucherChain contract as treasury
        VoucherChain voucherChain = new VoucherChain(treasury, MINTING_FEE, REDEMPTION_FEE, DEFAULT_EXPIRY_DAYS);

        // Add supported tokens
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            voucherChain.addSupportedToken(tokenAddresses[i]);
        }

        vm.stopBroadcast();

        // Log deployment information
        console2.log("=== VoucherChain Multi-Token Treasury Deployment ===");
        console2.log("Contract deployed at:", address(voucherChain));
        console2.log("Deployer:", deployer);
        console2.log("Treasury:", treasury);
        console2.log("Minting Fee (basis points):", MINTING_FEE);
        console2.log("Minting Fee (%):", MINTING_FEE / 100);
        console2.log("Redemption Fee (basis points):", REDEMPTION_FEE);
        console2.log("Redemption Fee (%):", REDEMPTION_FEE / 100);
        console2.log("Default Expiry (days):", DEFAULT_EXPIRY_DAYS);
        console2.log("Supported Tokens:");
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            console2.log("  -", tokenAddresses[i]);
        }
        console2.log("================================");
        console2.log("Note: Agents must approve tokens to contract before minting vouchers");
        console2.log("Contract acts as treasury - agents pay for vouchers when minting");
        console2.log("Agents can mint vouchers for any supported token");

        // Verify contract deployment
        require(address(voucherChain) != address(0), "Deployment failed");
        require(voucherChain.treasury() == treasury, "Treasury not set correctly");
        require(voucherChain.mintingFee() == MINTING_FEE, "Minting fee not set correctly");
        require(voucherChain.redemptionFee() == REDEMPTION_FEE, "Redemption fee not set correctly");
        require(voucherChain.defaultExpiryDays() == DEFAULT_EXPIRY_DAYS, "Default expiry not set correctly");

        // Verify supported tokens
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            require(voucherChain.isTokenSupported(tokenAddresses[i]), "Token not supported");
        }

        console2.log("Contract deployed and verified successfully!");
    }
    // Helper to split a string by a delimiter

    function split(string memory str, string memory delim) internal pure returns (string[] memory) {
        bytes memory strBytes = bytes(str);
        bytes memory delimBytes = bytes(delim);
        uint256 count = 1;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == delimBytes[0]) count++;
        }
        string[] memory parts = new string[](count);
        uint256 partIdx = 0;
        uint256 lastIdx = 0;
        for (uint256 i = 0; i <= strBytes.length; i++) {
            if (i == strBytes.length || strBytes[i] == delimBytes[0]) {
                bytes memory part = new bytes(i - lastIdx);
                for (uint256 j = 0; j < part.length; j++) {
                    part[j] = strBytes[lastIdx + j];
                }
                parts[partIdx++] = string(part);
                lastIdx = i + 1;
            }
        }
        return parts;
    }
    // Helper to parse address from string

    function parseAddr(string memory _a) internal pure returns (address) {
        bytes memory tmp = bytes(_a);
        uint160 iaddr = 0;
        uint160 b1;
        uint160 b2;
        for (uint256 i = 2; i < 2 + 2 * 20; i += 2) {
            iaddr *= 256;
            b1 = uint160(uint8(tmp[i]));
            b2 = uint160(uint8(tmp[i + 1]));
            b1 = b1 >= 97 ? b1 - 87 : b1 >= 65 ? b1 - 55 : b1 - 48;
            b2 = b2 >= 97 ? b2 - 87 : b2 >= 65 ? b2 - 55 : b2 - 48;
            iaddr += (b1 * 16 + b2);
        }
        return address(iaddr);
    }
}
