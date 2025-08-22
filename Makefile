deploy-staking-mainnet:
	source .env && forge script script/Deploy.s.sol:Deploy --rpc-url dbc-mainnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --legacy

verify-staking-mainnet:
	source .env && forge verify-contract --chain 19880818  --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL $STAKING_PROXY  src/NFTStaking.sol:NFTStaking

upgrade-staking-mainnet:
	source .env && forge script script/Upgrade.s.sol:Upgrade --rpc-url dbc-mainnet --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL  --legacy


deploy-rent-mainnet:
	source .env && forge script script/rent/Deploy.s.sol:Deploy --rpc-url dbc-mainnet --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --legacy

verify-rent-mainnet:
	source .env && forge verify-contract --chain 19880818 --compiler-version v0.8.26 --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL $RENT_PROXY  src/rent/Rent.sol:Rent

upgrade-rent-mainnet:
	source .env && forge script script/rent/Upgrade.s.sol:Upgrade --rpc-url dbc-mainnet --broadcast --verify --verifier blockscout --verifier-url $MAIN_NET_VERIFIER_URL --force --skip-simulation --legacy

remapping:
	forge remappings > remappings.txt
