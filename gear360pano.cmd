:<<"remIGNORE_THIS_LINE"
@echo off
goto :CMDSCRIPT
remIGNORE_THIS_LINE

# This is a small script to stitch panorama images produced
# by Samsung Gear360
#
# TODOs:
# - vignetting correction is not there yet
# - could add some parameters for output, jpeg quality, etc.
#
# Trick with Win/Linux from here:
# http://stackoverflow.com/questions/17510688/single-script-to-run-in-both-windows-batch-and-linux-bash

################################ Linux part here

# http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in
DIR=$(dirname `which $0`)
PTOTMPL=$3
OUTTMPNAME="out"
OUTNAME=$2
JPGQUALITY=97
PTOJPGFILENAME="dummy.jpg"

# Clean-up function
clean_up() {
    if [ -d "$TEMPDIR" ]; then
        rm -rf "$TEMPDIR"
    fi
}

# Function to check if a command fails
# http://stackoverflow.com/questions/5195607/checking-bash-exit-status-of-several-commands-efficiently
run_command() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "Error while running $1" >&2
        if [ $1 != "notify-send" ]; then
            # Display error in a nice graphical popup if available
            run_command notify-send "Error while running $1"
        fi
        clean_up
        exit 1
    fi
    return $status
}

# Check argument(s)
if [ -z "$1" ]; then
    echo "Small script to stitch raw panorama files."
    echo "Raw meaning two fisheye images side by side."
    echo -e "Script originally writen for Samsung Gear 360.\n"
    echo -e "Usage:\n$0 INNAME [outputfile] [hugintemplate]\n"
    echo "Where INNAME is a panorama file from camera,"
    echo "output parameter and hugintemplate are optional."
    exit 1
fi

# Output name as second argument
if [ -z "$2" ]; then
    # The output needs to be done in the folder of the original file if used via nautlius open-with
    OUTNAME=`dirname "$1"`/`basename "${1%.*}"`_pano.jpg
fi

# Template to use as third argument
if [ -z "$3" ]; then
    # Assume default template
    PTOTMPL="$DIR/gear360tmpl.pto"
fi

# Check if we have the software to do it (Hugin, ImageMagick)
# http://stackoverflow.com/questions/592620/check-if-a-program-exists-from-a-bash-script
type nona >/dev/null 2>&1 || { echo >&2 "Hugin required but it's not installed. Aborting."; exit 1; }

# Create temporary directory locally to stay compatible with other OSes
# Not using '-p .' might cause some problems on non-unix systems (cygwin?)
TEMPDIR=`mktemp -d`

STARTTS=`date +%s`
# Stitch panorama (same file twice as input)
echo "Processing input images (nona)"
# We need to use run_command with many parameters, or $1 doesn't get
# quoted correctly and we cannot use filenames with spaces
run_command  "nona" "-o" "$TEMPDIR/$OUTTMPNAME" \
             "-m" "TIFF_m" \
             "-z" "LZW" \
             $PTOTMPL \
             "$1" \
             "$1"

echo "Stitching input images (enblend)"
# We need to use run_command with many parameters,
# or the directories don't get quoted correctly
run_command "enblend" "-o" "$OUTNAME" \
            "--compression=jpeg:$JPGQUALITY" \
            "$TEMPDIR/${OUTTMPNAME}0000.tif" \
            "$TEMPDIR/${OUTTMPNAME}0001.tif"

# TODO: not sure about the tag exclusion list...
# Note: there's no check as exiftool is needed by Hugin
IMG_WIDTH=7776
IMG_HEIGHT=3888
echo "Setting EXIF data (exiftool)"
run_command "exiftool" "-ProjectionType=equirectangular" \
            "-q" \
            "-m" \
            "-TagsFromFile" "$1" \
            "-exif:all" \
            "-ExifByteOrder=II" \
            "-FullPanoWidthPixels=$IMG_WIDTH" \
            "-FullPanoHeightPixels=$IMG_HEIGHT" \
            "-CroppedAreaImageWidthPixels=$IMG_WIDTH" \
            "-CroppedAreaImageHeightPixels=$IMG_HEIGHT" \
            "-CroppedAreaLeftPixels=0" \
            "-CroppedAreaTopPixels=0" \
            "--FocalLength" \
            "--FieldOfView" \
            "--ThumbnailImage" \
            "--PreviewImage" \
            "--EncodingProcess" \
            "--YCbCrSubSampling" \
            "--Compression" \
            "$OUTNAME"

# Problems with "-delete_original!", manually remove the file
rm ${OUTNAME}_original

# Clean up any files/directories we created on the way
clean_up

# Inform user about the result
ENDTS=`date +%s`
RUNTIME=$((ENDTS-STARTTS))
echo Panorama written to $OUTNAME, took: $RUNTIME s

# Uncomment this if you don't do videos; otherwise, it is quite annoying
#notify-send "Panorama written to $OUTNAME, took: $RUNTIME s"
exit 0

################################ Windows part here

:CMDSCRIPT

rem http://stackoverflow.com/questions/673523/how-to-measure-execution-time-of-command-in-windows-command-line
set start=%time%

set HUGINPATH1=C:/Program Files/Hugin/bin
set HUGINPATH2=C:/Program Files (x86)/Hugin/bin
rem This is to avoid some weird bug (???) %~dp0 doesn't work in a loop (effect of shift?)
set SCRIPTNAME=%0
set SCRIPTPATH=%~dp0
set OUTTMPNAME=out
set INNAME=
set OUTNAME=
set PTOTMPL=
set JPGQUALITY=97
set PTOJPGFILENAME=dummy.jpg

rem Process arguments
set PARAMCOUNT=0
rem We need this due to stupid parameter substitution
setlocal enabledelayedexpansion
:PARAMLOOP
rem Small hack as substring doesn't work on %1 (need to use delayed sub.?)
set _TMP=%1
set FIRSTCHAR=%_TMP:~0,1%
if "%_TMP%" == "" goto PARAMDONE
if "%FIRSTCHAR%" == "/" (
  set SWITCH=%_TMP:~1,2%
  rem Switch processing
  if /i "%SWITCH%" == "q" (
    shift
    set JPGQUALITY=%1
    echo "JPEG quality set to: !JPGQUALITY!"
  )
) else (
  if %PARAMCOUNT% EQU 0 set PROTOINNAME=%_TMP%
  if %PARAMCOUNT% EQU 1 set OUTNAME=%_TMP%
  if %PARAMCOUNT% EQU 2 set PTOTMPL=%_TMP%
  set /a PARAMCOUNT+=1
)
shift & goto PARAMLOOP
:PARAMDONE

rem Check arguments and assume defaults
if "%PROTOINNAME%" == "" goto NOARGS
rem OUTNAME will be calculated dynamically
if "%PTOTMPL%" == "" (
  set PTOTMPL="%SCRIPTPATH%gear360tmpl.pto"
)

rem Where's enblend? Prefer 64 bits
if not exist "%HUGINPATH1%/enblend.exe" (
  rem 64 bits not found? Check x86
  if not exist "%HUGINPATH2%/enblend.exe" goto NOHUGIN
  rem Found x86, overwrite original path
  set HUGINPATH1=%HUGINPATH2%
)

rem Do processing of files
for %%f in (%PROTOINNAME%) do (
  set OUTNAME=%%~nf_pano.jpg
  set INNAME=%%f
  call :PROCESSPANORAMA !INNAME! !OUTNAME!
)

rem Time calculation
set end=%time%
set options="tokens=1-4 delims=:.,"
rem Don't try to break lines here, it will most probably not work
for /f %options% %%a in ("%start%") do set start_h=%%a&set /a start_m=100%%b %% 100&set /a start_s=100%%c %% 100&set /a start_ms=100%%d %% 100
for /f %options% %%a in ("%end%") do set end_h=%%a&set /a end_m=100%%b %% 100&set /a end_s=100%%c %% 100&set /a end_ms=100%%d %% 100

set /a hours=%end_h%-%start_h%
set /a mins=%end_m%-%start_m%
set /a secs=%end_s%-%start_s%
set /a ms=%end_ms%-%start_ms%
if %ms% lss 0 set /a secs = %secs% - 1 & set /a ms = 100%ms%
if %secs% lss 0 set /a mins = %mins% - 1 & set /a secs = 60%secs%
if %mins% lss 0 set /a hours = %hours% - 1 & set /a mins = 60%mins%
if %hours% lss 0 set /a hours = 24%hours%
if 1%ms% lss 100 set ms=0%ms%

rem mission accomplished
set /a totalsecs = %hours%*3600 + %mins%*60 + %secs%

echo Processing took: %totalsecs% s

goto END

:NOARGS

echo.
echo Script to stitch raw panorama files, raw meaning
echo two fisheye images side by side.
echo.
echo Script originally writen for Samsung Gear 360.
echo.
echo Usage:
echo %SCRIPTNAME% [/q quality] infile [outputfile] [hugintemplate]
echo.
echo Where infile is a panorama file from camera, it can
echo be a wildcard (ex. *.jpg).
echo output and hugintemplate are optional, defaults will
echo be assumed if they are not given
echo.
echo /q switch sets output jpeg quality
echo.
goto END

:NOHUGIN

echo.
echo Hugin is not installed or installed in non-standard directory
echo Was looking in: %HUGINPATH1%
echo and: %HUGINPATH2%
goto END

:NONAERROR

echo nona failed, panorama not created
goto END

:ENBLENDERROR

echo enblend failed, panorama not created
goto END

:PROCESSPANORAMA

set LOCALINNAME=%1
set LOCALOUTNAME=%2

rem Execute commands (as simple as it is)
echo Processing input images (nona)
"%HUGINPATH1%/nona.exe" -o %TEMP%/%OUTTMPNAME% ^
              -m TIFF_m ^
              -z LZW ^
              %PTOTMPL% ^
              %LOCALINNAME% ^
              %LOCALINNAME%
if %ERRORLEVEL% equ 1 goto NONAERROR

echo Stitching input images (enblend)
"%HUGINPATH1%/enblend.exe" -o %2 ^
              --compression=jpeg:%JPGQUALITY% ^
              %TEMP%/%OUTTMPNAME%0000.tif ^
              %TEMP%/%OUTTMPNAME%0001.tif
if %ERRORLEVEL% equ 1 goto ENBLENDERROR

rem Check if we have exiftool...
echo Setting EXIF data (exiftool)
set IMG_WIDTH=7776
set IMG_HEIGHT=3888
"%HUGINPATH1%/exiftool.exe" -ProjectionType=equirectangular ^
                            -m ^
                            -q ^
                            -TagsFromFile %LOCALINNAME% ^
                            -exif:all ^
                            -ExifByteOrder=II ^
                            -FullPanoWidthPixels=%IMG_WIDTH% ^
                            -FullPanoHeightPixels=%IMG_HEIGHT% ^
                            -CroppedAreaImageWidthPixels=%IMG_WIDTH% ^
                            -CroppedAreaImageHeightPixels=%IMG_HEIGHT% ^
                            -CroppedAreaLeftPixels=0 ^
                            -CroppedAreaTopPixels=0 ^
                            --FocalLength ^
                            --FieldOfView ^
                            --ThumbnailImage ^
                            --PreviewImage ^
                            --EncodingProcess ^
                            --YCbCrSubSampling ^
                            --Compression %LOCALOUTNAME%
if "%ERRORLEVEL%" EQU 1 echo Setting EXIF failed, ignoring

rem There are problems with -delete_original in exiftool, manually remove the file
del %LOCALOUTNAME%_original
exit /b 0

:END
