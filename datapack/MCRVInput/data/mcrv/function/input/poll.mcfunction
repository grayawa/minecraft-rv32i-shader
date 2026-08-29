scoreboard players operation #current mcrv_owner = @s mcrv_owner
execute positioned ^ ^ ^0.4 as @e[type=minecraft:text_display,tag=mcrv_input_marker] if score @s mcrv_owner = #current mcrv_owner run tp @s ~ ~ ~
scoreboard players set @s mcrv_input 0
execute if predicate mcrv:input/up run scoreboard players set @s mcrv_input 1
execute if predicate mcrv:input/down run scoreboard players set @s mcrv_input 2
execute if predicate mcrv:input/left run scoreboard players set @s mcrv_input 3
execute if predicate mcrv:input/right run scoreboard players set @s mcrv_input 4
execute if score @s mcrv_jump > @s mcrv_jump_prev run scoreboard players set @s mcrv_input 5
execute if predicate mcrv:input/confirm run scoreboard players set @s mcrv_input 5
execute if predicate mcrv:input/page run scoreboard players set @s mcrv_input 6
execute if predicate mcrv:input/cancel run scoreboard players set @s mcrv_input 7
execute unless score @s mcrv_input matches 6 run scoreboard players set @s mcrv_hold 0
execute unless score @s mcrv_input = @s mcrv_prev if score @s mcrv_input matches 1..7 run scoreboard players operation @s mcrv_debug = @s mcrv_input
execute unless score @s mcrv_input = @s mcrv_prev if score @s mcrv_input matches 1..7 run function mcrv:input/emit
execute if score @s mcrv_input matches 6 if score @s mcrv_prev matches 6 run scoreboard players add @s mcrv_hold 1
execute if score @s mcrv_input matches 6 if score @s mcrv_prev matches 6 if score @s mcrv_hold matches 10.. run function mcrv:input/emit
execute if score @s mcrv_input matches 6 if score @s mcrv_prev matches 6 if score @s mcrv_hold matches 10.. run scoreboard players set @s mcrv_hold 7
scoreboard players operation @s mcrv_prev = @s mcrv_input
scoreboard players operation @s mcrv_jump_prev = @s mcrv_jump
execute if entity @s[tag=mcrv_input_debug] run title @s actionbar [{"text":"MCRV  LAST ","color":"aqua"},{"score":{"name":"@s","objective":"mcrv_debug"},"color":"white"},{"text":"  NOW ","color":"gray"},{"score":{"name":"@s","objective":"mcrv_input"},"color":"white"},{"text":"  JUMP ","color":"gray"},{"score":{"name":"@s","objective":"mcrv_jump"},"color":"white"},{"text":"  PH ","color":"gray"},{"score":{"name":"@s","objective":"mcrv_phase"},"color":"white"}]
