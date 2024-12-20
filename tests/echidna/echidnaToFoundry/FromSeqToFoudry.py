import re

def transform_text(input_text):
    output = []
    output.append("// SPDX-License-Identifier: MIT")
    output.append("pragma solidity ^0.8.13;")
    output.append("")
    output.append("import \"../PropertiesMain.sol\";")
    output.append("import \"../PropertiesBase.sol\";") 
    output.append("import \"forge-std/Test.sol\";")
    output.append("")
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
input_text = """   PropertiesMain.randApproveMP((208, 229, 5, 41, 32, 199, 210, 5, 75, 1, 92, 224, true),165,143,53,5,157198259) from: 0x0000000000000000000000000000000000010000 Time delay: 56422 seconds Block delay: 1234
    PropertiesMain.randIncreaseAllowanceLP((195, 18, 251, 97, 95, 47, 139, 127, 37, 6, 231, 331480418922820317996216655663103607818, false),171,9,161,10950824) from: 0x0000000000000000000000000000000000010000 Time delay: 11473 seconds Block delay: 59
    *wait* Time delay: 40681 seconds Block delay: 6646
    PropertiesMain.balanceIntegrityLP((38, 75, 224, 97, 112, 80, 105, 99, 59, 65, 83, 211787051686234132553877910386450331740, true)) from: 0x0000000000000000000000000000000000020000 Time delay: 23961 seconds Block delay: 2977
    *wait* Time delay: 61207 seconds Block delay: 4008
    PropertiesMain.randApproveDelegation((131, 95, 0, 129, 2, 190, 21, 72, 40, 0, 230, 5, true),11,235,165,70000000000000000000000000) from: 0x0000000000000000000000000000000000020000 Time delay: 54242 seconds Block delay: 77
    PropertiesMain.randRehypothecationRebalanceLP((65, 17, 17, 27, 100, 130, 204, 97, 165, 75, 93, 121029355650768047120685522461757678721, false),21) from: 0x0000000000000000000000000000000000030000 Time delay: 60723 seconds Block delay: 621
    *wait* Time delay: 126443 seconds Block delay: 6821
    PropertiesMain.randDepositLP((124, 64, 94, 179, 60, 124, 40, 253, 168, 58, 78, 340282366920938463463374607431768211451, true),88,125,200,223) from: 0x0000000000000000000000000000000000020000 Time delay: 72850 seconds Block delay: 2408
    PropertiesMain.randForceFeedAssetLP((9, 221, 88, 245, 9, 3, 101, 29, 8, 229, 0, 99999999999999999999999999999999, true),223,3000000000000000000000000000,55,126) from: 0x0000000000000000000000000000000000030000 Time delay: 2744 seconds Block delay: 2677
    PropertiesMain.randApproveLP((222, 223, 113, 26, 103, 5, 55, 63, 254, 42, 234, 1513845946, false),164,49,175,99488534965059224699413310674197875786) from: 0x0000000000000000000000000000000000020000 Time delay: 71557 seconds Block delay: 27
    *wait* Time delay: 30299 seconds Block delay: 1232
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000010000 Time delay: 76403 seconds Block delay: 595
    *wait* Time delay: 32844 seconds Block delay: 2971
    PropertiesMain.randRehypothecationRebalanceLP((147, 31, 69, 76, 57, 208, 225, 224, 183, 164, 31, 306178324328245921083310309498959983482, true),23) from: 0x0000000000000000000000000000000000010000 Time delay: 23961 seconds Block delay: 4804
    *wait* Time delay: 78821 seconds Block delay: 2998
    PropertiesMain.randATokenNonRebasingApproveLP((140, 52, 39, 56, 224, 12, 254, 199, 18, 18, 27, 659, false),196,75,85,165) from: 0x0000000000000000000000000000000000010000 Time delay: 75 seconds Block delay: 221
    *wait* Time delay: 22847 seconds Block delay: 7921
    PropertiesMain.randApproveDelegation((24, 116, 240, 170, 5, 27, 59, 242, 53, 27, 242, 3858086692, false),80,99,158,214728646673741649683592915683211341215) from: 0x0000000000000000000000000000000000010000 Time delay: 81227 seconds Block delay: 8122
    *wait* Time delay: 49306 seconds Block delay: 402
    PropertiesMain.randApproveDelegation((15, 128, 17, 32, 98, 102, 4, 83, 15, 86, 128, 2001, true),193,251,44,100000000000000000000000000000001) from: 0x0000000000000000000000000000000000020000 Time delay: 83354 seconds Block delay: 6600
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000020000 Time delay: 10049 seconds Block delay: 6296
    *wait* Time delay: 59956 seconds Block delay: 4003
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000020000 Time delay: 7710 seconds Block delay: 2749
    *wait* Time delay: 114621 seconds Block delay: 3161
    PropertiesMain.randRehypothecationRebalanceLP((45, 236, 3, 187, 224, 5, 205, 16, 145, 96, 201, 84181156204322141939909439679103977871, false),48) from: 0x0000000000000000000000000000000000010000 Time delay: 48014 seconds Block delay: 2408
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000020000 Time delay: 69657 seconds Block delay: 3783
    *wait* Time delay: 12082 seconds Block delay: 4949
    PropertiesMain.balanceIntegrityLP((32, 12, 77, 35, 56, 63, 37, 3, 13, 97, 211, 197962784693039651388021348953788764990, false)) from: 0x0000000000000000000000000000000000020000 Time delay: 75552 seconds Block delay: 5229
    PropertiesMain.randIncreaseAllowanceLP((222, 99, 41, 63, 58, 73, 254, 57, 252, 99, 7, 83281981611963724009267427569936817892, false),46,115,251,53) from: 0x0000000000000000000000000000000000010000 Time delay: 2000 seconds Block delay: 1005
    *wait* Time delay: 186492 seconds Block delay: 12309
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000030000 Time delay: 21374 seconds Block delay: 3645
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000030000 Time delay: 32591 seconds Block delay: 3725
    PropertiesMain.randApproveMP((68, 225, 29, 21, 64, 237, 164, 16, 39, 18, 74, 32, false),40,219,184,129,18) from: 0x0000000000000000000000000000000000020000 Time delay: 50698 seconds Block delay: 1772
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000010000 Time delay: 83623 seconds Block delay: 1818
    PropertiesMain.randForceFeedAssetLP((32, 255, 27, 5, 93, 45, 191, 17, 135, 215, 29, 75588992356565203791851515264941305091, true),61,131487547781901334629427301319422922386,63,127) from: 0x0000000000000000000000000000000000020000 Time delay: 82489 seconds Block delay: 3524
    *wait* Time delay: 167107 seconds Block delay: 24329
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000020000 Time delay: 34814 seconds Block delay: 6860
    *wait* Time delay: 78481 seconds Block delay: 2675
    PropertiesMain.randATokenNonRebasingApproveLP((228, 58, 188, 129, 102, 225, 104, 69, 238, 82, 167, 1513845945, false),179,166,83,83) from: 0x0000000000000000000000000000000000020000 Time delay: 27845 seconds Block delay: 7791
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000010000 Time delay: 6538 seconds Block delay: 8414
    *wait* Time delay: 81528 seconds Block delay: 4438
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000010000 Time delay: 49305 seconds Block delay: 7867
    PropertiesMain.randApproveLP((126, 0, 47, 224, 40, 99, 253, 30, 79, 208, 8, 117465952766340123235596638509226324540, true),34,246,187,243135741360440036778641167649762513770) from: 0x0000000000000000000000000000000000010000 Time delay: 47878 seconds Block delay: 3296
    *wait* Time delay: 106269 seconds Block delay: 9713
    PropertiesMain.randIncreaseAllowanceLP((77, 118, 44, 165, 223, 4, 118, 67, 55, 75, 191, 129999999999999999999, false),254,26,229,55859410204966926991600039811614493709) from: 0x0000000000000000000000000000000000010000 Time delay: 32829 seconds Block delay: 1450
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000010000 Time delay: 72624 seconds Block delay: 5286
    PropertiesMain.randRehypothecationRebalanceLP((28, 17, 8, 54, 51, 0, 221, 253, 190, 202, 96, 250688659670327381777800050051526447263, false),41) from: 0x0000000000000000000000000000000000010000 Time delay: 16667 seconds Block delay: 5360
    *wait* Time delay: 33355 seconds Block delay: 717
    PropertiesMain.randBorrowLP((10, 165, 237, 60, 51, 28, 47, 205, 4, 161, 182, 137857030844153070337, false),55,253,217,4722366482869645213694) from: 0x0000000000000000000000000000000000030000 Time delay: 32751 seconds Block delay: 3783
    PropertiesMain.randApproveDelegationMP((251, 154, 16, 1, 13, 32, 154, 121, 2, 83, 82, 158941824030900297821932968934821527953, false),40,39,254,3858086692) from: 0x0000000000000000000000000000000000010000 Time delay: 60881 seconds Block delay: 2927
    *wait* Time delay: 76569 seconds Block delay: 11652
    PropertiesMain.randIncreaseAllowanceLP((92, 41, 4, 190, 48, 8, 88, 40, 39, 65, 102, 0, true),8,95,199,300225887261959012694174758168105953345) from: 0x0000000000000000000000000000000000010000 Time delay: 40681 seconds Block delay: 6847
    *wait* Time delay: 79112 seconds Block delay: 2996
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 32032 seconds Block delay: 6848
    PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000030000 Time delay: 34166 seconds Block delay: 630
    PropertiesMain.randFlashloanLP((29, 111, 225, 252, 228, 33, 28, 48, 40, 130, 146, 1, false),20,82,8,130000000000000000000) from: 0x0000000000000000000000000000000000030000 Time delay: 58040 seconds Block delay: 28
    *wait* Time delay: 69532 seconds Block delay: 3530
    PropertiesMain.randDepositLP((225, 141, 7, 44, 36, 187, 45, 5, 19, 219, 85, 3000000000000000000000000000, false),127,45,240,0) from: 0x0000000000000000000000000000000000030000 Time delay: 81227 seconds Block delay: 327
    *wait* Time delay: 93534 seconds Block delay: 18361
    PropertiesMain.randDepositMP((83, 49, 192, 212, 30, 121, 90, 5, 80, 204, 166, 8499, true),224,47,0,16,2527694023419119584791204) from: 0x0000000000000000000000000000000000020000 Time delay: 81468 seconds Block delay: 1557
    PropertiesMain.randIncreaseAllowanceLP((16, 124, 78, 246, 83, 46, 194, 129, 34, 70, 131, 291976025836606357508282980588599425071, true),111,202,58,57647321269539967467859376230639981803) from: 0x0000000000000000000000000000000000010000 Time delay: 32763 seconds Block delay: 326
    *wait* Time delay: 78071 seconds Block delay: 11636
    PropertiesMain.randATokenNonRebasingApproveLP((64, 11, 253, 9, 159, 95, 32, 223, 47, 83, 66, 2304117921, false),161,244,164,129) from: 0x0000000000000000000000000000000000020000 Time delay: 56420 seconds Block delay: 4140
    *wait* Time delay: 132438 seconds Block delay: 13327
    PropertiesMain.randATokenNonRebasingBalanceOfLP((26, 7, 12, 26, 8, 56, 4, 61, 201, 211, 46, 223, false),45,60) from: 0x0000000000000000000000000000000000030000 Time delay: 71370 seconds Block delay: 1005
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000010000 Time delay: 60 seconds Block delay: 4758
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000020000 Time delay: 129 seconds Block delay: 5045
    PropertiesMain.randDepositMP((129, 68, 93, 33, 251, 17, 80, 100, 31, 217, 123, 340282366920938463463374607431768211454, true),196,48,4,163,206016472122027160160793903914740153539) from: 0x0000000000000000000000000000000000010000 Time delay: 40136 seconds Block delay: 328
    *wait* Time delay: 28712 seconds Block delay: 8577
    PropertiesMain.balanceIntegrityLP((212, 99, 129, 51, 9, 129, 5, 255, 9, 104, 139, 141907550092936123757029828965107113947, true)) from: 0x0000000000000000000000000000000000010000 Time delay: 51133 seconds Block delay: 6348
    *wait* Time delay: 15 seconds Block delay: 2678
    PropertiesMain.randApproveDelegationMP((244, 151, 123, 21, 19, 53, 221, 7, 119, 13, 54, 932, true),85,68,188,206250261669788515122451869359934715274) from: 0x0000000000000000000000000000000000010000 Time delay: 32621 seconds Block delay: 47
    PropertiesMain.randApproveMP((253, 15, 141, 251, 160, 225, 129, 0, 13, 76, 93, 65536, true),6,48,146,7,213172705580863229722421592710095432707) from: 0x0000000000000000000000000000000000020000 Time delay: 8501 seconds Block delay: 4043
    *wait* Time delay: 74189 seconds Block delay: 7515
    PropertiesMain.balanceIntegrityLP((70, 142, 190, 118, 163, 6, 11, 13, 29, 33, 132, 750000000000000000000000000, false)) from: 0x0000000000000000000000000000000000010000 Time delay: 24008 seconds Block delay: 6844
    PropertiesMain.randDepositMP((142, 75, 96, 166, 95, 55, 83, 254, 49, 39, 46, 273495236032054538980738115951354833664, true),250,2,39,129,182660709228169656047254987756046517227) from: 0x0000000000000000000000000000000000030000 Time delay: 32833 seconds Block delay: 2959
    *wait* Time delay: 86395 seconds Block delay: 6707
    PropertiesMain.randATokenNonRebasingApproveLP((157, 182, 215, 91, 0, 78, 190, 227, 102, 99, 180, 259490611036414510785381847531025848362, false),92,51,56,1000000000) from: 0x0000000000000000000000000000000000030000 Time delay: 32750 seconds Block delay: 7442
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000020000 Time delay: 75047 seconds Block delay: 1553
    *wait* Time delay: 17 seconds Block delay: 2000
    PropertiesMain.randRehypothecationRebalanceLP((238, 228, 228, 164, 84, 18, 85, 76, 205, 225, 47, 305331874590177833231615090755724413283, true),46) from: 0x0000000000000000000000000000000000030000 Time delay: 7 seconds Block delay: 7539
    *wait* Time delay: 36014 seconds Block delay: 5172
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000030000 Time delay: 13377 seconds Block delay: 3447
    *wait* Time delay: 21 seconds Block delay: 3005
    PropertiesMain.randRehypothecationRebalanceLP((168, 93, 93, 92, 8, 139, 144, 91, 159, 65, 55, 175422070998419010188617177576459464177, true),51) from: 0x0000000000000000000000000000000000030000 Time delay: 21088 seconds Block delay: 4785
    *wait* Time delay: 82509 seconds Block delay: 2640
    PropertiesMain.randDepositLP((214, 8, 85, 138, 8, 165, 32, 254, 137, 128, 128, 44192829903815909566362688415202944505, true),221,31,20,99584408515318050749348825632594721538) from: 0x0000000000000000000000000000000000030000 Time delay: 8886 seconds Block delay: 5857
    PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000010000 Time delay: 32621 seconds Block delay: 6036
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000010000 Time delay: 9000 seconds Block delay: 337
    PropertiesMain.randWithdrawLP((63, 5, 94, 59, 183, 70, 48, 3, 65, 128, 48, 64, false),75,86,164,39343507628001565568230361069503330233) from: 0x0000000000000000000000000000000000010000 Time delay: 21087 seconds Block delay: 1970
    PropertiesMain.randApproveMP((19, 21, 65, 59, 11, 8, 99, 28, 184, 84, 107, 1114277010, true),77,95,26,85,9) from: 0x0000000000000000000000000000000000010000 Time delay: 8501 seconds Block delay: 7973
    PropertiesMain.randDepositMP((19, 183, 166, 47, 187, 65, 51, 251, 48, 122, 198, 56, false),223,21,42,177,15) from: 0x0000000000000000000000000000000000020000 Time delay: 43674 seconds Block delay: 2000
    *wait* Time delay: 66147 seconds Block delay: 6200
    PropertiesMain.randBorrowLP((6, 91, 64, 20, 93, 8, 30, 228, 93, 65, 0, 96, false),52,61,115,26566403025) from: 0x0000000000000000000000000000000000030000 Time delay: 9629 seconds Block delay: 3490
    PropertiesMain.balanceIntegrityMP((7, 170, 93, 201, 35, 47, 22, 101, 158, 206, 11, 310086464381011713799004772745219778820, false)) from: 0x0000000000000000000000000000000000010000 Time delay: 32814 seconds Block delay: 7233
    PropertiesMain.randATokenNonRebasingTransferLP((20, 82, 85, 251, 101, 183, 163, 127, 106, 201, 253, 2304117922, true),127,21,28,750000000000000000000000001) from: 0x0000000000000000000000000000000000010000 Time delay: 76402 seconds Block delay: 4205
    PropertiesMain.randForceFeedAssetLP((185, 225, 121, 5, 240, 214, 100, 254, 71, 53, 112, 4012859179, true),231,3226110479,46,56) from: 0x0000000000000000000000000000000000020000 Time delay: 48 seconds Block delay: 2928
    *wait* Time delay: 113314 seconds Block delay: 284
    PropertiesMain.randDepositLP((6, 164, 37, 101, 108, 65, 190, 161, 159, 8, 104, 51403719232320662386945405155504860668, true),137,6,40,203933354784856372420521383559695259614) from: 0x0000000000000000000000000000000000010000 Time delay: 53711 seconds Block delay: 48
    *wait* Time delay: 10499 seconds Block delay: 96
    PropertiesMain.randForceFeedAssetLP((90, 241, 248, 20, 142, 140, 225, 254, 38, 253, 129, 133007534789816507343379479163702354830, false),224,668,70,49) from: 0x0000000000000000000000000000000000030000 Time delay: 32841 seconds Block delay: 29
    *wait* Time delay: 125150 seconds Block delay: 12905
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 58366 seconds Block delay: 1837
    *wait* Time delay: 17538 seconds Block delay: 2904
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000020000 Time delay: 224 seconds Block delay: 7920
    PropertiesMain.randApproveDelegation((47, 57, 84, 2, 95, 92, 5, 21, 15, 12, 252, 75556710804409716572161, true),46,140,35,53) from: 0x0000000000000000000000000000000000010000 Time delay: 21013 seconds Block delay: 223
    *wait* Time delay: 420103 seconds Block delay: 35056
    PropertiesMain.randDepositMP((38, 13, 252, 138, 93, 179, 254, 138, 16, 21, 28, 185379997337707705778692728290839877108, true),150,90,46,2,3305345829) from: 0x0000000000000000000000000000000000010000 Time delay: 65004 seconds Block delay: 2971
    PropertiesMain.randForceFeedATokensLP((39, 163, 222, 194, 127, 3, 55, 91, 61, 195, 216, 3305345829, true),160,115,92,164,177) from: 0x0000000000000000000000000000000000030000 Time delay: 18821 seconds Block delay: 2725
    PropertiesMain.balanceIntegrityMP((84, 64, 110, 10, 84, 180, 209, 1, 0, 58, 108, 24404150380937476687338283891234625743, false)) from: 0x0000000000000000000000000000000000010000 Time delay: 35780 seconds Block delay: 5837
    *wait* Time delay: 2 seconds Block delay: 868
    PropertiesMain.randApproveDelegationMP((33, 93, 195, 155, 225, 192, 253, 6, 11, 28, 16, 1774647075, true),56,18,177,170505318369057591928196393461912786411) from: 0x0000000000000000000000000000000000010000 Time delay: 34660 seconds Block delay: 2
    *wait* Time delay: 68548 seconds Block delay: 1000
    PropertiesMain.randForceFeedAssetLP((4, 52, 64, 45, 163, 235, 61, 184, 144, 47, 84, 183049328180519380731393844040474799090, true),251,2757214935,17,223) from: 0x0000000000000000000000000000000000010000 Time delay: 9001 seconds Block delay: 1403
    *wait* Time delay: 84778 seconds Block delay: 2876
    PropertiesMain.randATokenNonRebasingTransferFromLP((114, 154, 98, 115, 31, 148, 161, 29, 165, 46, 92, 28, true),55,76,59,44,340282366920938463463374607431768211454) from: 0x0000000000000000000000000000000000030000 Time delay: 56938 seconds Block delay: 2942
    PropertiesMain.randApproveDelegation((9, 12, 29, 16, 129, 165, 252, 75, 252, 110, 165, 291503605525841526958835153407386746170, true),38,31,58,10950824) from: 0x0000000000000000000000000000000000020000 Time delay: 32771 seconds Block delay: 2958
    PropertiesMain.randApproveLP((28, 127, 95, 5, 52, 229, 146, 214, 159, 85, 134, 23988087880024335790930660968442977277, false),22,29,246,111568424927003989234967863669656038422) from: 0x0000000000000000000000000000000000020000 Time delay: 34166 seconds Block delay: 1402
    PropertiesMain.randBorrowLP((86, 253, 39, 20, 6, 118, 148, 227, 182, 85, 40, 164, false),93,2,56,432000) from: 0x0000000000000000000000000000000000020000 Time delay: 25135 seconds Block delay: 652
    *wait* Time delay: 32801 seconds Block delay: 6034
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000010000 Time delay: 57 seconds Block delay: 2667
    PropertiesMain.randRehypothecationRebalanceLP((74, 96, 85, 10, 165, 5, 92, 7, 133, 107, 128, 2129999999999999999999999999, true),227) from: 0x0000000000000000000000000000000000030000 Time delay: 69532 seconds Block delay: 159
    PropertiesMain.randForceFeedATokensLP((39, 163, 222, 194, 127, 3, 55, 91, 61, 195, 216, 3305345829, true),160,115,92,164,177) from: 0x0000000000000000000000000000000000010000 Time delay: 16423 seconds Block delay: 6840
    *wait* Time delay: 84406 seconds Block delay: 8154
    PropertiesMain.randIncreaseAllowanceLP((74, 64, 7, 221, 21, 138, 40, 252, 222, 155, 254, 2129999999999999999999999999, true),58,58,92,31884187684239770784939637377413075927) from: 0x0000000000000000000000000000000000020000 Time delay: 32844 seconds Block delay: 2841
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 46623 seconds Block delay: 1934
    PropertiesMain.randIncreaseAllowanceLP((254, 1, 137, 57, 110, 28, 12, 124, 193, 145, 6, 333330530046570944762925866135026375788, true),85,13,29,260) from: 0x0000000000000000000000000000000000030000 Time delay: 32031 seconds Block delay: 6577
    PropertiesMain.randATokenNonRebasingApproveLP((29, 1, 63, 163, 80, 77, 56, 99, 15, 0, 30, 340282366920938463463374607431768211452, false),0,47,96,100564918818876359581265102222805488808) from: 0x0000000000000000000000000000000000030000 Time delay: 32793 seconds Block delay: 8121
    PropertiesMain.randForceFeedAssetLP((216, 8, 6, 32, 57, 251, 56, 217, 27, 253, 3, 31412307794537861358108981610105988739, true),208,263635600473058731983442044859989775761,216,13) from: 0x0000000000000000000000000000000000030000 Time delay: 18823 seconds Block delay: 6653
    PropertiesMain.randSetUseReserveAsCollateralLP((252, 58, 231, 11, 48, 129, 197, 215, 220, 171, 128, 4951684599277795185273077762, true),3,212,false) from: 0x0000000000000000000000000000000000010000 Time delay: 79112 seconds Block delay: 1359
    PropertiesMain.randApproveDelegation((28, 110, 20, 166, 15, 56, 75, 39, 172, 65, 73, 7, false),99,92,189,104013910121842198863090381096820869492) from: 0x0000000000000000000000000000000000030000 Time delay: 69657 seconds Block delay: 1145
    *wait* Time delay: 23686 seconds Block delay: 45
    PropertiesMain.randDepositLP((165, 100, 6, 5, 170, 52, 127, 14, 37, 249, 95, 227605828963050347471998891856592502877, false),60,95,189,268254502960634545340185791206924221292) from: 0x0000000000000000000000000000000000020000 Time delay: 6 seconds Block delay: 6560
    PropertiesMain.randFlashloanLP((61, 192, 190, 152, 252, 159, 87, 255, 46, 18, 213, 340282366920938463463374607431768211453, true),91,101,18,165) from: 0x0000000000000000000000000000000000030000 Time delay: 37374 seconds Block delay: 7442
    PropertiesMain.randApproveLP((51, 12, 54, 27, 32, 187, 21, 31, 53, 97, 253, 4392673442063432250692702082908131726, true),150,163,154,749999999999999999999999999) from: 0x0000000000000000000000000000000000030000 Time delay: 7999 seconds Block delay: 3747
    PropertiesMain.integrityOfDepositCapMP() from: 0x0000000000000000000000000000000000030000 Time delay: 71233 seconds Block delay: 5445
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000030000 Time delay: 86021 seconds Block delay: 6294
    PropertiesMain.randRepayLP((59, 253, 129, 113, 41, 74, 223, 4, 6, 84, 41, 340282366920938463463374607431768211452, false),56,254,16,14748393186666212867487059486437605413) from: 0x0000000000000000000000000000000000010000 Time delay: 32805 seconds Block delay: 7861
    PropertiesMain.randApproveDelegation((253, 33, 129, 39, 6, 121, 169, 248, 173, 53, 198, 422654419819300880896, false),92,10,238,63896810947383556969851914094694933767) from: 0x0000000000000000000000000000000000020000 Time delay: 52013 seconds Block delay: 3447
    *wait* Time delay: 40427 seconds Block delay: 1934
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000030000 Time delay: 32829 seconds Block delay: 4043
    *wait* Time delay: 79351 seconds Block delay: 326
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000020000 Time delay: 32767 seconds Block delay: 39
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000030000 Time delay: 41910 seconds Block delay: 2927
    PropertiesMain.randATokenNonRebasingBalanceOfLP((225, 7, 12, 95, 48, 3, 6, 202, 173, 169, 95, 82414882158374946631009924383919690498, false),112,242) from: 0x0000000000000000000000000000000000010000 Time delay: 69531 seconds Block delay: 7503
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000030000 Time delay: 15916 seconds Block delay: 1451
    PropertiesMain.randApproveDelegationMP((3, 127, 4, 186, 184, 31, 8, 197, 19, 145, 237, 174579126761133898752761917522327386987, false),252,251,84,99) from: 0x0000000000000000000000000000000000020000 Time delay: 83969 seconds Block delay: 8153
    PropertiesMain.randApproveLP((27, 54, 99, 129, 255, 57, 101, 216, 107, 132, 28, 961581906, false),63,15,64,61828970454108598199048935852122645917) from: 0x0000000000000000000000000000000000010000 Time delay: 8500 seconds Block delay: 4447
    *wait* Time delay: 204987 seconds Block delay: 22389
    PropertiesMain.randDepositLP((5, 40, 247, 20, 93, 163, 194, 60, 192, 236, 143, 226942849784917209310975793206871381055, true),7,48,2,9431501804307174799881650281458117341) from: 0x0000000000000000000000000000000000020000 Time delay: 85079 seconds Block delay: 1
    PropertiesMain.randForceFeedAssetLP((58, 52, 99, 197, 56, 1, 31, 111, 22, 65, 97, 326824799652157341258287971368319958065, false),104,461506751594809913927138899725552676,108,15) from: 0x0000000000000000000000000000000000010000 Time delay: 62455 seconds Block delay: 3054
    PropertiesMain.randSetUseReserveAsCollateralLP((147, 74, 150, 68, 200, 125, 126, 177, 51, 36, 182, 340282366920938463463374607431768211452, false),44,2,false) from: 0x0000000000000000000000000000000000030000 Time delay: 32806 seconds Block delay: 2958
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000020000 Time delay: 60879 seconds Block delay: 226
    PropertiesMain.randDepositMP((180, 77, 187, 75, 29, 253, 220, 74, 224, 245, 252, 164932600553061042957385055658381135604, true),11,187,251,242,931818775) from: 0x0000000000000000000000000000000000030000 Time delay: 46881 seconds Block delay: 330
    *wait* Time delay: 10005 seconds Block delay: 58
    PropertiesMain.randRehypothecationRebalanceLP((14, 181, 127, 65, 51, 127, 3, 95, 72, 63, 47, 157011382, true),75) from: 0x0000000000000000000000000000000000020000 Time delay: 65416 seconds Block delay: 2844
    *wait* Time delay: 7496 seconds Block delay: 2722
    PropertiesMain.randApproveDelegation((129, 101, 253, 145, 99, 74, 51, 40, 1, 104, 52, 77, false),29,32,69,5) from: 0x0000000000000000000000000000000000030000 Time delay: 31847 seconds Block delay: 300
    PropertiesMain.randATokenNonRebasingBalanceOfLP((56, 15, 224, 185, 77, 161, 46, 67, 51, 96, 11, 15001, false),155,139) from: 0x0000000000000000000000000000000000020000 Time delay: 62825 seconds Block delay: 8640
    *wait* Time delay: 66671 seconds Block delay: 2941
    PropertiesMain.randSetUseReserveAsCollateralMP((75, 55, 148, 206, 20, 193, 0, 128, 50, 59, 2, 405, true),93,55,193,false) from: 0x0000000000000000000000000000000000030000 Time delay: 48015 seconds Block delay: 4046
    *wait* Time delay: 23685 seconds Block delay: 18
    PropertiesMain.randForceFeedATokensLP((231, 197, 162, 83, 61, 96, 253, 0, 2, 65, 224, 31537706391308531813223333529590537892, true),10,52,248779382523408090426443746155399828197,234,29) from: 0x0000000000000000000000000000000000010000 Time delay: 75184 seconds Block delay: 2004
    PropertiesMain.randRehypothecationRebalanceLP((165, 47, 173, 250, 0, 91, 92, 82, 45, 28, 210, 157011382, false),74) from: 0x0000000000000000000000000000000000020000 Time delay: 75573 seconds Block delay: 571
    PropertiesMain.randDepositMP((179, 112, 28, 13, 82, 58, 15, 58, 163, 254, 225, 10555206164924217733779292548566539678, false),208,82,49,225,70000000000000000000000001) from: 0x0000000000000000000000000000000000010000 Time delay: 13253 seconds Block delay: 3231
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000010000 Time delay: 45643 seconds Block delay: 2965
    *wait* Time delay: 34166 seconds Block delay: 6886
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000010000 Time delay: 32837 seconds Block delay: 5974
    PropertiesMain.randTransferMP((5, 245, 49, 36, 56, 47, 85, 159, 91, 64, 254, 599290589, true),162,135,84,226,4722366482869645213695) from: 0x0000000000000000000000000000000000020000 Time delay: 84007 seconds Block delay: 533
    PropertiesMain.randApproveMP((0, 57, 65, 13, 96, 84, 82, 19, 92, 11, 159, 72057594037927937, false),163,40,96,33,182837927602140450046228576098332464110) from: 0x0000000000000000000000000000000000010000 Time delay: 17847 seconds Block delay: 7601
    PropertiesMain.randFlashloanLP((91, 247, 0, 11, 55, 254, 176, 153, 0, 127, 61, 322443447928629392245910249107370100872, true),28,163,95,961581905) from: 0x0000000000000000000000000000000000030000 Time delay: 8500 seconds Block delay: 2958
    *wait* Time delay: 83405 seconds Block delay: 4757
    PropertiesMain.randIncreaseAllowanceLP((213, 254, 45, 58, 101, 76, 65, 60, 127, 187, 46, 87, false),49,17,59,320) from: 0x0000000000000000000000000000000000010000 Time delay: 14999 seconds Block delay: 3747
    PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000010000 Time delay: 32356 seconds Block delay: 7919
    PropertiesMain.randApproveDelegationMP((224, 7, 93, 18, 57, 52, 190, 253, 252, 92, 9, 214972767508723774559014466309695066586, false),154,96,208,189041169728045472945367071725597048762) from: 0x0000000000000000000000000000000000020000 Time delay: 3 seconds Block delay: 4949
    PropertiesMain.randApproveLP((76, 129, 21, 164, 4, 15, 102, 222, 56, 11, 224, 288230376151711744, true),187,21,252,334721235119589601638163210182382699239) from: 0x0000000000000000000000000000000000010000 Time delay: 53710 seconds Block delay: 5966
    *wait* Time delay: 144773 seconds Block delay: 16911
    PropertiesMain.randFlashloanLP((30, 100, 5, 13, 61, 179, 196, 232, 96, 254, 217, 165, false),174,106,30,340282366920938463463374607431768211452) from: 0x0000000000000000000000000000000000010000 Time delay: 78727 seconds Block delay: 5049
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000020000 Time delay: 29237 seconds Block delay: 2909
    *wait* Time delay: 126352 seconds Block delay: 11887
    PropertiesMain.randApproveDelegationMP((11, 58, 98, 31, 207, 223, 52, 172, 150, 182, 190, 749999999999999999999999999, false),230,243,20,290472553868502617022171117611583755734) from: 0x0000000000000000000000000000000000020000 Time delay: 62454 seconds Block delay: 6859
    *wait* Time delay: 69659 seconds Block delay: 6438
    PropertiesMain.randATokenNonRebasingBalanceOfLP((110, 15, 83, 1, 254, 205, 9, 106, 202, 86, 99, 73932299302530200096609607372776687200, true),253,27) from: 0x0000000000000000000000000000000000010000 Time delay: 46942 seconds Block delay: 2716
    PropertiesMain.randForceFeedATokensMP((56, 224, 7, 95, 33, 91, 23, 156, 240, 87, 97, 340282366920938463463374607431768211454, false),235,219,2708836571,2,false) from: 0x0000000000000000000000000000000000010000 Time delay: 32826 seconds Block delay: 8640
    PropertiesMain.randATokenNonRebasingBalanceOfLP((122, 237, 86, 243, 163, 1, 133, 195, 237, 58, 58, 733, true),63,46) from: 0x0000000000000000000000000000000000030000 Time delay: 36721 seconds Block delay: 7866
    PropertiesMain.randRehypothecationRebalanceLP((108, 129, 17, 252, 165, 165, 57, 65, 27, 17, 186, 227385002318838541568326066276347914469, false),75) from: 0x0000000000000000000000000000000000030000 Time delay: 62310 seconds Block delay: 3854
    *wait* Time delay: 32592 seconds Block delay: 3913
    PropertiesMain.randSetUseReserveAsCollateralMP((144, 251, 161, 18, 123, 92, 54, 68, 77, 64, 100, 4012859179, false),61,60,211,false) from: 0x0000000000000000000000000000000000010000 Time delay: 815 seconds Block delay: 2912
    PropertiesMain.randFlashloanLP((15, 165, 224, 2, 78, 107, 220, 182, 58, 210, 39, 4722366482869645213696, true),101,6,165,340282366920938463463374607431768211451) from: 0x0000000000000000000000000000000000010000 Time delay: 32836 seconds Block delay: 7178
    *wait* Time delay: 129 seconds Block delay: 6200
    PropertiesMain.randATokenNonRebasingApproveLP((96, 12, 5, 246, 9, 186, 174, 85, 59, 254, 85, 28949858258243279678364464131809718034, false),39,173,15,1774647077) from: 0x0000000000000000000000000000000000010000 Time delay: 18826 seconds Block delay: 6696
    *wait* Time delay: 32805 seconds Block delay: 8280
    PropertiesMain.indexIntegrityLP() from: 0x0000000000000000000000000000000000020000 Time delay: 35623 seconds Block delay: 3371
    PropertiesMain.randFlashloanLP((174, 251, 11, 253, 33, 108, 91, 253, 32, 59, 162, 1524785992, true),164,46,138,198) from: 0x0000000000000000000000000000000000010000 Time delay: 60880 seconds Block delay: 2780
    PropertiesMain.randApproveDelegation((234, 9, 251, 11, 43, 164, 58, 165, 73, 238, 52, 140117483086901141870217551709891140353, true),16,223,95,70000000000000000000000000) from: 0x0000000000000000000000000000000000020000 Time delay: 22847 seconds Block delay: 999
    PropertiesMain.randRehypothecationRebalanceLP((32, 23, 62, 221, 97, 4, 147, 25, 161, 20, 21, 254409456970973098928920722902766044853, false),129) from: 0x0000000000000000000000000000000000010000 Time delay: 223 seconds Block delay: 7898
    PropertiesMain.invariantRehypothecationLP() from: 0x0000000000000000000000000000000000020000 Time delay: 48016 seconds Block delay: 220
    PropertiesMain.randForceFeedATokensLP((48, 11, 45, 44, 223, 41, 41, 228, 83, 5, 226, 308714094350756366598019219822542183430, true),97,11,91049709609021683746606178325742643351,21,237) from: 0x0000000000000000000000000000000000010000 Time delay: 49305 seconds Block delay: 4951
    PropertiesMain.randDepositLP((57, 11, 201, 245, 212, 252, 171, 83, 38, 95, 0, 4722366482869645213694, true),138,203,111,432000) from: 0x0000000000000000000000000000000000020000 Time delay: 71371 seconds Block delay: 4460
    PropertiesMain.globalSolvencyCheckMP() from: 0x0000000000000000000000000000000000030000 Time delay: 23961 seconds Block delay: 1358
    *wait* Time delay: 165393 seconds Block delay: 27878
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000020000 Time delay: 73515 seconds Block delay: 7553
    PropertiesMain.randBorrowMP((41, 98, 164, 229, 250, 39, 171, 216, 143, 253, 47, 3000000000000000000000000000, false),31,0,254,129,16) from: 0x0000000000000000000000000000000000010000 Time delay: 21472 seconds Block delay: 2678
    PropertiesMain.randApproveMP((40, 159, 20, 7, 47, 95, 55, 101, 169, 52, 56, 1001, false),218,224,130,53,128065036400998170023726207952591868322) from: 0x0000000000000000000000000000000000030000 Time delay: 3 seconds Block delay: 3146
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000010000 Time delay: 34840 seconds Block delay: 413
    *wait* Time delay: 82759 seconds Block delay: 1233
    PropertiesMain.randBorrowLP((47, 64, 95, 64, 17, 225, 56, 28, 91, 33, 209, 7650911349247085624743333541774296335, true),93,53,33,53) from: 0x0000000000000000000000000000000000020000 Time delay: 14023 seconds Block delay: 7442
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000010000 Time delay: 17845 seconds Block delay: 2725
    *wait* Time delay: 70572 seconds Block delay: 7625
    PropertiesMain.randRehypothecationRebalanceLP((167, 12, 47, 151, 28, 220, 237, 29, 11, 32, 182, 71515978643968147880334926789847602182, false),185) from: 0x0000000000000000000000000000000000020000 Time delay: 44498 seconds Block delay: 4046
    *wait* Time delay: 6 seconds Block delay: 8533
    PropertiesMain.randDepositLP((190, 76, 4, 224, 127, 111, 5, 60, 64, 27, 213, 60, true),42,127,40,72057594037927936) from: 0x0000000000000000000000000000000000030000 Time delay: 13254 seconds Block delay: 2999
    *wait* Time delay: 144826 seconds Block delay: 19467
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000030000 Time delay: 25077 seconds Block delay: 28
    *wait* Time delay: 225703 seconds Block delay: 17774
    PropertiesMain.randATokenNonRebasingBalanceOfLP((128, 5, 9, 180, 250, 129, 83, 45, 128, 129, 246, 139343887422500084728061707903916044268, false),173,140) from: 0x0000000000000000000000000000000000020000 Time delay: 62454 seconds Block delay: 7599
    *wait* Time delay: 45645 seconds Block delay: 695
    PropertiesMain.integrityOfDepositCapLP() from: 0x0000000000000000000000000000000000020000 Time delay: 72850 seconds Block delay: 301
    *wait* Time delay: 19592 seconds Block delay: 7866
    PropertiesMain.globalSolvencyCheckLP() from: 0x0000000000000000000000000000000000010000 Time delay: 44498 seconds Block delay: 8332
    *wait* Time delay: 75660 seconds Block delay: 4826
    PropertiesMain.randApproveMP((157, 2, 105, 242, 7, 223, 236, 230, 13, 159, 93, 260645152080814653486572954429084682287, false),20,27,31,64,3000000000000000000000000001) from: 0x0000000000000000000000000000000000010000 Time delay: 80852 seconds Block delay: 226
    PropertiesMain.randForceFeedATokensLP((221, 0, 31, 180, 159, 205, 32, 47, 64, 57, 96, 310399856643845594062252202401609946831, false),9,55,100000000000000000001,7,251) from: 0x0000000000000000000000000000000000010000 Time delay: 32 seconds Block delay: 1504
    *wait* Time delay: 38019 seconds Block delay: 5049
    PropertiesMain.randApproveDelegation((234, 9, 251, 11, 43, 164, 58, 165, 73, 238, 52, 140117483086901141870217551709891140353, true),16,223,95,70000000000000000000000000) from: 0x0000000000000000000000000000000000030000 Time delay: 85242 seconds Block delay: 300
    PropertiesMain.userDebtIntegrityMP() from: 0x0000000000000000000000000000000000020000 Time delay: 22847 seconds Block delay: 2975
    *wait* Time delay: 76855 seconds Block delay: 11302
    PropertiesMain.randBorrowLP((17, 0, 84, 48, 95, 113, 180, 84, 53, 139, 91, 42952603902358316973025163089853986403, true),248,173,131,10000000000000000000000001) from: 0x0000000000000000000000000000000000020000 Time delay: 60881 seconds Block delay: 1603

"""

string = 'tests/echidna/echidnaToFoundry/echidnaToFoundry.sol'
with open(string, 'w') as f:
    f.write(transform_text(input_text))

print("Done ::: the %s file has been generated." % string)