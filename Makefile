deploy-staking:
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL --force --skip-simulation --legacy
	#source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL  --legacy

verify-staking:
	source .env && forge verify-contract --chain 19850818  --compiler-version v0.8.25 --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL $STAKING_PROXY  src/NFTStaking.sol:NFTStaking

upgrade-staking:
	source .env && forge script script/Upgrade.s.sol:Upgrade --rpc-url dbc-testnet --broadcast --verify --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL --force --skip-simulation --legacy



deploy-staking-mainnet:
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-mainnet --private-key $PRIVATE_KEY_MAINNET --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --legacy
	#source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-mainnet --private-key $PRIVATE_KEY_MAINNET --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL  --legacy

verify-staking-mainnet:
	source .env && forge verify-contract --chain 19880818  --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL $STAKING_PROXY  src/NFTStaking.sol:NFTStaking
	source .env && forge verify-contract --chain 19880818  --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL 0x6268aba94d0d0e4fb917cc02765f631f309a7388 src/NFTStaking.sol:NFTStaking


upgrade-staking-mainnet:
	source .env && forge script script/Upgrade.s.sol:Upgrade --rpc-url dbc-mainnet --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL  --legacy
	source .env && forge script script/Upgrade.s.sol:Upgrade --rpc-url dbc-mainnet --broadcast  --legacy


deploy-rent:
	source .env && forge script script/rent/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL --force --skip-simulation --legacy
	source .env && forge script script/rent/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast

verify-rent:
	source .env && forge verify-contract --chain 19850818  --compiler-version v0.8.25 --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL $RENT_PROXY  src/rent/Rent.sol:Rent --force

upgrade-rent:
	source .env && forge script script/rent/Upgrade.s.sol:Upgrade --rpc-url dbc-testnet --broadcast --verify --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL --force --skip-simulation --legacy


deploy-rent-mainnet:
	source .env && forge script script/rent/Deploy.s.sol:Deploy --rpc-url dbc-mainnet --private-key $PRIVATE_KEY_MAINNET --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --legacy

verify-rent-mainnet:
	source .env && forge verify-contract --chain 19880818 --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL $RENT_PROXY  src/rent/Rent.sol:Rent
	source .env && forge verify-contract --chain 19880818 --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL 0x34B2d49EcbC42191113A9E5740Ac85A0DE7bC41D  src/rent/Rent.sol:Rent

upgrade-rent-mainnet:
	source .env && forge script script/rent/Upgrade.s.sol:Upgrade --rpc-url dbc-mainnet --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --force --skip-simulation --legacy



remapping:
	forge remappings > remappings.txt

call-staking:
	cast call ${STAKING_PROXY}  --rpc-url https://rpc.dbcwallet.io


deploy-staking-bsc-testnet:
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url bsc-testnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $BSC_TESTNET_VERIFIER_URL  --legacy

verify-staking-bsc-testnet:
	source .env && forge verify-contract --chain 97  --compiler-version v0.8.25 --verifier blockscout --verifier-url $BSC_TESTNET_VERIFIER_URL $STAKING_PROXY  src/NFTStaking.sol:NFTStaking

upgrade-staking-bsc-testnet:
	source .env && forge script script/Upgrade.s.sol:Upgrade --rpc-url bsc-testnet --broadcast --verify --verifier blockscout --verifier-url $BSC_TESTNET_VERIFIER_URL --legacy


deploy-rent:
	source .env && forge script script/rent/Deploy.s.sol:Deploy --rpc-url bsc-testnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $BSC_TESTNET_VERIFIER_URL --legacy

verify-rent:
	source .env && forge verify-contract --chain 19850818  --compiler-version v0.8.26 --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL $RENT_PROXY  src/rent/Rent.sol:Rent --force

upgrade-rent:
	source .env && forge script script/rent/Upgrade.s.sol:Upgrade --rpc-url bsc-testnet --broadcast --verify --verifier blockscout --verifier-url $BSC_TESTNET_VERIFIER_URL --force --skip-simulation --legacy
