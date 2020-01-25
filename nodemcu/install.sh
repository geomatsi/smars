#!/bin/bash

TOOL=nodemcu-tool

usage ()
{
	cat << EOH
Usage: ./install [project]

Projects:
  test1
  Simple HC-SR04 sensor example: forward/rotate movements based on range sensor data.

  test2
  Simple WebSocket example: forward/rotate/backward movements based on server commands.

  test3
  Simple PWM example: control motor pins using PWM module rather than simple GPIO.

  test4
  Simple WebSocket/JSON/PWM example: get commands from server in JSON format to control motor pins using PWM module
EOH
}

upload ()
{
	main=$1
	shift
	mods="$@"

	sudo ${TOOL} upload ${main}.lua -n main.lua

	for n in ${mods}
	do
		sudo ${TOOL} upload $n.lua -n $n.lua
	done

	sudo ${TOOL} upload init.lua -n init.lua
	sudo ${TOOL} upload settings.lua -n settings.lua
}

case "$1" in
	test1)
		upload "test1" "gpio_motors" "hc_sr_04"
		;;
	test2)
		upload "test2" "gpio_motors" "hc_sr_04"
		;;
	test3)
		upload "test3" "pwm_motors"
		;;
	test4)
		upload "test4" "pwm_motors" "hc_sr_04"
		;;
	*)
		usage	
		;;
esac
