tag @s remove mcrv_input_disabled
function mcrv:input/init
tellraw @s [{"text":"[MCRV] ","color":"aqua"},{"text":"On-screen keyboard enabled.","color":"gray"}]
