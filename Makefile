deploy-staking:
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL --force --skip-simulation --legacy
	#source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL  --legacy

verify-staking:
	source .env && forge verify-contract --chain 19850818  --compiler-version v0.8.25 --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL $STAKING_PROXY  src/NFTStaking.sol:NFTStaking

upgrade-staking:
	source .env && forge script script/Upgrade.s.sol:Upgrade --rpc-url dbc-testnet --broadcast --verify --verifier blockscout --verifier-url $TEST_NET_VERIFIER_URL --force --skip-simulation --legacy



deploy-staking-mainnet:
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-mainnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --legacy
	#source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $PRIVATE_KEY --broadcast
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-mainnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL  --legacy


verify-staking-mainnet:
	source .env && forge verify-contract --chain 19880818  --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL $STAKING_PROXY  src/NFTStaking.sol:NFTStaking
	source .env && forge verify-contract --chain 19880818  --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL 0x558E132b734E1002233914E9f9cbBA526f316E9e src/NFTStaking.sol:NFTStaking


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
	source .env && forge script script/rent/Deploy.s.sol:Deploy --rpc-url dbc-mainnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --legacy

verify-rent-mainnet:
	source .env && forge verify-contract --chain 19880818 --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL $RENT_PROXY  src/rent/Rent.sol:Rent
	source .env && forge verify-contract --chain 19880818 --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL 0x64C04f9f41788F5b6E27E64be2Fca883e49bb190  src/rent/Rent.sol:Rent

upgrade-rent-mainnet:
	source .env && forge script script/rent/Upgrade.s.sol:Upgrade --rpc-url dbc-mainnet --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --force --skip-simulation --legacy
	source .env && forge script script/rent/Upgrade.s.sol:Upgrade --rpc-url dbc-mainnet --broadcast 


remapping:
	forge remappings > remappings.txt

call-staking:
	cast call ${STAKING_PROXY}  --rpc-url https://rpc.dbcwallet.io "isRentedM()"
0b203986479609afb233709f6b596d4644a4243689889f2fb9cf39a8f48d671e



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
