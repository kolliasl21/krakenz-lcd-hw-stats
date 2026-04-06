#!/bin/bash

SPEED=()
BRIGHTNESS=-1
GIF="/path/to/file.gif"
IMG_PATH="$(mktemp -u /tmp/image.XXXX.png)"
FONT="/usr/share/fonts/noto/NotoSans-ThinItalic.ttf"
CLOCK=
MON=
IMG_RES="320x320"
Z53_NAME=
CORSAIR_PSU_NAME=
LIQUID_COOLER_NAME="NZXT"
CELSIUS=$'\xe2\x84\x83'

init() {
	local sensor_data
	sensor_data=$(sensors -j)
	Z53_NAME=$(
		jq -r '.|keys|map(select(.|startswith("z53-hid-3-")))|first' \
		<(echo "$sensor_data"))
	CORSAIR_PSU_NAME=$(
		jq -r '.|keys|map(select(.|startswith("corsairpsu-hid-3-")))|first' \
		<(echo "$sensor_data"))
}

init

cleanup() {
	[[ -f "${IMG_PATH}" ]] && rm "${IMG_PATH}"
	unset FONT GIF SPEED BRIGHTNESS IMG_PATH CLOCK MON Z53_NAME \
		CORSAIR_PSU_NAME IMG_RES LIQUID_COOLER_NAME CELSIUS
}

print_usage() {
	cat <<-EOF
		Wrong input! Available flags:
		-b brightness:0-100%
		-l liquid lcd mode
		-g gif lcd mode
		-s pump speed
		   dynamic: 0-100%,0-100C (in pairs seperated by ",")
		   static : 0-100% (single value for static speed)
		-c change .gif
		-t clock mode
		-m monitor mode
		-d load default profile
		-p load user profile
	EOF
}

set_lcd_mode() {
	liquidctl --match "${LIQUID_COOLER_NAME}" set lcd screen "$1" "$2"
}

_set_lcd_brightness() {
	liquidctl --match "${LIQUID_COOLER_NAME}" set lcd screen brightness "${BRIGHTNESS}"
}

_set_pump_speed() (
	IFS=,
	liquidctl --match "${LIQUID_COOLER_NAME}" set pump speed ${SPEED[*]}
)

get_sensor_data() {
	sensors -j | jq "(
		.\"amdgpu-pci-2800\".\"edge\".\"temp1_input\",
		.\"${Z53_NAME}\".\"Coolant temp\".\"temp1_input\",
		.\"k10temp-pci-00c3\".\"Tctl\".\"temp1_input\", 
		.\"amdgpu-pci-2800\".\"mem\".\"temp3_input\", 
		.\"amdgpu-pci-2800\".\"junction\".\"temp2_input\",
		.\"${CORSAIR_PSU_NAME}\".\"power +12v\".\"power2_input\",
		.\"${Z53_NAME}\".\"Pump speed\".\"fan1_input\"
	)*10|round/10"
}

update_clock_image() {
	local strtime
	strtime="$(date +%H:%M)"
	magick 	-size "${IMG_RES}" gradient:black-black \
		-font "${FONT}" \
		-tile gradient:blue-magenta \
		-gravity center \
		-pointsize 150 \
		-annotate +0-70 "${strtime:0:2}" \
		-pointsize 150 \
		-annotate +0+70 "${strtime:3}" "${IMG_PATH}"
	set_lcd_mode "static" "${IMG_PATH}"
}

_update_sensors_image() {
	declare -a data
	readarray -t data < <(get_sensor_data)
	magick  -size "${IMG_RES}" gradient:black-black \
		-font "${FONT}" \
		-tile gradient:blue-magenta \
		-gravity center \
		-pointsize 80 \
		-annotate +0-100 "$(date +%H:%M)" \
		-pointsize 30 \
		-annotate +0+135 "${data[6]}rpm" \
		-tile gradient:red-yellow \
		-gravity center \
		-pointsize 30 \
		-annotate -60-45 "$1" \
		-pointsize 30 \
		-annotate +60-45 "$2" \
		-pointsize 30 \
		-annotate -60+45 "$3" \
		-pointsize 30 \
		-annotate +60+45 "$4" \
		-tile gradient:red-red \
		-gravity center \
		-pointsize 40 \
		-annotate -60-0  "${data[$5]}$CELSIUS" \
		-pointsize 40 \
		-annotate +60-0  "${data[$6]}$CELSIUS" \
		-pointsize 40 \
		-annotate -60+90 "${data[$7]}$8" \
		-pointsize 40 \
		-annotate +60+90 "${data[1]}$CELSIUS" "${IMG_PATH}"
	set_lcd_mode "static" "${IMG_PATH}"
}

update_sensors_image() {
	_update_sensors_image \
		"GPU" \
		"CPU" \
		"Power" \
		"Coolant" \
		0 \
		2 \
		5 \
		"W"
}

update_sensors_image_alt() {
	_update_sensors_image \
		"GPUMem" \
		"GPUHot" \
		"CPU" \
		"Coolant" \
		3 \
		4 \
		2 \
		"$CELSIUS"
}

refresh_display() {
	while true; do
		"$1"
		sleep "$2"
	done
}

if ! (return 2>/dev/null); then

	trap cleanup EXIT

	[[ -z $GIF ]] && echo "GIF not set!" && exit 1

	liquidctl initialize all > /dev/null 2>&1

	while getopts "b:lgs:c:tmdp" flag; do
		case "${flag}" in
			b) BRIGHTNESS="${OPTARG}" ;;
			l) set_lcd_mode "liquid" ;;
			g) set_lcd_mode "gif" "${GIF}" ;;
			s) SPEED+=("${OPTARG}") ;;
			c) GIF="${OPTARG}" ;; 
			t) CLOCK=1 ;; 
			m) ((MON++)) ;;
			d) BRIGHTNESS=50 SPEED=(25 40 30 60 35 80 40 100)
				set_lcd_mode "liquid"; break ;;
			p) BRIGHTNESS=50  SPEED=(50)
				set_lcd_mode "gif" "${GIF}"; break ;;
			*) print_usage; exit 0 ;;
		esac
	done

	[[ ${BRIGHTNESS} -ge 0 ]] && [[ ${BRIGHTNESS} -le 100 ]] && _set_lcd_brightness

	[[ ${#SPEED[@]} -gt 0 ]] && _set_pump_speed

	[[ -n $CLOCK ]] && refresh_display "update_clock_image" "30"

	[[ -n $MON ]] && ((MON < 2)) && refresh_display "update_sensors_image" ".5"

	[[ -n $MON ]] && refresh_display "update_sensors_image_alt" ".5"
fi
