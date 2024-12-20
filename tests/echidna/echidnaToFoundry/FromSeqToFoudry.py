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
input_text = """       PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000010000 Time delay: 73640 seconds Block delay: 4797
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000020000 Time delay: 53 seconds Block delay: 2783
    *wait* Time delay: 55653 seconds Block delay: 13556
    PropertiesMain.randDepositMP((19, 45, 48, 28, 91, 31, 39, 83, 4, 31, 194, 75556710804409716572161, true),57,39,45,5,51340885865410570674416158866210557407) from: 0x0000000000000000000000000000000000010000 Time delay: 69942 seconds Block delay: 6125
    *wait* Time delay: 37831 seconds Block delay: 10941
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000010000 Time delay: 19593 seconds Block delay: 7865
    PropertiesMain.randForceFeedAssetLP((83, 222, 12, 164, 161, 217, 144, 7, 102, 77, 93, 3725587546, false),2,1,200,57) from: 0x0000000000000000000000000000000000020000 Time delay: 12704 seconds Block delay: 2675
    *wait* Time delay: 204410 seconds Block delay: 12893
    PropertiesMain.balanceIntegrityLP((41, 140, 31, 233, 165, 83, 38, 197, 1, 253, 86, 89463000176247804858481045367348210674, true)) from: 0x0000000000000000000000000000000000010000 Time delay: 71233 seconds Block delay: 164
    *wait* Time delay: 32799 seconds Block delay: 4544
    PropertiesMain.randATokenNonRebasingApproveLP((244, 205, 46, 57, 7, 230, 64, 197, 252, 188, 81, 93, false),68,129,1,169182917653354964098321622043809906643) from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 83708 seconds Block delay: 11205
    PropertiesMain.randFlashloanLP((126, 51, 205, 253, 140, 252, 252, 41, 9, 12, 255, 90, true),48,76,59,100000) from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 53710 seconds Block delay: 327
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000010000 Time delay: 72367 seconds Block delay: 6597
    PropertiesMain.randDepositMP((75, 87, 5, 240, 52, 53, 51, 210, 13, 246, 49, 422, true),55,77,172,52,2708836573) from: 0x0000000000000000000000000000000000010000 Time delay: 5639 seconds Block delay: 3491
    PropertiesMain.randIncreaseAllowanceLP((57, 58, 59, 225, 255, 129, 27, 10, 39, 238, 32, 149010725882750124440092154071855106800, true),76,11,1,209522542804048950312701734522268526141) from: 0x0000000000000000000000000000000000010000 Time delay: 15914 seconds Block delay: 2971
    PropertiesMain.integrityOfDepositCapMP() from: 0x0000000000000000000000000000000000010000 Time delay: 71371 seconds Block delay: 6888
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 32786 seconds Block delay: 7470
    PropertiesMain.randFlashloanLP((9, 53, 17, 145, 222, 4, 191, 251, 134, 145, 198, 142572861378587884234722977979035075183, false),254,129,235,142030855481234937043455964463621223561) from: 0x0000000000000000000000000000000000010000
    PropertiesMain.randBorrowMP((163, 46, 63, 61, 175, 84, 166, 213, 167, 48, 48, 1499, false),199,65,100,53,1774647075) from: 0x0000000000000000000000000000000000020000 Time delay: 78728 seconds Block delay: 7469
    *wait* Time delay: 68563 seconds Block delay: 9230
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 9829 seconds Block delay: 4202
    PropertiesMain.balanceIntegrityLP((167, 29, 15, 240, 10, 24, 182, 16, 116, 28, 12, 31097775698636801506390037248028084663, false)) from: 0x0000000000000000000000000000000000020000
    PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000010000
    PropertiesMain.randApproveDelegation((166, 84, 108, 0, 246, 20, 93, 246, 84, 0, 180, 9277947802268641400951295581329059336, true),80,77,133,4294901762) from: 0x0000000000000000000000000000000000020000 Time delay: 70390 seconds Block delay: 79
    *wait* Time delay: 51133 seconds Block delay: 2784
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000020000 Time delay: 18822 seconds Block delay: 7539
    *wait* Time delay: 58368 seconds Block delay: 6568
    PropertiesMain.randForceFeedAssetLP((10, 12, 21, 50, 9, 106, 125, 39, 21, 72, 60, 11, false),18,48,6,185) from: 0x0000000000000000000000000000000000010000 Time delay: 52 seconds Block delay: 2689
    PropertiesMain.randDepositLP((192, 12, 91, 253, 76, 85, 27, 31, 251, 92, 50, 221786960397500123250377184720867557361, false),63,45,201,322759608743509015290817181385612209096) from: 0x0000000000000000000000000000000000010000
    PropertiesMain.randForceFeedATokensMP((51, 10, 59, 40, 8, 51, 91, 243, 5, 135, 96, 94, false),251,5,179385569736717435120143478327317842854,133,false) from: 0x0000000000000000000000000000000000010000 Time delay: 38019 seconds Block delay: 5049
    PropertiesMain.randForceFeedAssetLP((170, 163, 0, 148, 69, 181, 166, 124, 41, 73, 0, 1166, false),1,260100219191091835669916841408835423906,252,124) from: 0x0000000000000000000000000000000000010000 Time delay: 18826 seconds Block delay: 2913
    PropertiesMain.randRehypothecationRebalanceLP((218, 33, 2, 225, 194, 37, 252, 198, 70, 9, 105, 55, false),128) from: 0x0000000000000000000000000000000000010000 Time delay: 13469 seconds Block delay: 1359
    PropertiesMain.randDepositLP((51, 238, 20, 97, 97, 95, 96, 20, 11, 113, 80, 66913124145103122520683749530335435675, true),252,99,33,42359011975676773962813480294555317637) from: 0x0000000000000000000000000000000000010000 Time delay: 9 seconds Block delay: 4008
    PropertiesMain.randDepositMP((16, 33, 163, 1, 0, 28, 7, 12, 7, 159, 22, 288532261366340887874715698303188359901, true),48,10,51,1,57624051166818834188) from: 0x0000000000000000000000000000000000010000 Time delay: 101 seconds Block delay: 5355
    PropertiesMain.randBorrowMP((41, 201, 7, 188, 144, 128, 85, 69, 8, 5, 194, 94760548677343536387109886102435049128, false),144,189,49,164,340282366920938463463374607431768211452) from: 0x0000000000000000000000000000000000010000 Time delay: 2728 seconds Block delay: 4799
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 73594 seconds Block delay: 7598
    *wait* Time delay: 64343 seconds Block delay: 6199
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000010000 Time delay: 35058 seconds Block delay: 70
    PropertiesMain.randATokenNonRebasingBalanceOfLP((254, 188, 7, 12, 121, 17, 100, 159, 137, 22, 160, 241449520387062776950456104394056199786, true),11,187) from: 0x0000000000000000000000000000000000010000 Time delay: 32826 seconds Block delay: 2725
    *wait* Time delay: 48 seconds Block delay: 4176
    PropertiesMain.randApproveDelegationMP((53, 16, 30, 224, 191, 81, 86, 48, 164, 6, 193, 187649586809692726918070048612448169444, true),48,70,53,100000000000000000000000000000000) from: 0x0000000000000000000000000000000000010000 Time delay: 91 seconds Block delay: 7179
    PropertiesMain.balanceIntegrityLP((4, 20, 83, 147, 40, 93, 23, 23, 68, 127, 2, 52138242200308413054505853208324603538, false)) from: 0x0000000000000000000000000000000000010000 Time delay: 32842 seconds Block delay: 7101
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000010000 Time delay: 32797 seconds Block delay: 4785
    PropertiesMain.integrityOfDepositCapMP() from: 0x0000000000000000000000000000000000010000 Time delay: 65005 seconds Block delay: 85
    PropertiesMain.randIncreaseAllowanceLP((142, 63, 218, 152, 19, 90, 21, 198, 32, 132, 32, 321356630161105394335837631041377702350, false),133,151,240,248446029861494680627667157029489841771) from: 0x0000000000000000000000000000000000010000 Time delay: 52575 seconds Block delay: 4176
    *wait* Time delay: 7999 seconds Block delay: 5671
    *wait* Time delay: 143135 seconds Block delay: 14284
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000010000 Time delay: 80854 seconds Block delay: 3645
    *wait* Time delay: 84585 seconds Block delay: 5045
    PropertiesMain.randFlashloanLP((60, 253, 95, 188, 183, 50, 67, 18, 48, 226, 58, 2304117921, false),109,23,165,7) from: 0x0000000000000000000000000000000000020000 Time delay: 32783 seconds Block delay: 4141
    *wait* Time delay: 168749 seconds Block delay: 18781
    PropertiesMain.randIncreaseAllowanceLP((239, 179, 164, 163, 101, 196, 45, 158, 13, 94, 97, 18, false),199,53,251,340282366920938463463374607431768211451) from: 0x0000000000000000000000000000000000010000 Time delay: 32798 seconds Block delay: 4447
    PropertiesMain.randApproveMP((222, 14, 95, 47, 207, 15, 18, 59, 223, 229, 21, 316563394738586043928478905800545127830, true),76,208,33,203,99200417980737395403312553832745828242) from: 0x0000000000000000000000000000000000010000
    PropertiesMain.randDepositLP((28, 21, 53, 56, 209, 0, 136, 18, 253, 41, 3, 287225889533802839861287759363960314873, true),72,77,45,167316696238596700437513238130353982015) from: 0x0000000000000000000000000000000000010000 Time delay: 70152 seconds Block delay: 2676
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 83623 seconds Block delay: 3748
    PropertiesMain.randForceFeedAssetLP((251, 226, 255, 147, 220, 223, 80, 137, 4, 189, 2, 40594309589334028716522816908670304748, true),28,244762662757493019460587321372842737861,52,254) from: 0x0000000000000000000000000000000000010000 Time delay: 46622 seconds Block delay: 3566
    *wait* Time delay: 74750 seconds Block delay: 8254
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 16168 seconds Block delay: 4701
    *wait* Time delay: 132865 seconds Block delay: 4389
    PropertiesMain.balanceIntegrityLP((14, 93, 8, 1, 182, 1, 2, 162, 42, 12, 151, 1513845944, false)) from: 0x0000000000000000000000000000000000020000 Time delay: 17845 seconds Block delay: 1644
    PropertiesMain.randDepositMP((202, 92, 35, 5, 65, 161, 225, 20, 28, 214, 144, 2129999999999999999999999999, false),42,120,11,100,304643165208763333313553288579804780036) from: 0x0000000000000000000000000000000000010000 Time delay: 60203 seconds Block delay: 4448
    PropertiesMain.randApproveLP((253, 57, 13, 204, 3, 97, 52, 0, 254, 141, 0, 972, false),193,175,91,196501569170543750327888823188758304877) from: 0x0000000000000000000000000000000000010000
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000010000 Time delay: 11 seconds Block delay: 362
    PropertiesMain.randSetUseReserveAsCollateralLP((252, 48, 40, 128, 10, 7, 228, 8, 123, 68, 254, 155162630169116841328405036823922938316, true),65,101,false) from: 0x0000000000000000000000000000000000010000
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 83328 seconds Block delay: 99
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000010000 Time delay: 23685 seconds Block delay: 5924
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000010000 Time delay: 86035 seconds Block delay: 2992
    PropertiesMain.randApproveDelegationMP((20, 95, 193, 204, 17, 0, 61, 37, 122, 84, 166, 198572100187628801334572441256732, true),121,49,22,133738936790260605874535023175479741388) from: 0x0000000000000000000000000000000000010000 Time delay: 6 seconds Block delay: 2945
    PropertiesMain.randDepositLP((121, 172, 163, 83, 255, 143, 15, 97, 165, 31, 161, 258158516, true),69,116,98,576460752303423489) from: 0x0000000000000000000000000000000000010000
    PropertiesMain.randFlashloanLP((58, 224, 6, 92, 91, 84, 90, 97, 56, 170, 15, 10501, false),91,10,33,279742866881193716296603612083689076149) from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 48710 seconds Block delay: 13923
    PropertiesMain.randATokenNonRebasingBalanceOfLP((219, 247, 201, 106, 36, 69, 0, 134, 91, 29, 0, 136096609729750775570287063383604227642, false),209,106) from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 97563 seconds Block delay: 3602
    PropertiesMain.integrityOfDepositCapMP() from: 0x0000000000000000000000000000000000010000 Time delay: 32763 seconds Block delay: 8275
    *wait* Time delay: 32790 seconds Block delay: 4355
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000
    PropertiesMain.randATokenNonRebasingBalanceOfLP((99, 25, 235, 100, 70, 11, 4, 171, 4, 161, 85, 167328225359236456196687998743582101018, true),12,78) from: 0x0000000000000000000000000000000000010000 Time delay: 84586 seconds Block delay: 2674
    PropertiesMain.randApproveDelegationMP((113, 161, 243, 59, 6, 252, 13, 59, 29, 52, 161, 340282366920938463463374607431768211451, true),46,70,78,10000000000000000000000001) from: 0x0000000000000000000000000000000000010000 Time delay: 83 seconds Block delay: 4001
    PropertiesMain.randATokenNonRebasingBalanceOfLP((219, 247, 201, 106, 36, 69, 0, 134, 91, 29, 0, 136096609729750775570287063383604227642, false),209,106) from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 16093 seconds Block delay: 2974
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000020000 Time delay: 32755 seconds Block delay: 5034
    PropertiesMain.balanceIntegrityLP((5, 108, 114, 0, 30, 22, 33, 75, 61, 33, 196, 43748025088326846790950464816652111201, true)) from: 0x0000000000000000000000000000000000010000
    PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000010000 Time delay: 5359 seconds Block delay: 4201
    PropertiesMain.randDepositMP((63, 17, 13, 234, 96, 163, 33, 178, 3, 23, 73, 340282366920938463463374607431768211451, true),58,1,6,96,46) from: 0x0000000000000000000000000000000000020000
    PropertiesMain.randATokenNonRebasingBalanceOfLP((47, 65, 251, 51, 84, 41, 253, 75, 239, 155, 167, 77, true),41,183) from: 0x0000000000000000000000000000000000010000 Time delay: 8686 seconds Block delay: 1976
    PropertiesMain.randApproveLP((187, 148, 7, 188, 37, 169, 217, 223, 97, 127, 127, 314106607323630526758811965361681487662, true),9,187,5,4271441049) from: 0x0000000000000000000000000000000000010000 Time delay: 25175 seconds Block delay: 129
    *wait* Time delay: 10553 seconds Block delay: 5850
    PropertiesMain.randFlashloanLP((68, 16, 59, 221, 223, 166, 117, 52, 254, 58, 0, 160260515401203516649599385495307499007, true),253,39,67,1000000000000000000) from: 0x0000000000000000000000000000000000010000 Time delay: 7 seconds Block delay: 41
    *wait* Time delay: 65536 seconds Block delay: 1003
    PropertiesMain.integrityOfDepositCapMP() from: 0x0000000000000000000000000000000000010000 Time delay: 49094 seconds Block delay: 3726
    *wait* Time delay: 65668 seconds Block delay: 21444
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000020000 Time delay: 22346 seconds Block delay: 377
    *wait* Time delay: 20599 seconds Block delay: 11745
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000020000 Time delay: 57 seconds Block delay: 7919
    PropertiesMain.randATokenNonRebasingBalanceOfLP((219, 247, 201, 106, 36, 69, 0, 134, 91, 29, 0, 136096609729750775570287063383604227642, false),209,106) from: 0x0000000000000000000000000000000000010000 Time delay: 224 seconds Block delay: 51
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000010000 Time delay: 69658 seconds Block delay: 2987
    *wait* Time delay: 58367 seconds Block delay: 1860
    PropertiesMain.randSetUseReserveAsCollateralMP((129, 65, 6, 31, 229, 232, 63, 218, 169, 21, 85, 8, false),33,56,36,false) from: 0x0000000000000000000000000000000000010000 Time delay: 38019 seconds Block delay: 5854
    PropertiesMain.randApproveMP((139, 1, 254, 81, 5, 22, 114, 94, 221, 20, 16, 86613153, true),87,25,3,0,11524537248520665260514525216615913103) from: 0x0000000000000000000000000000000000010000 Time delay: 24847 seconds Block delay: 6123
    PropertiesMain.randTransferLP((133, 209, 127, 113, 178, 29, 103, 164, 135, 245, 63, 28, true),75,45,57,82904498304637991348498647248329939246) from: 0x0000000000000000000000000000000000010000 Time delay: 28847 seconds Block delay: 6560
    PropertiesMain.randRehypothecationRebalanceLP((136, 159, 56, 55, 48, 6, 7, 56, 239, 140, 254, 340282366920938463463374607431768211451, false),181) from: 0x0000000000000000000000000000000000010000 Time delay: 68113 seconds Block delay: 4120
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000010000 Time delay: 32789 seconds Block delay: 1934
    PropertiesMain.randFlashloanLP((164, 247, 164, 243, 8, 35, 75, 39, 136, 16, 91, 208380715375835653407198601606631548760, false),15,127,225,1001) from: 0x0000000000000000000000000000000000020000 Time delay: 12081 seconds Block delay: 7921
    PropertiesMain.randATokenNonRebasingApproveLP((2, 28, 47, 131, 6, 178, 159, 41, 59, 74, 0, 33645668186671660992163235941600552042, false),3,15,96,3729) from: 0x0000000000000000000000000000000000020000 Time delay: 47034 seconds Block delay: 127
    PropertiesMain.integrityOfDepositCapMP() from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 55197 seconds Block delay: 4043
    PropertiesMain.randATokenNonRebasingBalanceOfLP((140, 127, 10, 48, 223, 0, 147, 48, 99, 161, 126, 4722366482869645213694, true),53,69) from: 0x0000000000000000000000000000000000010000 Time delay: 34813 seconds Block delay: 6596
    PropertiesMain.randATokenNonRebasingTransferLP((191, 1, 20, 225, 127, 253, 1, 108, 0, 45, 6, 209922661970529702821165534660029159063, false),225,58,65,9493010900183148435268178641316583264) from: 0x0000000000000000000000000000000000010000 Time delay: 46941 seconds Block delay: 3001
    *wait* Time delay: 7393 seconds Block delay: 1166
    PropertiesMain.randApproveDelegationMP((19, 244, 203, 30, 66, 245, 83, 67, 100, 123, 76, 237814500398367985235974255014463168947, true),140,102,239,55) from: 0x0000000000000000000000000000000000010000 Time delay: 46879 seconds Block delay: 6846
    PropertiesMain.randDepositMP((66, 3, 189, 6, 202, 32, 8, 79, 71, 87, 20, 309464685855671251213709062355693908162, false),83,20,219,11,122) from: 0x0000000000000000000000000000000000010000 Time delay: 10007 seconds Block delay: 2959
    *wait* Time delay: 32789 seconds Block delay: 5048
    PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000010000 Time delay: 84585 seconds Block delay: 2955
    *wait* Time delay: 18822 seconds Block delay: 695
    PropertiesMain.randWithdrawLP((21, 16, 0, 93, 244, 225, 119, 41, 99, 127, 23, 82576152808032551811056927115500678463, false),3,20,65,381) from: 0x0000000000000000000000000000000000010000 Time delay: 26308 seconds Block delay: 63
    *wait* Time delay: 318775 seconds Block delay: 27499
    PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000010000 Time delay: 59040 seconds Block delay: 1197
    PropertiesMain.userConfigurationMapIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 6511 seconds Block delay: 6996
"""

string = 'tests/echidna/echidnaToFoundry/echidnaToFoundry.sol'
with open(string, 'w') as f:
    f.write(transform_text(input_text))

print("Done ::: the %s file has been generated." % string)