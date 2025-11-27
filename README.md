# NFT Reward Crowdfunding(DEMO)

## 项目概述

本项目作为Web3开发的演示项目，旨在展示Web3开发的全面能力，从智能合约设计到前端集成，打造一个可扩展的去中心化应用原型。采用了现代Solidity最佳实践，包括OpenZeppelin的ReentrancyGuard和Ownable合约库，确保安全性与可扩展性。全面的测试覆盖率通过Foundry测试套件实现，覆盖核心功能和边界情况。本地RPC开发环境基于Anvil，合约创意亮点在于tiered NFT奖励系统：根据总捐赠金额自动分配Bronze、Silver或Gold等级NFT，提倡经济激励与数字收藏价值的理念 🙂。

## 技术栈

- **后端合约**: Solidity ^0.8.20，使用Foundry框架开发
  - 核心合约: Crowdfund.sol (众筹管理), RewardNFT.sol (ERC-721奖励), MockUSDC.sol (ERC-20模拟代币)
  - 安全库: OpenZeppelin ReentrancyGuard, Ownable
  - 预言机集成: Chainlink价格喂价
- **前端**: Vue 3 + Vite + TypeScript
  - Web3集成: ethers.js v6
  - UI组件: Ant Design Vue
- **开发工具**: Foundry (编译、测试、部署), Anvil (本地区块链)

## 核心功能

- **众筹活动管理**: 创建时间限制的众筹项目，设定目标金额
- **多币种捐赠**: 支持原生ETH和ERC-20 (MockUSDC) 捐赠
- **NFT奖励系统**: 根据捐赠金额自动铸造分级NFT (Bronze/Silver/Gold)
- **透明记录**: 所有捐赠和活动状态上链，确保不可篡改
- **提现与退款**: 项目成功后提现，失败时退款并销毁NFT
- **全面测试**: Foundry测试套件覆盖捐赠、提现、退款等关键流程


- **创意合约**: tiered NFT奖励机制，结合Chainlink预言机实现公平定价

## 未来计划

- [ ] 多币支付支持：扩展支持更多ERC-20代币和跨链资产
- [ ] Oracle定价提升公平性：集成更多Chainlink喂价，确保实时准确的代币估值

---