execute as @a[tag=!mcrv_input_ready,tag=!mcrv_input_disabled] run function mcrv:input/init
execute as @a[tag=mcrv_input_ready] run function mcrv:input/poll
