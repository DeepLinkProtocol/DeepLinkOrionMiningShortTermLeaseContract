import json
import requests
from datetime import datetime

def hex_to_int(hex_str):
    return int(hex_str, 16)

def parse_rent_event(log):
    """Parse RentMachine event"""
    data = log['data'][2:]  # Remove 0x
    rent_id = hex_to_int('0x' + data[0:64])
    rent_end_time = hex_to_int('0x' + data[128:192])
    renter = '0x' + data[192:256][-40:]
    rent_fee = hex_to_int('0x' + data[256:320])
    str_len = hex_to_int('0x' + data[320:384])
    machine_id_hex = data[384:384 + str_len * 2]
    try:
        machine_id = bytes.fromhex(machine_id_hex).decode('utf-8')
    except:
        machine_id = machine_id_hex
    stake_holder = '0x' + log['topics'][1][-40:]
    return {
        'type': 'RentMachine',
        'rentId': rent_id,
        'machineId': machine_id,
        'rentEndTime': rent_end_time,
        'rentEndTimeStr': datetime.fromtimestamp(rent_end_time).strftime('%Y-%m-%d %H:%M:%S'),
        'renter': renter,
        'rentFee': rent_fee / 1e18,
        'stakeHolder': stake_holder,
        'blockNumber': hex_to_int(log['blockNumber']),
        'txHash': log['transactionHash']
    }

def parse_end_rent_event(log):
    """Parse EndRentMachine event"""
    data = log['data'][2:]  # Remove 0x
    machine_owner = '0x' + data[0:64][-40:]
    rent_id = hex_to_int('0x' + data[64:128])
    rent_end_time = hex_to_int('0x' + data[192:256])
    renter = '0x' + data[256:320][-40:]
    str_len = hex_to_int('0x' + data[320:384])
    machine_id_hex = data[384:384 + str_len * 2]
    try:
        machine_id = bytes.fromhex(machine_id_hex).decode('utf-8')
    except:
        machine_id = machine_id_hex
    return {
        'type': 'EndRentMachine',
        'rentId': rent_id,
        'machineId': machine_id,
        'rentEndTime': rent_end_time,
        'rentEndTimeStr': datetime.fromtimestamp(rent_end_time).strftime('%Y-%m-%d %H:%M:%S'),
        'renter': renter,
        'machineOwner': machine_owner,
        'blockNumber': hex_to_int(log['blockNumber']),
        'txHash': log['transactionHash']
    }

# Target machine ID (857293199)
TARGET_MACHINE = '378690c40801969736babfdf7752cac836d518d95f9fce0ce113c1be0b2bf4ed'
RPC_URL = 'https://rpc2.dbcwallet.io'
RENT_CONTRACT = '0xda9efdff9ca7b7065b7706406a1a79c0e483815a'

# Get current block
response = requests.post(RPC_URL, json={
    "jsonrpc": "2.0",
    "method": "eth_blockNumber",
    "params": [],
    "id": 1
})
current_block = hex_to_int(response.json()['result'])
print(f"Current block: {current_block}")

# Calculate 24 hours ago (6 seconds per block)
blocks_in_24_hours = 24 * 60 * 60 // 6
from_block = current_block - blocks_in_24_hours
print(f"Searching from block {from_block} to {current_block} ({blocks_in_24_hours} blocks = 24 hours)")

# Event topics
RENT_TOPIC = '0x8868ab8675c4ea524ef9bdbc475946b833975048b2230f7abbc19422d6688142'
END_RENT_TOPIC = '0x117ce5e3db4b0df87d298bf7a372a2a5e1359f21271f69221b4834a7894c3527'

# Query RentMachine events
print("\n" + "="*80)
print("Querying RentMachine events...")
response = requests.post(RPC_URL, json={
    "jsonrpc": "2.0",
    "method": "eth_getLogs",
    "params": [{
        "address": RENT_CONTRACT,
        "fromBlock": hex(from_block),
        "toBlock": hex(current_block),
        "topics": [RENT_TOPIC]
    }],
    "id": 1
})
rent_logs = response.json().get('result', [])
print(f"Found {len(rent_logs)} RentMachine events in last 24 hours")

# Query EndRentMachine events
print("\nQuerying EndRentMachine events...")
response = requests.post(RPC_URL, json={
    "jsonrpc": "2.0",
    "method": "eth_getLogs",
    "params": [{
        "address": RENT_CONTRACT,
        "fromBlock": hex(from_block),
        "toBlock": hex(current_block),
        "topics": [END_RENT_TOPIC]
    }],
    "id": 1
})
end_rent_logs = response.json().get('result', [])
print(f"Found {len(end_rent_logs)} EndRentMachine events in last 24 hours")

# Parse and filter for target machine
print("\n" + "="*80)
print(f"Searching for target machine: {TARGET_MACHINE}")
print("="*80)

target_events = []

for log in rent_logs:
    try:
        event = parse_rent_event(log)
        if event['machineId'] == TARGET_MACHINE:
            target_events.append(event)
    except Exception as e:
        pass

for log in end_rent_logs:
    try:
        event = parse_end_rent_event(log)
        if event['machineId'] == TARGET_MACHINE:
            target_events.append(event)
    except Exception as e:
        pass

# Sort by block number
target_events.sort(key=lambda x: x['blockNumber'])

if target_events:
    print(f"\nFound {len(target_events)} events for target machine:\n")
    for event in target_events:
        print(f"Block: {event['blockNumber']}")
        print(f"Type: {event['type']}")
        print(f"Rent ID: {event['rentId']}")
        if event['type'] == 'RentMachine':
            print(f"Renter: {event['renter']}")
            print(f"StakeHolder: {event['stakeHolder']}")
            print(f"Rent Fee: {event['rentFee']:.4f} DLC")
        else:
            print(f"Renter: {event['renter']}")
            print(f"Machine Owner: {event['machineOwner']}")
        print(f"Rent End Time: {event['rentEndTimeStr']}")
        print(f"TX Hash: {event['txHash']}")
        print("-" * 60)
else:
    print("\nNo rent events found for target machine in the last 24 hours.")

# Also check current rent status
print("\n" + "="*80)
print("Current Rent Status:")
print("="*80)

# Check isRented
from eth_abi import encode
machine_id_encoded = encode(['string'], [TARGET_MACHINE]).hex()
is_rented_selector = '0xa034d084'
calldata = is_rented_selector + machine_id_encoded

response = requests.post(RPC_URL, json={
    "jsonrpc": "2.0",
    "method": "eth_call",
    "params": [{"to": RENT_CONTRACT, "data": calldata}, "latest"],
    "id": 1
})
result = response.json().get('result', '0x')
is_rented = hex_to_int(result) == 1 if result != '0x' else False
print(f"isRented: {is_rented}")

# Check machineId2RentId
rent_id_selector = '0xed0200ff'
calldata = rent_id_selector + machine_id_encoded

response = requests.post(RPC_URL, json={
    "jsonrpc": "2.0",
    "method": "eth_call",
    "params": [{"to": RENT_CONTRACT, "data": calldata}, "latest"],
    "id": 1
})
result = response.json().get('result', '0x')
rent_id = hex_to_int(result) if result != '0x' else 0
print(f"Current Rent ID: {rent_id}")
