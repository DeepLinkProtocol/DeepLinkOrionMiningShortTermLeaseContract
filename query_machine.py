import json
import requests
from datetime import datetime

def hex_to_int(hex_str):
    return int(hex_str, 16)

def decode_string_from_data(data_hex):
    """Decode a string from ABI-encoded data"""
    # Remove 0x prefix
    data = data_hex[2:] if data_hex.startswith('0x') else data_hex

    # Skip offset (first 32 bytes = 64 hex chars) and length (next 32 bytes)
    # String starts after that
    if len(data) < 128:
        return ""

    # Get string length (bytes 32-64)
    str_len = int(data[64:128], 16)

    # Get string data (after length)
    str_hex = data[128:128 + str_len * 2]

    try:
        return bytes.fromhex(str_hex).decode('utf-8')
    except:
        return str_hex

def parse_rent_event(log):
    """Parse RentMachine event"""
    data = log['data'][2:]  # Remove 0x

    # rentId (uint256) - 32 bytes
    rent_id = hex_to_int('0x' + data[0:64])

    # offset for machineId (uint256) - skip

    # rentEndTime (uint256) - bytes 64-128
    rent_end_time = hex_to_int('0x' + data[128:192])

    # renter (address) - bytes 128-192
    renter = '0x' + data[192:256][-40:]

    # rentFee (uint256) - bytes 192-256
    rent_fee = hex_to_int('0x' + data[256:320])

    # machineId string - starts at offset (0xa0 = 160 = 320 hex chars from start)
    # String length at 320:384
    str_len = hex_to_int('0x' + data[320:384])
    # String data at 384:384+str_len*2
    machine_id_hex = data[384:384 + str_len * 2]
    try:
        machine_id = bytes.fromhex(machine_id_hex).decode('utf-8')
    except:
        machine_id = machine_id_hex

    # stakeHolder from topic
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

    # machineOwner (address) - 32 bytes
    machine_owner = '0x' + data[0:64][-40:]

    # rentId (uint256) - bytes 32-64
    rent_id = hex_to_int('0x' + data[64:128])

    # offset for machineId - skip

    # rentEndTime (uint256) - bytes 128-192
    rent_end_time = hex_to_int('0x' + data[192:256])

    # renter (address) - bytes 192-256
    renter = '0x' + data[256:320][-40:]

    # machineId string
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

# Target machine ID
TARGET_MACHINE = '67c468efb7cb6579c95695495c2c4677f11331c8dc918ab6e9c9a206a366b6ba'
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

# Calculate 6 hours ago (6 seconds per block)
blocks_in_6_hours = 6 * 60 * 60 // 6
from_block = current_block - blocks_in_6_hours
print(f"Searching from block {from_block} to {current_block} ({blocks_in_6_hours} blocks = 6 hours)")

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
print(f"Found {len(rent_logs)} RentMachine events in last 6 hours")

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
print(f"Found {len(end_rent_logs)} EndRentMachine events in last 6 hours")

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
    print("\nNo rent events found for target machine in the last 6 hours.")

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
