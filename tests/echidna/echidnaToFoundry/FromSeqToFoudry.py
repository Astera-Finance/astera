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
    PropertiesMain.balanceIntegrityMP((3, 25, 16, 46, 30, 58, 50, 224, 2, 0, 24, 246221129570129958448527617472959448, false))
    PropertiesMain.randATokenNonRebasingApproveLP((80, 89, 199, 3, 36, 12, 62, 49, 17, 56, 0, 99, false),1,15,9,1498494005)
    PropertiesMain.randRehypothecationRebalanceLP((7, 16, 3, 16, 3, 93, 0, 0, 21, 0, 1, 82787515665385814594281779132579905529, false),0)
    PropertiesMain.balanceIntegrityMP((7, 21, 4, 4, 3, 44, 2, 98, 26, 24, 1, 299366688053652699667520806443059933630, false))
    PropertiesMain.randForceFeedAssetLP((0, 41, 53, 6, 4, 146, 2, 34, 3, 63, 4, 149059856094054943404350899950145614043, false),0,48,32,0)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((50, 33, 62, 30, 11, 69, 0, 85, 12, 1, 0, 70968246707850283104759241505554082838, false),0,12)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((13, 214, 12, 0, 55, 97, 0, 11, 1, 24, 0, 38045367456443213345780433548863246766, false),0,0)
    PropertiesMain.randRehypothecationRebalanceLP((0, 1, 6, 0, 1, 19, 1, 19, 1, 0, 1, 1987198660169346396337455886091920046, false),0)
    PropertiesMain.randApproveDelegationMP((7, 7, 136, 7, 2, 27, 37, 16, 188, 164, 155, 125457204010425726085156370230551658399, false),18,0,26,116928022673724857876876092269162325547)
    PropertiesMain.randApproveMP((141, 53, 6, 15, 3, 46, 3, 1, 26, 3, 32, 93, true),2,10,8,25,22)
    PropertiesMain.randForceFeedAssetLP((1, 2, 7, 2, 3, 0, 1, 6, 2, 0, 0, 179317414127341694638952007821473706, false),0,141930194135256103625518426467824666,0,0)
    PropertiesMain.randIncreaseAllowanceLP((27, 8, 28, 132, 40, 9, 144, 45, 4, 6, 78, 691, false),23,19,0,17)
    PropertiesMain.randApproveDelegation((55, 146, 157, 155, 156, 23, 20, 200, 232, 96, 92, 758612288548647068442312857, true),7,23,183,12920168845449032428228214843801832846)
    PropertiesMain.randFlashloanLP((8, 42, 85, 153, 63, 89, 9, 211, 6, 0, 2, 227946792577719080308576085489028001948, false),0,1,153,56998291403192289944759203850370384144)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((116, 11, 251, 2, 201, 75, 0, 0, 25, 0, 78, 893778136417665197399, false),0,4)
    PropertiesMain.randDepositLP((37, 0, 85, 159, 25, 122, 19, 46, 1, 25, 14, 19517060225048056303761628647016002362, false),2,14,1,34611341961874600762689036068982424608)
    PropertiesMain.randATokenNonRebasingApproveLP((127, 4, 52, 0, 4, 3, 1, 51, 57, 126, 11, 4214045822038363900405617055608070392, false),49,0,0,408)
    PropertiesMain.randIncreaseAllowanceLP((210, 37, 45, 104, 37, 2, 1, 0, 146, 60, 98, 50048181911218946894436015016645041357, false),16,118,21,142095394)
    PropertiesMain.randIncreaseAllowanceLP((6, 14, 70, 123, 1, 82, 1, 1, 86, 128, 49, 249688, false),0,3,36,3)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((3, 3, 136, 4, 76, 57, 0, 6, 6, 4, 14, 3602183898746562714293, false),1,0)
    PropertiesMain.balanceIntegrityLP((4, 6, 27, 145, 17, 1, 2, 43, 10, 61, 48, 89424313254594506076417414443371481885, false))
    PropertiesMain.randATokenNonRebasingApproveLP((0, 29, 0, 16, 129, 3, 128, 62, 117, 17, 59, 63759371, false),0,91,120,70849838396173411549935219204787951268)
    PropertiesMain.randDepositMP((161, 67, 196, 174, 14, 90, 148, 24, 112, 178, 31, 65536, true),0,20,5,85,279416945937829085844524909615217678489)
    PropertiesMain.randApproveMP((20, 75, 80, 13, 3, 128, 8, 24, 0, 77, 213, 17078, false),4,0,0,2,17049006300638865053382655650166368928)
    PropertiesMain.randIncreaseAllowanceLP((3, 8, 22, 4, 1, 10, 213, 4, 87, 2, 34, 1057948505, false),1,0,1,19321481573813620208781161274580024427)
    PropertiesMain.randApproveDelegation((81, 15, 53, 249, 97, 8, 1, 0, 174, 48, 8, 25477095744354333394982906044784527355, false),29,0,17,4890429122498235428730497281448342782)
    PropertiesMain.randRehypothecationRebalanceLP((0, 110, 180, 1, 1, 8, 49, 0, 3, 2, 8, 2249377689, false),0)
    PropertiesMain.randApproveDelegation((1, 10, 254, 64, 14, 20, 22, 27, 54, 20, 102, 329681152426855030178572342790979355306, true),130,31,9,86411)
    PropertiesMain.randRehypothecationRebalanceLP((5, 18, 82, 22, 9, 96, 53, 1, 0, 0, 1, 28032774, false),0)
    PropertiesMain.balanceIntegrityMP((0, 1, 5, 3, 5, 59, 0, 0, 0, 2, 17, 9200815030011147542581486443645422190, false))
    PropertiesMain.randBorrowMP((18, 174, 57, 15, 31, 27, 52, 148, 179, 112, 0, 3858086692, false),4,1,49,226,218343749412336002673253792777943950664)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((0, 1, 153, 0, 11, 1, 2, 26, 3, 0, 0, 1599838344130413129531, false),3,4)
    PropertiesMain.randApproveDelegationMP((4, 252, 163, 41, 248, 1, 243, 5, 43, 18, 27, 123825494993740765743949008853328702387, false),12,0,134,82438629267813064968950353700116962254)
    PropertiesMain.randDepositMP((135, 225, 46, 84, 33, 65, 217, 70, 75, 121, 88, 340282366920938463463374607431768211452, true),43,7,85,119,74188707498321978376143096653022900581)
    PropertiesMain.randDepositLP((0, 179, 164, 0, 0, 0, 67, 10, 20, 61, 6, 1113008004916695407708725639032599526, false),36,0,45,10269227544491121539976123734763899108)
    *wait* Time delay: 5365 seconds Block delay: 4484
    PropertiesMain.randDepositLP((81, 167, 217, 173, 223, 95, 6, 85, 121, 0, 29, 296019591831012870763836988363852191338, false),43,209,27,72238042566135547494989300929222948629)
    PropertiesMain.randFlashloanLP((2, 1, 209, 51, 197, 44, 56, 0, 161, 126, 2, 72057594037927938, false),11,12,37,52978213055944769446210931456279471632)
    *wait* Time delay: 2536 seconds Block delay: 509
    PropertiesMain.randDepositMP((14, 148, 12, 158, 3, 8, 77, 65, 176, 167, 107, 302193859598533778967894813612049586525, false),82,11,7,48,263866211)
    *wait* Time delay: 2984 seconds Block delay: 139
    PropertiesMain.randIncreaseAllowanceLP((0, 248, 252, 0, 164, 91, 219, 41, 129, 51, 108, 130474573653338696091331867568010181289, false),223,224,84,7999)
    PropertiesMain.randFlashloanLP((7, 48, 221, 155, 78, 5, 11, 110, 53, 85, 147, 276289970007110923264017659729348297519, false),21,154,202,95249585306574261035)
    *wait* Time delay: 1627 seconds Block delay: 29
    PropertiesMain.randFlashloanLP((33, 185, 224, 25, 66, 60, 17, 238, 170, 64, 11, 624, false),0,3,1,394290620)
    PropertiesMain.randApproveDelegation((129, 46, 253, 88, 84, 27, 65, 224, 91, 32, 76, 333619198933797509492283906458346254839, false),27,22,48,397542931246761) Time delay: 1298 seconds Block delay: 89
    PropertiesMain.randApproveMP((91, 77, 129, 0, 151, 224, 49, 176, 210, 244, 46, 17432057721918769810333429537733194246, false),1,64,106,10,82895611447065281154686967252150197539)
    PropertiesMain.randDepositLP((44, 36, 217, 66, 194, 0, 150, 78, 36, 29, 127, 3000000000000000000000000000, false),54,80,78,88851) Time delay: 2027 seconds Block delay: 433
    PropertiesMain.randATokenNonRebasingTransferLP((2, 133, 214, 198, 251, 3, 60, 50, 18, 59, 43, 507, false),68,20,253,1000001) Time delay: 553 seconds Block delay: 793
    PropertiesMain.randApproveMP((27, 86, 10, 73, 0, 96, 40, 0, 53, 59, 11, 89654657517172059117843995713719189084, false),88,83,114,49,3456094790) Time delay: 3478 seconds Block delay: 76
    PropertiesMain.randApproveMP((3, 13, 199, 12, 60, 88, 192, 75, 31, 65, 135, 204720875638057167946633555331267961828, true),21,154,12,25,18274556660095846244910870213035972548)
    PropertiesMain.randBorrowMP((75, 175, 210, 242, 56, 94, 18, 66, 174, 166, 230, 103508700558604948629677178, true),87,252,2,228,340282366920938463463374607431768211451)
    PropertiesMain.userDebtIntegrityMP() Time delay: 1949 seconds Block delay: 757
"""

string = 'tests/echidna/echidnaToFoundry/FoundryTestSequence.sol'
with open(string, 'w') as f:
    f.write(transform_text(input_text))

print("Done ::: the %s file has been generated." % string)