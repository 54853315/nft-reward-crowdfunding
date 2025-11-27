<template>
  <a-layout style="min-height:100vh; padding:24px">
    <a-row justify="center">
      <a-col :span="16">
        <a-card title="NFT Reward Crowdfund">
          <wallet-connect @connected="onConnected" @disconnected="onDisconnected" />

          <a-modal v-model:open="createModalVisible" title="Create Campaign">
            <a-form layout="vertical">
              <a-form-item label="Title *" required>
                <a-input v-model:value="newTitle" placeholder="Campaign title" />
              </a-form-item>
              <a-form-item label="Goal (ETH, integer) *" required>
                <a-input-number v-model:value="newGoal" :min="1" :max="1000000" />
              </a-form-item>
              <a-form-item label="Start At *" required>
                <input type="datetime-local" v-model="newStart" />
              </a-form-item>
              <a-form-item label="End At *" required>
                <input type="datetime-local" v-model="newEnd" />
              </a-form-item>
            </a-form>
            <template #footer>
              <a-button @click="createModalVisible = false">Cancel</a-button>
              <a-button type="primary" @click="handleCreate">Create</a-button>
            </template>
          </a-modal>

          <div style="margin-top:24px">
            <a-row justify="space-between" align="middle">
              <a-col>
                <a-typography-title :level="4">Campaigns</a-typography-title>
              </a-col>
              <a-col>
                <a-space>
                  <a-button v-if="isConnected" type="primary" @click="openCreateModal">Create Campaign</a-button>
                  <a-button type="default" @click="loadCampaigns">Refresh</a-button>
                </a-space>
              </a-col>
            </a-row>
            <a-list :dataSource="campaigns" style="margin-top:12px" bordered>
              <template #renderItem="{ item }">
                <a-list-item>
                  <a-row gutter={16} style="width:100%">
                    <a-col :span="16">
                      <a-space direction="vertical" size="small">
                        <a-typography-title :level="5" style="margin: 0;">
                          <template #icon>
                            <TrophyOutlined />
                          </template>
                          #{{ item.id.toString() }} {{ item.title }}
                        </a-typography-title>
                        <a-descriptions :column="1" size="small" :bordered="false">
                          <a-descriptions-item label="Owner">
                            <a-typography-text copyable :copy-text="item.owner">
                              {{ formatAddress(item.owner) }}
                            </a-typography-text>
                          </a-descriptions-item>
                          <a-descriptions-item label="Goal Amount">
                            <a-statistic :value="formatEther(item.goal)" suffix="ETH"
                              value-style="color: #1890ff; font-size: 14px;" />
                          </a-descriptions-item>
                          <a-descriptions-item label="Raised Amount">
                            <a-statistic :value="formatEther(item.raised)" suffix="ETH"
                              value-style="color: #52c41a; font-size: 14px;" />
                          </a-descriptions-item>
                          <a-descriptions-item label="Campaign Period">
                            <a-tag color="blue">
                              <template #icon>
                                <CalendarOutlined />
                              </template>
                              {{ formatTs(item.startAt) }} - {{ formatTs(item.endAt) }}
                            </a-tag>
                          </a-descriptions-item>
                        </a-descriptions>
                        <div>
                          <a-badge :status="item.donationStatus.includes('Donated') ? 'success' : 'default'"
                            :text="item.donationStatus" />
                        </div>
                      </a-space>
                    </a-col>
                    <a-col :span="8">
                      <a-space direction="vertical" style="width:100%">
                        <div>ETH Amount: {{ donateEth[item.id] || '0' }} ETH</div>
                        <a-slider :min="0.1" :max="100" :step="0.1" :value="Number(donateEth[item.id] || 0)"
                          @change="(val: number) => donateEth[item.id] = val.toString()" />
                        <a-button type="primary" block
                          :disabled="Math.floor(Date.now() / 1000) < item.startAt || Math.floor(Date.now() / 1000) > item.endAt"
                          @click="donateEthTo(item.id)">Donate ETH</a-button>
                        <a-button type="primary" block :disabled="item.owner !== currentAddress"
                          @click="handleWithdraw(item.id)">Withdraw</a-button>
                        <a-button type="default" block :disabled="item.raised >= item.goal || !item.ended"
                          @click="handleRefund(item.id)">Refund</a-button>
                      </a-space>
                    </a-col>
                  </a-row>
                </a-list-item>
              </template>
            </a-list>
          </div>

          <!-- <div style="margin-top:24px">
            <a-typography-title :level="4">Debug / Example</a-typography-title>
            <a-button type="primary" @click="fetchPrice">Fetch Contract ETH Price (Example)</a-button>
            <div v-if="ethPrice !== null" style="margin-top:12px">Latest Price: {{ ethPrice }}</div>
          </div> -->
        </a-card>
      </a-col>
    </a-row>
  </a-layout>
</template>

<script lang="ts">
import { defineComponent, ref, onMounted } from 'vue'
import WalletConnect from './components/WalletConnect.vue'
import { getCrowdfundContract, getNextCampaignId, getCampaign, createCampaign, donateRealETH, withdraw, refund, myDonations, listenToEvents, getAccount } from './lib/ethers'
import { ethers } from 'ethers'
import { message } from 'ant-design-vue'
import { TrophyOutlined, CalendarOutlined } from '@ant-design/icons-vue'

export default defineComponent({
  components: { WalletConnect, TrophyOutlined, CalendarOutlined },
  setup() {
    const ethPrice = ref<number | null>(null)
    const campaigns = ref<Array<any>>([])

    const newTitle = ref('')
    const newGoal = ref<number | null>(1)
    const newStart = ref('')
    const newEnd = ref('')

    const donateEth = ref<Record<number, string>>({})
    const createModalVisible = ref(false)

    const isConnected = ref(false)

    const currentAddress = ref<string | null>(null)

    onMounted(async () => {
      const addr = await getAccount()
      if (addr) {
        isConnected.value = true
        currentAddress.value = addr
        await initConnection()
      }
    })

    async function initConnection() {
      await loadCampaigns()
      listenToEvents((eventName, args) => {
        if (eventName === "CampaignCreated") {
          message.success(`Campaign created successfully: ${args.title}`)
        } else if (eventName === "Refund") {
          message.info(`Refund successful: ${formatEther(args.ethAmount)} ETH, ${ethers.formatUnits(args.usdcAmount, 6)} USDC`)
        } else if (eventName === "Donated") {
          console.log(eventName, args);
          message.success(`Donation successful: ${ethers.formatEther(args.amount)} ETH, Tier ${args.tier}`)
        }
      })
    }

    async function onConnected() {
      if (!isConnected.value) {
        isConnected.value = true
        await initConnection()
      }
      currentAddress.value = await getAccount()
    }

    function onDisconnected() {
      isConnected.value = false
      currentAddress.value = null
    }

    function formatTs(ts: any) {
      try {
        const t = Number(ts) * 1000
        return new Date(t).toISOString().slice(0, 16).replace('T', ' ')
      } catch {
        return String(ts)
      }
    }

    function formatEther(wei: any) {
      if (wei == null) return '0';
      try {
        const num = parseFloat(ethers.formatEther(wei));
        return num.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      } catch {
        return String(wei);
      }
    }

    function copyToClipboard(text: string) {
      navigator.clipboard.writeText(text).then(() => {
        message.success('Address copied to clipboard');
      }).catch(err => {
        console.error('Copy failed', err);
        message.error('Copy failed');
      });
    }

    function formatAddress(addr: string | null) {
      if (!addr) return '';
      return addr.slice(0, 6) + '...' + addr.slice(-4);
    }

    async function loadCampaigns() {
      const n = await getNextCampaignId()
      if (n === null) return
      const arr = []
      for (let i = 0; i < n; i++) {
        const c = await getCampaign(i)
        // console.log('loadCampaigns got campaign', i, c)
        if (c) {
          const donation = await myDonations(i)
          const campaign = {
            id: i,
            owner: c[1],
            title: c[2],
            goal: c[3],
            raised: c[4],
            startAt: c[5],
            endAt: c[6],
            ended: c[7],
            donationStatus: donation && donation.amount > 0n ? `Donated ${formatEther(donation.amount)} ETH, Tier ${donation.tier}` : 'Not donated yet'
          }
          arr.push(campaign)
        }
      }
      campaigns.value = arr
    }

    async function handleCreate() {
      if (!newTitle.value || !newGoal.value || !newStart.value || !newEnd.value) {
        alert('Please fill in all fields; Goal is integer ETH')
        return
      }
      if (newGoal.value > 1000000 || newGoal.value < 1) {
        alert('Invalid goal amount, 1-1000000 ETH')
        return
      }
      const startAt = Math.floor(new Date(newStart.value).getTime() / 1000)
      const endAt = Math.floor(new Date(newEnd.value).getTime() / 1000)
      try {
        await createCampaign(newTitle.value, newGoal.value, startAt, endAt)
        alert('Created successfully, refresh list')
        await loadCampaigns()
        createModalVisible.value = false
        // Reset form
        newTitle.value = ''
        newGoal.value = null
        newStart.value = ''
        newEnd.value = ''
      } catch (e: any) {
        console.error(e)
        if (e.message === 'Wallet not connected') {
          alert('Please connect wallet first')
        } else {
          alert('Creation failed, check console')
        }
      }
    }

    async function donateEthTo(id: any) {
      const val = donateEth.value[id]
      if (!val || isNaN(Number(val)) || Number(val) <= 0 || Number(val) > 1000000) {
        alert('Please enter a valid ETH amount, max 1000000')
        return
      }
      try {
        await donateRealETH(Number(id), val)
        await loadCampaigns()
      } catch (e) { console.error(e); alert('Donation failed') }
    }

    async function handleWithdraw(id: any) {
      try {
        await withdraw(Number(id))
        alert('Withdrawal successful')
        await loadCampaigns()
      } catch (e: any) {
        console.error(e)
        let msg = 'Withdrawal failed'
        if (e.data) {
          try {
            const contract = await getCrowdfundContract()
            if (contract) {
              const parsedError = contract.interface.parseError(e.data)
              if (parsedError) {
                if (parsedError.name === 'OwnableUnauthorizedAccount') {
                  msg = 'You are not the campaign owner, cannot withdraw'
                } else {
                  msg = parsedError.name
                }
              }
            }
          } catch (parseErr) {
            // ignore
          }
        }
        if (e.message) {
          if (e.message.includes('Campaign not ended')) {
            msg = 'Campaign not ended, cannot withdraw'
          } else if (e.message.includes('Goal not reached')) {
            msg = 'Goal not reached, cannot withdraw'
          } else if (e.message.includes('Not owner')) {
            msg = 'You are not the campaign owner, cannot withdraw'
          } else if (e.message.includes('Already withdrawn')) {
            msg = 'Already withdrawn'
          }
        }
        alert(msg)
      }
    }

    async function handleRefund(id: any) {
      try {
        await refund(Number(id))
        alert('Refund successful')
        await loadCampaigns()
      } catch (e: any) {
        console.error(e)
        let msg = 'Refund failed'
        if (e.message) {
          if (e.message.includes('Campaign not ended')) {
            msg = 'Campaign not ended, cannot refund'
          } else if (e.message.includes('Goal reached')) {
            msg = 'Goal reached, cannot refund'
          } else if (e.message.includes('No donation')) {
            msg = 'You have not donated, cannot refund'
          }
        }
        alert(msg)
      }
    }

    async function openCreateModal() {
      console.log('Opening create modal')
      const now = new Date();
      newStart.value = now.toISOString().slice(0, 16); // YYYY-MM-DDTHH:mm
      const end = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
      newEnd.value = end.toISOString().slice(0, 16);
      createModalVisible.value = true;
      console.log('createModalVisible set to', createModalVisible.value);
    }

    async function fetchPrice() {
      const contract = await getCrowdfundContract()
      if (!contract) return
      try {
        const price = await contract.getETHPrice()
        // Chainlink price feed returns price with 8 decimals
        ethPrice.value = Number(price) / 1e8
      } catch (e) {
        console.error('fetchPrice error', e)
        ethPrice.value = null
      }
    }

    return { ethPrice, fetchPrice, onConnected, onDisconnected, campaigns, newTitle, newGoal, newStart, newEnd, loadCampaigns, formatTs, formatEther, copyToClipboard, donateEth, donateEthTo, handleCreate, handleWithdraw, handleRefund, createModalVisible, openCreateModal, isConnected, currentAddress, formatAddress }
  },
})
</script>

<style>
/* minimal styling */
</style>
