import { ethers } from "ethers";
import { CROWDFUND_ADDRESS, DEFAULT_RPC } from "../constants/contracts";
import CrowdfundABI from "../abi/Crowdfund.json";
import ERC20ABI from "../abi/ERC20.json";

let browserProvider: ethers.BrowserProvider | null = null;
// let defaultProvider: ethers.getDefaultProvider | null = null;
let signer: ethers.JsonRpcSigner | null = null;

function isContractValid(contract: any): contract is ethers.Contract {
  return !!(
    contract &&
    contract.target && // v6: string 地址
    // 或 contract.address     // v5: string 地址
    contract.interface && // Interface 实例
    typeof contract.callStatic === "object"
  );
}

export async function connectWallet(): Promise<string | null> {
  if (typeof window === "undefined" || !(window as any).ethereum) {
    console.error("No injected wallet found");
    return null;
  }
  try {
    browserProvider = new ethers.BrowserProvider((window as any).ethereum);
    // 请求权限
    await browserProvider.send("eth_requestAccounts", []);
    // 切换到本地 Anvil 网络 (chainId: 31337)
    try {
      await browserProvider.send("wallet_switchEthereumChain", [
        { chainId: "0x7a69" },
      ]);
    } catch (switchError: any) {
      // 如果网络不存在，添加网络
      if (
        switchError.code === 4902 ||
        switchError.message?.includes("Unrecognized")
      ) {
        await browserProvider.send("wallet_addEthereumChain", [
          {
            chainId: "0x7a69",
            chainName: "Local Anvil",
            rpcUrls: ["http://127.0.0.1:8545"],
            nativeCurrency: {
              name: "ETH",
              symbol: "ETH",
              decimals: 18,
            },
            blockExplorerUrls: [],
          },
        ]);
      } else {
        throw switchError;
      }
    }
    signer = await browserProvider.getSigner();
    const network = await browserProvider.getNetwork();
    if (network.chainId !== 31337n) {
      throw new Error("Failed to switch to local Anvil network");
    }
    const address = await signer.getAddress();
    return address;
  } catch (e) {
    console.error("connectWallet error", e);
    return null;
  }
}

export function disconnectWallet() {
  // EIP-1193 没有标准断开流程；前端只需清理本地引用
  browserProvider = null;
  signer = null;
}

export async function getAccount(): Promise<string | null> {
  try {
    // 钱包中已授权账户时，从 window.ethereum 恢复 provider
    if (!browserProvider) {
      if (typeof window !== "undefined" && (window as any).ethereum) {
        browserProvider = new ethers.BrowserProvider((window as any).ethereum);
      } else {
        return null;
      }
    }

    const s = await browserProvider.getSigner();
    signer = s; // Set global signer
    const addr = await s.getAddress();
    return addr;
  } catch {
    return null;
  }
}

export async function getBalance(): Promise<string | null> {
  try {
    // 优先使用 signer（已连接且可签名），其次尝试 browserProvider（可能在刷新后仍可用）
    let s: ethers.JsonRpcSigner | null = null;
    if (signer) {
      s = signer;
    } else if (browserProvider) {
      s = await browserProvider.getSigner();
    } else if (typeof window !== "undefined" && (window as any).ethereum) {
      // 在页面刷新后，尝试从注入的 wallet 恢复 provider
      browserProvider = new ethers.BrowserProvider((window as any).ethereum);
      s = await browserProvider.getSigner();
    } else {
      return null;
    }

    const addr = await s.getAddress();
    const provider = s.provider || browserProvider;
    if (!provider) return null;
    const balance = await provider.getBalance(addr);
    return ethers.formatEther(balance);
  } catch {
    return null;
  }
}

export async function getCrowdfundContract() {
  // 优先使用已连接的 provider/signer（能 write）；否则使用本地区块链 RPC 的只读 provider
  let providerOrSigner: any = null;
  if (signer) {
    providerOrSigner = signer;
  } else if (browserProvider) {
    providerOrSigner = browserProvider;
  } else {
    providerOrSigner = new ethers.JsonRpcProvider(DEFAULT_RPC);
  }

  try {
    const contract = new ethers.Contract(
      CROWDFUND_ADDRESS,
      CrowdfundABI as any,
      providerOrSigner
    );
    return contract;
  } catch (e) {
    console.error("getCrowdfundContract error", e);
    return null;
  }
}

// --- Crowdfund helpers ---
export async function getNextCampaignId(): Promise<number | null> {
  const contract = await getCrowdfundContract();
  if (!isContractValid(contract)) return null;
  try {
    const id = await contract.nextCampaignId();
    return Number(id);
  } catch (e: any) {
    if (e.code == "BAD_DATA" && e.value == "0x") {
      console.warn("ethers v6 经典 0 值解析 bug，已自动修复");
      return 0;
    } else {
      console.error("getNextCampaignId error", e);
      return null;
    }
  }
}

export async function getCampaign(id: number) {
  const contract = await getCrowdfundContract();
  if (!contract) return null;
  try {
    const c = await contract.campaigns(id);
    return c;
  } catch (e) {
    console.error("getCampaign error", e);
    return null;
  }
}

export async function createCampaign(
  title: string,
  goalEth: string | number,
  startAt: number,
  endAt: number
) {
  if (!signer) throw new Error("Wallet not connected");
  const contract = await getCrowdfundContract();
  if (!contract) throw new Error("contract not available");
  // Note: Crowdfund.createCampaign multiplies goal by 1e18 internally,
  // so pass goal as integer ETH amount (no wei conversion here).
  try {
    const tx = await contract.createCampaign(
      title,
      String(goalEth),
      startAt,
      endAt
    );
    const receipt = await tx.wait();
    return receipt;
  } catch (e) {
    console.error("createCampaign error", e);
    throw e;
  }
}

export async function donateRealETH(campaignId: number, amountEth: string) {
  if (!signer) throw new Error("Wallet not connected");
  const contract = await getCrowdfundContract();
  if (!contract) throw new Error("contract not available");
  try {
    const value = ethers.parseEther(amountEth);
    const tx = await contract.donateRealETH(campaignId, { value });
    const receipt = await tx.wait();
    return receipt;
  } catch (e) {
    console.error("donateRealETH error", e);
    throw e;
  }
}

export async function donateMockUSDC(campaignId: number, amountUSDC: string) {
  if (!signer) throw new Error("Wallet not connected");
  // amountUSDC should be a string like '10.5' meaning 10.5 USDC
  const contract = await getCrowdfundContract();
  if (!contract) throw new Error("contract not available");
  try {
    // get usdc token address from contract
    const usdcAddress = await contract.usdc();
    // create token contract with signer
    let providerOrSigner: any = null;
    if (signer) providerOrSigner = signer;
    else if (browserProvider) providerOrSigner = browserProvider;
    else providerOrSigner = new ethers.JsonRpcProvider(DEFAULT_RPC);

    const token = new ethers.Contract(
      usdcAddress,
      ERC20ABI as any,
      providerOrSigner
    );
    // read decimals
    let decimals = 6; // assume 6 if call fails
    try {
      const d = await token.decimals();
      decimals = Number(d);
    } catch (err) {
      // keep default
    }

    const amount = ethers.parseUnits(amountUSDC, decimals);

    // check allowance
    try {
      const allowance = await token.allowance(
        await (providerOrSigner.getAddress
          ? providerOrSigner.getAddress()
          : providerOrSigner.getSigner().getAddress()),
        CROWDFUND_ADDRESS
      );
      if (BigInt(allowance) < BigInt(amount)) {
        const approveTx = await token.approve(CROWDFUND_ADDRESS, amount);
        await approveTx.wait();
      }
    } catch (err) {
      // If allowance check fails, just attempt approve
      const approveTx = await token.approve(CROWDFUND_ADDRESS, amount);
      await approveTx.wait();
    }

    const tx = await contract.donateMockUSDC(campaignId, amount);
    const receipt = await tx.wait();
    return receipt;
  } catch (e) {
    console.error("donateMockUSDC error", e);
    throw e;
  }
}

export async function withdraw(campaignId: number) {
  if (!signer) throw new Error("Wallet not connected");
  const contract = await getCrowdfundContract();
  if (!contract) throw new Error("contract not available");
  try {
    const tx = await contract.withdraw(campaignId);
    const receipt = await tx.wait();
    return receipt;
  } catch (e) {
    console.error("withdraw error", e);
    throw e;
  }
}

export async function refund(campaignId: number) {
  if (!signer) throw new Error("Wallet not connected");
  const contract = await getCrowdfundContract();
  if (!contract) throw new Error("contract not available");
  try {
    const tx = await contract.refund(campaignId);
    const receipt = await tx.wait();
    return receipt;
  } catch (e) {
    console.error("refund error", e);
    throw e;
  }
}

export async function myDonations(campaignId: number) {
  const contract = await getCrowdfundContract();
  if (!contract) return null;
  try {
    const donation = await contract.myDonations(campaignId);
    return {
      amount: donation[0],
      tier: Number(donation[1]),
    };
  } catch (e) {
    console.error("myDonations error", e);
    return null;
  }
}

export async function listenToEvents(
  callback: (eventName: string, args: any) => void
) {
  const contract = await getCrowdfundContract();
  if (!contract) return;

  try {
    // Remove existing listeners to avoid duplicates
    contract.removeAllListeners("CampaignCreated");
    contract.removeAllListeners("Refund");
    contract.removeAllListeners("Donated");

    // Listen to CampaignCreated
    contract.on("CampaignCreated", (id, title, goal, startAt, endAt) => {
      callback("CampaignCreated", {
        id: Number(id),
        title,
        goal: Number(goal),
        startAt: Number(startAt),
        endAt: Number(endAt),
      });
    });

    // Listen to Refund, filtered by donor
    contract.on("Refund", async (id, donor, ethAmount, usdcAmount) => {
      if (signer) {
        const userAddr = await signer.getAddress();
        if (donor === userAddr) {
          callback("Refund", {
            id: Number(id),
            donor,
            ethAmount, // Keep as BigInt
            usdcAmount, // Keep as BigInt
          });
        }
      }
    });

    // Listen to Donated, filtered by donor
    contract.on("Donated", async (id, donor, amount, tier, tokenId) => {
      if (signer) {
        const userAddr = await signer.getAddress();
        if (donor === userAddr) {
          callback("Donated", {
            id: Number(id),
            donor,
            amount, // Keep as BigInt
            tier: Number(tier),
            tokenId: Number(tokenId),
          });
        }
      }
    });
  } catch (e) {
    console.error("listenToEvents error", e);
    // Ignore if contract not available on current network
  }
}

// 动态解析未知自定义错误
export async function parseUnknownError(
  data: string
): Promise<{ name: string; args: any[] } | null> {
  if (!data.startsWith("0x") || data.length < 10) return null;
  const selector = data.slice(0, 10); // 前 4 字节 + 0x

  try {
    // 查询 4byte.directory API
    const response = await fetch(
      `https://www.4byte.directory/api/v1/signatures/?hex_signature=${selector}`
    );
    const json = await response.json();
    if (json.results && json.results.length > 0) {
      const signature = json.results[0].text_signature; // 取第一个匹配
      const iface = new ethers.Interface([`error ${signature}`]);
      const parsed = iface.parseError(data);
      if (parsed) {
        return { name: parsed.name, args: parsed.args };
      }
    }
  } catch (e) {
    console.error("Error parsing unknown error:", e);
  }
  return null;
}
