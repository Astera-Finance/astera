import re

# cmd :: python3 tests/echidna/echidnaToFoundry/FromSeqToFoudry.py
def transform_text(input_text):
    output = []
    output.append("// SPDX-License-Identifier: MIT")
    output.append("pragma solidity ^0.8.13;")
    output.append("")
    output.append("import \"../PropertiesMain.sol\";")
    output.append("import \"../PropertiesBase.sol\";") 
    output.append("import \"forge-std/Test.sol\";")
    output.append("")
    output.append("// cmd :: forge t --mt testCallSequence -vvvv")
    output.append("/// @notice This is a foudry test contract to test failing properties echidna fuzzing found.")
    output.append("contract FoundryTestSequence is Test {")
    output.append("    PropertiesMain public propertiesMain;")
    output.append("")
    output.append("    constructor() {")
    output.append("        propertiesMain = new PropertiesMain();")
    output.append("    }")
    output.append("")
    output.append("    function testCallSequence() public {")

    # Remove leading whitespace (spaces and tabs) from each line and join them back with newlines
    # lstrip() removes all leading whitespace characters from the beginning of each line
    # This normalizes the indentation by removing inconsistent leading spaces/tabs
    lines = [line.lstrip() for line in input_text.split("\n")]
    for line in lines:
        if not line.strip():
            continue
            
        # Handle wait lines
        if line.startswith("*wait*"):
            match = re.search(r"Time delay: (\d+)", line)
            if match:
                output.append(f"        skip({match.group(1)});")
            continue
            
        # Handle function calls
        if line.startswith("PropertiesMain."):
            # Extract the main part before "from:"
            main_part = line.split(" from:")[0]
            
            # Extract time delay
            time_delay_match = re.search(r"Time delay: (\d+)", line)
            time_delay = time_delay_match.group(1) if time_delay_match else None
            
            # Check if there's a tuple in the function call
            tuple_match = re.search(r"\(([\d, ]+(?:, true|false))\)", main_part)
            if tuple_match:
                # Extract tuple values
                tuple_str = tuple_match.group(1)
                # Always wrap tuples with PropertiesBase.LocalVars_UPTL
                main_part = main_part.replace(f"({tuple_str})", f"PropertiesBase.LocalVars_UPTL({tuple_str})")
            
            # Convert to lowercase for the first word
            main_part = "propertiesMain" + main_part[14:]
            
            # Add semicolon and skip if there's a time delay
            if time_delay:
                output.append(f"        {main_part}; skip({time_delay});")
            else:
                output.append(f"        {main_part};")

    output.append("    }")
    output.append("}")
    output.append("")

    return "\n".join(output)

# Example usage
input_text = """     PropertiesMain.randDepositMP((0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3627169055486385356, false),0,0,2,1,37)
    PropertiesMain.randBorrowMP((0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false),0,0,2,0,1)
    PropertiesMain.randWithdrawMP((0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false),0,2,2,1,50709400810492495077782802097815808)
"""

string = 'tests/echidna/echidnaToFoundry/FoundryTestSequence.sol'
with open(string, 'w') as f:
    f.write(transform_text(input_text))

print("Done ::: the %s file has been generated." % string)