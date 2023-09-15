#
# SignNinja - runs a full screen slideshow of all of the images in the
#             the MVUC upcoming events directory.
#
# usage: SignNinja <start|stop>

# The cleanup function should be called whenever we exit the script
# after the slideshow has started

function cleanup {
  pkill -x mpv
  pkill -x unclutter
  rm -f $pidFile $oldLsFile
}

function log {
  echo   $program: "$@"
  logger $program: "$@"
}

  pidFile=/tmp/SignNinja.pid
 mediaDir=/tmp/gdrive
newLsFile=/tmp/SignNinja.new
oldLsFile=/tmp/SignNinja.old
  cfgFile=$mediaDir/SignNinja.conf
  program=SignNinja
 duration=10
    sleep=30

# if SignNinja is already running, then either exit, or, if requested, stop
# the already running process

if test -f "$pidFile"; then
  existingPid=`cat $pidFile`
  if ps -p $existingPid > /dev/null; then
    if [ "$1" == "stop" ]; then
        log stopping existing process $existingPid
        kill -SIGINT $existingPid
        exit 1
    else
        log "program is already running (pid=$existingPid)"
        exit 1
    fi
  fi
fi

# parse the command line parameters

if [ "$1" == "stop" ]; then
  log program is not running
  exit 1
elif [ "$1" == "start" ]; then
  : # continue since this is the default
elif [ "$1" != "" ]; then
  log unknown parameter: $1
  exit 1
fi

if [ ! -n "$DISPLAY" ]; then
  log No display defined
  exit 1
fi

echo $$ > $pidFile

ls -l $mediaDir > $oldLsFile

# Be sure to stop the slideshow if we get interupted

trap '{ log "signal received" ;cleanup ; exit 1; }' INT TERM

# Hide the cursor

unclutter -idle 1 &

# Continuously monitor the MVUC upcoming events directory

log program started, duration=$duration, sleep=$sleep

while true
do
  # rclone will wait, without issuing any errors, until the
  # gdrive is available, so to make sure this script continues
  # to work when the network is unavailable, we have to ping
  # the server before tring to sync the files.
  #
  # note that the rclone --contimeout flag does not seem to
  # do what I think it should do.

  #log "checking the media directory for updates..."
  if ping -c1 www.googleapis.com >/dev/null 2>&1; then
    rclone sync "gdrive:- Upcoming Events Media" $mediaDir
  else
    log ping failed, not syncing files from the google drive
  fi

  # check for changes in the configuration file

  sed '/^[[:blank:]]*#/d;s/#.*//' $cfgFile > $cfgFile.tmp

  value=`grep DURATION $cfgFile.tmp | cut -d= -f2`
  if [ -n "$value" -a "$value" -gt 0 2>/dev/null ]; then
    if [ $value != $duration ]; then
      log duration changed to $value
      duration=$value
      pkill -x mpv
    fi
  fi

  value=`grep SLEEP $cfgFile.tmp | cut -d= -f2`
  if [ -n "$value" -a "$value" -gt 0 2>/dev/null ]; then
    if [ $value != $sleep ]; then
      log sleep changed to $value
      sleep=$value
    fi
  fi

  if grep -q EXIT=true $cfgFile.tmp; then
      log forced exit
      break
  fi

  rm -f $cfgFile.tmp

  # if the contents of the slide show directory have changed, then stop the slideshow

  ls -l $mediaDir > $newLsFile 

  if ! diff $newLsFile $oldLsFile; then
    log media files have changed
    mv $newLsFile $oldLsFile
    pkill -x mpv
  else
    rm $newLsFile
  fi

  # if the slideshow has stopped, then check it's exit status and
  # restart it if it failed

  if ! pgrep -x mpv>/dev/null; then

    # if the slideshow stopped by someone hitting the q key, then
    # stop the script

    if [ "$mpvPid" != "" ]; then
      wait $mpvPid
      status=$?
      if [ "$status" == "0" ]; then
        log slideshow manually stopped
        break
      fi
    fi

    log restarting slide show
    #feh -F -D $duration -Z -B black -Y $mediaDir & fehPid=$!
    mpv --fs --loop-playlist --image-display-duration=$duration -really-quiet $mediaDir & mpvPid=$!
  fi

  # we can reach a google imposed limit if we accsses the drive too quickly, so
  # wait a while before trying again

  sleep $sleep
done

cleanup

log exited
