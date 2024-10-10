build:
	forge build

test:
	forge test

fmt:
	forge fmt

deploy:
	forge script script/Deploy.s.sol:Deploy --rpc-url dbc-testnet --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url $(TEST_NET_VERIFIER_URL) --force --skip-simulation

upgrade:
	forge script script/Upgrade.s.sol:Upgrade --rpc-url dbc-testnet --broadcast --verify --verifier blockscout --verifier-url $(TEST_NET_VERIFIER_URL) --force --skip-simulation

remapping:
	forge remappings > remappings.txt


