import pandas as pd
import matplotlib.pyplot as plt
import os
# import pdb

log = False
print(os.getcwd())
if "pidTests" in os.getcwd():
    dir = os.getcwd() + "/data"
else:
    dir = os.getcwd() + "/tests/foundry/pidTests/data"
idx = 0

liquidities = []
debts = []
timestamp = []
names = []
linestyles = ['-.', '--', ':']
for root, dirs, filenames in os.walk(dir):
    for filename in filenames:
        
        if ".csv" in filename:
            names.append(filename.split(".")[0])
            print("Filename: {}".format(filename))
            # Load the CSV file
            print(os.path.join(root, filename))
            data = pd.read_csv(os.path.join(root, filename))

            # Filter the data for the specified asset
            asset_data = data[data["asset"] == "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1"].copy()

            # Convert the timestamp to datetime and the rates to float
            timestamp = pd.to_datetime(asset_data["timestamp"], unit="s")
            asset_data["timestamp"] = pd.to_datetime(asset_data["timestamp"], unit="s")
            asset_data["currentVariableBorrowRate"] = asset_data["currentVariableBorrowRate"].astype(float)
            asset_data["currentLiquidityRate"] = asset_data["currentLiquidityRate"].astype(float)
            asset_data["utilizationRate"] = asset_data["utilizationRate"].astype(float)
            liquidities.append(asset_data["availableLiquidity"].astype(float))
            debts.append(asset_data["currentDebt"].astype(float))
            
            # Create a figure with two subplots
            fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

            # Upper subplot: currentVariableBorrowRate and currentLiquidityRate
            ax1.plot(asset_data["timestamp"], asset_data["currentVariableBorrowRate"] / 1e25, label="currentVariableBorrowRate")
            ax1.plot(asset_data["timestamp"], asset_data["currentLiquidityRate"] / 1e25, color='red', label="currentLiquidityRate")
            ax1.set_title("Rates over time for asset 0xda10009cbd5d07dd0cecc66161fc93d7c9000da1")
            ax1.set_ylabel("Rates (in %)")
            if log : 
                ax1.set_yscale('log')  # Set y-axis to log scale
            ax1.legend()
            ax1.grid(True)

            # Lower subplot: utilizationRate
            ax2.plot(asset_data["timestamp"], asset_data["utilizationRate"] / 1e25, color='green', label="utilizationRate")
            ax2.set_xlabel("Timestamp")
            ax2.set_ylabel("Utilization Rate (in %)")
            if log : 
                ax2.set_yscale('log')  # Set y-axis to log scale
            ax2.legend()
            ax2.grid(True)

            plt.tight_layout()
            
            plt.savefig(dir + "/rates_over_time_{}.png".format(filename.split(".")[0]))
            idx+=1
            # print("LIQUIDITIES: ", liquidities)
        

# Create a figure with two subplots
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

# Upper subplot: main pool and mini pool liquidities
for idx,liquidity in enumerate(liquidities):
    ax1.plot(timestamp, liquidity / 1e18, label="{} liquidity".format(names[idx]), linestyle=linestyles[idx%3])

ax1.set_title("Liquidities and debts over time for asset 0xda10009cbd5d07dd0cecc66161fc93d7c9000da1")
ax1.set_ylabel("Liquidity")
if log : 
    ax1.set_yscale('log')  # Set y-axis to log scale
ax1.legend()
ax1.grid(True)

# Lower subplot: main pool and mini pool debts
for idx,debt in enumerate(debts):
    ax2.plot(timestamp, debt / 1e18, label="{} debt".format(names[idx]), linestyle=linestyles[idx%3])
ax2.set_xlabel("Timestamp")
ax2.set_ylabel("Debts")
if log : 
    ax2.set_yscale('log')  # Set y-axis to log scale
ax2.legend()
ax2.grid(True)

plt.tight_layout()

plt.savefig(dir + "/liquiditiesAndDebts.png".format(filename.split(".")[0]))
