import matplotlib.pyplot as plt
from matplotlib.ticker import MultipleLocator

# Read and print the contents of a text file
def read_text_file(file_path):
    x_time = []
    y_twap = []
    y_spot = []
    
    try:
        with open(file_path, 'r') as file:
            for line in file:
                splitted_list = line.split(", ")
                #print(splitted_list)
                print(int(splitted_list[0].split(": ")[-1])  / 60)
                if(int(splitted_list[0].split(": ")[-1]) % 60 == 0):
                    time_s = str(int(int(splitted_list[0].split(": ")[-1]) / 60)) + "hr"
                else:
                    time_s = splitted_list[0].split(": ")[-1]
                    
                x_time.append(time_s)
                y_twap.append(int(splitted_list[1].split(": ")[-1])/1e18)
                y_spot.append(int(splitted_list[2].split(": ")[-1])/1e18)
    except FileNotFoundError:
        print(f"The file {file_path} does not exist.")
    except Exception as err:
        print(f"An error occurred: {err}")
    print(x_time)
    print(y_twap)
    print(y_spot)
    return x_time, y_twap, y_spot

# Example usage
file_path = "./Data120MinEtherex1.txt"
x_time, y_twap, y_spot = read_text_file(file_path)


# Create a figure and axis
fig, ax = plt.subplots()

# Plot data
ax.plot(x_time, y_twap, label='Twap', color='blue')

ax.plot(x_time, y_spot, label='Spot', color='red')

# Set title and labels
ax.set_title('Oracle price ({})'.format(file_path))
ax.set_xlabel('Time [min]')
ax.set_ylabel('Pirces')

plt.gca().xaxis.set_major_locator(MultipleLocator(2))
plt.gca().yaxis.set_major_locator(MultipleLocator(0.01))
ax.legend()
plt.grid(True)

# Show the plot
plt.savefig('plot.png')  # Save instead of show
plt.close()  # Free memory
# plt.show(block=False)  # Non-blocking show