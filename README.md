# DeepLinkOrionMiningLongTermLeaseContract
DeepLink Orion GPU Mining Long-Term Lease Contract

# mainnet
    - staking: 0x6268aba94d0d0e4fb917cc02765f631f309a7388
    - rent: 0xda9efdff9ca7b7065b7706406a1a79c0e483815a
    - DLC: 0x6f8F70C74FE7d7a61C8EAC0f35A4Ba39a51E1BEe
    - NFT: 0xFDB11c63b82828774D6A9E893f85D1998E6B36BF
    - DBCAI: 0xa7B9f404653841227AF204a561455113F36d8EC8


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/NFTStaking.sol.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
