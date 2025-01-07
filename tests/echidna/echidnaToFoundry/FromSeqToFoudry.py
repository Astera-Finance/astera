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
input_text = """        PropertiesMain.userConfigurationMapIntegrityLiquidityLP()
    PropertiesMain.randApproveMP((23, 3, 34, 7, 185, 188, 13, 37, 68, 15, 233, 8000, false),54,0,58,124,161996569505584861824992575397343759821)
    PropertiesMain.randDepositLP((99, 11, 233, 128, 91, 138, 33, 205, 132, 125, 255, 288230376151711745, false),9,251,196,319489586722768322494058480292276437960) Time delay: 62310 seconds Block delay: 2779
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 14299 seconds Block delay: 6349
    PropertiesMain.randDepositMP((22, 121, 99, 193, 216, 11, 44, 12, 132, 60, 28, 77507239986625076067294359011081772938, true),85,150,85,130,287551094376422544245156328420653708976) Time delay: 85203 seconds Block delay: 1216
    PropertiesMain.userConfigurationMapIntegrityDebtLP()
    PropertiesMain.balanceIntegrityMP((38, 61, 16, 25, 59, 5, 2, 215, 41, 46, 72, 10211031725069638327912689960430323101, false)) Time delay: 8832 seconds Block delay: 638
    PropertiesMain.integrityOfDepositCapLP()
    PropertiesMain.randATokenNonRebasingApproveLP((7, 119, 65, 32, 10, 38, 11, 100, 3, 2, 222, 37605905037815459132019520105447212090, false),4,1,208,3898796210) Time delay: 46622 seconds Block delay: 4759
    *wait* Time delay: 95564 seconds Block delay: 16323
    PropertiesMain.integrityOfDepositCapMP()
    *wait* Time delay: 68963 seconds Block delay: 3986
    PropertiesMain.randFlashloanLP((12, 56, 1, 141, 101, 12, 223, 90, 207, 160, 161, 20750477666298616995502764467272820362, true),13,90,223,164) Time delay: 20 seconds Block delay: 533
    PropertiesMain.randApproveDelegation((180, 129, 2, 17, 159, 0, 101, 71, 68, 27, 64, 20572047950394613250954051800198127865, false),64,17,81,4107696312)
    *wait* Time delay: 4011 seconds Block delay: 2912
    PropertiesMain.randIncreaseAllowanceLP((203, 43, 10, 53, 77, 133, 14, 23, 0, 100, 18, 287760096374733335756673257419790389982, false),68,115,165,28) Time delay: 2001 seconds Block delay: 7260
    PropertiesMain.randATokenNonRebasingBalanceOfLP((70, 37, 164, 140, 6, 56, 17, 128, 163, 142, 11, 258158514, true),25,225) Time delay: 13 seconds Block delay: 8568
    PropertiesMain.randDepositLP((105, 129, 99, 51, 17, 81, 97, 0, 163, 27, 154, 129, true),92,129,96,4) Time delay: 7832 seconds Block delay: 2034
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 30300 seconds Block delay: 4798
    PropertiesMain.integrityOfDepositCapLP() Time delay: 13427 seconds Block delay: 3540
    PropertiesMain.randApproveLP((44, 255, 190, 1, 57, 14, 42, 4, 171, 2, 45, 154151862604076946056839735192885441772, false),51,162,26,500000000000000000000000000) Time delay: 80854 seconds Block delay: 6887
    PropertiesMain.randApproveDelegation((18, 165, 160, 12, 60, 19, 44, 5, 248, 104, 5, 153027462413969145832724960634594999733, false),136,7,44,45) Time delay: 16795 seconds Block delay: 515
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP()
    *wait* Time delay: 34166 seconds Block delay: 11
    PropertiesMain.userConfigurationMapIntegrityDebtMP()
    PropertiesMain.randApproveMP((0, 52, 53, 132, 251, 7, 43, 21, 37, 187, 42, 17134693113846643008, true),163,80,13,37,19) Time delay: 32815 seconds Block delay: 1451
    PropertiesMain.indexIntegrityLP()
    PropertiesMain.randIncreaseAllowanceLP((133, 105, 197, 3, 182, 27, 40, 104, 160, 224, 186, 19770094214932864677613797880335107884, true),242,252,6,91) Time delay: 11759 seconds Block delay: 4807
    PropertiesMain.integrityOfDepositCapLP() Time delay: 18673 seconds Block delay: 5355
    PropertiesMain.indexIntegrityLP() Time delay: 85205 seconds Block delay: 1934
    PropertiesMain.randATokenNonRebasingBalanceOfLP((126, 77, 138, 234, 159, 33, 71, 56, 211, 162, 0, 1000000000, false),161,2)
    PropertiesMain.randForceFeedAssetLP((3, 13, 11, 251, 45, 95, 92, 27, 60, 129, 203, 238931790907274882394682070669516058262, false),91,3858086693,71,91) Time delay: 82761 seconds Block delay: 5000
    PropertiesMain.randDepositMP((16, 201, 181, 60, 9, 80, 6, 56, 64, 8, 192, 887250, false),15,1,144,180,0) Time delay: 6 seconds Block delay: 5807
    PropertiesMain.integrityOfDepositCapLP() Time delay: 16915 seconds Block delay: 92
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP()
    PropertiesMain.balanceIntegrityLP((185, 6, 11, 46, 135, 1, 46, 29, 184, 251, 247, 75556710804409716572161, false))
    *wait* Time delay: 32685 seconds Block delay: 161
    PropertiesMain.randForceFeedAssetLP((53, 15, 165, 74, 19, 220, 164, 64, 52, 168, 201, 291045601290849776888365864033363810155, true),40,18458572340154892706633863078468099267,82,187) Time delay: 78727 seconds Block delay: 4141
    PropertiesMain.randForceFeedAssetLP((128, 41, 168, 188, 1, 49, 20, 126, 88, 212, 225, 119819126879301059735161532394921931704, true),8,82369169824484962906607354494543638667,92,132) Time delay: 91 seconds Block delay: 2070
    PropertiesMain.integrityOfDepositCapLP() Time delay: 85205 seconds Block delay: 2919
    PropertiesMain.globalSolvencyCheckLP()
    *wait* Time delay: 40189 seconds Block delay: 390
    PropertiesMain.randApproveLP((141, 28, 154, 167, 83, 0, 249, 56, 199, 13, 227, 51, false),225,48,21,68751932859785938268004583684998609738)
    PropertiesMain.randForceFeedAssetLP((142, 4, 0, 8, 54, 99, 8, 78, 39, 85, 236, 271625398103420286142134083466937840945, false),243,488,9,247)
    PropertiesMain.randDepositLP((141, 80, 79, 85, 165, 216, 252, 2, 230, 64, 30, 329571582897035758209760717504638334662, true),13,123,31,157198260)
    PropertiesMain.randATokenNonRebasingApproveLP((241, 223, 170, 159, 50, 75, 214, 74, 97, 180, 194, 157198258, false),49,163,33,197877715965049505315693745167529770231) Time delay: 9161 seconds Block delay: 2075
    *wait* Time delay: 64299 seconds Block delay: 374
    PropertiesMain.indexIntegrityLP() Time delay: 5704 seconds Block delay: 164
    *wait* Time delay: 1999 seconds Block delay: 3523
    PropertiesMain.randRehypothecationRebalanceLP((116, 40, 46, 27, 123, 252, 48, 3, 0, 193, 69, 252227022278638450684331346337072140208, true),32) Time delay: 15160 seconds Block delay: 2988
    PropertiesMain.indexIntegrityLP() Time delay: 54948 seconds Block delay: 4175
    PropertiesMain.randApproveDelegationMP((3, 94, 91, 60, 82, 19, 92, 119, 15, 32, 84, 835, true),106,0,30,235635742888447926474780280888600513588)
    PropertiesMain.randApproveDelegation((184, 96, 87, 11, 53, 44, 101, 32, 117, 16, 7, 295985974735048783988980643814736407156, true),117,163,174,2708836573) Time delay: 850 seconds Block delay: 2397
    *wait* Time delay: 120324 seconds Block delay: 11638
    PropertiesMain.randApproveLP((74, 67, 63, 76, 239, 132, 75, 153, 53, 69, 16, 66560752782118250497272679765059951947, true),162,4,6,1114277010)
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 75552 seconds Block delay: 6085
    PropertiesMain.randATokenNonRebasingBalanceOfLP((31, 42, 39, 201, 19, 251, 254, 43, 147, 161, 16, 184014717096976045814314771371970716273, true),99,40)
    PropertiesMain.integrityOfDepositCapLP() Time delay: 5953 seconds Block delay: 4112
    PropertiesMain.integrityOfDepositCapMP()
    PropertiesMain.randApproveDelegation((160, 161, 249, 33, 163, 251, 113, 159, 194, 135, 164, 354, true),208,149,201,271919790060561829533662197766247175458)
    PropertiesMain.balanceIntegrityMP((156, 172, 16, 152, 16, 123, 28, 49, 14, 37, 127, 1000000000000000001, true)) Time delay: 58367 seconds Block delay: 6645
    PropertiesMain.randForceFeedAssetLP((254, 28, 21, 29, 83, 189, 212, 39, 163, 175, 19, 1501, false),4,340282366920938463463374607431768211452,86,92)
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 209 seconds Block delay: 2984
    *wait* Time delay: 189606 seconds Block delay: 9786
    PropertiesMain.integrityOfDepositCapMP()
    *wait* Time delay: 26145 seconds Block delay: 11891
    PropertiesMain.randFlashloanLP((2, 138, 88, 4, 193, 164, 243, 182, 214, 200, 2, 153630743671507614184212598433997238774, true),195,3,3,4431079937450) Time delay: 19558 seconds Block delay: 683
    PropertiesMain.randDepositLP((1, 223, 0, 253, 101, 128, 142, 59, 184, 231, 75, 254579280394622910069216220805634996085, true),10,10,190,1114277012) Time delay: 49306 seconds Block delay: 366
    *wait* Time delay: 19592 seconds Block delay: 6434
    PropertiesMain.randForceFeedAssetLP((173, 251, 48, 8, 49, 137, 74, 87, 43, 116, 254, 4107696311, true),39,576460752303423488,128,254) Time delay: 38711 seconds Block delay: 6861
    PropertiesMain.indexIntegrityLP()
    *wait* Time delay: 32621 seconds Block delay: 3523
    PropertiesMain.userConfigurationMapIntegrityDebtLP() Time delay: 71078 seconds Block delay: 4140
    *wait* Time delay: 76487 seconds Block delay: 16688
    PropertiesMain.integrityOfDepositCapMP() Time delay: 15915 seconds Block delay: 7178
    PropertiesMain.userConfigurationMapIntegrityDebtMP()
    PropertiesMain.randApproveLP((68, 26, 11, 223, 159, 253, 97, 46, 224, 17, 29, 750000000000000000000000000, true),159,253,246,123419989818064301742697985092355601085) Time delay: 573 seconds Block delay: 3778
    PropertiesMain.userConfigurationMapIntegrityDebtLP() Time delay: 84008 seconds Block delay: 5122
    PropertiesMain.randSetUseReserveAsCollateralLP((219, 159, 52, 127, 252, 203, 1, 255, 252, 139, 146, 340282366920938463463374607431768211451, false),10,118,true) Time delay: 49305 seconds Block delay: 5044
    PropertiesMain.invariantRehypothecationLP() Time delay: 69858 seconds Block delay: 8581
    PropertiesMain.randApproveDelegationMP((0, 168, 165, 47, 71, 230, 29, 38, 165, 0, 103, 340282366920938463463374607431768211453, false),77,56,87,3408174302)
    PropertiesMain.randApproveDelegation((92, 65, 188, 18, 11, 25, 28, 52, 28, 4, 52, 45, true),73,49,8,576460752303423489) Time delay: 23960 seconds Block delay: 2202
    PropertiesMain.globalSolvencyCheckLP() Time delay: 45644 seconds Block delay: 2812
    *wait* Time delay: 84433 seconds Block delay: 5779
    PropertiesMain.randIncreaseAllowanceLP((77, 59, 240, 47, 254, 255, 32, 121, 10, 32, 101, 140351526541113110277512083546552590131, true),26,20,91,180454163386344637906567989645901859889) Time delay: 35077 seconds Block delay: 328
    PropertiesMain.randBorrowLP((0, 111, 177, 178, 64, 62, 19, 251, 79, 88, 89, 110, false),57,18,92,46) Time delay: 85079 seconds Block delay: 3724
    PropertiesMain.randApproveDelegationMP((7, 246, 176, 49, 61, 18, 136, 109, 144, 65, 55, 246468471204924990616671587767928781737, false),93,70,53,100000000000000000001) Time delay: 32817 seconds Block delay: 4700
    *wait* Time delay: 49588 seconds Block delay: 3160
    PropertiesMain.globalSolvencyCheckMP() Time delay: 71369 seconds Block delay: 5522
    PropertiesMain.randATokenNonRebasingBalanceOfLP((2, 252, 72, 247, 225, 226, 237, 98, 186, 74, 3, 3221960613524969891979574567667250974, false),223,95) Time delay: 349 seconds Block delay: 5360
    PropertiesMain.randDepositLP((84, 76, 188, 194, 12, 13, 253, 254, 253, 61, 48, 4294901760, true),57,95,182,131997622414548872683757327525933262535)
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 63889 seconds Block delay: 2934
    PropertiesMain.randApproveDelegationMP((0, 76, 0, 119, 54, 3, 1, 2, 219, 82, 163, 512, false),0,45,7,299) Time delay: 19970 seconds Block delay: 663
    *wait* Time delay: 90667 seconds Block delay: 5775
    PropertiesMain.globalSolvencyCheckLP()
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 4 seconds Block delay: 1179
    PropertiesMain.randATokenNonRebasingBalanceOfLP((242, 27, 3, 93, 9, 124, 11, 132, 75, 20, 82, 135141812081878955885471144036403267921, true),51,40) Time delay: 46879 seconds Block delay: 5923
    PropertiesMain.randBorrowMP((129, 251, 197, 58, 8, 6, 133, 11, 122, 250, 4, 143114646512615379775545073300321848420, false),77,0,225,7,58) Time delay: 11760 seconds Block delay: 1391
    PropertiesMain.randDepositMP((204, 243, 93, 96, 9, 163, 253, 206, 250, 19, 8, 291788515084673408841326663126191490462, false),191,15,6,127,1001)
    PropertiesMain.randDepositLP((118, 0, 9, 3, 8, 2, 87, 49, 40, 64, 187, 2401290389529339451901949034102605858, false),64,59,0,4951684599277795185273077760) Time delay: 24499 seconds Block delay: 2869
    *wait* Time delay: 44735 seconds Block delay: 4992
    PropertiesMain.randATokenNonRebasingBalanceOfLP((157, 206, 89, 110, 131, 62, 91, 224, 134, 147, 160, 126877451405607071731070909597839327116, false),0,52) Time delay: 2138 seconds Block delay: 2971
    *wait* Time delay: 28010 seconds Block delay: 4816
    PropertiesMain.randTransferMP((20, 2, 128, 208, 45, 150, 112, 52, 54, 100, 68, 283160665589512580646190018509252640758, false),134,58,16,31,91)
    PropertiesMain.randApproveLP((8, 128, 32, 32, 12, 118, 224, 190, 154, 39, 49, 337843828452769926444523315244348793489, true),251,56,3,107865146851078517963580145097409834868) Time delay: 16805 seconds Block delay: 3725
    *wait* Time delay: 230928 seconds Block delay: 709
    PropertiesMain.indexIntegrityLP()
    PropertiesMain.balanceIntegrityMP((161, 3, 129, 77, 20, 68, 5, 5, 41, 188, 2, 7175186522283114610507170091668338470, false))
    PropertiesMain.randDepositMP((48, 96, 31, 92, 65, 13, 41, 127, 31, 154, 243, 60652837310236860914962435, true),146,27,0,99,146979856157034242927080596698681190459) Time delay: 75427 seconds Block delay: 1070
    *wait* Time delay: 119277 seconds Block delay: 29576
    PropertiesMain.integrityOfDepositCapLP()
    *wait* Time delay: 72212 seconds Block delay: 1970
    PropertiesMain.integrityOfDepositCapLP() Time delay: 18822 seconds Block delay: 229
    PropertiesMain.randBorrowLP((8, 1, 129, 20, 76, 164, 76, 17, 221, 15, 35, 35824846279495095579292231009044025755, false),254,101,96,40858384987371452884788288274900850552) Time delay: 5342 seconds Block delay: 6200
    *wait* Time delay: 32750 seconds Block delay: 7999
    PropertiesMain.randForceFeedATokensLP((26, 100, 159, 16, 20, 75, 199, 5, 48, 135, 0, 96, false),71,13,96,16,47)
    PropertiesMain.randApproveDelegationMP((171, 57, 63, 84, 127, 55, 207, 189, 165, 126, 18, 208116566019760252717660810990951121737, false),63,143,2,596) Time delay: 32843 seconds Block delay: 5528
    *wait* Time delay: 39412 seconds Block delay: 7618
    PropertiesMain.randRehypothecationRebalanceLP((171, 46, 21, 231, 152, 18, 205, 42, 178, 20, 234, 1774647076, false),2) Time delay: 75574 seconds Block delay: 1838
    *wait* Time delay: 7770 seconds Block delay: 6848
    PropertiesMain.randApproveDelegationMP((3, 17, 110, 123, 3, 164, 251, 75, 193, 208, 4, 241037204285652373503373981978858131455, false),214,112,95,77) Time delay: 48 seconds Block delay: 2340
    PropertiesMain.randSetUseReserveAsCollateralLP((42, 92, 75, 191, 60, 18, 240, 253, 0, 63, 58, 54605808392121097416260386929445357307, false),9,72,true)
    *wait* Time delay: 49714 seconds Block delay: 6602
    PropertiesMain.invariantRehypothecationLP()
    *wait* Time delay: 89795 seconds Block delay: 14454
    PropertiesMain.randForceFeedAssetLP((61, 58, 33, 6, 97, 1, 4, 68, 52, 1, 24, 103157378623281388592650617580111878839, false),8,69241625809835656171766611834921422742,27,166) Time delay: 18827 seconds Block delay: 2964
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 76878 seconds Block delay: 2703
    PropertiesMain.integrityOfDepositCapMP()
    PropertiesMain.randTransferLP((184, 26, 4, 191, 35, 55, 1, 222, 99, 83, 49, 931818774, false),125,66,64,210985) Time delay: 60879 seconds Block delay: 643
    *wait* Time delay: 84477 seconds Block delay: 5274
    PropertiesMain.randATokenNonRebasingBalanceOfLP((50, 44, 0, 48, 27, 40, 1, 152, 0, 29, 1, 101, false),1,46) Time delay: 65417 seconds Block delay: 51
    PropertiesMain.randApproveLP((168, 33, 55, 73, 223, 127, 213, 130, 128, 10, 19, 266042847041937031269239186552564888567, false),128,17,242,78794710305651000165012508343161764290)
    PropertiesMain.randForceFeedATokensMP((84, 128, 156, 17, 139, 215, 89, 88, 29, 214, 63, 599290588, false),113,160,787,115,false) Time delay: 69657 seconds Block delay: 7644
    *wait* Time delay: 65967 seconds Block delay: 8747
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP()
    *wait* Time delay: 56500 seconds Block delay: 5448
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP() Time delay: 25075 seconds Block delay: 2998
    PropertiesMain.globalSolvencyCheckLP()
    *wait* Time delay: 64298 seconds Block delay: 1302
    PropertiesMain.userConfigurationMapIntegrityDebtLP()
    PropertiesMain.randApproveLP((242, 137, 27, 64, 100, 121, 7, 236, 77, 251, 120, 84710925338574993269219466005378663435, false),255,28,3,13669815174681627934763698293070087337)
    PropertiesMain.randIncreaseAllowanceLP((64, 92, 246, 41, 132, 179, 200, 228, 65, 11, 126, 191713037830564806505288402921525589570, true),92,193,100,0)
    PropertiesMain.randApproveLP((47, 1, 0, 248, 33, 30, 27, 8, 64, 31, 93, 157368914677383252933326724745149902315, false),95,13,77,295150373645222560861711059987253541013) Time delay: 29236 seconds Block delay: 1713
    PropertiesMain.integrityOfDepositCapLP() Time delay: 1580 seconds Block delay: 1167
    PropertiesMain.randFlashloanLP((10, 24, 1, 83, 37, 163, 79, 13, 252, 188, 0, 123022487777107032485962239682818000364, false),10,65,106,172264641438969135377831760329579772917) Time delay: 160 seconds Block delay: 2965
    *wait* Time delay: 52128 seconds Block delay: 162
    PropertiesMain.randForceFeedAssetLP((254, 28, 21, 29, 83, 189, 153, 39, 163, 175, 8, 1501, true),4,340282366920938463463374607431768211452,86,92) Time delay: 60 seconds Block delay: 4992
    *wait* Time delay: 65418 seconds Block delay: 2047
    PropertiesMain.invariantRehypothecationLP() Time delay: 488 seconds Block delay: 8500
    PropertiesMain.randApproveDelegation((242, 251, 250, 65, 3, 170, 253, 29, 12, 33, 35, 8999, true),0,15,63,222233114825225915032981832383615656627) Time delay: 9829 seconds Block delay: 160
    PropertiesMain.randATokenNonRebasingApproveLP((80, 92, 4, 59, 126, 34, 45, 91, 21, 92, 194, 83300465143771164907414099250128231788, false),4,130,1,218162624956154617799783539614855325736) Time delay: 11094 seconds Block delay: 6834
    PropertiesMain.randATokenNonRebasingBalanceOfLP((4, 63, 40, 100, 196, 146, 240, 51, 201, 112, 227, 20, true),167,130) Time delay: 84009 seconds Block delay: 5048
    PropertiesMain.randRehypothecationRebalanceLP((116, 18, 44, 23, 24, 252, 23, 0, 0, 84, 69, 252227022278638450684331346337072140208, false),28) Time delay: 34 seconds Block delay: 1997
    *wait* Time delay: 4047 seconds Block delay: 9924
    PropertiesMain.randBorrowLP((57, 3, 181, 60, 75, 80, 247, 58, 253, 53, 10, 294971605166834130070342548260696444977, true),253,18,94,130000000000000000001)
    PropertiesMain.randApproveLP((223, 72, 34, 157, 104, 61, 3, 183, 110, 106, 3, 100973081, false),92,30,224,340282366920938463463374607431768211453)
    PropertiesMain.randApproveDelegationMP((0, 154, 118, 197, 27, 47, 41, 207, 7, 227, 1, 66768982348728734609318023435977367506, false),65,150,11,41528655130593235271182267050246322088)
    PropertiesMain.randATokenNonRebasingBalanceOfLP((2, 9, 20, 145, 61, 13, 5, 0, 73, 100, 23, 65537, false),0,47) Time delay: 75387 seconds Block delay: 3075
    *wait* Time delay: 46429 seconds Block delay: 8272
    PropertiesMain.randApproveLP((129, 29, 81, 21, 19, 189, 199, 8, 107, 235, 158, 327320074062848883566837774587640836028, false),57,9,26,50779356482709449986751191926300291930) Time delay: 58039 seconds Block delay: 4544
    *wait* Time delay: 46870 seconds Block delay: 1913
    PropertiesMain.randApproveDelegation((205, 246, 26, 41, 198, 0, 14, 65, 7, 4, 0, 8614182057857816101041533, true),146,178,77,2130000000000000000000000000) Time delay: 22208 seconds Block delay: 6296
    PropertiesMain.userConfigurationMapIntegrityLiquidityLP()
    PropertiesMain.globalSolvencyCheckMP() Time delay: 72366 seconds Block delay: 1998
    PropertiesMain.userConfigurationMapIntegrityDebtLP() Time delay: 56794 seconds Block delay: 3773
    *wait* Time delay: 102740 seconds Block delay: 1545
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 30101 seconds Block delay: 4447
    PropertiesMain.globalSolvencyCheckMP() Time delay: 22841 seconds Block delay: 378
    PropertiesMain.randSetUseReserveAsCollateralLP((45, 51, 8, 90, 251, 20, 55, 28, 54, 51, 173, 3725587544, false),183,78,true)
    PropertiesMain.randRehypothecationRebalanceLP((150, 172, 36, 165, 48, 52, 63, 160, 8, 41, 103, 46848428026353721343655207075299001033, false),28) Time delay: 11474 seconds Block delay: 704
    *wait* Time delay: 94379 seconds Block delay: 12408
    PropertiesMain.userConfigurationMapIntegrityDebtMP()
    *wait* Time delay: 159742 seconds Block delay: 2856
    PropertiesMain.userConfigurationMapIntegrityDebtMP() Time delay: 32844 seconds Block delay: 1646
    *wait* Time delay: 8500 seconds Block delay: 30
    PropertiesMain.userConfigurationMapIntegrityDebtLP() Time delay: 72304 seconds Block delay: 1056
    PropertiesMain.randRehypothecationRebalanceLP((127, 2, 106, 39, 165, 17, 178, 225, 238, 159, 152, 1881529894367062944087496869316008261, false),99)
    *wait* Time delay: 78 seconds Block delay: 3365
    PropertiesMain.randATokenNonRebasingApproveLP((4, 43, 1, 127, 63, 176, 19, 224, 35, 248, 252, 95496263443688148784327658421328144098, false),140,39,246,17) Time delay: 999 seconds Block delay: 4259
    PropertiesMain.integrityOfDepositCapLP() Time delay: 60203 seconds Block delay: 4949
    PropertiesMain.randATokenNonRebasingApproveLP((44, 95, 170, 251, 31, 92, 101, 107, 10, 4, 84, 6462791151070458911217528970007272397, false),213,83,118,67421187463599119173071555011534007774)
    PropertiesMain.randApproveLP((171, 200, 252, 114, 165, 64, 189, 219, 64, 0, 127, 9, false),6,9,200,15099180599884744612368167322805310343)
    *wait* Time delay: 81 seconds Block delay: 8158
    PropertiesMain.randATokenNonRebasingApproveLP((40, 0, 9, 142, 14, 46, 142, 11, 38, 9, 188, 155592357, true),7,78,197,3601147484) Time delay: 84172 seconds Block delay: 2780
    PropertiesMain.globalSolvencyCheckLP() Time delay: 53710 seconds Block delay: 7921
    *wait* Time delay: 32787 seconds Block delay: 3784
    PropertiesMain.indexIntegrityLP() Time delay: 2894 seconds Block delay: 2944
    *wait* Time delay: 64345 seconds Block delay: 3444
    PropertiesMain.globalSolvencyCheckMP() Time delay: 1 seconds Block delay: 2975
    PropertiesMain.randWithdrawLP((143, 7, 230, 112, 51, 176, 253, 32, 76, 178, 63, 75556710804409716572162, false),61,137,88,239050622879387164020771060559605868535)
   """

string = 'tests/echidna/echidnaToFoundry/FoundryTestSequence.sol'
with open(string, 'w') as f:
    f.write(transform_text(input_text))

print("Done ::: the %s file has been generated." % string)