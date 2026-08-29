scoreboard objectives add mcrv_input dummy
scoreboard objectives add mcrv_prev dummy
scoreboard objectives add mcrv_phase dummy
tag @a remove mcrv_input_ready
tellraw @a [{"text":"[MCRV] ","color":"aqua"},{"text":"On-screen keyboard input bridge loaded.","color":"gray"}]
