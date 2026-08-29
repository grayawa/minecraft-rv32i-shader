title @s clear
scoreboard players set #current mcrv_owner -1
scoreboard players operation #current mcrv_owner = @s mcrv_owner
execute as @e[type=minecraft:text_display,tag=mcrv_input_marker] if score @s mcrv_owner = #current mcrv_owner run kill @s
tag @s remove mcrv_input_ready
tag @s add mcrv_input_disabled
tellraw @s [{"text":"[MCRV] ","color":"aqua"},{"text":"On-screen keyboard disabled.","color":"gray"}]
