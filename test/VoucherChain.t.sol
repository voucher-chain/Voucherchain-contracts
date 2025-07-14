// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/VoucherChain.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

contract VoucherChainTest is Test {
    VoucherChain public voucherChain;
    MockToken public mockToken1;
    MockToken public mockToken2;
    MockToken public mockToken3;
    address public owner;
    address public agent;
    address public user;
    address public treasury;

    string public voucherCode = "SECRET123";
    bytes32 public voucherHash = keccak256(abi.encodePacked("SECRET123"));
    uint256 public tokenValue = 100 * 10 ** 18; // 100 tokens
    uint256 public mintingFee = 200; // 2%
    uint256 public redemptionFee = 100; // 1%
    uint256 public defaultExpiryDays = 30;

    function setUp() public {
        owner = address(this);
        agent = address(0xA1);
        user = address(0xB1);
        treasury = address(0xC1);

        // Deploy mock tokens
        mockToken1 = new MockToken("Token 1", "TK1");
        mockToken2 = new MockToken("Token 2", "TK2");
        mockToken3 = new MockToken("Token 3", "TK3");

        voucherChain = new VoucherChain(treasury, mintingFee, redemptionFee, defaultExpiryDays);

        // Add supported tokens
        voucherChain.addSupportedToken(address(mockToken1));
        voucherChain.addSupportedToken(address(mockToken2));
        voucherChain.addSupportedToken(address(mockToken3));

        // Register agent
        voucherChain.registerAgent(agent, 100); // 1% commission

        // Fund agent with tokens for minting vouchers
        mockToken1.transfer(agent, 10000 * 10 ** 18);
        mockToken2.transfer(agent, 10000 * 10 ** 18);
        mockToken3.transfer(agent, 10000 * 10 ** 18);

        // Fund treasury
        mockToken1.transfer(treasury, 1000 * 10 ** 18);
        mockToken2.transfer(treasury, 1000 * 10 ** 18);
        mockToken3.transfer(treasury, 1000 * 10 ** 18);
    }

    function testMintVoucherByAgent() public {
        voucherChain.addAuthorizedMinter(agent);

        uint256 agentBalanceBefore = mockToken1.balanceOf(agent);
        uint256 contractBalanceBefore = mockToken1.balanceOf(address(voucherChain));
        uint256 treasuryBalanceBefore = mockToken1.balanceOf(treasury);

        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 0);

        uint256 agentBalanceAfter = mockToken1.balanceOf(agent);
        uint256 contractBalanceAfter = mockToken1.balanceOf(address(voucherChain));
        uint256 treasuryBalanceAfter = mockToken1.balanceOf(treasury);
        uint256 fee = (tokenValue * mintingFee) / 10000;
        uint256 totalPaid = tokenValue + fee;

        assertEq(agentBalanceAfter, agentBalanceBefore - totalPaid);
        assertEq(contractBalanceAfter, contractBalanceBefore + tokenValue); // Only voucher value stays in contract
        assertEq(treasuryBalanceAfter, treasuryBalanceBefore + fee); // Fee goes to treasury

        (bool exists, bool isRedeemed, address token, uint256 value, address issuer,) =
            voucherChain.getVoucherStatus(voucherCode);
        assertTrue(exists);
        assertFalse(isRedeemed);
        assertEq(token, address(mockToken1));
        assertEq(value, tokenValue);
        assertEq(issuer, agent);
    }

    function testRedeemVoucher() public {
        voucherChain.addAuthorizedMinter(agent);
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 0);

        uint256 userBalanceBefore = mockToken1.balanceOf(user);
        uint256 treasuryBalanceBefore = mockToken1.balanceOf(treasury);

        vm.prank(user);
        voucherChain.redeemVoucher(voucherCode, user);

        uint256 userBalanceAfter = mockToken1.balanceOf(user);
        uint256 treasuryBalanceAfter = mockToken1.balanceOf(treasury);
        uint256 fee = (tokenValue * redemptionFee) / 10000;

        assertEq(userBalanceAfter, userBalanceBefore + tokenValue - fee);
        assertEq(treasuryBalanceAfter, treasuryBalanceBefore + fee);

        (, bool isRedeemed,,,,) = voucherChain.getVoucherStatus(voucherCode);
        assertTrue(isRedeemed);
    }

    function testCannotRedeemTwice() public {
        voucherChain.addAuthorizedMinter(agent);
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 0);

        vm.prank(user);
        voucherChain.redeemVoucher(voucherCode, user);

        vm.expectRevert(VoucherChain.VoucherAlreadyRedeemed.selector);
        vm.prank(user);
        voucherChain.redeemVoucher(voucherCode, user);
    }

    function testVoucherExpiry() public {
        voucherChain.addAuthorizedMinter(agent);
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 1); // 1 day expiry

        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(VoucherChain.VoucherExpired.selector);
        vm.prank(user);
        voucherChain.redeemVoucher(voucherCode, user);
    }

    function testReclaimExpiredVoucher() public {
        voucherChain.addAuthorizedMinter(agent);

        // Mint a voucher with 1 day expiry
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 1);

        uint256 agentBalanceBefore = mockToken1.balanceOf(agent);
        uint256 contractBalanceBefore = mockToken1.balanceOf(address(voucherChain));

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

        // Agent reclaims expired voucher
        vm.prank(agent);
        voucherChain.reclaimExpiredVoucher(voucherCode);

        uint256 agentBalanceAfter = mockToken1.balanceOf(agent);
        uint256 contractBalanceAfter = mockToken1.balanceOf(address(voucherChain));

        assertEq(agentBalanceAfter, agentBalanceBefore + tokenValue);
        assertEq(contractBalanceAfter, contractBalanceBefore - tokenValue);

        (, bool isRedeemed,,,,) = voucherChain.getVoucherStatus(voucherCode);
        assertTrue(isRedeemed);
    }

    function testCannotReclaimUnexpiredVoucher() public {
        voucherChain.addAuthorizedMinter(agent);

        // Mint a voucher with 30 day expiry
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 30);

        // Try to reclaim before expiry
        vm.prank(agent);
        vm.expectRevert(VoucherChain.VoucherNotExpired.selector);
        voucherChain.reclaimExpiredVoucher(voucherCode);
    }

    function testCannotReclaimOtherAgentVoucher() public {
        address otherAgent = address(0xD1);
        voucherChain.addAuthorizedMinter(agent);
        voucherChain.addAuthorizedMinter(otherAgent);

        // Agent mints voucher
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 1);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

        // Other agent tries to reclaim
        vm.prank(otherAgent);
        vm.expectRevert(VoucherChain.UnauthorizedMinter.selector);
        voucherChain.reclaimExpiredVoucher(voucherCode);
    }

    function testCannotReclaimRedeemedVoucher() public {
        voucherChain.addAuthorizedMinter(agent);

        // Mint a voucher with 1 day expiry
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 1);

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

        // Agent reclaims expired voucher
        vm.prank(agent);
        voucherChain.reclaimExpiredVoucher(voucherCode);

        // Try to reclaim again
        vm.prank(agent);
        vm.expectRevert(VoucherChain.VoucherAlreadyRedeemed.selector);
        voucherChain.reclaimExpiredVoucher(voucherCode);
    }

    function testOnlyOwnerCanRegisterAgent() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        voucherChain.registerAgent(user, 100);
    }

    function testUpdateFees() public {
        voucherChain.updateFees(300, 200);
        assertEq(voucherChain.mintingFee(), 300);
        assertEq(voucherChain.redemptionFee(), 200);
    }

    function testAddSupportedToken() public {
        MockToken newToken = new MockToken("New Token", "NEW");
        voucherChain.addSupportedToken(address(newToken));
        assertTrue(voucherChain.isTokenSupported(address(newToken)));
    }

    function testRemoveSupportedToken() public {
        voucherChain.removeSupportedToken(address(mockToken1));
        assertFalse(voucherChain.isTokenSupported(address(mockToken1)));
    }

    function testMintVoucherBatch() public {
        voucherChain.addAuthorizedMinter(agent);

        bytes32[] memory hashes = new bytes32[](3);
        address[] memory tokens = new address[](3);
        uint256[] memory values = new uint256[](3);
        uint256[] memory expiries = new uint256[](3);

        hashes[0] = keccak256(abi.encodePacked("CODE1"));
        hashes[1] = keccak256(abi.encodePacked("CODE2"));
        hashes[2] = keccak256(abi.encodePacked("CODE3"));

        tokens[0] = address(mockToken1);
        tokens[1] = address(mockToken2);
        tokens[2] = address(mockToken1);

        values[0] = tokenValue;
        values[1] = tokenValue * 2;
        values[2] = tokenValue / 2;

        expiries[0] = 0;
        expiries[1] = 30;
        expiries[2] = 60;

        VoucherChain.VoucherBatch memory batch = VoucherChain.VoucherBatch({
            voucherHashes: hashes,
            tokens: tokens,
            tokenValues: values,
            expiryDays: expiries
        });

        // Approve tokens
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        mockToken2.approve(address(voucherChain), type(uint256).max);

        // Record balances before
        uint256[2] memory agentBalanceBefore = [mockToken1.balanceOf(agent), mockToken2.balanceOf(agent)];
        uint256[2] memory contractBalanceBefore =
            [mockToken1.balanceOf(address(voucherChain)), mockToken2.balanceOf(address(voucherChain))];
        uint256[2] memory treasuryBalanceBefore = [mockToken1.balanceOf(treasury), mockToken2.balanceOf(treasury)];

        vm.prank(agent);
        voucherChain.mintVoucherBatch(batch);

        // Record balances after
        uint256[2] memory agentBalanceAfter = [mockToken1.balanceOf(agent), mockToken2.balanceOf(agent)];
        uint256[2] memory contractBalanceAfter =
            [mockToken1.balanceOf(address(voucherChain)), mockToken2.balanceOf(address(voucherChain))];
        uint256[2] memory treasuryBalanceAfter = [mockToken1.balanceOf(treasury), mockToken2.balanceOf(treasury)];

        // Calculate expected values
        uint256 totalValue1 = tokenValue + (tokenValue / 2); // Two vouchers for token1
        uint256 totalValue2 = tokenValue * 2; // One voucher for token2
        uint256 totalFee1 = (totalValue1 * mintingFee) / 10000;
        uint256 totalFee2 = (totalValue2 * mintingFee) / 10000;
        uint256 totalPaid1 = totalValue1 + totalFee1;
        uint256 totalPaid2 = totalValue2 + totalFee2;

        // Check balances
        checkBatchBalances(
            agentBalanceBefore,
            agentBalanceAfter,
            contractBalanceBefore,
            contractBalanceAfter,
            treasuryBalanceBefore,
            treasuryBalanceAfter,
            [totalPaid1, totalPaid2],
            [totalValue1, totalValue2],
            [totalFee1, totalFee2]
        );

        // Verify all vouchers were minted
        (bool exists1,,,,,) = voucherChain.getVoucherStatus("CODE1");
        (bool exists2,,,,,) = voucherChain.getVoucherStatus("CODE2");
        (bool exists3,,,,,) = voucherChain.getVoucherStatus("CODE3");

        assertTrue(exists1);
        assertTrue(exists2);
        assertTrue(exists3);
    }

    function checkBatchBalances(
        uint256[2] memory agentBefore,
        uint256[2] memory agentAfter,
        uint256[2] memory contractBefore,
        uint256[2] memory contractAfter,
        uint256[2] memory treasuryBefore,
        uint256[2] memory treasuryAfter,
        uint256[2] memory totalPaid,
        uint256[2] memory totalValue,
        uint256[2] memory totalFee
    ) internal {
        for (uint256 i = 0; i < 2; i++) {
            assertEq(agentAfter[i], agentBefore[i] - totalPaid[i]);
            assertEq(contractAfter[i], contractBefore[i] + totalValue[i]);
            assertEq(treasuryAfter[i], treasuryBefore[i] + totalFee[i]);
        }
    }

    function testDuplicateVoucherCode() public {
        voucherChain.addAuthorizedMinter(agent);
        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 0);

        vm.prank(agent);
        vm.expectRevert(VoucherChain.DuplicateVoucherCode.selector);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 0);
    }

    function testInvalidBatchSize() public {
        voucherChain.addAuthorizedMinter(agent);

        bytes32[] memory hashes = new bytes32[](2);
        address[] memory tokens = new address[](3); // Mismatch
        uint256[] memory values = new uint256[](2);
        uint256[] memory expiries = new uint256[](2);

        hashes[0] = keccak256(abi.encodePacked("CODE1"));
        hashes[1] = keccak256(abi.encodePacked("CODE2"));

        tokens[0] = address(mockToken1);
        tokens[1] = address(mockToken2);
        tokens[2] = address(mockToken3);

        values[0] = tokenValue;
        values[1] = tokenValue;

        expiries[0] = 0;
        expiries[1] = 0;

        VoucherChain.VoucherBatch memory batch = VoucherChain.VoucherBatch({
            voucherHashes: hashes,
            tokens: tokens,
            tokenValues: values,
            expiryDays: expiries
        });

        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        vm.expectRevert(VoucherChain.InvalidBatchSize.selector);
        voucherChain.mintVoucherBatch(batch);
    }

    function testGetContractStats() public {
        (uint256 totalMinted, uint256 totalRedeemed, uint256 mintingFeeRate, uint256 redemptionFeeRate) =
            voucherChain.getContractStats();

        assertEq(totalMinted, 0);
        assertEq(totalRedeemed, 0);
        assertEq(mintingFeeRate, mintingFee);
        assertEq(redemptionFeeRate, redemptionFee);
    }

    function testGetTokenStats() public {
        uint256 totalRedeemed = voucherChain.getTokenStats(address(mockToken1));
        assertEq(totalRedeemed, 0);
    }

    function testGetAgentStats() public {
        (bool isActive, uint256 totalMinted, uint256 totalValue, uint256 commissionRate, uint256 lastSettlement) =
            voucherChain.getAgentStats(agent);

        assertTrue(isActive);
        assertEq(totalMinted, 0);
        assertEq(totalValue, 0);
        assertEq(commissionRate, 100);
        assertEq(lastSettlement, 0);
    }

    function testGetAgentTokenBalance() public {
        uint256 balance = voucherChain.getAgentTokenBalance(agent, address(mockToken1));
        assertEq(balance, 0);
    }

    function testGetContractTokenBalance() public {
        uint256 balance = voucherChain.getContractTokenBalance(address(mockToken1));
        assertEq(balance, 0); // Contract starts with 0 balance
    }

    function testMultipleVouchers() public {
        voucherChain.addAuthorizedMinter(agent);

        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        mockToken2.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        mockToken3.approve(address(voucherChain), type(uint256).max);

        // Mint multiple vouchers with different tokens
        vm.prank(agent);
        voucherChain.mintVoucher(keccak256(abi.encodePacked("CODE1")), address(mockToken1), tokenValue, 0);
        vm.prank(agent);
        voucherChain.mintVoucher(keccak256(abi.encodePacked("CODE2")), address(mockToken2), tokenValue * 2, 0);
        vm.prank(agent);
        voucherChain.mintVoucher(keccak256(abi.encodePacked("CODE3")), address(mockToken3), tokenValue / 2, 0);

        // Redeem all vouchers
        vm.prank(user);
        voucherChain.redeemVoucher("CODE1", user);
        vm.prank(user);
        voucherChain.redeemVoucher("CODE2", user);
        vm.prank(user);
        voucherChain.redeemVoucher("CODE3", user);

        // getContractStats returns 4 values: totalMinted, totalRedeemed, mintingFee, redemptionFee
        (uint256 totalMinted, uint256 totalRedeemed,,) = voucherChain.getContractStats();
        assertEq(totalMinted, 3);
        assertEq(totalRedeemed, 3);
    }

    function testUnauthorizedMinter() public {
        vm.prank(user);
        vm.expectRevert(VoucherChain.UnauthorizedMinter.selector);
        voucherChain.mintVoucher(voucherHash, address(mockToken1), tokenValue, 0);
    }

    function testInvalidVoucherCode() public {
        vm.expectRevert(VoucherChain.VoucherNotFound.selector);
        voucherChain.redeemVoucher("INVALID_CODE", user);
    }

    function testTokenNotSupported() public {
        MockToken unsupportedToken = new MockToken("Unsupported", "UNS");
        voucherChain.addAuthorizedMinter(agent);

        vm.prank(agent);
        unsupportedToken.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        vm.expectRevert(VoucherChain.TokenNotSupported.selector);
        voucherChain.mintVoucher(voucherHash, address(unsupportedToken), tokenValue, 0);
    }

    function testMultipleTokensInBatch() public {
        voucherChain.addAuthorizedMinter(agent);

        vm.prank(agent);
        mockToken1.approve(address(voucherChain), type(uint256).max);
        vm.prank(agent);
        mockToken2.approve(address(voucherChain), type(uint256).max);

        bytes32[] memory hashes = new bytes32[](2);
        address[] memory tokens = new address[](2);
        uint256[] memory values = new uint256[](2);
        uint256[] memory expiries = new uint256[](2);

        hashes[0] = keccak256(abi.encodePacked("CODE1"));
        hashes[1] = keccak256(abi.encodePacked("CODE2"));

        tokens[0] = address(mockToken1);
        tokens[1] = address(mockToken2);

        values[0] = tokenValue;
        values[1] = tokenValue * 2;

        expiries[0] = 0;
        expiries[1] = 30;

        VoucherChain.VoucherBatch memory batch = VoucherChain.VoucherBatch({
            voucherHashes: hashes,
            tokens: tokens,
            tokenValues: values,
            expiryDays: expiries
        });

        vm.prank(agent);
        voucherChain.mintVoucherBatch(batch);

        // Verify vouchers were minted with correct tokens
        (bool exists1, bool isRedeemed1, address token1, uint256 value1,,) = voucherChain.getVoucherStatus("CODE1");
        (bool exists2, bool isRedeemed2, address token2, uint256 value2,,) = voucherChain.getVoucherStatus("CODE2");

        assertTrue(exists1);
        assertTrue(exists2);
        assertFalse(isRedeemed1);
        assertFalse(isRedeemed2);
        assertEq(token1, address(mockToken1));
        assertEq(token2, address(mockToken2));
        assertEq(value1, tokenValue);
        assertEq(value2, tokenValue * 2);
    }
}
