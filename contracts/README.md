## NFT Reward Crowdfunding — contracts

一个简单的去中心化众筹合约DEMO：捐款者在支持众筹时会获得按档次发放的奖励 NFT（ERC-721），支持原生 ETH 和模拟的 USDC（ERC-20 mock）。项目使用 Foundry 进行开发和测试。

## 目录与核心合约

- `src/Crowdfund.sol` — 核心合约，管理 Campaign（众筹活动），接收 ETH/USDC 捐款，按金额发放奖励 NFT，并在活动结束后允许提取或退款。
- `src/RewardNFT.sol` — 奖励用的 ERC-721 合约（简单 NFT，用于表示捐赠档位）。
- `src/MockUSDC.sol` — 本地测试用的 ERC-20 mock（6 位小数），用于模拟 USDC 行为。

测试文件位于 `test/`，包括 `Crowdfund.t.sol` 等 Foundry 测试。

## 快速开始（macOS）

确保已安装 Foundry（forge、cast）。

```bash
git clone https://github.com/54853315/nft-reward-crowdfunding.git
cd nft-reward-crowdfunding/contracts
npm install
forge install Openzeppelin/openzeppelin-contracts
forge build
forge test
```

### 功能注意点

- 本合约中对 MockUSDC 换算使用了简化的固定汇率（1 ETH = 1000 USDC）。
 
## 详细 Foundry（Forge + Anvil）操作流

下面是针对 Foundry（forge/cast）与 Anvil 的更详细使用步骤与常用命令，方便在本地开发、运行测试、广播脚本和调试合约。

1) 在本地启动 Anvil（本地 JSON-RPC 节点，用于测试/调试）

```bash
# 在默认端口 8545 启动
anvil

# 若要 fork 主网以在真实链状态上调试：
# anvil --fork-url https://mainnet.infura.io/v3/$INFURA_KEY --fork-block-number 17xxxxxx
```

2) 编译、运行测试与常用选项

```bash
# 编译合约
forge build

# 运行所有测试（详细输出）
forge test -vvvv

# 只运行某个合约的测试（按合约名）
forge test --match-contract Crowdfund -vvvv

# 只运行某个测试用例（按测试名）
forge test --match-test testDonateMockUSDC -vvvv

# 显示 gas 报告
forge test --gas-report
```

3) 部署脚本

```bash
# 在本地 anvil 上广播脚
forge script script/Crowdfund.s.sol:Crowdfund --rpc-url http://127.0.0.1:8545 --broadcast --private-key $PRIVATE_KEY -vvvv

# 直接用 cast 与已部署合约交互
cast send <CONTRACT_ADDRESS> "donateMockUSDC(uint256)" 1000000 --private-key $PRIVATE_KEY --rpc-url http://127.0.0.1:8545
```

4) 常见问题与排查建议

- 找不到 `forge`/`anvil`：确认已运行 `foundryup` 并把 `~/.foundry/bin` 加入 PATH，重新打开 shell。
- 编译错误找不到依赖：运行 `forge install` 或检查 `lib/` 与 `remappings.txt`。
- 测试失败但在独立合约中运行正常：使用 `forge test -vvvv` 查看堆栈回溯和 revert 原因；可配合 `anvil` 的 fork 来重现链上状态。
- 脚本广播失败：确认使用 `--broadcast` 与正确的 `--rpc-url` / `--private-key`，并先在本地用 `anvil` 检查。
