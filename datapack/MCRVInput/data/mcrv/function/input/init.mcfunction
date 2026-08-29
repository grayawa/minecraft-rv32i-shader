kill @e[type=minecraft:text_display,tag=mcrv_input_marker,distance=..2]
tag @s add mcrv_input_ready
tag @s remove mcrv_input_disabled
scoreboard players set @s mcrv_input 0
scoreboard players set @s mcrv_prev 0
scoreboard players set @s mcrv_phase 0
scoreboard players set @s mcrv_hold 0
scoreboard players add @s mcrv_jump 0
scoreboard players operation @s mcrv_jump_prev = @s mcrv_jump
scoreboard players set @s mcrv_debug 0
scoreboard players add #next mcrv_owner 1
scoreboard players operation @s mcrv_owner = #next mcrv_owner
summon minecraft:text_display ^ ^ ^0.4 {Tags:["mcrv_input_marker","mcrv_input_new"],billboard:"center",text:{text:"",font:"mcrv:input",color:"white",shadow_color:0},background:0,shadow:0b,see_through:1b,line_width:128,brightness:{block:15,sky:15},view_range:1.0f,teleport_duration:0,transformation:{translation:[0f,0f,0f],left_rotation:[0f,0f,0f,1f],scale:[0.05f,0.05f,0.05f],right_rotation:[0f,0f,0f,1f]}}
scoreboard players operation @e[type=minecraft:text_display,tag=mcrv_input_new,sort=nearest,limit=1,distance=..3] mcrv_owner = @s mcrv_owner
tag @e[type=minecraft:text_display,tag=mcrv_input_new,sort=nearest,limit=1,distance=..3] remove mcrv_input_new
title @s clear
