# Ants Empire – Solidity Smart Contracts

This repository contains the smart contracts powering the **Ants Empire** Web3 game.  
The system is composed of multiple interconnected contracts designed for modularity, security, and scalability, covering game economy, NFT marketplace, quest pools, and randomization mechanics.  
All contracts follow best practices for upgradeability, role-based access control (RBAC), and security.

## Overview
- **Network:** Ethereum-compatible (tested on EVM networks)
- **Architecture:** Modular, event-driven integration with the backend
- **Security:** OpenZeppelin standards, RBAC, gas optimization
- **External Integrations:** Chainlink oracles, IPFS for decentralized storage

## Contracts Summary

| Contract | Description |
|----------|-------------|
| `/token/Nectar.sol` | ERC-20 token representing the main in-game currency, used for trading, rewards, and economy balancing. |
| `/erc721/ANT_NFT.sol` | ERC-721 NFT contract for unique in-game assets (ants, items, packs). |
| `/pools/BasePool.sol` | Base contract for pool logic, providing core functionality for resource and reward management. |
| `/pools/QuestPool.sol` | Extends `BasePool`; manages pools specifically for quests, including contribution and reward distribution. |
| `/pools/RewardPool.sol` | Extends `BasePool`; Handles reward logic, payouts, and allocation of game incentives. |
| `/pools/PoolGeneral.sol` | Extends `BasePool`; General-purpose pool for miscellaneous in-game economic flows. |
| `/game/Expedition.sol` | Manages expedition gameplay mechanics, including player participation and rewards. |
| `/game/PackToBuy.sol` | Handles pack purchasing logic, linking in-game bundles with NFT minting. |
| `/game/Farming.sol` | Farming mechanics contract for producing resources over time, linked to NFTs and tokenomics. |
| `/localChainLink/VRFAntConsumer.sol` | Integrates Chainlink VRF to provide verifiable randomness for game events and outcomes. |
| `/marketplace/MarketV0.sol` | Initial version of the NFT marketplace, enabling buying, selling, edit prices and delist features. |
| `/faucet/FaucetTestnetV0.sol` | Faucet contract for distributing test tokens during development and QA stages. |

---

## License – Public Showcase

Copyright (c) 2025 - Carpenter Labs  
All Rights Reserved.

This repository is provided as a **public showcase** for educational and technical evaluation purposes only.  
It contains proprietary and confidential code.  
Unauthorized copying, modification, redistribution, or use of this code, in whole or in part, for any purpose, is strictly prohibited without the express written permission of the copyright holder.

You are permitted to:
- View and review the code for learning or evaluation
- Reference architectural patterns and ideas with proper attribution

You are **not** permitted to:
- Use this code in production systems
- Redistribute or sublicense it
- Use it for any commercial purpose

By accessing this repository, you agree to these terms.
