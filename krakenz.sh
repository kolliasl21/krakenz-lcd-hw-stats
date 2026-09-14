#!/bin/bash

# Change FONT, GIF, IMG_RES.
# IMG_RES for newer NZXT Kraken liquid coolers is 640x640.
# Change LIQUID_COOLER_NAME with other brand if supported by liquidctl.

BRIGHTNESS=-1
GIF="/path/to/file.gif"
IMG_PATH="$(mktemp -u /tmp/image.XXXX.png)"
FONT="/usr/share/fonts/noto/NotoSans-MediumItalic.ttf"
CLOCK=
MON=
IMG_RES="320x320"
LIQUID_COOLER_NAME="NZXT"
ORIENTATION=-1
CELSIUS=$'\xe2\x84\x83'
DEG=$'\xc2\xb0'
declare -a SPEED
declare -A DEVICES=([gpu]="amdgpu-pci-2800" [cpu]="k10temp-pci-00c3")
JQ_READ=
JQ_WRITE=

enable sleep

init() {
	local item count
	declare -a data
	declare -A item_count item_count_copy items

	# Get devices that don't have fixed names at startup, usually USB devices.
	# Match the first part of the string to get the full device name.
	readarray -t data < <(jq -r 'keys|map(
		select(startswith("z53-hid-3-")),
		select(startswith("corsairpsu-hid-3-")),
		select(startswith("jc42-i2c-9-"))
		)|sort .[]' <(sensors -j))

	# Strip sensor names from right to left up to the last dash "-" and
	# store them in a associative array paired with the sensor name as key.
	for item in "${data[@]}"; do
		items[$item]=${item%%-*}
		 ((item_count[${item%%-*}]++))
		 ((item_count_copy[${item%%-*}]++))
	done

	# Keep duplicate values by appending a suffix.
	for item in "${!items[@]}"; do
		[[ ${item_count[${item%%-*}]} -lt 2 ]] && continue
		count=$((${item_count_copy[${item%%-*}]}-1))
		items[$item]="${items[$item]}_$count"
		((item_count_copy[${item%%-*}]--))
	done

	# Store the values from "items" as keys in the DEVICES array and the
	# sensor names as values.
	for item in "${!items[@]}"; do
		DEVICES[${items[$item]}]=$item
	done

	if [[ -n $DEBUG ]]; then
		for item in "${!DEVICES[@]}"; do
			echo "Key: $item, Value: ${DEVICES[$item]}"
		done
		echo "Number of devices: ${#DEVICES[@]}"
	fi

	[[ -z $JQ_PID ]] && _init_coproc_jq
}

cleanup() {
	[[ -f "${IMG_PATH}" ]] && rm "${IMG_PATH}"
	enable -n sleep
	[[ -n $JQ_PID ]] && kill -15 "$JQ_PID"
	unset FONT GIF SPEED BRIGHTNESS IMG_PATH CLOCK MON \
		IMG_RES LIQUID_COOLER_NAME CELSIUS DEVICES \
		JQ_READ JQ_WRITE
}

print_usage() {
	cat <<-EOF
		-b brightness:0-100%
		-l liquid lcd mode
		-g gif lcd mode
		-s pump speed
		   dynamic: 0-100%,0-100$CELSIUS  (in pairs seperated by ",")
		   static : 0-100% (single value for static speed)
		-c change .gif
		-t clock mode
		-m monitor mode (add more "-m" flags to switch display)
		-d load default profile
		-p load user profile
		-h print usage
		-o set display orientation (0$DEG, 90$DEG, 180$DEG, 270$DEG)
	EOF
}

set_lcd_orientation() {
	liquidctl --match "${LIQUID_COOLER_NAME}" set lcd screen orientation "$1"
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

_init_coproc_jq() {
	local key
	declare -a args_list

	# Build arguments list
	# Pass the DEVICES array values into jq using --arg.
	for key in "${!DEVICES[@]}"; do
		args_list+=("--arg" "$key" "${DEVICES[$key]}")
	done

	# Replace with your own sensors. Don't copy these.
	# Start with a few simple sensors, add more later.
	coproc JQ {
		jq --unbuffered "${args_list[@]}" \
		'(
		.[$cpu]."Tctl"."temp1_input",
		.[$gpu]."edge"."temp1_input",
		.[$gpu]."mem"."temp3_input",
		.[$gpu]."junction"."temp2_input",
		.[$gpu]."sclk"."freq1_input"/1000000,
		.[$gpu]."PPT"."power1_average",
		.[$gpu]."fan1"."fan1_input",
		.[$corsairpsu]."power +12v"."power2_input",
		.[$z53]."Coolant temp"."temp1_input",
		.[$z53]."Pump speed"."fan1_input",
		.[$jc42_0]."temp1"."temp1_input",
		.[$jc42_1]."temp1"."temp1_input",
		.[$jc42_2]."temp1"."temp1_input",
		.[$jc42_3]."temp1"."temp1_input"
		)*10|round/10'
	}

	exec {JQ_READ}>&"${JQ[0]}"
	exec {JQ_WRITE}>&"${JQ[1]}"
}

get_sensor_data() {
	sensors -j >&"$JQ_WRITE"
	local i line
	# Read sensor data from file descriptor.
	for ((i=0; i<14; i++)); do
		read -r -u "$JQ_READ" line
		echo "$line"
	done
}

update_clock_image() {
	local strtime
	printf -v strtime '%(%H:%M)T'

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
	declare -a data sensor_order=(cput gpu{e,m,j,c,p,f} powr liqt pump dim{0..3})
	declare -A keyval_array
	local i=0 item strtime
	readarray -t data < <(get_sensor_data)

	# Create an associative array to pair keys with sensor values.
	# Format sensor data with printf and store the formatted values
	# into the array.
	for item in "${sensor_order[@]}"; do
		printf -v keyval_array["$item"] '%s' "${data[i]}"
		((i++))
	done

	# Format these sensors to one decimal place.
	for item in cput liqt dim{0..3}; do
		printf -v keyval_array["$item"] '%.1f' "${keyval_array[$item]}"
	done

	printf -v strtime '%(%H:%M)T'

	magick  -size "${IMG_RES}" gradient:black-black \
		-font "${FONT}" \
		-tile gradient:blue-magenta \
		-gravity center \
		-pointsize 80 \
		-annotate +0-100 "$strtime" \
		-pointsize 30 \
		-annotate +0+135 "${keyval_array[pump]}rpm" \
		-tile gradient:red-yellow \
		-gravity center \
		-pointsize 30 \
		-annotate -60-45 "$1" \
		-pointsize 30 \
		-annotate +60-45 "$4" \
		-pointsize 30 \
		-annotate -60+45 "$7" \
		-pointsize 30 \
		-annotate +60+45 "${10}" \
		-tile gradient:red-red \
		-gravity center \
		-pointsize 40 \
		-annotate -60-0  "${keyval_array[$2]}$3" \
		-pointsize 40 \
		-annotate +60-0  "${keyval_array[$5]}$6" \
		-pointsize 40 \
		-annotate -60+90 "${keyval_array[$8]}$9" \
		-pointsize 40 \
		-annotate +60+90 "${keyval_array[${11}]}${12}" "${IMG_PATH}"
	set_lcd_mode "static" "${IMG_PATH}"
}

# Create display modes bellow.
update_sensors_image() {
	_update_sensors_image \
		"GPU"      "gpue" "$CELSIUS" \
		"CPU"      "cput" "$CELSIUS" \
		"Power"    "powr" "W" \
		"Coolant"  "liqt" "$CELSIUS"
}

update_sensors_image_alt() {
	_update_sensors_image \
		"GPUMem"   "gpum" "$CELSIUS" \
		"GPUHot"   "gpuj" "$CELSIUS" \
		"CPU"      "cput" "$CELSIUS" \
		"Coolant"  "liqt" "$CELSIUS"
}

update_sensors_image_ddr() {
	_update_sensors_image \
		"DIMM0"    "dim0" "$CELSIUS" \
		"DIMM1"    "dim1" "$CELSIUS" \
		"DIMM2"    "dim2" "$CELSIUS" \
		"DIMM3"    "dim3" "$CELSIUS"
}

update_sensors_image_gpu() {
	_update_sensors_image \
		"GPU MHz"  "gpuc" "" \
		"Edge"     "gpue" "$CELSIUS" \
		"PPT"      "gpup" "W" \
		"Junction" "gpuj" "$CELSIUS"
}

cycle_display() {
	# Cycle through display modes.
	local item

	_loop() {
		local i=0
		for i in {0..9}; do
			"$1"
			sleep "$2"
		done
	}

	while true; do
		for item in update_sensors_image{,_alt,_ddr,_gpu}; do
			_loop "$item" "$1"
		done
	done
}

refresh_display() {
	while true; do
		"$1"
		sleep "$2"
	done
}

_main() {

	trap cleanup EXIT

	[[ -z $GIF ]] && echo "GIF not set!" && return 1

	liquidctl initialize all &>/dev/null

	local OPTARG OPTIND flag
	while getopts "b:lgs:c:tmdpho:" flag; do
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
			p) BRIGHTNESS=50 SPEED=(50)
				set_lcd_mode "gif" "${GIF}"; break ;;
			h) print_usage; return 0 ;;
			o) ORIENTATION="${OPTARG}" ;;
			*) echo "Wrong input! Available flags:" >&2;
				print_usage >&2; return 2 ;;
		esac
	done

	[[ ${ORIENTATION} -ge 0 ]] && set_lcd_orientation "$ORIENTATION"

	[[ ${BRIGHTNESS} -ge 0 && ${BRIGHTNESS} -le 100 ]] && _set_lcd_brightness

	[[ ${#SPEED[@]} -gt 0 ]] && _set_pump_speed

	[[ -n $CLOCK ]] && refresh_display "update_clock_image" "30"

	[[ -z $MON ]] && return 0

	case $MON in
		1) refresh_display "update_sensors_image"     ".5" ;;
		2) refresh_display "update_sensors_image_alt" ".5" ;;
		3) refresh_display "update_sensors_image_ddr" ".5" ;;
		4) refresh_display "update_sensors_image_gpu" ".5" ;;
		*) cycle_display ".5" ;;
	esac
}

init

if ! (return 2>/dev/null); then
	_main "$@"
fi
