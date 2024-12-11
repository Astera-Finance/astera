import json
import csv
import os

## CONFIG
testnet = True

explorer = ""
csv_file = ""
if(testnet):
    explorer = "https://sepolia.basescan.org/address/" 
    csv_file = os.getcwd() + "/scripts/outputs/testnet/contracts.csv"
    chain_id = "84532"
else:
    explorer = "https://basescan.org/address/"
    csv_file = os.getcwd() + "/scripts/outputs/mainnet/contracts.csv"
    chain_id = "8453"

# Write to the CSV file
with open(csv_file, mode='w', newline='', encoding='utf-8') as file:
    writer = csv.writer(file)
    writer.writerow(["contractName", "contractAddress","explorerUrl"])  # Header row

    # Walk through the directory
    for root, dirs, files in os.walk(os.getcwd() + "/scripts"):
        # Exclude specific folders
        print("1.DIRS: ", dirs)
        if "helpers" in dirs:
            dirs.remove("helpers")
        if "localFork" in dirs:
            dirs.remove("localFork")
        print("2.DIRS: ", dirs)

        for file in files:
            if file.endswith('.s.sol'):
                fileName = file.split("/")[-1]
                print("FILE NAME: ", fileName)
                # Path to the JSON file
                json_file_path = os.getcwd() + "/broadcast/" + fileName + "/" + chain_id + "/run-latest.json"

                print(json_file_path)

                # Open and load the JSON data
                with open(json_file_path, 'r', encoding='utf-8') as file:
                    data = json.load(file)

                # print(data)

                # Create a set to track unique addresses
                unique_addresses = set()

                for transaction in data.get("transactions", []):
                    contract_name = transaction.get("contractName")
                    contract_address = transaction.get("contractAddress")
                    explorer_url = explorer + contract_address + "#code"
                    
                    # Only write if contract name exists and address is unique
                    if contract_name and contract_address not in unique_addresses:
                        writer.writerow([contract_name, contract_address, explorer_url])
                        unique_addresses.add(contract_address)  # Add address to the set

                print(f"Data successfully written to {csv_file}")
