#!/bin/sh

PWD=$(pwd)
LOG="/mnt/us/weatherstation.log"
SLEEP_MINUTES=60
FBINK="/mnt/us/extensions/MRInstaller/bin/K5/fbink -q"
FONT="regular=/usr/java/lib/fonts/Palatino-Regular.ttf"

wait_wlan_connected() {
  return `lipc-get-prop com.lab126.wifid cmState | grep CONNECTED | wc -l`
}

wait_wlan_ready() {
  return `lipc-get-prop com.lab126.wifid cmState | grep -e READY -e PENDING -e CONNECTED | wc -l`
}

### Dim Backlight
echo -n 0 > /sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity

### Prepare Kindle, shutdown framework etc.
echo "------------------------------------------------------------------------" >> $LOG
echo "`date '+%Y-%m-%d_%H:%M:%S'`: Starting up, killing framework et. al." >> $LOG

echo 0 > /sys/devices/platform/mxc_epdc_fb/graphics/fb0/rotate
$FBINK -w -c -f -m -t $FONT,size=20,top=410,bottom=0,left=0,right=0 "Starting weatherstation..." > /dev/null 2>&1
echo 3 > /sys/devices/platform/mxc_epdc_fb/graphics/fb0/rotate
sleep 1

### stop processes that we don't need
stop lab126_gui
stop otaupd
stop phd
stop tmd
stop x
stop todo
stop mcsd
sleep 2

### If we have a wan module installed...
#if [ -f /usr/sbin/wancontrol ]
#then
#    wancontrol wanoffkill
#fi

### Disable Screensaver
lipc-set-prop com.lab126.powerd preventScreenSaver 1

echo "`date '+%Y-%m-%d_%H:%M:%S'`: Entering main loop..." >> $LOG

while true; do

	NOW=$(date +%s)

	let SLEEP_SECONDS=60*SLEEP_MINUTES
	let WAKEUP_TIME=$NOW+SLEEP_SECONDS
	echo `date '+%Y-%m-%d_%H:%M:%S'`: Wake-up time set for  `date -d @${WAKEUP_TIME}` >> $LOG

    ### Dim Backlight, fighting powerd...
    echo -n 0 > /sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity

	### Disable CPU Powersave
	echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    lipc-set-prop com.lab126.cmd wirelessEnable 1
    ### Wait for wifi interface to come up
    echo `date '+%Y-%m-%d_%H:%M:%S'`: Waiting for wifi interface to come up... >> $LOG
    while wait_wlan_ready; do
        sleep 1
    done

    ### Wifi interface is up, connect to wifi.
    /mnt/us/wifi.sh

	### Wait for WIFI connection
    TRYCNT=0
    NOWIFI=0
    echo `date '+%Y-%m-%d_%H:%M:%S'`: Waiting for wifi interface to become ready... >> $LOG
	while wait_wlan_connected; do
        if [ ${TRYCNT} -gt 30 ]; then
            ### waited long enough
            echo "`date '+%Y-%m-%d_%H:%M:%S'`: No Wifi... ($TRYCNT)" >> $LOG
            NOWIFI=1
            eips -f -g $PWD/error.png
            break
        fi
	  sleep 1
      let TRYCNT=$TRYCNT+1
	done

	echo `date '+%Y-%m-%d_%H:%M:%S'`: WIFI connected! >> $LOG

	### Get Weatherdata
	echo `date '+%Y-%m-%d_%H:%M:%S'`: Getting weatherdata >> $LOG
	rm -f $PWD/kindle-weather.png

	if $PWD/create-png.sh; then
	  eips -f -g $PWD/kindle-weather.png
	else
      echo `date '+%Y-%m-%d_%H:%M:%S'`: Something went wrong getting weatherdata >> $LOG
	  eips -f -g $PWD/error.png
      sleep 60
	fi

	#echo `date -d @${WAKEUP_TIME}` | xargs -0 eips
	BAT=$(gasgauge-info -s | sed s/%//)
#	echo $BAT | xargs -0 eips -f 1 1
	echo `date '+%Y-%m-%d_%H:%M:%S'`: Battery level: $BAT >> $LOG

    ### Enable powersave
    echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    ### flight mode on...
    lipc-set-prop com.lab126.cmd wirelessEnable 0

	sleep 2

    ### set wake up time to one hour
	rtcwake -d /dev/rtc1 -m no -s $SLEEP_SECONDS
	### Go into Suspend to Memory (STR)
	echo `date '+%Y-%m-%d_%H:%M:%S'`: Sleeping now... >> $LOG
	echo "mem" > /sys/power/state
done
