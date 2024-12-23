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
input_text = """        PropertiesMain.randForceFeedAssetLP((251, 39, 23, 7, 19, 121, 5, 148, 20, 3, 4, 145884196187800740579819857700273083402, true),72,467086966733892873,64,82) Time delay: 34167 seconds Block delay: 1700
    PropertiesMain.balanceIntegrityLP((135, 152, 255, 165, 57, 0, 21, 251, 75, 171, 101, 195509496565448397625665315109631895266, false))
    PropertiesMain.randIncreaseAllowanceLP((1, 173, 193, 97, 7, 49, 51, 168, 0, 95, 100, 749999999999999999999999999, false),8,156,198,322790015631949865911993173256646553031) Time delay: 16422 seconds Block delay: 225
    *wait* Time delay: 14999 seconds Block delay: 6035
    PropertiesMain.randApproveLP((41, 170, 155, 33, 85, 0, 95, 31, 1, 117, 209, 89, false),8,13,5,527087392) Time delay: 8839 seconds Block delay: 3145
    *wait* Time delay: 32828 seconds Block delay: 1303
    PropertiesMain.randFlashloanLP((201, 224, 36, 39, 253, 112, 8, 159, 156, 20, 33, 1000000000000000000, true),4,115,79,1508230384390593682071088067)
    PropertiesMain.globalSolvencyCheckLP()
    PropertiesMain.userConfigurationMapIntegrityDebtLP() Time delay: 43683 seconds Block delay: 6193
    PropertiesMain.globalSolvencyCheckLP() Time delay: 84172 seconds Block delay: 4044
    *wait* Time delay: 142357 seconds Block delay: 6925
    PropertiesMain.randATokenNonRebasingApproveLP((78, 138, 160, 52, 193, 9, 11, 1, 2, 129, 251, 146656083751569556466927776241172349291, true),23,7,59,27130116993958282500737165491223727336) Time delay: 32845 seconds Block delay: 2135
    PropertiesMain.randFlashloanLP((29, 55, 131, 158, 0, 20, 58, 75, 93, 31, 15, 1500, false),47,57,55,1000000001) Time delay: 75824 seconds Block delay: 1186
    PropertiesMain.randDepositMP((254, 60, 13, 39, 40, 77, 68, 66, 61, 232, 121, 239929003948884575134723464689803339107, true),40,246,111,100,141439750219730025782433135196746841599)
    PropertiesMain.indexIntegrityLP()
    *wait* Time delay: 89677 seconds Block delay: 15075
    PropertiesMain.randDepositMP((61, 100, 27, 165, 107, 76, 77, 16, 1, 251, 70, 310171081555509323281394063991703532578, true),87,95,95,0,100000000000000000000000000000000) Time delay: 85761 seconds Block delay: 5099
    PropertiesMain.balanceIntegrityMP((109, 141, 121, 79, 189, 235, 42, 7, 8, 6, 168, 145, false))
    PropertiesMain.randDepositLP((179, 250, 44, 252, 20, 127, 237, 129, 53, 223, 84, 900, false),178,15,91,18)
    *wait* Time delay: 68475 seconds Block delay: 5012
    PropertiesMain.randForceFeedAssetLP((252, 21, 63, 188, 99, 213, 158, 33, 13, 66, 223, 138283511245148256887947621947333622679, true),142,4951684599277795185273077762,141,250) Time delay: 19246 seconds Block delay: 3372
    PropertiesMain.integrityOfDepositCapMP()
    PropertiesMain.randApproveDelegationMP((201, 132, 60, 225, 12, 131, 231, 126, 189, 254, 49, 2, false),18,189,131,322452029640956520914146183960048761600) Time delay: 82759 seconds Block delay: 4999
    PropertiesMain.randDepositMP((76, 81, 24, 1, 33, 12, 15, 254, 21, 11, 13, 381468693, true),240,53,9,19,1513845946) Time delay: 32789 seconds Block delay: 223
    PropertiesMain.integrityOfDepositCapMP() Time delay: 46396 seconds Block delay: 3001
    PropertiesMain.integrityOfDepositCapMP() Time delay: 35623 seconds Block delay: 2375
    *wait* Time delay: 38472 seconds Block delay: 22986
    PropertiesMain.randForceFeedAssetLP((60, 19, 70, 173, 7, 2, 215, 60, 50, 138, 9, 255, false),23,96556152708155165845458542400882,1,87) Time delay: 32801 seconds Block delay: 5966
    PropertiesMain.randFlashloanLP((55, 216, 228, 31, 34, 233, 21, 92, 15, 221, 163, 599290588, true),2,67,97,2708836573) Time delay: 15309 seconds Block delay: 6695
    PropertiesMain.randIncreaseAllowanceLP((229, 53, 172, 45, 39, 38, 45, 7, 21, 228, 241, 171555557033141365046475222834488154211, true),23,159,64,262971457818377929210736939016024753973) Time delay: 26006 seconds Block delay: 4
    PropertiesMain.integrityOfDepositCapMP()
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 32621 seconds Block delay: 8199
    PropertiesMain.balanceIntegrityMP((16, 96, 77, 68, 178, 104, 5, 19, 40, 175, 16, 1774647077, true)) Time delay: 29759 seconds Block delay: 3913
    PropertiesMain.randApproveDelegationMP((253, 96, 128, 1, 177, 59, 120, 1, 4, 9, 153, 159092249285069000566661868127606013661, true),255,55,1,18) Time delay: 32818 seconds Block delay: 4758
    PropertiesMain.randApproveLP((90, 255, 253, 86, 127, 94, 65, 251, 97, 7, 252, 106793455498233751508110424950981601724, false),0,251,177,79967986283948843190009063746293092001) Time delay: 72616 seconds Block delay: 18
    *wait* Time delay: 106373 seconds Block delay: 1856
    PropertiesMain.randApproveLP((92, 85, 99, 31, 11, 23, 21, 56, 46, 101, 179, 51746793834685217718915159233147486607, false),20,101,64,1000000001) Time delay: 56793 seconds Block delay: 2373
    *wait* Time delay: 20033 seconds Block delay: 1604
    PropertiesMain.balanceIntegrityLP((22, 4, 186, 17, 46, 239, 5, 13, 36, 4, 165, 29926313682612408841834869772256697104, false)) Time delay: 49095 seconds Block delay: 1191
    *wait* Time delay: 1500 seconds Block delay: 48
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 17537 seconds Block delay: 2004
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 75992 seconds Block delay: 1816
    PropertiesMain.integrityOfDepositCapMP() Time delay: 19594 seconds Block delay: 2973
    PropertiesMain.globalSolvencyCheckMP()
    PropertiesMain.randDepositLP((61, 21, 120, 63, 252, 76, 23, 48, 9, 22, 251, 340282366920938463463374607431768211454, false),119,53,164,189338994830026533054556434507718303737) Time delay: 16410 seconds Block delay: 6123
    PropertiesMain.randATokenNonRebasingBalanceOfLP((218, 91, 61, 44, 114, 98, 234, 202, 131, 49, 66, 42547545544205894621282675877922724581, false),209,8)
    PropertiesMain.userConfigurationMapIntegrityDebtLP() Time delay: 10589 seconds Block delay: 2995
    PropertiesMain.randApproveLP((14, 202, 252, 228, 156, 52, 135, 32, 251, 204, 46, 114818995174731659701937671920817812245, false),211,251,122,296996006901594644867784199148965096409) Time delay: 23961 seconds Block delay: 59
    PropertiesMain.randApproveDelegationMP((0, 75, 39, 182, 60, 1, 250, 0, 142, 99, 15, 204853812922766243866656266921576001063, false),88,10,18,109248533090072397444791473265635554940) Time delay: 68975 seconds Block delay: 3817
    PropertiesMain.randApproveDelegation((160, 136, 128, 27, 223, 16, 162, 28, 255, 65, 50, 45474251354481654647103089601350143095, false),170,79,117,340282366920938463463374607431768211451) Time delay: 32833 seconds Block delay: 1499
    *wait* Time delay: 50896 seconds Block delay: 4205
    PropertiesMain.randIncreaseAllowanceLP((97, 81, 183, 135, 175, 58, 99, 9, 10, 251, 98, 127, false),184,15,224,853) Time delay: 68548 seconds Block delay: 3175
    PropertiesMain.balanceIntegrityLP((39, 53, 204, 32, 21, 134, 49, 192, 17, 103, 101, 1499, true)) Time delay: 16422 seconds Block delay: 4001
    PropertiesMain.randRehypothecationRebalanceLP((163, 133, 96, 126, 198, 183, 3, 69, 159, 93, 45, 3725587545, false),57) Time delay: 40518 seconds Block delay: 1334
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 68381 seconds Block delay: 7905
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 8885 seconds Block delay: 155
    PropertiesMain.integrityOfDepositCapMP() Time delay: 22345 seconds Block delay: 6595
    PropertiesMain.userConfigurationMapIntegrityLiquidityMP() Time delay: 97 seconds Block delay: 6289
    PropertiesMain.globalSolvencyCheckMP() Time delay: 44199 seconds Block delay: 5609
    PropertiesMain.randDepositMP((247, 59, 96, 76, 77, 42, 19, 56, 128, 160, 96, 228064377410586537334482223197808707066, true),251,127,229,161,107460725225300182198561180835855911641)
    *wait* Time delay: 26306 seconds Block delay: 4271
    PropertiesMain.randApproveDelegation((161, 0, 47, 168, 45, 47, 52, 2, 70, 84, 109, 3858086694, false),59,109,10,36252518849789496248601044804203675554) Time delay: 32749 seconds Block delay: 6886
    PropertiesMain.randFlashloanLP((27, 46, 56, 43, 99, 168, 174, 121, 74, 6, 16, 142748233002699231789714144034948581340, false),210,6,97,141841084356140549604108764001634765285) Time delay: 32829 seconds Block delay: 2013
    PropertiesMain.randIncreaseAllowanceLP((91, 73, 0, 221, 45, 82, 21, 6, 91, 0, 16, 32608871624853548060204648289894181259, true),100,2,254,118841423752775725499610509794642832916) Time delay: 24845 seconds Block delay: 1000
    PropertiesMain.randATokenNonRebasingBalanceOfLP((96, 164, 239, 6, 83, 163, 61, 55, 84, 137, 254, 340282366920938463463374607431768211452, true),0,39)
    PropertiesMain.randIncreaseAllowanceLP((63, 71, 255, 216, 144, 136, 75, 253, 108, 4, 240, 20282409603651670423947251286014, true),0,180,86,24167152368241585393436888142395547883) Time delay: 44065 seconds Block delay: 1000
    PropertiesMain.randFlashloanLP((119, 254, 101, 97, 72, 10, 71, 91, 69, 170, 217, 2001, false),20,198,240,20315961015390186945755814444219827010) Time delay: 1625 seconds Block delay: 7638
    *wait* Time delay: 64217 seconds Block delay: 12656
    PropertiesMain.randForceFeedAssetLP((17, 45, 193, 58, 23, 137, 36, 130, 90, 18, 246, 170951238315782879192365757979439670040, true),0,22686124098288687756789007562988613583,0,205) Time delay: 80853 seconds Block delay: 2778
    *wait* Time delay: 49305 seconds Block delay: 5655
    PropertiesMain.randDepositLP((50, 28, 225, 15, 137, 178, 129, 230, 8, 49, 10, 43445184096927756827564567618329178462, false),85,19,58,22430397435322630793851728106451481110) Time delay: 33355 seconds Block delay: 64
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 72850 seconds Block delay: 3123
    PropertiesMain.userConfigurationMapIntegrityLiquidityMP() Time delay: 60 seconds Block delay: 2940
    PropertiesMain.integrityOfDepositCapLP() Time delay: 22347 seconds Block delay: 247
    PropertiesMain.randApproveDelegation((29, 186, 51, 1, 65, 51, 210, 164, 46, 52, 177, 2000, true),146,127,252,219370185916626208375389518100263220428) Time delay: 36623 seconds Block delay: 4990
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP()
    *wait* Time delay: 32600 seconds Block delay: 11177
    PropertiesMain.randApproveDelegation((85, 83, 223, 147, 20, 65, 28, 45, 151, 44, 199, 185734898011967261729354488764303580850, false),78,0,28,67817513437199845253698309006875224216) Time delay: 54902 seconds Block delay: 5973
    PropertiesMain.userConfigurationMapIntegrityDebtLP()
    *wait* Time delay: 40698 seconds Block delay: 11618
    PropertiesMain.integrityOfDepositCapMP() Time delay: 1000 seconds Block delay: 1393
    *wait* Time delay: 49340 seconds Block delay: 9605
    PropertiesMain.randIncreaseAllowanceLP((202, 127, 12, 19, 43, 77, 55, 31, 200, 59, 135, 3226110480, false),76,223,76,39659135788560133416502580048029340338) Time delay: 49714 seconds Block delay: 1602
    PropertiesMain.randForceFeedAssetLP((255, 160, 251, 93, 75, 16, 191, 170, 174, 92, 126, 59, true),45,2901483582711727430939014748117223726,11,0) Time delay: 44497 seconds Block delay: 5298
    *wait* Time delay: 47817 seconds Block delay: 6201
    PropertiesMain.randIncreaseAllowanceLP((205, 27, 71, 1, 90, 188, 13, 16, 181, 65, 71, 324879860964176408838154572557736282427, false),128,79,75,31536000)
    PropertiesMain.randIncreaseAllowanceLP((101, 8, 223, 223, 62, 184, 46, 254, 20, 251, 100, 58547694244009991545127547620113092044, false),113,65,241,2000000000000000000000000001)
    PropertiesMain.randBorrowMP((163, 107, 160, 97, 15, 227, 27, 5, 101, 40, 12, 396, false),160,253,201,148,254514895729817220124550746208945677513)
    PropertiesMain.globalSolvencyCheckLP() Time delay: 31117 seconds Block delay: 1376
    PropertiesMain.randATokenNonRebasingBalanceOfLP((78, 240, 204, 93, 140, 4, 43, 182, 51, 28, 86, 78130222440418693188066969854901020374, true),33,20) Time delay: 69621 seconds Block delay: 8533
    PropertiesMain.integrityOfDepositCapLP() Time delay: 13253 seconds Block delay: 7103
    *wait* Time delay: 35918 seconds Block delay: 4468
    PropertiesMain.globalSolvencyCheckMP()
    PropertiesMain.randIncreaseAllowanceLP((251, 10, 7, 229, 103, 86, 92, 210, 1, 70, 75, 214323844242845932592167267459204642827, true),53,8,27,14142660769521563) Time delay: 12702 seconds Block delay: 2956
    PropertiesMain.randApproveDelegationMP((114, 72, 108, 31, 103, 149, 19, 18, 135, 63, 87, 4722366482869645213694, false),72,223,187,72057594037927937) Time delay: 24845 seconds Block delay: 768
    PropertiesMain.integrityOfDepositCapMP() Time delay: 76402 seconds Block delay: 337
    *wait* Time delay: 58845 seconds Block delay: 2725
    PropertiesMain.indexIntegrityLP() Time delay: 9001 seconds Block delay: 5400
    PropertiesMain.indexIntegrityLP() Time delay: 53830 seconds Block delay: 2908
    PropertiesMain.indexIntegrityLP() Time delay: 163 seconds Block delay: 226
    *wait* Time delay: 91312 seconds Block delay: 11900
    PropertiesMain.userConfigurationMapIntegrityDebtLP() Time delay: 82759 seconds Block delay: 2818
    PropertiesMain.userConfigurationMapIntegrityDebtLP() Time delay: 64298 seconds Block delay: 3844
    PropertiesMain.globalSolvencyCheckLP() Time delay: 16932 seconds Block delay: 12
    *wait* Time delay: 123759 seconds Block delay: 9553
    PropertiesMain.randApproveDelegationMP((1, 100, 210, 145, 60, 254, 84, 254, 97, 26, 99, 2297858554, true),9,100,119,25211216368502631195275396259412321836) Time delay: 80272 seconds Block delay: 7524
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 84408 seconds Block delay: 2952
    PropertiesMain.randApproveDelegation((110, 131, 99, 75, 100, 32, 74, 239, 230, 114, 220, 92741386194380819229789077632652390793, false),129,16,16,7632539894910705571642096870987601716) Time delay: 32819 seconds Block delay: 6645
    PropertiesMain.randDepositLP((30, 209, 0, 128, 8, 3, 3, 29, 75, 11, 135, 37, false),93,7,118,10) Time delay: 32621 seconds Block delay: 5327
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 71862 seconds Block delay: 1501
    PropertiesMain.randApproveLP((4, 156, 17, 192, 56, 81, 157, 53, 18, 110, 251, 66922496976676288131115278524484224560, true),8,5,95,521) Time delay: 83328 seconds Block delay: 606
    *wait* Time delay: 208241 seconds Block delay: 14124
    PropertiesMain.randApproveLP((147, 11, 57, 16, 42, 5, 19, 76, 39, 64, 33, 7712827665616402644244349066841211240, false),13,139,9,150771420330225193602568039902426764451) Time delay: 60879 seconds Block delay: 2944
    *wait* Time delay: 78728 seconds Block delay: 1142
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 35892 seconds Block delay: 281
    PropertiesMain.randDepositLP((16, 10, 2, 71, 201, 18, 0, 238, 251, 13, 28, 364, false),60,7,50,4001) Time delay: 46622 seconds Block delay: 1447
    PropertiesMain.randDepositMP((41, 77, 174, 254, 195, 191, 3, 60, 122, 38, 137, 749999999999999999999999999, true),2,182,47,20,144115188075855873) Time delay: 1501 seconds Block delay: 1970
    PropertiesMain.globalSolvencyCheckLP() Time delay: 22846 seconds Block delay: 3200
    PropertiesMain.invariantRehypothecationLP()
    PropertiesMain.randDepositLP((135, 28, 17, 97, 253, 252, 58, 1, 70, 161, 65, 1999, false),101,59,242,431999) Time delay: 66671 seconds Block delay: 4120
    *wait* Time delay: 60534 seconds Block delay: 3878
    PropertiesMain.randDepositLP((32, 47, 4, 0, 253, 93, 18, 158, 220, 9, 238, 236399613077278740155940505039366952253, true),176,181,108,8001) Time delay: 68125 seconds Block delay: 3696
    PropertiesMain.randDepositLP((52, 2, 171, 62, 138, 33, 19, 48, 250, 224, 149, 43837413786125059998424035986326554457, false),253,238,209,53) Time delay: 54902 seconds Block delay: 6943
    PropertiesMain.randATokenNonRebasingBalanceOfLP((2, 46, 93, 185, 100, 127, 16, 254, 116, 38, 1, 64, true),40,161)
    *wait* Time delay: 40681 seconds Block delay: 1932
    PropertiesMain.randTransferMP((16, 234, 41, 76, 130, 12, 73, 61, 13, 63, 37, 750000000000000000000000000, true),22,159,143,64,46000000000000000001) Time delay: 36104 seconds Block delay: 53
    *wait* Time delay: 98076 seconds Block delay: 11681
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 5 seconds Block delay: 2001
    PropertiesMain.randDepositLP((59, 12, 125, 8, 58, 188, 177, 93, 161, 167, 163, 339961688742713983674434050036560752461, false),16,49,193,313927077866820058615873067832439383112)
    PropertiesMain.randDepositLP((83, 70, 50, 55, 253, 209, 9, 13, 47, 167, 145, 553, false),4,19,51,4999)
    PropertiesMain.globalSolvencyCheckMP()
    PropertiesMain.randForceFeedAssetLP((15, 205, 46, 32, 29, 250, 16, 73, 57, 39, 67, 75556710804409716572161, false),160,35198906285211575284428553643995308890,157,29)
    PropertiesMain.userConfigurationMapIntegrityLiquidityMP() Time delay: 64344 seconds Block delay: 2627
    
   """

string = 'tests/echidna/echidnaToFoundry/FoundryTestSequence.sol'
with open(string, 'w') as f:
    f.write(transform_text(input_text))

print("Done ::: the %s file has been generated." % string)