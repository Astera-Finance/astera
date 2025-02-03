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
            # Extract the main part before any time delay info
            main_part = line.split(" Time delay:")[0]
            
            # Remove the "from: 0x..." part if present
            main_part = main_part.split(" from:")[0]   

            # Extract time delay if present
            time_delay_match = re.search(r"Time delay: (\d+)", line)
            time_delay = time_delay_match.group(1) if time_delay_match else None
            
            # Check if there's a tuple in the function call
            tuple_match = re.search(r"\(([\d, ]+(?:, true|false))\)", main_part)
            if tuple_match:
                # Extract tuple values
                tuple_str = tuple_match.group(1)
                # Always wrap tuples with PropertiesBase.LocalVars_UPTL
                main_part = main_part.replace(f"({tuple_str})", f"(PropertiesBase.LocalVars_UPTL({tuple_str}))")
            
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
input_text = """    PropertiesMain.randForceFeedAssetLP((5, 152, 128, 48, 100, 9, 2, 40, 34, 8, 34, 1501, false),121,54226010652114989114253842279358793987,181,52)
    PropertiesMain.randRehypothecationRebalanceLP((0, 97, 131, 3, 114, 9, 18, 69, 14, 12, 0, 644146345200320509442638598, false),0)
    PropertiesMain.balanceIntegrityMP((3, 147, 16, 52, 40, 1, 41, 224, 2, 0, 6, 944986130179235443279470948070735946, false))
    PropertiesMain.randRehypothecationRebalanceLP((7, 16, 3, 19, 3, 93, 0, 0, 21, 0, 1, 82787515665385814594281779132579905529, false),0)
    PropertiesMain.balanceIntegrityMP((7, 21, 4, 4, 3, 44, 2, 98, 26, 24, 1, 299366688053652699667520806443059933630, false))
    PropertiesMain.randForceFeedAssetLP((8, 41, 53, 10, 4, 146, 2, 52, 4, 63, 4, 230412744270376668990711099159295150754, true),1,45,32,4)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((50, 33, 62, 30, 11, 69, 0, 85, 12, 1, 0, 70968246707850283104759241505554082838, false),2,12)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((13, 214, 12, 0, 55, 97, 6, 11, 3, 24, 2, 223114662533879335170019189445425289063, false),0,1)
    PropertiesMain.randRehypothecationRebalanceLP((0, 5, 2, 0, 0, 19, 1, 17, 15, 0, 1, 15399013415214194558366896861180835833, false),0)
    PropertiesMain.randApproveDelegationMP((7, 7, 136, 7, 2, 27, 37, 16, 188, 164, 155, 125457204010425726085156370230551658399, false),18,0,26,116928022673724857876876092269162325547)
    PropertiesMain.randApproveMP((141, 53, 6, 15, 3, 46, 2, 0, 26, 3, 32, 93, false),0,9,0,24,7)
    PropertiesMain.randForceFeedAssetLP((1, 4, 20, 1, 0, 0, 1, 4, 1, 0, 0, 77999725134659503690874698400990357, false),0,43444486718927927519277947390413037,0,0)
    PropertiesMain.randIncreaseAllowanceLP((27, 225, 28, 58, 0, 9, 144, 45, 6, 64, 99, 2000, false),13,1,0,26)
    PropertiesMain.randApproveDelegation((55, 42, 157, 84, 156, 23, 20, 28, 232, 57, 92, 53138198135018813486024556, false),7,23,136,12920168845449032428228214843801832846)
    PropertiesMain.randFlashloanLP((19, 173, 19, 24, 13, 2, 4, 30, 42, 222, 89, 56298442179623642784898957328763779769, false),23,23,3,24)
    PropertiesMain.randFlashloanLP((10, 224, 85, 153, 63, 89, 17, 211, 53, 8, 5, 227946792577719080308576085489028001948, false),0,8,153,56998291403192289944759203850370384144)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((116, 6, 251, 2, 201, 75, 0, 0, 25, 0, 2, 893778136417665197399, false),0,0)
    PropertiesMain.randDepositLP((37, 0, 85, 159, 18, 21, 18, 46, 0, 25, 14, 19517060225048056303761628647016002362, false),2,14,1,34611341961874600762689036068982424608)
    PropertiesMain.randATokenNonRebasingApproveLP((86, 4, 52, 0, 4, 3, 0, 51, 57, 77, 11, 4214045822038363900405617055608070392, false),17,0,0,48)
    PropertiesMain.randIncreaseAllowanceLP((210, 37, 48, 104, 29, 114, 1, 45, 215, 54, 86, 7658409028368692304470642503984682750, false),1,100,1,68147694)
    PropertiesMain.randIncreaseAllowanceLP((17, 14, 70, 115, 34, 241, 57, 58, 145, 205, 239, 384000, false),0,9,86,3)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((2, 2, 131, 2, 41, 57, 0, 6, 3, 4, 14, 2054715664365430604936, false),0,0)
    PropertiesMain.balanceIntegrityLP((5, 5, 23, 4, 26, 0, 0, 49, 0, 117, 131, 92800218047652643161337046704555957618, false))
    PropertiesMain.randATokenNonRebasingApproveLP((1, 29, 0, 16, 129, 4, 237, 62, 117, 25, 59, 63759371, false),2,91,120,70849838396173411549935219204787951268)
    PropertiesMain.randDepositMP((161, 48, 156, 7, 3, 44, 38, 18, 78, 178, 31, 65536, true),0,8,5,85,279416945937829085844524909615217678489)
    PropertiesMain.randApproveMP((103, 75, 80, 15, 6, 99, 34, 92, 0, 168, 2, 6466, false),5,1,0,12,21687892296102167871494859254594166084)
    PropertiesMain.randIncreaseAllowanceLP((3, 0, 14, 4, 1, 10, 204, 0, 87, 2, 22, 1057948505, false),0,0,1,19321481573813620208781161274580024427)
    PropertiesMain.randApproveDelegation((81, 15, 53, 249, 97, 8, 1, 0, 174, 48, 8, 25477095744354333394982906044784527355, false),35,0,23,4890429122498235428730497281448342782)
    PropertiesMain.randApproveDelegation((0, 8, 254, 1, 3, 18, 6, 7, 54, 20, 54, 223247792321284384209060722630322754834, false),1,16,6,69824)
    PropertiesMain.randRehypothecationRebalanceLP((5, 21, 82, 22, 9, 111, 53, 1, 0, 0, 1, 38348043, false),0)
    PropertiesMain.balanceIntegrityMP((0, 1, 5, 3, 5, 59, 0, 0, 0, 2, 17, 9200815030011147542581486443645422190, false))
    PropertiesMain.randBorrowMP((18, 174, 57, 15, 31, 27, 52, 148, 179, 112, 0, 3858086692, false),4,1,49,226,218343749412336002673253792777943950664)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((0, 1, 153, 0, 11, 4, 2, 26, 3, 0, 0, 2833135388202602584488, false),4,6)
    PropertiesMain.randApproveDelegationMP((4, 252, 163, 41, 248, 1, 243, 5, 43, 18, 27, 123825494993740765743949008853328702387, false),12,0,123,79849183813832707959620360019012871334)
    PropertiesMain.randDepositMP((135, 225, 46, 84, 33, 65, 217, 70, 75, 121, 88, 340282366920938463463374607431768211452, true),43,7,85,119,74188707498321978376143096653022900581)
    PropertiesMain.randDepositLP((0, 179, 164, 0, 0, 0, 67, 10, 20, 61, 6, 1113008004916695407708725639032599526, false),36,0,45,10269227544491121539976123734763899108)
    PropertiesMain.randApproveLP((4, 0, 190, 5, 21, 35, 91, 0, 3, 10, 0, 36900918930485025500279233946831879092, false),3,5,8,4800457795126598917393473376752668025)
    PropertiesMain.randDepositMP((89, 68, 2, 0, 27, 159, 94, 21, 177, 19, 7, 140371643045405529648011490355138263791, true),0,0,4,0,62137712602760143599745061713599751554)
    PropertiesMain.userConfigurationMapIntegrityLiquidityMP()
"""

string = 'tests/echidna/echidnaToFoundry/FoundryTestSequence.sol'
with open(string, 'w') as f:
    f.write(transform_text(input_text))

print("Done ::: the %s file has been generated." % string)