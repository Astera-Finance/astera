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
    path_to_walk = "/scripts/outputs/testnet"
else:
    explorer = "https://basescan.org/address/"
    csv_file = os.getcwd() + "/scripts/outputs/mainnet/contracts.csv"
    chain_id = "8453"
    path_to_walk = "/scripts/outputs/mainnet"

def createFromScriptOut():
    rows_data = []
    for root, dirs, files in os.walk(os.getcwd() + "/scripts/outputs/testnet"):
        for file in files:
            print("File: ", file)
            if file.endswith('.json'):
                # Read and parse the JSON file
                try:
                    with open(os.path.join(root, file), 'r', encoding='utf-8') as json_file:
                        data = json.load(json_file)
                        
                        # Write all key-value pairs to CSV
                        for key, value in data.items():
                            if(isinstance(value, list)):
                                for atr in value:
                                    explorer_url = explorer + atr + "#code"
                                    rows_data.append([file.split(".")[0], key, atr, explorer_url]) 
                            else:
                                explorer_url = explorer + value + "#code"
                                rows_data.append([file.split(".")[0], key, value, explorer_url])
                
                except json.JSONDecodeError as e:
                    print(f"Error reading {file}: {e}")
    return rows_data


def createFromForgeOut():
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


def filter_repeating_values(input_file, output_file):
    with open(input_file, 'r') as infile:
        reader = csv.reader(infile)
        filtered_rows = []
        seen = set()
        for row in reader:
            # Use a set to track seen values
            print("Row", row)
            if row[2] not in seen and row[2] != "0x0000000000000000000000000000000000000000" and "0x" in row[2]:
                print(row[2])
                seen.add(row[2])
                filtered_rows.append(row)


    with open(output_file, 'w', newline='') as outfile:
        writer = csv.writer(outfile)
        writer.writerow([])  # Writing an empty row (optional)
        print("FILTERED ROWS", filtered_rows)
        writer.writerows(filtered_rows)

def sort_csv_alphabetically(input_rows, output_file):
    # Sort the rows alphabetically based on the first column, excluding the header
    sorted_rows = sorted(input_rows, key=lambda x: x[0].lower())  # Using .lower() for case-insensitive sorting

    # Write the header and sorted rows to the output file
    with open(output_file, 'w', newline='') as outfile:
        writer = csv.writer(outfile)
        writer.writerows(sorted_rows)  # Write the sorted rows

# Write to the CSV file
with open(csv_file, mode='w', newline='', encoding='utf-8') as file:
    writer = csv.writer(file)
    writer.writerow(["file" ,"contractName", "contractAddress","explorerUrl"])  # Header row
    rows_data = createFromScriptOut()
    sort_csv_alphabetically(rows_data, csv_file)
    filter_repeating_values(csv_file, csv_file)



