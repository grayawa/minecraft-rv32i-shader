title @s clear
tag @s remove mcrv_input_ready
tag @s add mcrv_input_disabled
tellraw @s [{"text":"[MCRV] ","color":"aqua"},{"text":"On-screen keyboard disabled.","color":"gray"}]
