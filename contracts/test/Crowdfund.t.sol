// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Crowdfund.sol";
import "../src/MockUSDC.sol";
import "../src/RewardNFT.sol";

contract CrowdfundTest is Test {
    Crowdfund public crowdfund;
    MockUSDC public usdc;
    RewardNFT public nft;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    event Refund(uint indexed id, address donor, uint ethAmount, uint usdcAmount);

    // Allow the test contract to receive ETH when Crowdfund withdraws
    receive() external payable {}

    function setUp() public {
        usdc = new MockUSDC();
        crowdfund = new Crowdfund(address(usdc));
        nft = crowdfund.nft();

        // 给测试用户发送 ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // 给测试用户 mint USDC， 1 ETH = 1000 USDC（即 USDC/ETH = 0.001）
        usdc.mint(user1, 100000);
        usdc.mint(user2, 100000);
    }

    function testCreateCampaign() public {
        (uint campaignId, string memory title) = createCampaign();

        assertEq(campaignId, 0);
        assertEq(title, "Test Campaign");

        (uint id, address campaignOwner, , uint goal, uint raised, , , bool withdrawn) = crowdfund.campaigns(0);

        assertEq(id, 0);
        assertEq(campaignOwner, owner);
        assertEq(goal, 10 ether);
        assertEq(raised, 0);
        assertFalse(withdrawn);
    }

    function testDonateETH() public {
        // 创建活动
        createCampaign();

        // 用户1 捐赠 0.4 ETH
        vm.prank(user1);
        crowdfund.donateRealETH{value: 40000000000000000}(0);

        // 检查募集金额（ETH）
        assertEq(crowdfund.campaignTokenRaised(0, address(0)), 40000000000000000);

        // 检查用户获得 NFT (铜牌)
        // 第一次捐赠会铸造铜牌 NFT
        assertEq(nft.balanceOf(user1), 1);

        // 再次由 user1 捐赠0.2 ETH
        vm.prank(user1);
        crowdfund.donateRealETH{value: 20000000000000000}(0);

        // 检查募集金额（ETH）
        assertEq(crowdfund.campaignTokenRaised(0, address(0)), 60000000000000000);

        // 检查用户获得 NFT (银牌)
        assertEq(nft.balanceOf(user1), 2);
    }

    function testDonateUSDC() public {
        // 创建活动
        createCampaign();

        // 用户1 授权并捐赠 1000 USDC
        vm.startPrank(user1);
        usdc.approve(address(crowdfund), 1000 * 1e6);
        crowdfund.donateMockUSDC(0, 1000 * 1e6);
        vm.stopPrank();

        // 检查 USDC 募集金额
        assertEq(crowdfund.campaignTokenRaised(0, address(usdc)), 1000 * 1e6);

        // 检查等值 ETH (1000 USDC = 1 ETH)
        (, , , , uint raised, , , ) = crowdfund.campaigns(0);
        assertEq(raised, 1 ether);
    }

    function testUpgradeTier() public {
        // 创建活动
        createCampaign();

        // 第一次捐赠 0.01 ETH (铜牌)
        vm.prank(user1);
        crowdfund.donateRealETH{value: 0.01 ether}(0);
        assertEq(nft.balanceOf(user1), 1);
        assertEq(nft.tierOf(0), 0); // 铜牌

        // 第二次捐赠 0.05 ETH (累计 0.06 ETH，升级到银牌)
        vm.prank(user1);
        crowdfund.donateRealETH{value: 0.05 ether}(0);
        assertEq(nft.balanceOf(user1), 2);
        assertEq(nft.tierOf(1), 1); // 银牌

        // 第三次捐赠 5 ETH (累计 5.06 ETH，升级到金牌)
        vm.prank(user1);
        crowdfund.donateRealETH{value: 5 ether}(0);
        assertEq(nft.balanceOf(user1), 3);
        assertEq(nft.tierOf(2), 2); // 金牌
    }

    function testWithdraw() public {
        // 创建活动
        createCampaign();

        // 用户捐赠 15 ETH (超过目标)
        vm.prank(user1);
        crowdfund.donateRealETH{value: 15 ether}(0);

        // 用户捐赠 1000 USDC
        vm.startPrank(user2);
        usdc.approve(address(crowdfund), 1000 * 1e6);
        crowdfund.donateMockUSDC(0, 1000 * 1e6);
        vm.stopPrank();

        // 时间快进到活动结束
        vm.warp(31 days);

        // 记录 owner 初始余额
        uint ownerBalanceBefore = owner.balance;

        // 提现
        crowdfund.withdraw(0);

        // 检查 owner 收到 15 ETH和 1000USDC
        assertEq(owner.balance - ownerBalanceBefore, 15 ether);
        assertEq(usdc.balanceOf(owner), 1000 * 1e6);

        // 检查活动标记为已提现
        (, , , , , , , bool withdrawn) = crowdfund.campaigns(0);
        assertTrue(withdrawn);
    }

    function testCannotDonateAfterEnd() public {
        createCampaign();

        // 时间快进到活动结束后
        vm.warp(31 days);

        // 尝试捐赠应该失败
        vm.prank(user1);
        vm.expectRevert("Ended");
        crowdfund.donateRealETH{value: 1 ether}(0);
    }

    function testCannotWithdrawBeforeGoalReached() public {
        createCampaign();

        // 只捐赠 5 ETH (未达到目标)
        vm.prank(user1);
        crowdfund.donateRealETH{value: 5 ether}(0);

        // 时间快进
        vm.warp(31 days);

        // 尝试提现应该失败
        vm.expectRevert("Goal not reached");
        crowdfund.withdraw(0);
    }

    function testCannotWithdrawTwice() public {
        createCampaign();

        vm.prank(user1);
        crowdfund.donateRealETH{value: 15 ether}(0);

        // console2.log(
        //     "%s user's campaignTokenRaised : %d ether",
        //     user1,
        //     crowdfund.campaignTokenRaised(0, address(0)) / 1e18
        // );

        vm.warp(31 days);
        crowdfund.withdraw(0);
        // console2.log("current address= %s", address(this));
        // console2.log("current msg.sender= %s", msg.sender);

        // 第二次提现应该失败
        vm.expectRevert("Already withdrawn");
        crowdfund.withdraw(0);
    }

    // ================================
    // Refund Function Tests
    // ================================
    function testRefundMixedTokensSuccessfully() public {
        createCampaign();
        uint usdcDonateAmount = 1000 * 1e6;
        uint ethDonateAmount = 4 ether;
        vm.prank(user1);
        crowdfund.donateRealETH{value: ethDonateAmount}(0);

        vm.startPrank(user2);
        usdc.approve(address(crowdfund), usdcDonateAmount);
        crowdfund.donateMockUSDC(0, usdcDonateAmount);
        vm.stopPrank();

        vm.warp(31 days);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Refund(0, user1, ethDonateAmount, 0);
        crowdfund.refund(0);
        assertEq(address(user1).balance, 100 ether);

        vm.prank(user2);
        vm.expectEmit(true, false, false, true);
        emit Refund(0, user2, 0, usdcDonateAmount);
        crowdfund.refund(0);
        assertEq(usdc.balanceOf(user2), 100000 * 1e6);
    }

    function testRefundUpdatesRaisedAmountCorrectly() public {
        //测试退款后 campaign.raised 金额正确更新
        createCampaign();
        uint ethDonateAmount = 4 ether;
        vm.prank(user1);
        crowdfund.donateRealETH{value: ethDonateAmount}(0);

        vm.warp(31 days);

        vm.prank(user1);
        crowdfund.refund(0);
        assertEq(address(user1).balance, 100 ether);

        (, , , , uint raised, , , ) = crowdfund.campaigns(0);
        assertEq(raised, 0);
    }

    function testCannotRefundCampaignNotExists() public {
        //测试不存在的活动无法退款
        vm.prank(user1);
        vm.expectRevert("Campaign does not exist");
        crowdfund.refund(4);
    }

    function testCannotRefundWhenNotEnded() public {
        // 测试活动未结束时无法退款
        createCampaign();
        vm.expectRevert("Campaign not ended");
        crowdfund.refund(0);
    }

    function testCannotRefundWhenGoalReached() public {
        // 测试目标达成时无法退款
        createCampaign();
        uint ethDonateAmount = 10 ether;
        vm.prank(user1);
        crowdfund.donateRealETH{value: ethDonateAmount}(0);
        vm.warp(10 days);
        vm.expectRevert("Campaign reached goal, cannot refund");
        crowdfund.refund(0);
    }

    function testCannotRefundWhenAlreadyWithdrawn() public {
        // 测试已提现后无法退款
        createCampaign();

        vm.prank(user1);
        crowdfund.donateRealETH{value: 15 ether}(0);

        vm.warp(31 days);
        crowdfund.withdraw(0);

        // (, , , , , , , bool withdrawn) = crowdfund.campaigns(0);
        // console.log("withdrawal: %b", withdrawn);

        vm.prank(user1);
        vm.expectRevert("Already withdrawn");
        crowdfund.refund(0);
    }

    function testRefundWithInsufficientContractETH() public {
        // TODO: 测试合约 ETH 余额不足时的退款行为
        // 这是一个边界情况，可能需要特殊设置来模拟
    }

    function createCampaign() internal returns (uint, string memory) {
        uint startAt = block.timestamp;
        uint endAt = block.timestamp + 1 days;
        return crowdfund.createCampaign("Test Campaign", 10, startAt, endAt);
    }
}
