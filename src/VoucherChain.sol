// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VoucherChain is Ownable, ReentrancyGuard {
    struct Voucher {
        bytes32 voucherHash;
        address token;
        uint256 tokenValue;
        bool isRedeemed;
        address issuer;
        uint256 mintTimestamp;
        uint256 expiryTimestamp;
        bool exists;
    }

    struct Agent {
        bool isActive;
        uint256 totalMinted;
        uint256 totalValue;
        uint256 commissionRate;
        uint256 lastSettlement;
    }

    struct VoucherBatch {
        bytes32[] voucherHashes;
        address[] tokens;
        uint256[] tokenValues;
        uint256[] expiryDays;
    }

    mapping(bytes32 => Voucher) public vouchers;
    mapping(address => Agent) public agents;
    mapping(address => bool) public authorizedMinters;
    mapping(address => bool) public supportedTokens;
    mapping(address => mapping(address => uint256)) public agentBalances; // Agent address => Token address => balance

    uint256 public totalVouchersMinted;
    uint256 public totalVouchersRedeemed;
    mapping(address => uint256) public totalTokensRedeemed; // Token address => total redeemed
    uint256 public mintingFee;
    uint256 public redemptionFee;
    uint256 public defaultExpiryDays;

    address public treasury;

    event VoucherMinted(
        bytes32 indexed voucherHash,
        address indexed token,
        uint256 tokenValue,
        address indexed issuer,
        uint256 expiryTimestamp
    );
    event VoucherBatchMinted(address indexed issuer, uint256 batchSize, uint256 totalValue);
    event VoucherRedeemed(
        bytes32 indexed voucherHash, address indexed token, address indexed recipient, uint256 tokenValue, uint256 fee
    );
    event AgentRegistered(address indexed agent, uint256 commissionRate);
    event AgentDeactivated(address indexed agent);
    event AgentBalanceSettled(address indexed agent, address indexed token, uint256 amount);
    event FeesUpdated(uint256 mintingFee, uint256 redemptionFee);
    event TreasuryUpdated(address indexed newTreasury);
    event TokenSupported(address indexed token, bool supported);
    event VoucherReclaimed(
        bytes32 indexed voucherHash, address indexed token, address indexed agent, uint256 tokenValue
    );

    error VoucherNotFound();
    error VoucherAlreadyRedeemed();
    error VoucherExpired();
    error AgentNotActive();
    error InsufficientBalance();
    error InvalidFee();
    error InvalidExpiry();
    error UnauthorizedMinter();
    error TokenTransferFailed();
    error InvalidBatchSize();
    error DuplicateVoucherCode();
    error VoucherNotExpired();
    error TokenNotSupported();

    constructor(address _treasury, uint256 _mintingFee, uint256 _redemptionFee, uint256 _defaultExpiryDays)
        Ownable(msg.sender)
    {
        require(_treasury != address(0), "Invalid treasury address");

        treasury = _treasury;
        mintingFee = _mintingFee;
        redemptionFee = _redemptionFee;
        defaultExpiryDays = _defaultExpiryDays;
    }

    modifier onlyAuthorizedMinter() {
        if (!authorizedMinters[msg.sender] && !agents[msg.sender].isActive) {
            revert UnauthorizedMinter();
        }
        _;
    }

    function mintVoucher(bytes32 voucherHash, address token, uint256 tokenValue, uint256 expiryDays)
        external
        onlyAuthorizedMinter
        nonReentrant
    {
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (tokenValue == 0) revert InvalidFee();
        if (expiryDays > 365) revert InvalidExpiry();

        if (vouchers[voucherHash].exists) {
            revert DuplicateVoucherCode();
        }

        uint256 expiryTimestamp = 0;
        if (expiryDays > 0) {
            expiryTimestamp = block.timestamp + (expiryDays * 1 days);
        } else if (defaultExpiryDays > 0) {
            expiryTimestamp = block.timestamp + (defaultExpiryDays * 1 days);
        }

        // Calculate fee and total amount agent needs to pay
        uint256 fee = (tokenValue * mintingFee) / 10000;
        uint256 totalAmount = tokenValue + fee;

        // Transfer tokens from agent to contract
        IERC20(token).transferFrom(msg.sender, address(this), totalAmount);

        // Transfer fee to treasury immediately
        if (fee > 0) {
            IERC20(token).transfer(treasury, fee);
        }

        Voucher memory newVoucher = Voucher({
            voucherHash: voucherHash,
            token: token,
            tokenValue: tokenValue,
            isRedeemed: false,
            issuer: msg.sender,
            mintTimestamp: block.timestamp,
            expiryTimestamp: expiryTimestamp,
            exists: true
        });

        vouchers[voucherHash] = newVoucher;
        totalVouchersMinted++;

        if (agents[msg.sender].isActive) {
            agents[msg.sender].totalMinted++;
            agents[msg.sender].totalValue += tokenValue;
        }

        emit VoucherMinted(voucherHash, token, tokenValue, msg.sender, expiryTimestamp);
    }

    function mintVoucherBatch(VoucherBatch memory batch) external onlyAuthorizedMinter nonReentrant {
        if (batch.voucherHashes.length == 0) revert InvalidBatchSize();
        if (
            batch.voucherHashes.length != batch.tokens.length || batch.voucherHashes.length != batch.tokenValues.length
                || batch.voucherHashes.length != batch.expiryDays.length
        ) {
            revert InvalidBatchSize();
        }

        // Calculate totals and validate all vouchers
        for (uint256 i = 0; i < batch.voucherHashes.length; i++) {
            address token = batch.tokens[i];
            if (!supportedTokens[token]) revert TokenNotSupported();
            if (batch.tokenValues[i] == 0) revert InvalidFee();
            if (batch.expiryDays[i] > 365) revert InvalidExpiry();

            if (vouchers[batch.voucherHashes[i]].exists) {
                revert DuplicateVoucherCode();
            }
        }

        // Transfer tokens from agent to contract for each voucher
        for (uint256 i = 0; i < batch.voucherHashes.length; i++) {
            address token = batch.tokens[i];
            uint256 fee = (batch.tokenValues[i] * mintingFee) / 10000;
            uint256 totalAmount = batch.tokenValues[i] + fee;

            IERC20(token).transferFrom(msg.sender, address(this), totalAmount);

            // Transfer fee to treasury immediately
            if (fee > 0) {
                IERC20(token).transfer(treasury, fee);
            }
        }

        // Mint all vouchers
        for (uint256 i = 0; i < batch.voucherHashes.length; i++) {
            uint256 expiryTimestamp = 0;
            if (batch.expiryDays[i] > 0) {
                expiryTimestamp = block.timestamp + (batch.expiryDays[i] * 1 days);
            } else if (defaultExpiryDays > 0) {
                expiryTimestamp = block.timestamp + (defaultExpiryDays * 1 days);
            }

            Voucher memory newVoucher = Voucher({
                voucherHash: batch.voucherHashes[i],
                token: batch.tokens[i],
                tokenValue: batch.tokenValues[i],
                isRedeemed: false,
                issuer: msg.sender,
                mintTimestamp: block.timestamp,
                expiryTimestamp: expiryTimestamp,
                exists: true
            });

            vouchers[batch.voucherHashes[i]] = newVoucher;
            totalVouchersMinted++;

            emit VoucherMinted(
                batch.voucherHashes[i], batch.tokens[i], batch.tokenValues[i], msg.sender, expiryTimestamp
            );
        }

        if (agents[msg.sender].isActive) {
            agents[msg.sender].totalMinted += batch.voucherHashes.length;
            // Calculate total value across all tokens
            uint256 totalValue = 0;
            for (uint256 i = 0; i < batch.tokenValues.length; i++) {
                totalValue += batch.tokenValues[i];
            }
            agents[msg.sender].totalValue += totalValue;
        }

        emit VoucherBatchMinted(msg.sender, batch.voucherHashes.length, 0); // Total value calculation removed for multi-token
    }

    function redeemVoucher(string memory voucherCode, address recipient) external nonReentrant {
        bytes32 voucherHash = keccak256(abi.encodePacked(voucherCode));
        Voucher storage voucher = vouchers[voucherHash];

        if (!voucher.exists) revert VoucherNotFound();
        if (voucher.isRedeemed) revert VoucherAlreadyRedeemed();
        if (voucher.expiryTimestamp > 0 && block.timestamp > voucher.expiryTimestamp) {
            revert VoucherExpired();
        }

        voucher.isRedeemed = true;
        totalVouchersRedeemed++;

        uint256 fee = (voucher.tokenValue * redemptionFee) / 10000;
        uint256 netAmount = voucher.tokenValue - fee;

        totalTokensRedeemed[voucher.token] += voucher.tokenValue;

        IERC20(voucher.token).transfer(recipient, netAmount);

        if (fee > 0) {
            IERC20(voucher.token).transfer(treasury, fee);
        }

        emit VoucherRedeemed(voucherHash, voucher.token, recipient, voucher.tokenValue, fee);
    }

    function reclaimExpiredVoucher(string memory voucherCode) external nonReentrant {
        bytes32 voucherHash = keccak256(abi.encodePacked(voucherCode));
        Voucher storage voucher = vouchers[voucherHash];

        if (!voucher.exists) revert VoucherNotFound();
        if (voucher.isRedeemed) revert VoucherAlreadyRedeemed();
        if (voucher.issuer != msg.sender) revert UnauthorizedMinter();

        // Check if voucher has expired
        if (voucher.expiryTimestamp == 0 || block.timestamp <= voucher.expiryTimestamp) {
            revert VoucherNotExpired();
        }

        voucher.isRedeemed = true;
        totalVouchersRedeemed++;

        // Transfer the voucher value back to the agent
        IERC20(voucher.token).transfer(msg.sender, voucher.tokenValue);

        emit VoucherReclaimed(voucherHash, voucher.token, msg.sender, voucher.tokenValue);
    }

    function getVoucherStatus(string memory voucherCode)
        external
        view
        returns (
            bool exists,
            bool isRedeemed,
            address token,
            uint256 tokenValue,
            address issuer,
            uint256 expiryTimestamp
        )
    {
        bytes32 voucherHash = keccak256(abi.encodePacked(voucherCode));
        Voucher memory voucher = vouchers[voucherHash];

        return (
            voucher.exists,
            voucher.isRedeemed,
            voucher.token,
            voucher.tokenValue,
            voucher.issuer,
            voucher.expiryTimestamp
        );
    }

    function registerAgent(address agent, uint256 commissionRate) external onlyOwner {
        require(agent != address(0), "Invalid agent address");
        require(commissionRate <= 1000, "Commission rate too high");

        agents[agent] =
            Agent({isActive: true, totalMinted: 0, totalValue: 0, commissionRate: commissionRate, lastSettlement: 0});

        emit AgentRegistered(agent, commissionRate);
    }

    function deactivateAgent(address agent) external onlyOwner {
        require(agents[agent].isActive, "Agent not active");
        agents[agent].isActive = false;
        emit AgentDeactivated(agent);
    }

    function settleAgentBalance(address agent, address token) external nonReentrant {
        Agent storage agentData = agents[agent];
        require(agentData.isActive, "Agent not active");
        require(agentBalances[agent][token] > 0, "No balance to settle");

        uint256 amount = agentBalances[agent][token];
        agentBalances[agent][token] = 0;
        agentData.lastSettlement = block.timestamp;

        IERC20(token).transfer(agent, amount);

        emit AgentBalanceSettled(agent, token, amount);
    }

    function updateFees(uint256 _mintingFee, uint256 _redemptionFee) external onlyOwner {
        require(_mintingFee <= 500, "Minting fee too high");
        require(_redemptionFee <= 500, "Redemption fee too high");

        mintingFee = _mintingFee;
        redemptionFee = _redemptionFee;

        emit FeesUpdated(_mintingFee, _redemptionFee);
    }

    function updateTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        supportedTokens[token] = true;
        emit TokenSupported(token, true);
    }

    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        emit TokenSupported(token, false);
    }

    function updateDefaultExpiryDays(uint256 _defaultExpiryDays) external onlyOwner {
        require(_defaultExpiryDays <= 365, "Expiry too long");
        defaultExpiryDays = _defaultExpiryDays;
    }

    function addAuthorizedMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = true;
    }

    function removeAuthorizedMinter(address minter) external onlyOwner {
        authorizedMinters[minter] = false;
    }

    function getContractStats()
        external
        view
        returns (uint256 totalMinted, uint256 totalRedeemed, uint256 mintingFeeRate, uint256 redemptionFeeRate)
    {
        return (totalVouchersMinted, totalVouchersRedeemed, mintingFee, redemptionFee);
    }

    function getTokenStats(address token) external view returns (uint256 totalRedeemed) {
        return totalTokensRedeemed[token];
    }

    function getAgentStats(address agent)
        external
        view
        returns (bool isActive, uint256 totalMinted, uint256 totalValue, uint256 commissionRate, uint256 lastSettlement)
    {
        Agent memory agentData = agents[agent];
        return (
            agentData.isActive,
            agentData.totalMinted,
            agentData.totalValue,
            agentData.commissionRate,
            agentData.lastSettlement
        );
    }

    function getAgentTokenBalance(address agent, address token) external view returns (uint256) {
        return agentBalances[agent][token];
    }

    function getContractTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function isTokenSupported(address token) external view returns (bool) {
        return supportedTokens[token];
    }
}
