scoreboard players set @s mcrv_input 0
execute if predicate mcrv:input/up run scoreboard players set @s mcrv_input 1
execute if predicate mcrv:input/down run scoreboard players set @s mcrv_input 2
execute if predicate mcrv:input/left run scoreboard players set @s mcrv_input 3
execute if predicate mcrv:input/right run scoreboard players set @s mcrv_input 4
execute if predicate mcrv:input/confirm run scoreboard players set @s mcrv_input 5
execute if predicate mcrv:input/backspace run scoreboard players set @s mcrv_input 6
execute if predicate mcrv:input/cancel run scoreboard players set @s mcrv_input 7
execute unless score @s mcrv_input = @s mcrv_prev if score @s mcrv_input matches 1..7 run function mcrv:input/emit
scoreboard players operation @s mcrv_prev = @s mcrv_input
