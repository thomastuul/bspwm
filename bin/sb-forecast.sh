#!/usr/bin/env sh

DEFAULT_LOCATION="München"

# Displays today's precipication chance (☔), and daily low (🥶) and high (🌞).
# Usually intended for the statusbar.

URL="${WTTRURL:-wttr.in}"
WEATHERREPORT="${XDG_CACHE_HOME:-$HOME/.cache}/weather"

parse_params() {
    location=""
    time_of_last_update=false

    if [ $# -gt 2 ]; then
        printf "Wrong number of arguments!\n"
        exit 1
    elif [ $# -eq 2 ]; then
        if [ "$2" = "age" ] || [ "$2" = "AGE" ]; then
            time_of_last_update=true
            location="$1"
        else
            printf "Wrong parameter!\n"
            exit 1
        fi
    elif [ $# -eq 1 ]; then
        location="$1"
    else
        location="$DEFAULT_LOCATION"
    fi
}

# Get a weather report from 'wttr.in' and save it locally.
getforecast() {
    if weather_dump=$(curl --max-time 0.5 --silent --fail "$URL/$location"); then
        echo "$weather_dump" > "$weatherreport"
        return 0;
    else
        return 1;
    fi
}

# Forecast should be updated only once a day.
checkforecast() {
    ret_val=0
    # is file not empty
	if [ -s "$weatherreport" ]; then
        # update if weatherreport is older then 4h
        if [ "$(find "${weatherreport}" -mmin +240)" ]; then
            ret_val=1
        else
            ret_val=0
        fi
    else
        ret_val=1
    fi
    return $ret_val
}

getprecipchance() {
	echo "$weatherdata" | sed '16q;d' |    # Extract line 16 from file
		grep -wo "[0-9]*%" |           # Find a sequence of digits followed by '%'
		sort -rn |                     # Sort in descending order
		head -1q                       # Extract first line
}

getdailyhighlow() {
	echo "$weatherdata" | sed '13q;d' |      # Extract line 13 from file
		grep -o "m\\([-+]\\)*[0-9]\\+" | # Find temperatures in the format "m<signed number>"
		sed 's/[+m]//g' |                # Remove '+' and 'm'
		sort -g |                        # Sort in ascending order
		sed -e 1b -e '$!d'               # Extract the first and last lines
}

readfile() {
    weatherdata="$(cat "$weatherreport")" ;
}

showweather() {
	readfile
    # shellcheck disable=SC2183,2046 # this is intended but not nice, improve it later
	printf "爫%s %s° %s°" "$(getprecipchance)" $(getdailyhighlow)
}

if ! parse_params "$@"; then
    exit
fi

weatherreport="${WEATHERREPORT}_${location}"

if [ "$time_of_last_update" = true ]; then
    if [ -f "$weatherreport" ]; then
        # print age of file
        file_mod_time=$(stat -c %Y "$weatherreport")
        current_time=$(date +%s)
        age_seconds=$((current_time - file_mod_time))
        age_minutes=$((age_seconds / 60))
        printf "%s" "$age_minutes"
    else
        printf "%s" "0"
    fi
elif ! checkforecast; then
    if getforecast; then
        showweather
    fi
else
    showweather
fi
