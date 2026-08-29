scoreboard objectives add mcrv_input dummy
scoreboard objectives add mcrv_prev dummy
scoreboard objectives add mcrv_phase dummy
scoreboard objectives add mcrv_hold dummy
scoreboard objectives add mcrv_owner dummy
scoreboard players add #next mcrv_owner 0
kill @e[type=minecraft:text_display,tag=mcrv_input_marker]
title @a clear
tag @a remove mcrv_input_ready
tag @a add mcrv_input_disabled
tellraw @a [{"text":"[MCRV] ","color":"aqua"},{"text":"Input bridge loaded. Run /function mcrv:input/enable after enabling the Post Effect.","color":"gray"}]
