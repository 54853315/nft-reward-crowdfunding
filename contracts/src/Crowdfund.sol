// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./RewardNFT.sol";
import "./MockUSDC.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract Crowdfund is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    RewardNFT public nft;
    MockUSDC public usdc;
    uint public nextCampaignId;
    uint public constant USDC_DECIMALS = 1e6;
    uint public constant USDC_PER_ETH = 1000;
    struct Campaign {
        uint id;
        address owner;
        string title;
        uint goal; //总需募集的 eth
        uint raised; // 已筹备到的 eth
        uint startAt;
        uint endAt;
        bool withdrawn;
    }
    struct Donation {
        uint amount;
        uint tier;
    }
    Campaign[] public campaigns;
    mapping(uint => mapping(address => uint[])) public donationNftTokens; // campaignId => donor => nft tokenIds
    mapping(uint => mapping(address => Donation)) public donations;
    // Tracks total raised amounts per campaign by token.
    // - Key:   campaignId
    // - Token: ERC20 token address, or address(0) for native ETH
    // - Value: accumulated amount for that token
    // Useful to compute and transfer totals efficiently on withdraw.
    mapping(uint => mapping(address => uint)) public campaignTokenRaised;

    // Records per-donor deposited amounts per campaign by token.
    // - Key:   campaignId
    // - Sub:   donor address
    // - Token: ERC20 token address, or address(0) for native ETH
    // - Value: amount that donor deposited for that token (used for refunds)
    mapping(uint => mapping(address => mapping(address => uint))) public donationsTokenAmount;

    AggregatorV3Interface public usdcUsdPriceFeed;
    AggregatorV3Interface public usdtUsdPriceFeed;

    event CampaignCreated(uint indexed id, string title, uint goal, uint startAt, uint endAt);
    event Withdrawn(uint indexed id, uint amount);
    event Refund(uint indexed id, address donor, uint ethAmount, uint usdcAmount);
    // Donated: index campaign id and donor so listeners can filter by campaign or donor.
    event Donated(uint indexed id, address indexed donor, uint amount, uint tier, uint256 tokenId);
    // NFTBurned: index campaignId and donor for easy lookup of burn activity per campaign or user.
    event NFTBurned(uint indexed campaignId, address indexed donor, uint tokenId);
    // NFTBurnFailed: index campaignId so failures for a specific token can be queried.
    event NFTBurnFailed(uint indexed campaignId, address indexed donor, uint tokenId);

    constructor(address _usdcAddress) Ownable(msg.sender) {
        // ethUsdPriceFeed = AggregatorV3Interface(
        //     0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419
        // );
        usdcUsdPriceFeed = AggregatorV3Interface(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);
        usdtUsdPriceFeed = AggregatorV3Interface(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46);
        nft = new RewardNFT();
        // 将 NFT 合约的所有权转移给当前合约
        nft.transferOwnership(address(this));

        // 如果传入零地址，则自动部署新的 MockUSDC；否则使用提供的地址
        if (_usdcAddress == address(0)) {
            usdc = new MockUSDC();
        } else {
            usdc = MockUSDC(_usdcAddress);
        }
    }

    modifier onlyValidCampaign(uint256 campaignId) {
        require(campaignId < campaigns.length, "Campaign not registered");
        _;
    }

    modifier onlyCampaignActive(Campaign memory campaign) {
        require(block.timestamp < campaign.endAt, "Ended");
        require(block.timestamp >= campaign.startAt, "Not Yet");
        _;
    }

    //✅
    function createCampaign(string memory title, uint goal, uint startAt, uint endAt) public returns (uint, string memory) {
        // require(startAt >= block.timestamp, "start at should be >= now");
        require(endAt > startAt, "end at should be > start at");
        require(bytes(title).length > 0, "Title should not be empty");
        require(goal > 0, "Goal should less 0 ");
        require(msg.sender != address(0), "contract can not create campaign");

        Campaign memory newCampaign = Campaign({id: nextCampaignId, title: title, startAt: startAt, endAt: endAt, goal: goal * 1e18, owner: msg.sender, raised: 0, withdrawn: false});
        campaigns.push(newCampaign);
        nextCampaignId++;
        emit CampaignCreated(newCampaign.id, title, goal, startAt, endAt);

        return (newCampaign.id, title);
    }

    //✅
    function myDonations(uint campaignId) public view returns (Donation memory) {
        return donations[campaignId][msg.sender];
    }

    // ✅
    function donateRealETH(uint campaignId) external payable nonReentrant onlyValidCampaign(campaignId) onlyCampaignActive(campaigns[campaignId]) {
        require(campaignId < campaigns.length, "Campaign does not exist");
        require(msg.value > 0, "ETH amount must be greater than 0");
        campaignTokenRaised[campaignId][address(0)] += msg.value;
        donationsTokenAmount[campaignId][msg.sender][address(0)] += msg.value;
        _recordDonate(campaignId, msg.value);
    }

    //✅
    /**
     * @notice 向指定众筹活动使用模拟 USDC 捐款，并以 ETH 的等价金额记录该捐款。
     * @dev
     * - 受 nonReentrant 修饰器保护以防重入攻击，并受 onlyCampaignActive(campaigns[campaignId]) 修饰器约束活动必须处于可接收捐款状态。
     * - 将 USDC 数量转换为 ETH 等价的 wei 数量供内部记录：
     *     - 假设固定汇率为 1 ETH = 1000 USDC（即 USDC/ETH = 0.001）。
     *     - 考虑 USDC 使用 6 位小数，ETH 使用 18 位小数，因此计算：
     *       ethAmount = amount * 1e18 / (1000 * 1e6)
     *     - 计算结果为以 wei 为单位的 ETH 等价值。
     *
     * @param campaignId 要捐款的众筹活动 ID（索引，需小于 campaigns.length）
     * @param amount     捐赠的 USDC 数量，以 USDC 的最小单位（6 位小数）表示
     *
     * @notice 注意事项：
     * - 本函数使用了一个固定的汇率假设（1 ETH = 1000 USDC），如果要在生产环境使用须改为可配置或通过预言机获取实时汇率以避免估值偏差。
     * - amount 的溢出/下溢等边界取决于上层逻辑及 Solidity 版本的算术行为；若需要额外保护可在调用前验证范围。
     */
    function donateMockUSDC(uint campaignId, uint256 amount) external nonReentrant onlyValidCampaign(campaignId) onlyCampaignActive(campaigns[campaignId]) {
        require(campaignId < campaigns.length, "Campaign does not exist");
        campaignTokenRaised[campaignId][address(usdc)] += amount;
        donationsTokenAmount[campaignId][msg.sender][address(usdc)] += amount;
        IERC20(address(usdc)).safeTransferFrom(msg.sender, address(this), amount);
        // 假设 USDC/ETH = 0.001，即 1 ETH = 1000 USDC
        // USDC 使用 6 位小数，ETH 使用 18 位小数
        // ethAmount = amount * 1e18 / (1000 * 1e6) = amount * 1e12 / 1000 = amount * 1e9
        uint256 ethAmount = (amount * 1e18) / (USDC_PER_ETH * USDC_DECIMALS);
        _recordDonate(campaignId, ethAmount);
    }

    // ✅
    function _recordDonate(uint campaignId, uint256 amount) internal {
        Campaign storage campaign = campaigns[campaignId];
        Donation storage donation = donations[campaignId][msg.sender];
        campaign.raised += amount;
        donation.amount += amount;
        uint totalDonationAmount = donation.amount;
        uint tier = _getTier(totalDonationAmount);
        donation.tier = tier;
        uint nftTokenId = nft.mint(msg.sender, tier);
        donationNftTokens[campaignId][msg.sender].push(nftTokenId);
        emit Donated(campaignId, msg.sender, amount, tier, nftTokenId);
    }

    //✅
    function _getTier(uint totalAmount) internal pure returns (uint) {
        if (totalAmount >= 5 ether) return 2; // 金
        if (totalAmount >= 0.05 ether) return 1; // 银
        return 0; // 铜
    }

    // ✅
    function withdraw(uint campaignId) external nonReentrant {
        require(campaignId < campaigns.length, "Campaign does not exist");
        Campaign storage campaign = campaigns[campaignId];
        require(msg.sender == campaign.owner, "Not owner");
        require(!campaign.withdrawn, "Already withdrawn");
        require(block.timestamp > campaign.endAt, "Campaign not ended");
        require(campaign.raised >= campaign.goal, "Goal not reached");
        campaign.withdrawn = true;

        // 提取该活动募集的 ETH
        uint256 ethAmount = campaignTokenRaised[campaignId][address(0)];
        require(address(this).balance >= ethAmount, "Insufficient contract ETH");
        if (ethAmount > 0) {
            (bool sent, ) = payable(campaign.owner).call{value: ethAmount}("");
            require(sent, "ETH transfer failed");
        }

        // 提取该活动募集的 USDC
        uint256 usdcAmount = campaignTokenRaised[campaignId][address(usdc)];
        if (usdcAmount > 0) {
            IERC20(address(usdc)).safeTransfer(campaign.owner, usdcAmount);
        }

        emit Withdrawn(campaignId, campaign.raised);
    }

    function refund(uint campaignId) external nonReentrant {
        require(campaignId < campaigns.length, "Campaign does not exist");
        Campaign memory campaign = campaigns[campaignId];
        require(block.timestamp > campaign.endAt, "Campaign not ended");
        require(!campaign.withdrawn, "Already withdrawn");
        require(campaign.raised < campaign.goal, "Campaign reached goal, cannot refund");
        require(donations[campaignId][msg.sender].amount > 0, "No donations");

        (uint256 ethDonated, uint256 usdcDonated) = _settleRaisedAmounts(campaignId, msg.sender);
        _refundAssets(msg.sender, ethDonated, usdcDonated);
        _burnRewardNFTs(campaignId, msg.sender);
        emit Refund(campaignId, msg.sender, ethDonated, usdcDonated);
    }

    function _settleRaisedAmounts(uint campaignId, address donor) internal returns (uint256 ethDonated, uint256 usdcDonated) {
        Campaign storage campaign = campaigns[campaignId];
        Donation storage donation = donations[campaignId][donor];
        mapping(address => uint256) storage donorTokenAmounts = donationsTokenAmount[campaignId][donor];

        ethDonated = donorTokenAmounts[address(0)];
        usdcDonated = donorTokenAmounts[address(usdc)];
        require(address(this).balance >= ethDonated, "Insufficient contract ETH");

        donorTokenAmounts[address(0)] = 0;
        donorTokenAmounts[address(usdc)] = 0;
        donation.amount = 0;

        campaignTokenRaised[campaignId][address(0)] -= ethDonated;
        campaignTokenRaised[campaignId][address(usdc)] -= usdcDonated;

        //将 USDC 对应的 ETH 等价值从 raised 中减去
        uint256 totalEthImpact = ethDonated + _usdcToEth(usdcDonated);
        campaign.raised -= totalEthImpact;
    }

    function _usdcToEth(uint256 usdcAmount) internal pure returns (uint256) {
        if (usdcAmount == 0) return 0;
        return (usdcAmount * 1e18) / (USDC_PER_ETH * USDC_DECIMALS);
    }

    function _refundAssets(address donor, uint256 ethAmount, uint256 usdcAmount) internal {
        if (ethAmount > 0) {
            (bool sent, ) = payable(donor).call{value: ethAmount}("");
            require(sent, "ETH transfer failed");
        }
        if (usdcAmount > 0) {
            IERC20(address(usdc)).safeTransfer(donor, usdcAmount);
        }
    }

    function _burnRewardNFTs(uint campaignId, address donor) internal {
        uint[] storage nftTokens = donationNftTokens[campaignId][donor];
        for (uint i = nftTokens.length; i > 0; i--) {
            uint tokenId = nftTokens[i - 1];
            nftTokens.pop();
            try nft.burn(tokenId) {
                emit NFTBurned(campaignId, donor, tokenId);
            } catch {
                emit NFTBurnFailed(campaignId, donor, tokenId);
            }
        }
    }

    // Emergency functions
    function emergencyWithdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    //@TODO
    function getETHPrice() public view returns (int) {
        (, int price, , , ) = usdcUsdPriceFeed.latestRoundData();
        return price;
    }

    // function _toEth(
    //     address token,
    //     uint amount
    // ) internal view returns (uint ethScaled) {
    //     AggregatorV3Interface feed = priceFeeds[token];
    //     (, int price, , , ) = feed.latestRoundData(); // price with feed.decimals()
    //     uint feedDecimals = feed.decimals();
    //     // compute usdScaled with chosen scale, e.g., 1e18
    //     usdScaled =
    //         ((uint(price) * amount) / (10 ** feedDecimals)) *
    //         (10 ** (18 - tokenDecimals[token]));
    // }
}
