<template>
  <div>
    <a-row justify="space-between" align="middle">
      <a-col>
        <a-space>
          <a-button @click="connect" type="primary">{{ connected ? '已连接' : '连接钱包' }}</a-button>
          <a-button v-if="connected" @click="disconnect">断开</a-button>
        </a-space>
      </a-col>
      <a-col v-if="connected">
        <div>
          <div>账户: <span style="text-decoration: underline;">{{ formatAddress(account) }}</span></div>
          <div>ETH 余额：{{ formatBalance(balance) }}</div>
        </div>
      </a-col>
    </a-row>
  </div>
</template>

<script lang="ts">
import { defineComponent, ref } from 'vue'
import { connectWallet, disconnectWallet, getAccount, getBalance } from '../lib/ethers'

export default defineComponent({
  emits: ['connected', 'disconnected'],
  setup(_, { emit }) {
    const connected = ref(false)
    const account = ref<string | null>(null)
    const balance = ref<string | null>(null)

    async function connect() {
      const acc = await connectWallet()
      if (acc) {
        account.value = acc
        connected.value = true
        emit('connected')
        const b = await getBalance()
        balance.value = b
      }
    }

    function disconnect() {
      disconnectWallet()
      account.value = null
      balance.value = null
      connected.value = false
      emit('disconnected')
    }

    function formatAddress(addr: string | null) {
      if (!addr) return '';
      return addr.slice(0, 6) + '...' + addr.slice(-5);
    }

    function formatBalance(bal: string | null) {
      if (!bal) return '0.00';
      const num = parseFloat(bal);
      return num.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    getAccount().then(async (acc) => {
      if (acc) {
        account.value = acc
        connected.value = true
        const b = await getBalance()
        if (b) balance.value = b
      }
    })


    return { connect, disconnect, connected, account, balance, formatAddress, formatBalance }
  },
})
</script>

<style scoped></style>
