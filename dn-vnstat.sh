#!/bin/sh

##############################################################
##                                                          ##
##                     vnStat on Merlin                     ##
##                for AsusWRT-Merlin routers                ##
##                                                          ##
##                    Concept by dev_null                   ##
##                  Implemented by Jack Yaz                 ##
##       https://github.com/AMTM-OSR/vnstat-on-merlin       ##
## Forked from https://github.com/de-vnull/vnstat-on-merlin ##
##                                                          ##
##############################################################
# Last Modified: 2025-Aug-04
#-------------------------------------------------------------

########         Shellcheck directives     ######
# shellcheck disable=SC1091
# shellcheck disable=SC2009
# shellcheck disable=SC2012
# shellcheck disable=SC2016
# shellcheck disable=SC2018
# shellcheck disable=SC2019
# shellcheck disable=SC2059
# shellcheck disable=SC2086
# shellcheck disable=SC2154
# shellcheck disable=SC2155
# shellcheck disable=SC2174
# shellcheck disable=SC2181
# shellcheck disable=SC3018
# shellcheck disable=SC3037
# shellcheck disable=SC3043
# shellcheck disable=SC3045
#################################################

### Start of script variables ###
readonly SCRIPT_NAME="dn-vnstat"
readonly SCRIPT_VERSION="v2.0.9"
readonly SCRIPT_VERSTAG="25080400"
SCRIPT_BRANCH="develop"
SCRIPT_REPO="https://raw.githubusercontent.com/AMTM-OSR/vnstat-on-merlin/$SCRIPT_BRANCH"
readonly SCRIPT_DIR="/jffs/addons/$SCRIPT_NAME.d"
readonly SCRIPT_WEBPAGE_DIR="$(readlink -f /www/user)"
readonly SCRIPT_WEB_DIR="$SCRIPT_WEBPAGE_DIR/$SCRIPT_NAME"
readonly TEMP_MENU_TREE="/tmp/menuTree.js"
readonly SHARED_DIR="/jffs/addons/shared-jy"
readonly SHARED_REPO="https://raw.githubusercontent.com/AMTM-OSR/shared-jy/master"
readonly SHARED_WEB_DIR="$SCRIPT_WEBPAGE_DIR/shared-jy"

[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL="$(nvram get productid)" || ROUTER_MODEL="$(nvram get odmpid)"
[ -f /opt/bin/sqlite3 ] && SQLITE3_PATH=/opt/bin/sqlite3 || SQLITE3_PATH=/usr/sbin/sqlite3

##-------------------------------------##
## Added by Martinski W. [2025-Apr-27] ##
##-------------------------------------##
readonly scriptVersRegExp="v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})"
readonly webPageMenuAddons="menuName: \"Addons\","
readonly webPageHelpSupprt="tabName: \"Help & Support\"},"
readonly webPageFileRegExp="user([1-9]|[1-2][0-9])[.]asp"
readonly webPageLineTabExp="\{url: \"$webPageFileRegExp\", tabName: "
readonly webPageLineRegExp="${webPageLineTabExp}\"$SCRIPT_NAME\"\},"
readonly BEGIN_MenuAddOnsTag="/\*\*BEGIN:_AddOns_\*\*/"
readonly ENDIN_MenuAddOnsTag="/\*\*ENDIN:_AddOns_\*\*/"
readonly branchx_TAG="Branch: $SCRIPT_BRANCH"
readonly version_TAG="${SCRIPT_VERSION}_${SCRIPT_VERSTAG}"

readonly _12Hours=43200
readonly _24Hours=86400
readonly _36Hours=129600
readonly oneKByte=1024
readonly oneMByte=1048576
readonly ei8MByte=8388608
readonly ni9MByte=9437184
readonly tenMByte=10485760
readonly oneGByte=1073741824
readonly SHARE_TEMP_DIR="/opt/share/tmp"

##-------------------------------------##
## Added by Martinski W. [2025-Jun-16] ##
##-------------------------------------##
readonly sqlDBLogFileSize=102400
readonly sqlDBLogDateTime="%Y-%m-%d %H:%M:%S"
readonly sqlDBLogFileName="${SCRIPT_NAME}_DBSQL_DEBUG.LOG"

### End of script variables ###

### Start of output format variables ###
readonly CRIT="\\e[41m"
readonly ERR="\\e[31m"
readonly WARN="\\e[33m"
readonly PASS="\\e[32m"
readonly BOLD="\\e[1m"
readonly SETTING="${BOLD}\\e[36m"
readonly CLEARFORMAT="\\e[0m"

##----------------------------------------##
## Modified by Martinski W. [2025-Apr-28] ##
##----------------------------------------##
readonly CLRct="\e[0m"
readonly REDct="\e[1;31m"
readonly GRNct="\e[1;32m"
readonly MGNTct="\e[1;35m"
readonly CritBREDct="\e[30;101m"
readonly WarnBYLWct="\e[30;103m"
readonly WarnBMGNct="\e[30;105m"

### End of output format variables ###

# Give priority to built-in binaries #
export PATH="/bin:/usr/bin:/sbin:/usr/sbin:$PATH"

##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output()
{
	local prioStr  prioNum
	if [ $# -gt 2 ] && [ -n "$3" ]
	then prioStr="$3"
	else prioStr="NOTICE"
	fi
	if [ "$1" = "true" ]
	then
		case "$prioStr" in
		    "$CRIT") prioNum=2 ;;
		     "$ERR") prioNum=3 ;;
		    "$WARN") prioNum=4 ;;
		    "$PASS") prioNum=6 ;; #INFO#
		          *) prioNum=5 ;; #NOTICE#
		esac
		logger -t "$SCRIPT_NAME" -p $prioNum "$2"
	fi
	printf "${BOLD}${3}%s${CLEARFORMAT}\n\n" "$2"
}

### Check firmware version contains the "am_addons" feature flag ###
Firmware_Version_Check()
{
	if nvram get rc_support | grep -qF "am_addons"; then
		return 0
	else
		return 1
	fi
}

### Create "lock" file to ensure script only allows 1 concurrent process for certain actions ###
### Code for these functions inspired by https://github.com/Adamm00 - credit to @Adamm ###
Check_Lock()
{
	if [ -f "/tmp/$SCRIPT_NAME.lock" ]
	then
		ageoflock="$(($(date +'%s') - $(date +'%s' -r "/tmp/$SCRIPT_NAME.lock")))"
		if [ "$ageoflock" -gt 600 ]  #10 minutes#
		then
			Print_Output true "Stale lock file found (>600 seconds old) - purging lock" "$ERR"
			kill "$(sed -n '1p' "/tmp/$SCRIPT_NAME.lock")" >/dev/null 2>&1
			Clear_Lock
			echo "$$" > "/tmp/$SCRIPT_NAME.lock"
			return 0
		else
			Print_Output true "Lock file found (age: $ageoflock seconds)" "$ERR"
			if [ $# -eq 0 ] || [ -z "$1" ]
			then
				exit 1
			else
				if [ "$1" = "webui" ]
				then
					echo 'var vnstatstatus = "LOCKED";' > /tmp/detect_vnstat.js
					exit 1
				fi
				return 1
			fi
		fi
	else
		echo "$$" > "/tmp/$SCRIPT_NAME.lock"
		return 0
	fi
}

Clear_Lock()
{
	rm -f "/tmp/$SCRIPT_NAME.lock" 2>/dev/null
	return 0
}
############################################################################

### Create "settings" in the custom_settings file, used by the WebUI for version information and script updates ###
### local is the version of the script installed, server is the version on Github ###
##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Set_Version_Custom_Settings()
{
	SETTINGSFILE="/jffs/addons/custom_settings.txt"
	case "$1" in
		local)
			if [ -f "$SETTINGSFILE" ]
			then
				if [ "$(grep -c "^dnvnstat_version_local" "$SETTINGSFILE")" -gt 0 ]
				then
					if [ "$2" != "$(grep "^dnvnstat_version_local" "$SETTINGSFILE" | cut -f2 -d' ')" ]
					then
						sed -i "s/^dnvnstat_version_local.*/dnvnstat_version_local $2/" "$SETTINGSFILE"
					fi
				else
					echo "dnvnstat_version_local $2" >> "$SETTINGSFILE"
				fi
			else
				echo "dnvnstat_version_local $2" >> "$SETTINGSFILE"
			fi
		;;
		server)
			if [ -f "$SETTINGSFILE" ]
			then
				if [ "$(grep -c "^dnvnstat_version_server" "$SETTINGSFILE")" -gt 0 ]
				then
					if [ "$2" != "$(grep "^dnvnstat_version_server" "$SETTINGSFILE" | cut -f2 -d' ')" ]
					then
						sed -i "s/^dnvnstat_version_server.*/dnvnstat_version_server $2/" "$SETTINGSFILE"
					fi
				else
					echo "dnvnstat_version_server $2" >> "$SETTINGSFILE"
				fi
			else
				echo "dnvnstat_version_server $2" >> "$SETTINGSFILE"
			fi
		;;
	esac
}

### Checks for changes to Github version of script and returns reason for change (version or md5/minor), local version and server version ###
##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Update_Check()
{
	echo 'var updatestatus = "InProgress";' > "$SCRIPT_WEB_DIR/detect_update.js"
	doupdate="false"
	localver="$(grep "SCRIPT_VERSION=" "/jffs/scripts/$SCRIPT_NAME" | grep -m1 -oE "$scriptVersRegExp")"
	[ -n "$localver" ] && Set_Version_Custom_Settings local "$localver"
	curl -fsL --retry 4 --retry-delay 5 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep -qF "de-vnull" || \
	{ Print_Output true "404 error detected - stopping update" "$ERR"; return 1; }
	serverver="$(curl -fsL --retry 4 --retry-delay 5 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep "SCRIPT_VERSION=" | grep -m1 -oE "$scriptVersRegExp")"
	if [ "$localver" != "$serverver" ]
	then
		doupdate="version"
		Set_Version_Custom_Settings server "$serverver"
		echo 'var updatestatus = "'"$serverver"'";'  > "$SCRIPT_WEB_DIR/detect_update.js"
	else
		localmd5="$(md5sum "/jffs/scripts/$SCRIPT_NAME" | awk '{print $1}')"
		remotemd5="$(curl -fsL --retry 4 --retry-delay 5 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | md5sum | awk '{print $1}')"
		if [ "$localmd5" != "$remotemd5" ]
		then
			doupdate="md5"
			Set_Version_Custom_Settings server "$serverver-hotfix"
			echo 'var updatestatus = "'"$serverver-hotfix"'";'  > "$SCRIPT_WEB_DIR/detect_update.js"
		fi
	fi
	if [ "$doupdate" = "false" ]; then
		echo 'var updatestatus = "None";' > "$SCRIPT_WEB_DIR/detect_update.js"
	fi
	echo "$doupdate,$localver,$serverver"
}

### Updates the script from Github including any secondary files ###
### Accepts arguments of:
### force - download from server even if no change detected
### unattended - don't return user to script CLI menu
##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Update_Version()
{
	if [ $# -eq 0 ] || [ -z "$1" ]
	then
		updatecheckresult="$(Update_Check)"
		isupdate="$(echo "$updatecheckresult" | cut -f1 -d',')"
		localver="$(echo "$updatecheckresult" | cut -f2 -d',')"
		serverver="$(echo "$updatecheckresult" | cut -f3 -d',')"

		if [ "$isupdate" = "version" ]; then
			Print_Output true "New version of $SCRIPT_NAME available - $serverver" "$PASS"
		elif [ "$isupdate" = "md5" ]; then
			Print_Output true "MD5 hash of $SCRIPT_NAME does not match - hotfix available - $serverver" "$PASS"
		fi

		if [ "$isupdate" != "false" ]
		then
			printf "\n${BOLD}Do you want to continue with the update? (y/n)${CLEARFORMAT}  "
			read -r confirm
			case "$confirm" in
				y|Y)
					printf "\n"
					Update_File shared-jy.tar.gz
					Update_File vnstat-ui.asp
					Update_File vnstat.conf
					Update_File S33vnstat
					Download_File "$SCRIPT_REPO/$SCRIPT_NAME.sh" "/jffs/scripts/$SCRIPT_NAME" && \
					Print_Output true "$SCRIPT_NAME successfully updated" "$PASS"
					chmod 0755 "/jffs/scripts/$SCRIPT_NAME"
					Set_Version_Custom_Settings local "$serverver"
					Set_Version_Custom_Settings server "$serverver"
					Clear_Lock
					PressEnter
					exec "$0"
					exit 0
				;;
				*)
					printf "\n"
					Clear_Lock
					return 1
				;;
			esac
		else
			Print_Output true "No updates available - latest is $localver" "$WARN"
			Clear_Lock
		fi
	fi

	if [ "$1" = "force" ]
	then
		serverver="$(curl -fsL --retry 4 --retry-delay 5 "$SCRIPT_REPO/$SCRIPT_NAME.sh" | grep "SCRIPT_VERSION=" | grep -m1 -oE "$scriptVersRegExp")"
		Print_Output true "Downloading latest version ($serverver) of $SCRIPT_NAME" "$PASS"
		Update_File shared-jy.tar.gz
		Update_File vnstat-ui.asp
		Update_File vnstat.conf
		Update_File S33vnstat
		Download_File "$SCRIPT_REPO/$SCRIPT_NAME.sh" "/jffs/scripts/$SCRIPT_NAME" && \
		Print_Output true "$SCRIPT_NAME successfully updated" "$PASS"
		chmod 0755 "/jffs/scripts/$SCRIPT_NAME"
		Set_Version_Custom_Settings local "$serverver"
		Set_Version_Custom_Settings server "$serverver"
		Clear_Lock
		if [ $# -lt 2 ] || [ -z "$2" ]
		then
			PressEnter
			exec "$0"
		elif [ "$2" = "unattended" ]
		then
			exec "$0" postupdate
		fi
		exit 0
	fi
}

Validate_Number()
{
	if [ "$1" -eq "$1" ] 2>/dev/null; then
		return 0
	else
		return 1
	fi
}

Validate_Bandwidth()
{
	if echo "$1" | /bin/grep -oq "^[0-9]*\.\?[0-9]\?[0-9]$"; then
		return 0
	else
		return 1
	fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Aug-03] ##
##-------------------------------------##
VNStat_ServiceCheck()
{
    local runFullCheck=true
    local initServicePath  saveServicePath

    if [ $# -gt 0 ] && [ -n "$1" ] && \
       echo "$1" | grep -qE "^(true|false)$"
    then runFullCheck="$1" ; fi

    "$runFullCheck" && Entware_Ready
    initServicePath="/opt/etc/init.d/S33vnstat"
    saveServicePath="$SCRIPT_DIR/S33vnstat"

    if "$runFullCheck" || [ ! -s "$saveServicePath" ]
    then
        Update_File S33vnstat >/dev/null 2>&1
    else
        # Stop & remove extraneous service scripts #
        if [ -f /opt/etc/init.d/S32vnstat ]
        then
            /opt/etc/init.d/S32vnstat stop >/dev/null 2>&1
            sleep 2 ; killall -q vnstatd ; sleep 1
            rm -f /opt/etc/init.d/S32vnstat
        fi
        if [ -f /opt/etc/init.d/S32vnstat2 ]
        then
            /opt/etc/init.d/S32vnstat2 stop >/dev/null 2>&1
            sleep 2 ; killall -q vnstatd ; sleep 1
            rm -f /opt/etc/init.d/S32vnstat2
        fi

        # Make sure we have the vnStat version #
        if [ -s "$saveServicePath" ] && [ -s "$initServicePath" ] && \
           ! diff -q "$initServicePath" "$saveServicePath" >/dev/null 2>&1 
        then
            "$initServicePath" stop >/dev/null 2>&1
            sleep 2 ; killall -q vnstatd
            cp -fp "$saveServicePath" "$initServicePath"
            chmod a+x "$initServicePath"
        fi
        [ -z "$(pidof vnstatd)" ] && "$initServicePath" restart
    fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Aug-03] ##
##-------------------------------------##
VNStat_ServiceUpdate()
{
	local initServicePath="/opt/etc/init.d/S33vnstat"

	if [ -f "$initServicePath" ]
	then
		"$initServicePath" stop >/dev/null 2>&1
		sleep 2 ; killall -q vnstatd ; sleep 1
		rm -f "$initServicePath"
	fi
	if [ -f /opt/etc/init.d/S32vnstat ]
	then
		/opt/etc/init.d/S32vnstat stop >/dev/null 2>&1
		sleep 2 ; killall -q vnstatd ; sleep 1
		rm -f /opt/etc/init.d/S32vnstat
	fi
	if [ -f /opt/etc/init.d/S32vnstat2 ]
	then
		/opt/etc/init.d/S32vnstat2 stop >/dev/null 2>&1
		sleep 2 ; killall -q vnstatd ; sleep 1
		rm -f /opt/etc/init.d/S32vnstat2
	fi

	Download_File "$SCRIPT_REPO/S33vnstat" "$initServicePath"
	chmod a+x "$initServicePath"
	"$initServicePath" restart >/dev/null 2>&1
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-03] ##
##----------------------------------------##
Update_File()
{
	if [ "$1" = "vnstat-ui.asp" ]
	then  ## WebUI page ##
		tmpfile="/tmp/$1"
		if [ -f "$SCRIPT_DIR/$1" ]
		then
			Download_File "$SCRIPT_REPO/$1" "$tmpfile"
			if ! diff -q "$tmpfile" "$SCRIPT_DIR/$1" >/dev/null 2>&1
			then
				Get_WebUI_Page "$SCRIPT_DIR/$1"
				sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"
				rm -f "$SCRIPT_WEBPAGE_DIR/$MyWebPage" 2>/dev/null
				Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
				Print_Output true "New version of $1 downloaded" "$PASS"
				Mount_WebUI
			fi
			rm -f "$tmpfile"
		else
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_DIR/$1"
			Print_Output true "New version of $1 downloaded" "$PASS"
			Mount_WebUI
		fi
	elif [ "$1" = "shared-jy.tar.gz" ]
	then  ## shared web resources ##
		if [ ! -f "$SHARED_DIR/${1}.md5" ]
		then
			Download_File "$SHARED_REPO/$1" "$SHARED_DIR/$1"
			Download_File "$SHARED_REPO/${1}.md5" "$SHARED_DIR/${1}.md5"
			tar -xzf "$SHARED_DIR/$1" -C "$SHARED_DIR"
			rm -f "$SHARED_DIR/$1"
			Print_Output true "New version of $1 downloaded" "$PASS"
		else
			localmd5="$(cat "$SHARED_DIR/${1}.md5")"
			remotemd5="$(curl -fsL --retry 4 --retry-delay 5 "$SHARED_REPO/${1}.md5")"
			if [ "$localmd5" != "$remotemd5" ]
			then
				Download_File "$SHARED_REPO/$1" "$SHARED_DIR/$1"
				Download_File "$SHARED_REPO/${1}.md5" "$SHARED_DIR/${1}.md5"
				tar -xzf "$SHARED_DIR/$1" -C "$SHARED_DIR"
				rm -f "$SHARED_DIR/$1"
				Print_Output true "New version of $1 downloaded" "$PASS"
			fi
		fi
	elif [ "$1" = "S33vnstat" ]
	then
		srvceFile="$SCRIPT_DIR/$1"
		rm -f "$srvceFile"
		Download_File "$SCRIPT_REPO/$1" "$srvceFile"
		if ! diff -q "$srvceFile" "/opt/etc/init.d/$1" >/dev/null 2>&1
		then
			Print_Output true "New version of $1 downloaded" "$PASS"
			VNStat_ServiceUpdate
		else
			VNStat_ServiceCheck false
		fi
	elif [ "$1" = "vnstat.conf" ]
	then  ## vnstat config file ##
		tmpfile="/tmp/$1"
		Download_File "$SCRIPT_REPO/$1" "$tmpfile"
		if [ ! -f "$SCRIPT_STORAGE_DIR/$1" ]
		then
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_STORAGE_DIR/$1.default"
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_STORAGE_DIR/$1"
			Print_Output true "$SCRIPT_STORAGE_DIR/$1 does not exist, downloading now." "$PASS"
		elif [ -f "$SCRIPT_STORAGE_DIR/$1.default" ]
		then
			if ! diff -q "$tmpfile" "$SCRIPT_STORAGE_DIR/$1.default" >/dev/null 2>&1
			then
				Download_File "$SCRIPT_REPO/$1" "$SCRIPT_STORAGE_DIR/$1.default"
				Print_Output true "New default version of $1 downloaded to $SCRIPT_STORAGE_DIR/$1.default, please compare against your $SCRIPT_STORAGE_DIR/$1" "$PASS"
			fi
		else
			Download_File "$SCRIPT_REPO/$1" "$SCRIPT_STORAGE_DIR/$1.default"
			Print_Output true "$SCRIPT_STORAGE_DIR/$1.default does not exist, downloading now. Please compare against your $SCRIPT_STORAGE_DIR/$1" "$PASS"
		fi
		rm -f "$tmpfile"
	else
		return 1
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2025-May-01] ##
##----------------------------------------##
Conf_FromSettings()
{
	SETTINGSFILE="/jffs/addons/custom_settings.txt"
	TMPFILE="/tmp/dnvnstat_settings.txt"

	if [ -f "$SETTINGSFILE" ]
	then
		if [ "$(grep "^dnvnstat_" "$SETTINGSFILE" | grep -v "version" -c)" -gt 0 ]
		then
			Print_Output true "Updated settings from WebUI found, merging into $SCRIPT_CONF..." "$PASS"
			cp -a "$SCRIPT_CONF" "${SCRIPT_CONF}.bak"
			cp -a "$VNSTAT_CONFIG" "${VNSTAT_CONFIG}.bak"
			grep "^dnvnstat_" "$SETTINGSFILE" | grep -v "version" > "$TMPFILE"
			sed -i "s/^dnvnstat_//g;s/ /=/g" "$TMPFILE"
			warningresetrequired="false"
			while IFS='' read -r line || [ -n "$line" ]
			do
				SETTINGNAME="$(echo "$line" | cut -f1 -d'=' | awk '{ print toupper($1) }')"
				SETTINGVALUE="$(echo "$line" | cut -f2 -d'=')"
				if [ "$SETTINGNAME" != "MONTHROTATE" ]
				then
					if [ "$SETTINGNAME" = "DATAALLOWANCE" ]
					then
						if [ "$(echo "$SETTINGVALUE $(BandwidthAllowance check)" | awk '{print ($1 != $2)}')" -eq 1 ]
						then
							warningresetrequired="true"
						fi
					fi
					sed -i "s/$SETTINGNAME=.*/$SETTINGNAME=$SETTINGVALUE/" "$SCRIPT_CONF"
				elif [ "$SETTINGNAME" = "MONTHROTATE" ]
				then
					if [ "$SETTINGVALUE" != "$(AllowanceStartDay check)" ]
					then
						warningresetrequired="true"
					fi
					sed -i 's/^MonthRotate .*$/MonthRotate '"$SETTINGVALUE"'/' "$VNSTAT_CONFIG"
				fi
			done < "$TMPFILE"

			grep '^dnvnstat_version' "$SETTINGSFILE" > "$TMPFILE"
			sed -i "\\~dnvnstat_~d" "$SETTINGSFILE"
			mv -f "$SETTINGSFILE" "${SETTINGSFILE}.bak"
			cat "${SETTINGSFILE}.bak" "$TMPFILE" > "$SETTINGSFILE"
			rm -f "$TMPFILE"
			rm -f "${SETTINGSFILE}.bak"

			if diff "$SCRIPT_CONF" "${SCRIPT_CONF}.bak" | grep -q "STORAGELOCATION="
			then
				STORAGEtype="$(ScriptStorageLocation check)"
				if [ "$STORAGEtype" = "jffs" ]
				then
				    ## Check if enough free space is available in JFFS ##
				    if _Check_JFFS_SpaceAvailable_ "$SCRIPT_STORAGE_DIR"
				    then ScriptStorageLocation jffs
				    else ScriptStorageLocation usb
				    fi
				elif [ "$STORAGEtype" = "usb" ]
				then
				    ScriptStorageLocation usb
				fi
				Create_Symlinks
			fi

			/opt/etc/init.d/S33vnstat restart >/dev/null 2>&1
			TZ=$(cat /etc/TZ)
			export TZ

			if [ "$warningresetrequired" = "true" ]; then
				Reset_Allowance_Warnings force
			fi
			Check_Bandwidth_Usage silent

			Print_Output true "Merge of updated settings from WebUI completed successfully" "$PASS"
		else
			Print_Output false "No updated settings from WebUI found, no merge necessary" "$PASS"
		fi
	fi
}

### Create directories in filesystem if they do not exist ###
##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Create_Dirs()
{
	if [ ! -d "$SCRIPT_DIR" ]; then
		mkdir -p "$SCRIPT_DIR"
	fi

	if [ ! -d "$SCRIPT_STORAGE_DIR" ]; then
		mkdir -p "$SCRIPT_STORAGE_DIR"
	fi

	if [ ! -d "$IMAGE_OUTPUT_DIR" ]; then
		mkdir -p "$IMAGE_OUTPUT_DIR"
	fi

	if [ ! -d "$CSV_OUTPUT_DIR" ]; then
		mkdir -p "$CSV_OUTPUT_DIR"
	fi

	if [ ! -d "$SHARED_DIR" ]; then
		mkdir -p "$SHARED_DIR"
	fi

	if [ ! -d "$SCRIPT_WEBPAGE_DIR" ]; then
		mkdir -p "$SCRIPT_WEBPAGE_DIR"
	fi

	if [ ! -d "$SCRIPT_WEB_DIR" ]; then
		mkdir -p "$SCRIPT_WEB_DIR"
	fi

	if [ ! -d "$SHARE_TEMP_DIR" ]
	then
		mkdir -m 777 -p "$SHARE_TEMP_DIR"
		export SQLITE_TMPDIR TMPDIR
	fi
}

### Create symbolic links to /www/user for WebUI files to avoid file duplication ###
Create_Symlinks()
{
	rm -rf "${SCRIPT_WEB_DIR:?}/"* 2>/dev/null

	ln -s /tmp/detect_vnstat.js "$SCRIPT_WEB_DIR/detect_vnstat.js" 2>/dev/null
	ln -s "$SCRIPT_STORAGE_DIR/.vnstatusage" "$SCRIPT_WEB_DIR/vnstatusage.js" 2>/dev/null
	ln -s "$VNSTAT_OUTPUT_FILE" "$SCRIPT_WEB_DIR/vnstatoutput.htm" 2>/dev/null
	ln -s "$SCRIPT_CONF" "$SCRIPT_WEB_DIR/config.htm" 2>/dev/null
	ln -s "$VNSTAT_CONFIG" "$SCRIPT_WEB_DIR/vnstatconf.htm" 2>/dev/null
	ln -s "$IMAGE_OUTPUT_DIR" "$SCRIPT_WEB_DIR/images" 2>/dev/null
	ln -s "$CSV_OUTPUT_DIR" "$SCRIPT_WEB_DIR/csv" 2>/dev/null

	if [ ! -d "$SHARED_WEB_DIR" ]; then
		ln -s "$SHARED_DIR" "$SHARED_WEB_DIR" 2>/dev/null
	fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-16] ##
##-------------------------------------##
_GetConfigParam_()
{
   if [ $# -eq 0 ] || [ -z "$1" ]
   then echo '' ; return 1 ; fi

   local keyValue  checkFile
   local defValue="$([ $# -eq 2 ] && echo "$2" || echo '')"

   if [ ! -s "$SCRIPT_CONF" ]
   then echo "$defValue" ; return 0 ; fi

   if [ "$(grep -c "^${1}=" "$SCRIPT_CONF")" -gt 1 ]
   then  ## Remove duplicates. Keep ONLY the 1st key ##
       checkFile="${SCRIPT_CONF}.DUPKEY.txt"
       awk "!(/^${1}=/ && dup[/^${1}=/]++)" "$SCRIPT_CONF" > "$checkFile"
       if diff -q "$checkFile" "$SCRIPT_CONF" >/dev/null 2>&1
       then rm -f "$checkFile"
       else mv -f "$checkFile" "$SCRIPT_CONF"
       fi
   fi

   keyValue="$(grep "^${1}=" "$SCRIPT_CONF" | cut -d'=' -f2)"
   echo "${keyValue:=$defValue}"
   return 0
}

##----------------------------------------##
## Modified by Martinski W. [2025-May-01] ##
##----------------------------------------##
Conf_Exists()
{
	local restartvnstat=false

	if [ -f "$VNSTAT_CONFIG" ]
	then
		restartvnstat=false
		if ! grep -q "^MaxBandwidth 1000" "$VNSTAT_CONFIG"; then
			sed -i 's/^MaxBandwidth.*$/MaxBandwidth 1000/' "$VNSTAT_CONFIG"
			restartvnstat=true
		fi
		if ! grep -q "^TimeSyncWait 10" "$VNSTAT_CONFIG"; then
			sed -i 's/^TimeSyncWait.*$/TimeSyncWait 10/' "$VNSTAT_CONFIG"
			restartvnstat=true
		fi
		if ! grep -q "^UpdateInterval 30" "$VNSTAT_CONFIG"; then
			sed -i 's/^UpdateInterval.*$/UpdateInterval 30/' "$VNSTAT_CONFIG"
			restartvnstat=true
		fi
		if ! grep -q "^UnitMode 2" "$VNSTAT_CONFIG"; then
			sed -i 's/^UnitMode.*$/UnitMode 2/' "$VNSTAT_CONFIG"
			restartvnstat=true
		fi
		if ! grep -q "^RateUnitMode 1" "$VNSTAT_CONFIG"; then
			sed -i 's/^RateUnitMode.*$/RateUnitMode 1/' "$VNSTAT_CONFIG"
			restartvnstat=true
		fi
		if ! grep -q "^OutputStyle 0" "$VNSTAT_CONFIG"; then
			sed -i 's/^OutputStyle.*$/OutputStyle 0/' "$VNSTAT_CONFIG"
			restartvnstat=true
		fi
		if ! grep -q '^MonthFormat "%Y-%m"' "$VNSTAT_CONFIG"; then
			sed -i 's/^MonthFormat.*$/MonthFormat "%Y-%m"/' "$VNSTAT_CONFIG"
			restartvnstat=true
		fi
		if [ "$restartvnstat" = "true" ]
		then
			/opt/etc/init.d/S33vnstat restart >/dev/null 2>&1
			Generate_Images silent
			Generate_Stats silent
			Check_Bandwidth_Usage silent
		fi
	else
		Update_File vnstat.conf
	fi

	if [ -f "$SCRIPT_CONF" ]
	then
		dos2unix "$SCRIPT_CONF"
		chmod 0644 "$SCRIPT_CONF"
		sed -i -e 's/"//g' "$SCRIPT_CONF"
		if ! grep -q "^DAILYEMAIL=" "$SCRIPT_CONF"; then
			echo "DAILYEMAIL=none" >> "$SCRIPT_CONF"
		fi
		if ! grep -q "^USAGEEMAIL=" "$SCRIPT_CONF"; then
			echo "USAGEEMAIL=false" >> "$SCRIPT_CONF"
		fi
		if ! grep -q "^DATAALLOWANCE=" "$SCRIPT_CONF"; then
			echo "DATAALLOWANCE=1200.00" >> "$SCRIPT_CONF"
		fi
		if ! grep -q "^ALLOWANCEUNIT=" "$SCRIPT_CONF"; then
			echo "ALLOWANCEUNIT=G" >> "$SCRIPT_CONF"
		fi
		if ! grep -q "^STORAGELOCATION=" "$SCRIPT_CONF"; then
			echo "STORAGELOCATION=jffs" >> "$SCRIPT_CONF"
		fi
		if ! grep -q "^OUTPUTTIMEMODE=" "$SCRIPT_CONF"; then
			echo "OUTPUTTIMEMODE=unix" >> "$SCRIPT_CONF"
		fi
		if ! grep -q "^JFFS_MSGLOGTIME=" "$SCRIPT_CONF"; then
			echo "JFFS_MSGLOGTIME=0" >> "$SCRIPT_CONF"
		fi
		return 0
	else
		{
		   echo "DAILYEMAIL=none"; echo "USAGEEMAIL=false"
		   echo "DATAALLOWANCE=1200.00"; echo "ALLOWANCEUNIT=G"
		   echo "STORAGELOCATION=jffs"; echo "OUTPUTTIMEMODE=unix"
		   echo "JFFS_MSGLOGTIME=0"
		} > "$SCRIPT_CONF"
		return 1
	fi
}

### Add script hook to service-event and pass service_event argument and all other arguments passed to the service call ###
##----------------------------------------##
## Modified by Martinski W. [2025-Jun-17] ##
##----------------------------------------##
Auto_ServiceEvent()
{
	local theScriptFilePath="/jffs/scripts/$SCRIPT_NAME"
	case $1 in
		create)
			if [ -f /jffs/scripts/service-event ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)"
				STARTUPLINECOUNTEX="$(grep -cx 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'"; then { '"$theScriptFilePath"' service_event "$@" & }; fi # '"$SCRIPT_NAME" /jffs/scripts/service-event)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi

				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					{
					  echo 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'"; then { '"$theScriptFilePath"' service_event "$@" & }; fi # '"$SCRIPT_NAME"
					} >> /jffs/scripts/service-event
				fi
			else
				{
				  echo "#!/bin/sh" ; echo
				  echo 'if echo "$2" | /bin/grep -q "'"$SCRIPT_NAME"'"; then { '"$theScriptFilePath"' service_event "$@" & }; fi # '"$SCRIPT_NAME"
				  echo
				} > /jffs/scripts/service-event
				chmod 0755 /jffs/scripts/service-event
			fi
		;;
		delete)
			if [ -f /jffs/scripts/service-event ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/service-event)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/service-event
				fi
			fi
		;;
	esac
}

### Add script hook to post-mount and pass startup argument and all other arguments passed with the partition mount ###
##----------------------------------------##
## Modified by Martinski W. [2025-Jun-17] ##
##----------------------------------------##
Auto_Startup()
{
	local theScriptFilePath="/jffs/scripts/$SCRIPT_NAME"
	case $1 in
		create)
			if [ -f /jffs/scripts/post-mount ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/post-mount)"
				STARTUPLINECOUNTEX="$(grep -cx '\[ -x "${1}/entware/bin/opkg" \] && \[ -x '"$theScriptFilePath"' \] && '"$theScriptFilePath"' startup "$@" & # '"$SCRIPT_NAME" /jffs/scripts/post-mount)"

				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }
				then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/post-mount
				fi

				if [ "$STARTUPLINECOUNTEX" -eq 0 ]
				then
					{
					  echo '[ -x "${1}/entware/bin/opkg" ] && [ -x '"$theScriptFilePath"' ] && '"$theScriptFilePath"' startup "$@" & # '"$SCRIPT_NAME"
					} >> /jffs/scripts/post-mount
				fi
			else
				{
				  echo "#!/bin/sh" ; echo
				  echo '[ -x "${1}/entware/bin/opkg" ] && [ -x '"$theScriptFilePath"' ] && '"$theScriptFilePath"' startup "$@" & # '"$SCRIPT_NAME"
				  echo
				} > /jffs/scripts/post-mount
				chmod 0755 /jffs/scripts/post-mount
			fi
		;;
		delete)
			if [ -f /jffs/scripts/post-mount ]
			then
				STARTUPLINECOUNT="$(grep -c '# '"$SCRIPT_NAME" /jffs/scripts/post-mount)"
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$SCRIPT_NAME"'/d' /jffs/scripts/post-mount
				fi
			fi
		;;
	esac
}

Auto_Cron()
{
	case $1 in
		create)
			STARTUPLINECOUNT="$(cru l | grep -c "${SCRIPT_NAME}_images")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "${SCRIPT_NAME}_images"
			fi

			STARTUPLINECOUNT="$(cru l | grep -c "${SCRIPT_NAME}_stats")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "${SCRIPT_NAME}_stats"
			fi

			STARTUPLINECOUNT="$(cru l | grep -c "${SCRIPT_NAME}_generate")"
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "${SCRIPT_NAME}_generate" "*/5 * * * * /jffs/scripts/$SCRIPT_NAME generate"
			fi

			STARTUPLINECOUNT="$(cru l | grep -c "${SCRIPT_NAME}_summary")"
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "${SCRIPT_NAME}_summary" "59 23 * * * /jffs/scripts/$SCRIPT_NAME summary"
			fi
		;;
		delete)
			STARTUPLINECOUNT="$(cru l | grep -c "${SCRIPT_NAME}_images")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "${SCRIPT_NAME}_images"
			fi

			STARTUPLINECOUNT="$(cru l | grep -c "${SCRIPT_NAME}_stats")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "${SCRIPT_NAME}_stats"
			fi

			STARTUPLINECOUNT="$(cru l | grep -c "${SCRIPT_NAME}_generate")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "${SCRIPT_NAME}_generate"
			fi

			STARTUPLINECOUNT="$(cru l | grep -c "${SCRIPT_NAME}_summary")"
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "${SCRIPT_NAME}_summary"
			fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Download_File()
{ /usr/sbin/curl -LSs --retry 4 --retry-delay 5 --retry-connrefused "$1" -o "$2" ; }

##-------------------------------------##
## Added by Martinski W. [2025-Apr-27] ##
##-------------------------------------##
_Check_WebGUI_Page_Exists_()
{
   local webPageStr  webPageFile  theWebPage

   if [ ! -f "$TEMP_MENU_TREE" ]
   then echo "NONE" ; return 1 ; fi

   theWebPage="NONE"
   webPageStr="$(grep -E -m1 "^$webPageLineRegExp" "$TEMP_MENU_TREE")"
   if [ -n "$webPageStr" ]
   then
       webPageFile="$(echo "$webPageStr" | grep -owE "$webPageFileRegExp" | head -n1)"
       if [ -n "$webPageFile" ] && [ -s "${SCRIPT_WEBPAGE_DIR}/$webPageFile" ]
       then theWebPage="$webPageFile" ; fi
   fi
   echo "$theWebPage"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-20] ##
##----------------------------------------##
Get_WebUI_Page()
{
	if [ $# -eq 0 ] || [ -z "$1" ] || [ ! -s "$1" ]
	then MyWebPage="NONE" ; return 1 ; fi

	local webPageFile  webPagePath

	MyWebPage="$(_Check_WebGUI_Page_Exists_)"

	for indx in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20
	do
		webPageFile="user${indx}.asp"
		webPagePath="${SCRIPT_WEBPAGE_DIR}/$webPageFile"

		if [ -s "$webPagePath" ] && \
		   [ "$(md5sum < "$1")" = "$(md5sum < "$webPagePath")" ]
		then
			MyWebPage="$webPageFile"
			break
		elif [ "$MyWebPage" = "NONE" ] && [ ! -s "$webPagePath" ]
		then
			MyWebPage="$webPageFile"
		fi
	done
}

### function based on @dave14305's FlexQoS webconfigpage function ###
##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Get_WebUI_URL()
{
	local urlPage  urlProto  urlDomain  urlPort  lanPort

	if [ ! -f "$TEMP_MENU_TREE" ]
	then
		echo "**ERROR**: WebUI page NOT mounted"
		return 1
	fi

	urlPage="$(sed -nE "/$SCRIPT_NAME/ s/.*url\: \"(user[0-9]+\.asp)\".*/\1/p" "$TEMP_MENU_TREE")"

	if [ "$(nvram get http_enable)" -eq 1 ]; then
		urlProto="https"
	else
		urlProto="http"
	fi
	if [ -n "$(nvram get lan_domain)" ]; then
		urlDomain="$(nvram get lan_hostname).$(nvram get lan_domain)"
	else
		urlDomain="$(nvram get lan_ipaddr)"
	fi

	lanPort="$(nvram get ${urlProto}_lanport)"
	if [ "$lanPort" -eq 80 ] || [ "$lanPort" -eq 443 ]
	then
		urlPort=""
	else
		urlPort=":$lanPort"
	fi

	if echo "$urlPage" | grep -qE "^${webPageFileRegExp}$" && \
	   [ -s "${SCRIPT_WEBPAGE_DIR}/$urlPage" ]
	then
		echo "${urlProto}://${urlDomain}${urlPort}/${urlPage}" | tr "A-Z" "a-z"
	else
		echo "**ERROR**: WebUI page NOT found"
	fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Apr-27] ##
##-------------------------------------##
_CreateMenuAddOnsSection_()
{
   if grep -qE "^${webPageMenuAddons}$" "$TEMP_MENU_TREE" && \
      grep -qE "${webPageHelpSupprt}$" "$TEMP_MENU_TREE"
   then return 0 ; fi

   lineinsBefore="$(($(grep -n "^exclude:" "$TEMP_MENU_TREE" | cut -f1 -d':') - 1))"

   sed -i "$lineinsBefore""i\
${BEGIN_MenuAddOnsTag}\n\
,\n{\n\
${webPageMenuAddons}\n\
index: \"menu_Addons\",\n\
tab: [\n\
{url: \"javascript:var helpwindow=window.open('\/ext\/shared-jy\/redirect.htm')\", ${webPageHelpSupprt}\n\
{url: \"NULL\", tabName: \"__INHERIT__\"}\n\
]\n}\n\
${ENDIN_MenuAddOnsTag}" "$TEMP_MENU_TREE"
}

### locking mechanism code credit to Martineau (@MartineauUK) ###
##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Mount_WebUI()
{
	Print_Output true "Mounting WebUI tab for $SCRIPT_NAME" "$PASS"

	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"
	Get_WebUI_Page "$SCRIPT_DIR/vnstat-ui.asp"
	if [ "$MyWebPage" = "NONE" ]
	then
		Print_Output true "**ERROR** Unable to mount $SCRIPT_NAME WebUI page." "$CRIT"
		flock -u "$FD"
		return 1
	fi
	cp -fp "$SCRIPT_DIR/vnstat-ui.asp" "$SCRIPT_WEBPAGE_DIR/$MyWebPage"
	echo "$SCRIPT_NAME" > "$SCRIPT_WEBPAGE_DIR/$(echo "$MyWebPage" | cut -f1 -d'.').title"

	if [ "$(uname -o)" = "ASUSWRT-Merlin" ]
	then
		if [ ! -f /tmp/index_style.css ]; then
			cp -fp /www/index_style.css /tmp/
		fi

		if ! grep -q '.menu_Addons' /tmp/index_style.css
		then
			echo ".menu_Addons { background: url(ext/shared-jy/addons.png); }" >> /tmp/index_style.css
		fi

		umount /www/index_style.css 2>/dev/null
		mount -o bind /tmp/index_style.css /www/index_style.css

		if [ ! -f "$TEMP_MENU_TREE" ]; then
			cp -fp /www/require/modules/menuTree.js "$TEMP_MENU_TREE"
		fi
		sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"

		_CreateMenuAddOnsSection_

		sed -i "/url: \"javascript:var helpwindow=window.open('\/ext\/shared-jy\/redirect.htm'/i {url: \"$MyWebPage\", tabName: \"$SCRIPT_NAME\"}," "$TEMP_MENU_TREE"

		umount /www/require/modules/menuTree.js 2>/dev/null
		mount -o bind "$TEMP_MENU_TREE" /www/require/modules/menuTree.js
	fi
	flock -u "$FD"

	Print_Output true "Mounted $SCRIPT_NAME WebUI page as $MyWebPage" "$PASS"
}

##-------------------------------------##
## Added by Martinski W. [2025-Apr-27] ##
##-------------------------------------##
_CheckFor_WebGUI_Page_()
{
   if [ "$(_Check_WebGUI_Page_Exists_)" = "NONE" ]
   then Mount_WebUI ; fi
}

Shortcut_Script()
{
	case $1 in
		create)
			if [ -d /opt/bin ] && \
			   [ ! -f "/opt/bin/$SCRIPT_NAME" ] && \
			   [ -f "/jffs/scripts/$SCRIPT_NAME" ]
			then
				ln -s "/jffs/scripts/$SCRIPT_NAME" /opt/bin
				chmod 0755 "/opt/bin/$SCRIPT_NAME"
			fi
		;;
		delete)
			if [ -f "/opt/bin/$SCRIPT_NAME" ]; then
				rm -f "/opt/bin/$SCRIPT_NAME"
			fi
		;;
	esac
}

PressEnter()
{
	while true
	do
		printf "Press <Enter> key to continue..."
		read -rs key
		case "$key" in
			*) break ;;
		esac
	done
	return 0
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-03] ##
##----------------------------------------##
Check_Requirements()
{
	CHECKSFAILED=false

	if [ "$(nvram get jffs2_scripts)" -ne 1 ]
	then
		nvram set jffs2_scripts=1
		nvram commit
		Print_Output true "Custom JFFS Scripts enabled" "$WARN"
	fi

	if [ ! -f /opt/bin/opkg ]
	then
		CHECKSFAILED=true
		Print_Output false "Entware NOT detected!" "$ERR"
	fi

	if ! Firmware_Version_Check
	then
		CHECKSFAILED=true
		Print_Output false "Unsupported firmware version detected" "$ERR"
		Print_Output false "$SCRIPT_NAME requires Merlin 384.15/384.13_4 or Fork 43E5 (or later)" "$ERR"
	fi

	if [ "$CHECKSFAILED" = "false" ]
	then
		Print_Output false "Installing required packages from Entware" "$PASS"
		opkg update
		opkg install vnstat2 vnstati2
		opkg install libjpeg-turbo >/dev/null 2>&1
		opkg install jq
		opkg install sqlite3-cli
		opkg install p7zip
		opkg install findutils
		if [ -s /opt/etc/init.d/S32vnstat2 ]
		then
			/opt/etc/init.d/S32vnstat2 stop >/dev/null 2>&1
			sleep 2 ; killall -q vnstatd ; sleep 1
		fi
		rm -f /opt/etc/vnstat.conf
		rm -f /opt/etc/init.d/S33vnstat
		rm -f /opt/etc/init.d/S32vnstat2
		return 0
	else
		return 1
	fi
}

### Determine WAN interface using nvram ###
##----------------------------------------##
## Modified by Martinski W. [2025-Apr-29] ##
##----------------------------------------##
Get_WAN_IFace()
{
    local wanPrefix=""  wanProto
    for ifaceNum in 0 1
    do
        if [ "$(nvram get "wan${ifaceNum}_primary")" = "1" ]
        then wanPrefix="wan${ifaceNum}" ; break
        fi
    done
    if [ -z "$wanPrefix" ] ; then echo "ERROR" ; return 1
    fi

    wanProto="$(nvram get "${wanPrefix}_proto")"
    if [ "$wanProto" = "pptp" ] || \
       [ "$wanProto" = "l2tp" ] || \
       [ "$wanProto" = "pppoe" ]
    then
        IFACE_WAN="$(nvram get "${wanPrefix}_pppoe_ifname")"
    else
        IFACE_WAN="$(nvram get "${wanPrefix}_ifname")"
    fi
    echo "$IFACE_WAN"
    return 0
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
ScriptStorageLocation()
{
	case "$1" in
		usb)
			printf "Please wait..."
			sed -i 's/^STORAGELOCATION.*$/STORAGELOCATION=usb/' "$SCRIPT_CONF"
			mkdir -p "/opt/share/$SCRIPT_NAME.d/"
			rm -fr "/opt/share/$SCRIPT_NAME.d/csv" 2>/dev/null
			rm -fr "/opt/share/$SCRIPT_NAME.d/images" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/csv" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/images" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/config" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/config.bak" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/vnstat.conf" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/vnstat.conf.bak" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/vnstat.conf.default" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/.vnstatusage" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/vnstat.txt" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/.v2upgraded" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/jffs/addons/$SCRIPT_NAME.d/v1" "/opt/share/$SCRIPT_NAME.d/" 2>/dev/null
			SCRIPT_CONF="/opt/share/$SCRIPT_NAME.d/config"
			VNSTAT_CONFIG="/opt/share/$SCRIPT_NAME.d/vnstat.conf"
			/opt/etc/init.d/S33vnstat restart >/dev/null 2>&1
			ScriptStorageLocation load true
			sleep 1
		;;
		jffs)
			printf "Please wait..."
			sed -i 's/^STORAGELOCATION.*$/STORAGELOCATION=jffs/' "$SCRIPT_CONF"
			mkdir -p "/jffs/addons/$SCRIPT_NAME.d/"
			rm -fr "/jffs/addons/$SCRIPT_NAME.d/csv" 2>/dev/null
			rm -fr "/jffs/addons/$SCRIPT_NAME.d/images" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/csv" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/images" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/config" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/config.bak" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/vnstat.conf" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/vnstat.conf.bak" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/vnstat.conf.default" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/.vnstatusage" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/vnstat.txt" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/.v2upgraded" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			mv -f "/opt/share/$SCRIPT_NAME.d/v1" "/jffs/addons/$SCRIPT_NAME.d/" 2>/dev/null
			SCRIPT_CONF="/jffs/addons/$SCRIPT_NAME.d/config"
			VNSTAT_CONFIG="/jffs/addons/$SCRIPT_NAME.d/vnstat.conf"
			/opt/etc/init.d/S33vnstat restart >/dev/null 2>&1
			ScriptStorageLocation load true
			sleep 1
		;;
		check)
			STORAGELOCATION="$(_GetConfigParam_ STORAGELOCATION jffs)"
			echo "$STORAGELOCATION"
		;;
		load)
			STORAGELOCATION="$(ScriptStorageLocation check)"
			if [ "$STORAGELOCATION" = "usb" ]
			then
				SCRIPT_STORAGE_DIR="/opt/share/$SCRIPT_NAME.d"
			elif [ "$STORAGELOCATION" = "jffs" ]
			then
				SCRIPT_STORAGE_DIR="/jffs/addons/$SCRIPT_NAME.d"
			fi
			chmod 777 "$SCRIPT_STORAGE_DIR"
			CSV_OUTPUT_DIR="$SCRIPT_STORAGE_DIR/csv"
			IMAGE_OUTPUT_DIR="$SCRIPT_STORAGE_DIR/images"
			VNSTAT_DBASE="$(_GetVNStatDatabaseFilePath_)"
			VNSTAT_COMMAND="vnstat --config $VNSTAT_CONFIG"
			VNSTATI_COMMAND="vnstati --config $VNSTAT_CONFIG"
			VNSTAT_OUTPUT_FILE="$SCRIPT_STORAGE_DIR/vnstat.txt"
			if [ $# -gt 1 ] && [ "$2" = "true" ]
			then _UpdateJFFS_FreeSpaceInfo_ ; fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
OutputTimeMode()
{
	case "$1" in
		unix)
			sed -i 's/^OUTPUTTIMEMODE.*$/OUTPUTTIMEMODE=unix/' "$SCRIPT_CONF"
			Generate_CSVs
		;;
		non-unix)
			sed -i 's/^OUTPUTTIMEMODE.*$/OUTPUTTIMEMODE=non-unix/' "$SCRIPT_CONF"
			Generate_CSVs
		;;
		check)
			OUTPUTTIMEMODE="$(_GetConfigParam_ OUTPUTTIMEMODE unix)"
			echo "$OUTPUTTIMEMODE"
		;;
	esac
}

##-------------------------------------##
## Added by Martinski W. [2025-Apr-28] ##
##-------------------------------------##
_GetFileSize_()
{
   local sizeUnits  sizeInfo  fileSize
   if [ $# -eq 0 ] || [ -z "$1" ] || [ ! -s "$1" ]
   then echo 0; return 1 ; fi

   if [ $# -lt 2 ] || [ -z "$2" ] || \
      ! echo "$2" | grep -qE "^(B|KB|MB|GB|HR|HRx)$"
   then sizeUnits="B" ; else sizeUnits="$2" ; fi

   _GetNum_() { printf "%.1f" "$(echo "$1" | awk "{print $1}")" ; }

   case "$sizeUnits" in
       B|KB|MB|GB)
           fileSize="$(ls -1l "$1" | awk -F ' ' '{print $3}')"
           case "$sizeUnits" in
               KB) fileSize="$(_GetNum_ "($fileSize / $oneKByte)")" ;;
               MB) fileSize="$(_GetNum_ "($fileSize / $oneMByte)")" ;;
               GB) fileSize="$(_GetNum_ "($fileSize / $oneGByte)")" ;;
           esac
           echo "$fileSize"
           ;;
       HR|HRx)
           fileSize="$(ls -1lh "$1" | awk -F ' ' '{print $3}')"
           sizeInfo="${fileSize}B"
           if [ "$sizeUnits" = "HR" ]
           then echo "$sizeInfo" ; return 0 ; fi
           sizeUnits="$(echo "$sizeInfo" | tr -d '.0-9')"
           case "$sizeUnits" in
               MB) fileSize="$(_GetFileSize_ "$1" KB)"
                   sizeInfo="$sizeInfo [${fileSize}KB]"
                   ;;
               GB) fileSize="$(_GetFileSize_ "$1" MB)"
                   sizeInfo="$sizeInfo [${fileSize}MB]"
                   ;;
           esac
           echo "$sizeInfo"
           ;;
       *) echo 0 ;;
   esac
   return 0
}

##-------------------------------------##
## Added by Martinski W. [2025-May-01] ##
##-------------------------------------##
_Get_JFFS_Space_()
{
   local typex  total  usedx  freex  totalx
   local sizeUnits  sizeType  sizeInfo  sizeNum
   local jffsMountStr  jffsUsageStr  percentNum  percentStr

   if [ $# -lt 1 ] || [ -z "$1" ] || \
      ! echo "$1" | grep -qE "^(ALL|USED|FREE)$"
   then sizeType="ALL" ; else sizeType="$1" ; fi

   if [ $# -lt 2 ] || [ -z "$2" ] || \
      ! echo "$2" | grep -qE "^(KB|KBP|MBP|GBP|HR|HRx)$"
   then sizeUnits="KB" ; else sizeUnits="$2" ; fi

   _GetNum_() { printf "%.2f" "$(echo "$1" | awk "{print $1}")" ; }

   jffsMountStr="$(mount | grep '/jffs')"
   jffsUsageStr="$(df -kT /jffs | grep -E '.*[[:blank:]]+/jffs$')"

   if [ -z "$jffsMountStr" ] || [ -z "$jffsUsageStr" ]
   then echo "**ERROR**: JFFS is *NOT* mounted." ; return 1
   fi
   if echo "$jffsMountStr" | grep -qE "[[:blank:]]+[(]?ro[[:blank:],]"
   then echo "**ERROR**: JFFS is mounted READ-ONLY." ; return 2
   fi

   typex="$(echo "$jffsUsageStr" | awk -F ' ' '{print $2}')"
   total="$(echo "$jffsUsageStr" | awk -F ' ' '{print $3}')"
   usedx="$(echo "$jffsUsageStr" | awk -F ' ' '{print $4}')"
   freex="$(echo "$jffsUsageStr" | awk -F ' ' '{print $5}')"
   totalx="$total"
   if [ "$typex" = "ubifs" ] && [ "$((usedx + freex))" -ne "$total" ]
   then totalx="$((usedx + freex))" ; fi

   if [ "$sizeType" = "ALL" ] ; then echo "$totalx" ; return 0 ; fi

   case "$sizeUnits" in
       KB|KBP|MBP|GBP)
           case "$sizeType" in
               USED) sizeNum="$usedx"
                     percentNum="$(printf "%.1f" "$(_GetNum_ "($usedx * 100 / $totalx)")")"
                     percentStr="[${percentNum}%]"
                     ;;
               FREE) sizeNum="$freex"
                     percentNum="$(printf "%.1f" "$(_GetNum_ "($freex * 100 / $totalx)")")"
                     percentStr="[${percentNum}%]"
                     ;;
           esac
           case "$sizeUnits" in
                KB) sizeInfo="$sizeNum"
                    ;;
               KBP) sizeInfo="${sizeNum}.0KB $percentStr"
                    ;;
               MBP) sizeNum="$(_GetNum_ "($sizeNum / $oneKByte)")"
                    sizeInfo="${sizeNum}MB $percentStr"
                    ;;
               GBP) sizeNum="$(_GetNum_ "($sizeNum / $oneMByte)")"
                    sizeInfo="${sizeNum}GB $percentStr"
                    ;;
           esac
           echo "$sizeInfo"
           ;;
       HR|HRx)
           jffsUsageStr="$(df -hT /jffs | grep -E '.*[[:blank:]]+/jffs$')"
           case "$sizeType" in
               USED) usedx="$(echo "$jffsUsageStr" | awk -F ' ' '{print $4}')"
                     sizeInfo="${usedx}B"
                     ;;
               FREE) freex="$(echo "$jffsUsageStr" | awk -F ' ' '{print $5}')"
                     sizeInfo="${freex}B"
                     ;;
           esac
           if [ "$sizeUnits" = "HR" ]
           then echo "$sizeInfo" ; return 0 ; fi
           sizeUnits="$(echo "$sizeInfo" | tr -d '.0-9')"
           case "$sizeUnits" in
               KB) sizeInfo="$(_Get_JFFS_Space_ "$sizeType" KBP)" ;;
               MB) sizeInfo="$(_Get_JFFS_Space_ "$sizeType" MBP)" ;;
               GB) sizeInfo="$(_Get_JFFS_Space_ "$sizeType" GBP)" ;;
           esac
           echo "$sizeInfo"
           ;;
       *) echo 0 ;;
   esac
   return 0
}

##----------------------------------------##
## Modified by Martinski W. [2025-May-01] ##
##----------------------------------------##
##--------------------------------------------------------##
## Minimum Reserved JFFS Available Free Space is roughly
## about 20% of total space or about 9MB to 10MB.
##--------------------------------------------------------##
_JFFS_MinReservedFreeSpace_()
{
   local jffsAllxSpace  jffsMinxSpace

   if ! jffsAllxSpace="$(_Get_JFFS_Space_ ALL KB)"
   then echo "$jffsAllxSpace" ; return 1 ; fi
   jffsAllxSpace="$(echo "$jffsAllxSpace" | awk '{printf("%s", $1 * 1024);}')"

   jffsMinxSpace="$(echo "$jffsAllxSpace" | awk '{printf("%d", $1 * 20 / 100);}')"
   if [ "$(echo "$jffsMinxSpace $ni9MByte" | awk -F ' ' '{print ($1 < $2)}')" -eq 1 ]
   then jffsMinxSpace="$ni9MByte"
   elif [ "$(echo "$jffsMinxSpace $tenMByte" | awk -F ' ' '{print ($1 > $2)}')" -eq 1 ]
   then jffsMinxSpace="$tenMByte"
   fi
   echo "$jffsMinxSpace" ; return 0
}

##----------------------------------------##
## Modified by Martinski W. [2025-May-01] ##
##----------------------------------------##
##--------------------------------------------------------##
## Check JFFS free space *BEFORE* moving files from USB.
##--------------------------------------------------------##
_Check_JFFS_SpaceAvailable_()
{
   local requiredSpace  jffsFreeSpace  jffsMinxSpace
   if [ $# -eq 0 ] || [ -z "$1" ] || [ ! -d "$1" ] ; then return 0 ; fi

   [ "$1" = "/jffs/addons/${SCRIPT_NAME}.d" ] && return 0

   if ! jffsFreeSpace="$(_Get_JFFS_Space_ FREE KB)" ; then return 1 ; fi
   if ! jffsMinxSpace="$(_JFFS_MinReservedFreeSpace_)" ; then return 1 ; fi
   jffsFreeSpace="$(echo "$jffsFreeSpace" | awk '{printf("%s", $1 * 1024);}')"

   requiredSpace="$(du -kc "$1" | grep -w 'total$' | awk -F ' ' '{print $1}')"
   requiredSpace="$(echo "$requiredSpace" | awk '{printf("%s", $1 * 1024);}')"
   requiredSpace="$(echo "$requiredSpace $jffsMinxSpace" | awk -F ' ' '{printf("%s", $1 + $2);}')"
   if [ "$(echo "$requiredSpace $jffsFreeSpace" | awk -F ' ' '{print ($1 < $2)}')" -eq 1 ]
   then return 0 ; fi

   ## Current JFFS Available Free Space is NOT sufficient ##
   requiredSpace="$(du -hc "$1" | grep -w 'total$' | awk -F ' ' '{print $1}')"
   errorMsg1="Not enough free space [$(_Get_JFFS_Space_ FREE HR)] available in JFFS."
   errorMsg2="Minimum storage space required: $requiredSpace"
   Print_Output true "${errorMsg1} ${errorMsg2}" "$CRIT"
   return 1
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-19] ##
##-------------------------------------##
_EscapeChars_()
{ printf "%s" "$1" | sed 's/[][\/$.*^&-]/\\&/g' ; }

##-------------------------------------##
## Added by Martinski W. [2025-Jun-20] ##
##-------------------------------------##
_WriteVarDefToJSFile_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]
   then return 1; fi

   local varValue  sedValue
   if [ $# -eq 3 ] && [ "$3" = "true" ]
   then
       varValue="$2"
   else
       varValue="'${2}'"
       sedValue="$(_EscapeChars_ "$varValue")"
   fi

   local targetJSfile="$SCRIPT_STORAGE_DIR/.vnstatusage"
   if [ ! -s "$targetJSfile" ]
   then
       echo "var $1 = ${varValue};" > "$targetJSfile"
   elif
      ! grep -q "^var $1 =.*" "$targetJSfile"
   then
       sed -i "1 i var $1 = ${varValue};" "$targetJSfile"
   elif
      ! grep -q "^var $1 = ${sedValue};" "$targetJSfile"
   then
       sed -i "s/^var $1 =.*/var $1 = ${sedValue};/" "$targetJSfile"
   fi
}

##-------------------------------------##
## Added by Martinski W. [2025-May-01] ##
##-------------------------------------##
JFFS_WarningLogTime()
{
   case "$1" in
       update)
           sed -i 's/^JFFS_MSGLOGTIME=.*$/JFFS_MSGLOGTIME='"$2"'/' "$SCRIPT_CONF"
           ;;
       check)
           JFFS_MSGLOGTIME="$(_GetConfigParam_ JFFS_MSGLOGTIME 0)"
           if ! echo "$JFFS_MSGLOGTIME" | grep -qE "^[0-9]+$"
           then JFFS_MSGLOGTIME=0
           fi
           echo "$JFFS_MSGLOGTIME"
           ;;
   esac
}

##-------------------------------------##
## Added by Martinski W. [2025-May-01] ##
##-------------------------------------##
_JFFS_WarnLowFreeSpace_()
{
   if [ $# -eq 0 ] || [ -z "$1" ] ; then return 0 ; fi
   local jffsWarningLogFreq  jffsWarningLogTime  storageLocStr
   local logPriNum  logTagStr  logMsgStr  currTimeSecs  currTimeDiff

   storageLocStr="$(ScriptStorageLocation check | tr 'a-z' 'A-Z')"
   if [ "$storageLocStr" = "JFFS" ]
   then
       if [ "$JFFS_LowFreeSpaceStatus" = "WARNING2" ]
       then
           logPriNum=2
           logTagStr="**ALERT**"
           jffsWarningLogFreq="$_12Hours"
       else
           logPriNum=3
           logTagStr="**WARNING**"
           jffsWarningLogFreq="$_24Hours"
       fi
   else
       if [ "$JFFS_LowFreeSpaceStatus" = "WARNING2" ]
       then
           logPriNum=3
           logTagStr="**WARNING**"
           jffsWarningLogFreq="$_24Hours"
       else
           logPriNum=4
           logTagStr="**NOTICE**"
           jffsWarningLogFreq="$_36Hours"
       fi
   fi
   jffsWarningLogTime="$(JFFS_WarningLogTime check)"

   currTimeSecs="$(date +'%s')"
   currTimeDiff="$(echo "$currTimeSecs $jffsWarningLogTime" | awk -F ' ' '{printf("%s", $1 - $2);}')"
   if [ "$currTimeDiff" -ge "$jffsWarningLogFreq" ]
   then
       JFFS_WarningLogTime update "$currTimeSecs"
       logMsgStr="${logTagStr} JFFS Available Free Space ($1) is getting LOW."
       logger -t "$SCRIPT_NAME" -p $logPriNum "$logMsgStr"
   fi
}

##-------------------------------------##
## Added by Martinski W. [2025-May-01] ##
##-------------------------------------##
_UpdateJFFS_FreeSpaceInfo_()
{
   local jffsFreeSpaceHR  jffsFreeSpace  jffsMinxSpace
   [ ! -d "$SCRIPT_STORAGE_DIR" ] && return 1

   jffsFreeSpaceHR="$(_Get_JFFS_Space_ FREE HRx)"
   _WriteVarDefToJSFile_ "jffsAvailableSpaceStr" "$jffsFreeSpaceHR"

   if ! jffsFreeSpace="$(_Get_JFFS_Space_ FREE KB)" ; then return 1 ; fi
   if ! jffsMinxSpace="$(_JFFS_MinReservedFreeSpace_)" ; then return 1 ; fi
   jffsFreeSpace="$(echo "$jffsFreeSpace" | awk '{printf("%s", $1 * 1024);}')"

   JFFS_LowFreeSpaceStatus="OK"
   ## Warning Level 1 if JFFS Available Free Space is LESS than Minimum Reserved ##
   if [ "$(echo "$jffsFreeSpace $jffsMinxSpace" | awk -F ' ' '{print ($1 < $2)}')" -eq 1 ]
   then
       JFFS_LowFreeSpaceStatus="WARNING1"
       ## Warning Level 2 if JFFS Available Free Space is LESS than 8.0MB ##
       if [ "$(echo "$jffsFreeSpace $ei8MByte" | awk -F ' ' '{print ($1 < $2)}')" -eq 1 ]
       then
           JFFS_LowFreeSpaceStatus="WARNING2"
       fi
       _JFFS_WarnLowFreeSpace_ "$jffsFreeSpaceHR"
   fi
   _WriteVarDefToJSFile_ "jffsAvailableSpaceLow" "$JFFS_LowFreeSpaceStatus"
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-30] ##
##-------------------------------------##
_UpdateDatabaseFileSizeInfo_()
{
   local databaseFileSize
   [ ! -d "$SCRIPT_STORAGE_DIR" ] && return 1

   _UpdateJFFS_FreeSpaceInfo_
   databaseFileSize="$(_GetFileSize_ "$(_GetVNStatDatabaseFilePath_)" HRx)"
   _WriteVarDefToJSFile_ "sqlDatabaseFileSize" "$databaseFileSize"
}

##-------------------------------------##
## Added by Martinski W. [2025-Apr-28] ##
##-------------------------------------##
_GetVNStatDatabaseFilePath_()
{
    local dbaseDirPath
    if [ ! -s "$VNSTAT_CONFIG" ] ; then echo ; return 1 ; fi
    dbaseDirPath="$(grep '^DatabaseDir ' "$VNSTAT_CONFIG" | awk -F ' ' '{print $2}' | sed 's/"//g')"
    echo "${dbaseDirPath}/vnstat.db"
    return 0
}

##-------------------------------------##
## Added by Martinski W. [2025-Apr-27] ##
##-------------------------------------##
_GetInterfaceNameFromConfig_()
{
    local iFaceName
    if [ ! -s "$VNSTAT_CONFIG" ] ; then echo ; return 1 ; fi
    iFaceName="$(grep '^Interface ' "$VNSTAT_CONFIG" | awk -F ' ' '{print $2}' | sed 's/"//g')"
    echo "$iFaceName"
    return 0
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-16] ##
##-------------------------------------##
_SQLCheckDBLogFileSize_()
{
   if [ "$(_GetFileSize_ "$sqlDBLogFilePath")" -gt "$sqlDBLogFileSize" ]
   then
       cp -fp "$sqlDBLogFilePath" "${sqlDBLogFilePath}.BAK"
       echo -n > "$sqlDBLogFilePath"
   fi
}

_SQLGetDBLogTimeStamp_()
{ printf "[$(date +"$sqlDBLogDateTime")]" ; }

##-------------------------------------##
## Added by Martinski W. [2025-Jun-16] ##
##-------------------------------------##
readonly errorMsgsRegExp="Parse error|Runtime error|Error:"
readonly corruptedBinExp="Illegal instruction|SQLite header and source version mismatch"
readonly sqlErrorsRegExp="($errorMsgsRegExp|$corruptedBinExp)"
readonly sqlLockedRegExp="(Parse|Runtime) error .*: database is locked"
readonly sqlCorruptedMsg="SQLite3 binary is likely corrupted. Remove and reinstall the Entware package."
##-----------------------------------------------------------------------
_ApplyDatabaseSQLCmds_()
{
    local errorCount=0  maxErrorCount=3  callFlag
    local triesCount=0  maxTriesCount=10  sqlErrorMsg
    local tempLogFilePath="/tmp/${SCRIPT_NAME}_TMP_$$.LOG"
    local debgLogFilePath="/tmp/${SCRIPT_NAME}_DEBUG_$$.LOG"
    local debgLogSQLcmds=false

    if [ $# -gt 1 ] && [ -n "$2" ]
    then callFlag="$2"
    else callFlag="err"
    fi

    resultStr=""
    foundError=false ; foundLocked=false
    rm -f "$tempLogFilePath" "$debgLogFilePath"

    while [ "$errorCount" -lt "$maxErrorCount" ] && \
          [ "$((triesCount++))" -lt "$maxTriesCount" ]
    do
        if "$SQLITE3_PATH" "$VNSTAT_DBASE" < "$1" >> "$tempLogFilePath" 2>&1
        then foundError=false ; foundLocked=false ; break
        fi
        sqlErrorMsg="$(cat "$tempLogFilePath")"

        if echo "$sqlErrorMsg" | grep -qE "^$sqlErrorsRegExp"
        then
            if echo "$sqlErrorMsg" | grep -qE "^$sqlLockedRegExp"
            then
                foundLocked=true ; maxTriesCount=25
                echo -n > "$tempLogFilePath"  ##Clear for next error found##
                sleep 2 ; continue
            fi
            if echo "$sqlErrorMsg" | grep -qE "^($corruptedBinExp)"
            then  ## Corrupted SQLite3 Binary?? ##
                errorCount="$maxErrorCount"
                echo "$sqlCorruptedMsg" >> "$tempLogFilePath"
                Print_Output true "SQLite3 Fatal Error[$callFlag]: $sqlCorruptedMsg" "$CRIT"
            fi
            errorCount="$((errorCount + 1))"
            foundError=true ; foundLocked=false
            Print_Output true "SQLite3 Failure[$callFlag]: $sqlErrorMsg" "$ERR"
        fi

        if ! "$debgLogSQLcmds"
        then
           debgLogSQLcmds=true
           {
              echo "==========================================="
              echo "$(_SQLGetDBLogTimeStamp_) BEGIN [$callFlag]"
              echo "Database: $VNSTAT_DBASE"
           } > "$debgLogFilePath"
        fi
        cat "$tempLogFilePath" >> "$debgLogFilePath"
        echo -n > "$tempLogFilePath"  ##Clear for next error found##
        [ "$triesCount" -ge "$maxTriesCount" ] && break
        [ "$errorCount" -ge "$maxErrorCount" ] && break
        sleep 1
    done

    if "$debgLogSQLcmds"
    then
       {
          echo "--------------------------------"
          cat "$1"
          echo "--------------------------------"
          echo "$(_SQLGetDBLogTimeStamp_) END [$callFlag]"
       } >> "$debgLogFilePath"
       cat "$debgLogFilePath" >> "$sqlDBLogFilePath"
    fi

    rm -f "$tempLogFilePath" "$debgLogFilePath"
    if "$foundError"
    then resultStr="reported error(s)."
    elif "$foundLocked"
    then resultStr="found database locked."
    else resultStr="completed successfully."
    fi
    if "$foundError" || "$foundLocked"
    then
        Print_Output true "SQLite process[$callFlag] ${resultStr}" "$ERR"
    fi
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-30] ##
##----------------------------------------##
Generate_CSVs()
{
	local foundError  foundLocked  resultStr  sqlProcSuccess

	interface="$(_GetInterfaceNameFromConfig_)"
	VNSTAT_DBASE="$(_GetVNStatDatabaseFilePath_)"
	if [ -z "$interface" ] || [ -z "$VNSTAT_DBASE" ] || [ ! -f "$VNSTAT_DBASE" ]
	then
		Print_Output true "**ERROR** Unable to generate CSV files" "$CRIT"
		return 1
	fi
	renice 15 $$
	TZ="$(cat /etc/TZ)"
	export TZ
	timenow="$(date +"%s")"

	rm -f /tmp/dn-vnstatiface

	sqlProcSuccess=true
	{
		echo ".headers off"
		echo ".output /tmp/dn-vnstatiface"
		echo "PRAGMA temp_store=1;"
		echo "SELECT id FROM [interface] WHERE [name] = '$interface';"
	} > /tmp/dn-vnstat.sql
	_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr1

	if "$foundError" || "$foundLocked" || [ ! -s /tmp/dn-vnstatiface ]
	then
		sqlProcSuccess=false
		Print_Output true "**ERROR**: Unable to get vnStat Interface ID [gnr1]." "$CRIT"
		return 1
	fi

	interfaceid="$(cat /tmp/dn-vnstatiface)"
	rm -f /tmp/dn-vnstatiface

	intervalList="fiveminute hour day"
	for interval in $intervalList
	do
		metricList="rx tx"
		for metric in $metricList
		do
			{
				echo ".mode csv"
				echo ".headers off"
				echo ".output $CSV_OUTPUT_DIR/${metric}daily.tmp"
				echo "PRAGMA temp_store=1;"
				echo "SELECT '$metric' Metric,strftime('%s',[date],'utc') Time,[$metric] Value FROM $interval WHERE [interface] = '$interfaceid' AND strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','-1 day'));"
			} > /tmp/dn-vnstat.sql
			_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr2

			{
				echo ".mode csv"
				echo ".headers off"
				echo ".output $CSV_OUTPUT_DIR/${metric}weekly.tmp"
				echo "PRAGMA temp_store=1;"
				echo "SELECT '$metric' Metric,strftime('%s',[date],'utc') Time,[$metric] Value FROM $interval WHERE [interface] = '$interfaceid' AND strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','-7 day'));"
			} > /tmp/dn-vnstat.sql
			_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr3

			{
				echo ".mode csv"
				echo ".headers off"
				echo ".output $CSV_OUTPUT_DIR/${metric}monthly.tmp"
				echo "PRAGMA temp_store=1;"
				echo "SELECT '$metric' Metric,strftime('%s',[date],'utc') Time,[$metric] Value FROM $interval WHERE [interface] = '$interfaceid' AND strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','-30 day'));"
			} > /tmp/dn-vnstat.sql
			_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr4

			rm -f /tmp/dn-vnstat.sql
		done

		cat "$CSV_OUTPUT_DIR/rxdaily.tmp" "$CSV_OUTPUT_DIR/txdaily.tmp" > "$CSV_OUTPUT_DIR/DataUsage_${interval}_daily.htm" 2>/dev/null
		cat "$CSV_OUTPUT_DIR/rxweekly.tmp" "$CSV_OUTPUT_DIR/txweekly.tmp" > "$CSV_OUTPUT_DIR/DataUsage_${interval}_weekly.htm" 2>/dev/null
		cat "$CSV_OUTPUT_DIR/rxmonthly.tmp" "$CSV_OUTPUT_DIR/txmonthly.tmp" > "$CSV_OUTPUT_DIR/DataUsage_${interval}_monthly.htm" 2>/dev/null

		sed -i 's/rx/Received/g;s/tx/Sent/g;1i Metric,Time,Value' "$CSV_OUTPUT_DIR/DataUsage_${interval}_daily.htm"
		sed -i 's/rx/Received/g;s/tx/Sent/g;1i Metric,Time,Value' "$CSV_OUTPUT_DIR/DataUsage_${interval}_weekly.htm"
		sed -i 's/rx/Received/g;s/tx/Sent/g;1i Metric,Time,Value' "$CSV_OUTPUT_DIR/DataUsage_${interval}_monthly.htm"

		rm -f "$CSV_OUTPUT_DIR/rx"*
		rm -f "$CSV_OUTPUT_DIR/tx"*
	done

	metricList="rx tx"
	for metric in $metricList
	do
		{
			echo ".mode csv"
			echo ".headers off"
			echo ".output $CSV_OUTPUT_DIR/week_this_${metric}.tmp"
			echo "PRAGMA temp_store=1;"
			echo "SELECT '$metric' Metric,strftime('%w', [date]) Time,[$metric] Value FROM day WHERE [interface] = '$interfaceid' AND strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','start of day','+1 day','-7 day'));"
		} > /tmp/dn-vnstat.sql
		_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr5

		{
			echo ".mode csv"
			echo ".headers off"
			echo ".output $CSV_OUTPUT_DIR/week_prev_${metric}.tmp"
			echo "PRAGMA temp_store=1;"
			echo "SELECT '$metric' Metric,strftime('%w', [date]) Time,[$metric] Value FROM day WHERE [interface] = '$interfaceid' AND strftime('%s',[date],'utc') < strftime('%s',datetime($timenow,'unixepoch','start of day','+1 day','-7 day')) AND strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','start of day','+1 day','-14 day'));"
		} > /tmp/dn-vnstat.sql
		_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr6

		{
			echo ".mode csv"
			echo ".headers off"
			echo ".output $CSV_OUTPUT_DIR/week_summary_this_${metric}.tmp"
			echo "PRAGMA temp_store=1;"
			echo "SELECT '$metric' Metric,'Current 7 days' Time,IFNULL(SUM([$metric]),'0') Value FROM day WHERE [interface] = '$interfaceid' AND strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','start of day','+1 day','-7 day'));"
		} > /tmp/dn-vnstat.sql
		_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr7

		{
			echo ".mode csv"
			echo ".headers off"
			echo ".output $CSV_OUTPUT_DIR/week_summary_prev_${metric}.tmp"
			echo "PRAGMA temp_store=1;"
			echo "SELECT '$metric' Metric,'Previous 7 days' Time,IFNULL(SUM([$metric]),'0') Value FROM day WHERE [interface] = '$interfaceid' AND strftime('%s',[date],'utc') < strftime('%s',datetime($timenow,'unixepoch','start of day','+1 day','-7 day')) AND strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','start of day','+1 day','-14 day'));"
		} > /tmp/dn-vnstat.sql
		_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr8

		{
			echo ".mode csv"
			echo ".headers off"
			echo ".output $CSV_OUTPUT_DIR/week_summary_prev2_${metric}.tmp"
			echo "PRAGMA temp_store=1;"
			echo "SELECT '$metric' Metric,'2 weeks ago' Time,IFNULL(SUM([$metric]),'0') Value FROM day WHERE [interface] = '$interfaceid' AND strftime('%s',[date],'utc') < strftime('%s',datetime($timenow,'unixepoch','start of day','+1 day','-14 day')) AND strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','start of day','+1 day','-21 day'));"
		} > /tmp/dn-vnstat.sql
		_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat.sql gnr9
	done

	cat "$CSV_OUTPUT_DIR/week_this_rx.tmp" "$CSV_OUTPUT_DIR/week_this_tx.tmp" > "$CSV_OUTPUT_DIR/WeekThis.htm" 2>/dev/null
	cat "$CSV_OUTPUT_DIR/week_prev_rx.tmp" "$CSV_OUTPUT_DIR/week_prev_tx.tmp" > "$CSV_OUTPUT_DIR/WeekPrev.htm" 2>/dev/null

	sed -i 's/rx/Received/g;s/tx/Sent/g;1i Metric,Time,Value' "$CSV_OUTPUT_DIR/WeekThis.htm"
	sed -i 's/rx/Received/g;s/tx/Sent/g;1i Metric,Time,Value' "$CSV_OUTPUT_DIR/WeekPrev.htm"

	cat "$CSV_OUTPUT_DIR/week_summary_this_rx.tmp" "$CSV_OUTPUT_DIR/week_summary_this_tx.tmp" "$CSV_OUTPUT_DIR/week_summary_prev_rx.tmp" "$CSV_OUTPUT_DIR/week_summary_prev_tx.tmp" "$CSV_OUTPUT_DIR/week_summary_prev2_rx.tmp" "$CSV_OUTPUT_DIR/week_summary_prev2_tx.tmp" > "$CSV_OUTPUT_DIR/WeekSummary.htm" 2>/dev/null
	sed -i 's/rx/Received/g;s/tx/Sent/g;1i Metric,Time,Value' "$CSV_OUTPUT_DIR/WeekSummary.htm"

	rm -f "$CSV_OUTPUT_DIR/week"*

	sqlProcSuccess=true
	{
		echo ".mode csv"
		echo ".headers on"
		echo ".output $CSV_OUTPUT_DIR/CompleteResults.htm"
		echo "PRAGMA temp_store=1;"
		echo "SELECT strftime('%s',[date],'utc') Time,[rx],[tx] FROM fiveminute WHERE strftime('%s',[date],'utc') >= strftime('%s',datetime($timenow,'unixepoch','-30 day')) ORDER BY strftime('%s', [date]) DESC;"
	} > /tmp/dn-vnstat-complete.sql
	_ApplyDatabaseSQLCmds_ /tmp/dn-vnstat-complete.sql gnr10
	rm -f /tmp/dn-vnstat-complete.sql

	if "$foundError" || "$foundLocked" || \
	   [ ! -f "$CSV_OUTPUT_DIR/CompleteResults.htm" ]
	then sqlProcSuccess=false ; fi

	dos2unix "$CSV_OUTPUT_DIR/"*.htm

	tmpOutputDir="/tmp/${SCRIPT_NAME}results"
	mkdir -p "$tmpOutputDir"

	[ -f "$CSV_OUTPUT_DIR/CompleteResults.htm" ] && \
	mv -f "$CSV_OUTPUT_DIR/CompleteResults.htm" "$tmpOutputDir/."

	OUTPUTTIMEMODE="$(OutputTimeMode check)"

	if [ "$OUTPUTTIMEMODE" = "unix" ]
	then
		find "$tmpOutputDir/" -name '*.htm' -exec sh -c 'i="$1"; mv -- "$i" "${i%.htm}.csv"' _ {} \;
	elif [ "$OUTPUTTIMEMODE" = "non-unix" ]
	then
		for i in "$tmpOutputDir/"*".htm"
		do
			awk -F"," 'NR==1 {OFS=","; print} NR>1 {OFS=","; $1=strftime("%Y-%m-%d %H:%M:%S", $1); print }' "$i" > "$i.out"
		done

		find "$tmpOutputDir/" -name '*.htm.out' -exec sh -c 'i="$1"; mv -- "$i" "${i%.htm.out}.csv"' _ {} \;
		rm -f "$tmpOutputDir/"*.htm
	fi

	if [ ! -f /opt/bin/7za ]
	then
		opkg update
		opkg install p7zip
	fi
	/opt/bin/7za a -y -bsp0 -bso0 -tzip "/tmp/${SCRIPT_NAME}data.zip" "$tmpOutputDir/*"
	mv -f "/tmp/${SCRIPT_NAME}data.zip" "$CSV_OUTPUT_DIR"
	rm -rf "$tmpOutputDir"

	_UpdateDatabaseFileSizeInfo_
	renice 0 $$
}

##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Generate_Images()
{
	Create_Dirs
	Conf_Exists
	ScriptStorageLocation load
	Create_Symlinks
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Shortcut_Script create
	Process_Upgrade
	if [ ! -f /opt/lib/libjpeg.so ]
	then
		opkg update >/dev/null 2>&1
		opkg install libjpeg-turbo >/dev/null 2>&1
	fi
	TZ="$(cat /etc/TZ)"
	export TZ

	if [ $# -eq 0 ] || [ -z "$1" ]
	then Print_Output false "vnstati updating stats for WebUI" "$PASS"
	fi

	interface="$(_GetInterfaceNameFromConfig_)"
	outputs="s hg d t m"   # what images to generate #

	$VNSTATI_COMMAND -s -i "$interface" -o "$IMAGE_OUTPUT_DIR/vnstat_s.png"
	$VNSTATI_COMMAND -hg -i "$interface" -o "$IMAGE_OUTPUT_DIR/vnstat_hg.png"
	$VNSTATI_COMMAND -d 31 -i "$interface" -o "$IMAGE_OUTPUT_DIR/vnstat_d.png"
	$VNSTATI_COMMAND -m 12 -i "$interface" -o "$IMAGE_OUTPUT_DIR/vnstat_m.png"
	$VNSTATI_COMMAND -t 10 -i "$interface" -o "$IMAGE_OUTPUT_DIR/vnstat_t.png"
	sleep 1

	for output in $outputs
	do
		cp -fp "$IMAGE_OUTPUT_DIR/vnstat_$output.png" "$IMAGE_OUTPUT_DIR/.vnstat_$output.htm"
		rm -f "$IMAGE_OUTPUT_DIR/vnstat_$output.htm"
	done
}

##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Generate_Stats()
{
	if [ ! -f /opt/bin/xargs ]
	then
		Print_Output true "Installing findutils from Entware" "$PASS"
		opkg update
		opkg install findutils
	fi
	if [ -n "$PPID" ]
	then
		ps | grep -v grep | grep -v $$ | grep -v "$PPID" | grep -i "$SCRIPT_NAME" | grep generate | awk '{print $1}' | xargs kill -9 >/dev/null 2>&1
	else
		ps | grep -v grep | grep -v $$ | grep -i "$SCRIPT_NAME" | grep generate | awk '{print $1}' | xargs kill -9 >/dev/null 2>&1
	fi
	sleep 3
	Create_Dirs
	Conf_Exists
	ScriptStorageLocation load
	Create_Symlinks
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Shortcut_Script create
	Process_Upgrade

	interface="$(_GetInterfaceNameFromConfig_)"
	TZ="$(cat /etc/TZ)"
	export TZ

	printf "vnstats [%s] as of: %s\n\n" "$interface" "$(date)" > "$VNSTAT_OUTPUT_FILE"
	{
		$VNSTAT_COMMAND -h 25 -i "$interface";
		$VNSTAT_COMMAND -d 8 -i "$interface";
		$VNSTAT_COMMAND -m 6 -i "$interface";
		$VNSTAT_COMMAND -y 5 -i "$interface";
	} >> "$VNSTAT_OUTPUT_FILE"

	if [ $# -eq 0 ] || [ -z "$1" ]
	then
		cat "$VNSTAT_OUTPUT_FILE"
		printf "\n"
		Print_Output false "vnstat_totals summary generated" "$PASS"
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
Generate_Email()
{
	if [ -f /jffs/addons/amtm/mail/email.conf ] && \
	   [ -f /jffs/addons/amtm/mail/emailpw.enc ]
	then
		. /jffs/addons/amtm/mail/email.conf
		PWENCFILE=/jffs/addons/amtm/mail/emailpw.enc
	else
		Print_Output true "$SCRIPT_NAME relies on amtm to send email summaries and email settings have not been configured" "$ERR"
		Print_Output true "Navigate to amtm > em (email settings) to set them up" "$ERR"
		return 1
	fi

	PASSWORD=""
	if /usr/sbin/openssl aes-256-cbc -d -in "$PWENCFILE" -pass pass:ditbabot,isoi >/dev/null 2>&1
	then
		# old OpenSSL 1.0.x #
		PASSWORD="$(/usr/sbin/openssl aes-256-cbc -d -in "$PWENCFILE" -pass pass:ditbabot,isoi 2>/dev/null)"
	elif /usr/sbin/openssl aes-256-cbc -d -md md5 -in "$PWENCFILE" -pass pass:ditbabot,isoi >/dev/null 2>&1
	then
		# new OpenSSL 1.1.x non-converted password #
		PASSWORD="$(/usr/sbin/openssl aes-256-cbc -d -md md5 -in "$PWENCFILE" -pass pass:ditbabot,isoi 2>/dev/null)"
	elif /usr/sbin/openssl aes-256-cbc $emailPwEnc -d -in "$PWENCFILE" -pass pass:ditbabot,isoi >/dev/null 2>&1
	then
		# new OpenSSL 1.1.x converted password with -pbkdf2 flag #
		PASSWORD="$(/usr/sbin/openssl aes-256-cbc $emailPwEnc -d -in "$PWENCFILE" -pass pass:ditbabot,isoi 2>/dev/null)"
	fi

	emailtype="$1"
	if [ "$emailtype" = "daily" ]
	then
		Print_Output true "Attempting to send summary statistic email" "$PASS"
		if [ "$(DailyEmail check)" = "text" ]
		then
			# plain text email to send #
			{
				echo "From: \"$FRIENDLY_ROUTER_NAME\" <$FROM_ADDRESS>"
				echo "To: \"$TO_NAME\" <$TO_ADDRESS>"
				echo "Subject: $FRIENDLY_ROUTER_NAME - vnstat-stats as of $(date +"%H.%M on %F")"
				echo "Date: $(date -R)"
				echo ""
				printf "%s\\n\\n" "$(_GetBandwidthUsageStringFromFile_)"
			} > /tmp/mail.txt
			cat "$VNSTAT_OUTPUT_FILE" >>/tmp/mail.txt
		elif [ "$(DailyEmail check)" = "html" ]
		then
			# html message to send #
			{
				echo "From: \"$FRIENDLY_ROUTER_NAME\" <$FROM_ADDRESS>"
				echo "To: \"$TO_NAME\" <$TO_ADDRESS>"
				echo "Subject: $FRIENDLY_ROUTER_NAME - vnstat-stats as of $(date +"%H.%M on %F")"
				echo "Date: $(date -R)"
				echo "MIME-Version: 1.0"
				echo "Content-Type: multipart/mixed; boundary=\"MULTIPART-MIXED-BOUNDARY\""
				echo "hello there"
				echo ""
				echo "--MULTIPART-MIXED-BOUNDARY"
				echo "Content-Type: multipart/related; boundary=\"MULTIPART-RELATED-BOUNDARY\""
				echo ""
				echo "--MULTIPART-RELATED-BOUNDARY"
				echo "Content-Type: multipart/alternative; boundary=\"MULTIPART-ALTERNATIVE-BOUNDARY\""
			} > /tmp/mail.txt

			echo "<html><body><p>Welcome to your dn-vnstat stats email!</p>" > /tmp/message.html
			echo "<p>$(_GetBandwidthUsageStringFromFile_)</p>" >> /tmp/message.html

			outputs="s hg d t m"
			for output in $outputs
			do
				echo "<p><img src=\"cid:vnstat_$output.png\"></p>" >> /tmp/message.html
			done

			echo "</body></html>" >> /tmp/message.html

			message_base64="$(openssl base64 -A < /tmp/message.html)"
			rm -f /tmp/message.html

			{
				echo ""
				echo "--MULTIPART-ALTERNATIVE-BOUNDARY"
				echo "Content-Type: text/html; charset=utf-8"
				echo "Content-Transfer-Encoding: base64"
				echo ""
				echo "$message_base64"
				echo ""
				echo "--MULTIPART-ALTERNATIVE-BOUNDARY--"
				echo ""
			} >> /tmp/mail.txt

			for output in $outputs
			do
				image_base64="$(openssl base64 -A < "$IMAGE_OUTPUT_DIR/vnstat_$output.png")"
				Encode_Image "vnstat_$output.png" "$image_base64" /tmp/mail.txt
			done

			Encode_Text vnstat.txt "$(cat "$VNSTAT_OUTPUT_FILE")" /tmp/mail.txt

			{
				echo "--MULTIPART-RELATED-BOUNDARY--"
				echo ""
				echo "--MULTIPART-MIXED-BOUNDARY--"
			} >> /tmp/mail.txt
		fi
	elif [ "$emailtype" = "usage" ]
	then
		if [ $# -lt 4 ] || [ -z "$4" ]
		then Print_Output true "Attempting to send bandwidth usage email" "$PASS"
		fi
		usagePercentage="$2"
		bwUsageStr="$3"
		# plain text email to send #
		{
			echo "From: \"$FRIENDLY_ROUTER_NAME\" <$FROM_ADDRESS>"
			echo "To: \"$TO_NAME\" <$TO_ADDRESS>"
			echo "Subject: $FRIENDLY_ROUTER_NAME - vnstat data usage $usagePercentage warning - $(date +"%H.%M on %F")"
			echo "Date: $(date -R)"
			echo ""
		} > /tmp/mail.txt
		printf "%s" "$bwUsageStr" >> /tmp/mail.txt
	fi

	#Send Email#
	/usr/sbin/curl -s --show-error --url "$PROTOCOL://$SMTP:$PORT" \
	--mail-from "$FROM_ADDRESS" --mail-rcpt "$TO_ADDRESS" \
	--upload-file /tmp/mail.txt \
	--ssl-reqd \
 	--crlf \
	--user "$USERNAME:$PASSWORD" $SSL_FLAG

	if [ $? -eq 0 ]
	then
		echo
		if [ $# -lt 4 ] || [ -z "$4" ]
		then Print_Output true "Email sent successfully" "$PASS"
		fi
		rm -f /tmp/mail.txt
		PASSWORD=""
		return 0
	else
		echo
		if [ $# -lt 4 ] || [ -z "$4" ]
		then Print_Output true "Email failed to send" "$ERR"
		fi
		rm -f /tmp/mail.txt
		PASSWORD=""
		return 1
	fi
}

# encode image for email inline
# $1 : image content id filename (match the cid:filename.png in html document)
# $2 : image content base64 encoded
# $3 : output file
Encode_Image()
{
	{
		echo "";
		echo "--MULTIPART-RELATED-BOUNDARY";
		echo "Content-Type: image/png;name=\"$1\"";
		echo "Content-Transfer-Encoding: base64";
		echo "Content-Disposition: inline;filename=\"$1\"";
		echo "Content-Id: <$1>";
		echo "";
		echo "$2";
	} >> "$3"
}

# encode text for email inline
# $1 : text content base64 encoded
# $2 : output file
Encode_Text()
{
	{
		echo "";
		echo "--MULTIPART-RELATED-BOUNDARY";
		echo "Content-Type: text/plain;name=\"$1\"";
		echo "Content-Transfer-Encoding: quoted-printable";
		echo "Content-Disposition: attachment;filename=\"$1\"";
		echo "";
		echo "$2";
	} >> "$3"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
DailyEmail()
{
	case "$1" in
		enable)
			if [ $# -lt 2 ] || [ -z "$2" ]
			then
				ScriptHeader
				exitmenu="false"
				printf "\n${BOLD}A choice of emails is available:${CLEARFORMAT}\n"
				printf " 1.  HTML (includes images from WebUI + summary stats as attachment)\n"
				printf " 2.  Plain text (summary stats only)\n\n"
				printf " e.  Exit to main menu\n"

				while true
				do
					printf "\n${BOLD}Choose an option:${CLEARFORMAT}  "
					read -r emailtype
					case "$emailtype" in
						1)
							sed -i 's/^DAILYEMAIL.*$/DAILYEMAIL=html/' "$SCRIPT_CONF"
							break
						;;
						2)
							sed -i 's/^DAILYEMAIL.*$/DAILYEMAIL=text/' "$SCRIPT_CONF"
							break
						;;
						e)
							exitmenu="true"
							break
						;;
						*)
							printf "\nPlease choose a valid option\n\n"
						;;
					esac
				done
				printf "\n"

				if [ "$exitmenu" = "true" ]; then
					return
				fi
			else
				sed -i 's/^DAILYEMAIL.*$/DAILYEMAIL='"$2"'/' "$SCRIPT_CONF"
			fi

			Generate_Email daily
			if [ $? -eq 1 ]; then
				DailyEmail disable
			fi
		;;
		disable)
			sed -i 's/^DAILYEMAIL.*$/DAILYEMAIL=none/' "$SCRIPT_CONF"
		;;
		check)
			DAILYEMAIL="$(_GetConfigParam_ DAILYEMAIL none)"
			echo "$DAILYEMAIL"
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
UsageEmail()
{
	case "$1" in
		enable)
			sed -i 's/^USAGEEMAIL.*$/USAGEEMAIL=true/' "$SCRIPT_CONF"
			Check_Bandwidth_Usage
		;;
		disable)
			sed -i 's/^USAGEEMAIL.*$/USAGEEMAIL=false/' "$SCRIPT_CONF"
		;;
		check)
			USAGEEMAIL="$(_GetConfigParam_ USAGEEMAIL 'false')"
			if [ "$USAGEEMAIL" = "true" ]
			then return 0; else return 1; fi
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
BandwidthAllowance()
{
	case "$1" in
		update)
			bandwidth="$(echo "$2" | awk '{printf("%.2f", $1);}')"
			sed -i 's/^DATAALLOWANCE.*$/DATAALLOWANCE='"$bandwidth"'/' "$SCRIPT_CONF"
			if [ $# -lt 3 ] || [ -z "$3" ]
			then
				Reset_Allowance_Warnings force
			fi
			Check_Bandwidth_Usage
		;;
		check)
			DATAALLOWANCE="$(_GetConfigParam_ DATAALLOWANCE '1200.00')"
			echo "$DATAALLOWANCE"
		;;
	esac
}

AllowanceStartDay()
{
	case "$1" in
		update)
			sed -i 's/^MonthRotate .*$/MonthRotate '"$2"'/' "$VNSTAT_CONFIG"
			/opt/etc/init.d/S33vnstat restart >/dev/null 2>&1
			TZ=$(cat /etc/TZ)
			export TZ
			Reset_Allowance_Warnings force
			Check_Bandwidth_Usage
		;;
		check)
			MonthRotate=$(grep "^MonthRotate " "$VNSTAT_CONFIG" | cut -f2 -d" ")
			echo "$MonthRotate"
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
AllowanceUnit()
{
	case "$1" in
		update)
		sed -i 's/^ALLOWANCEUNIT.*$/ALLOWANCEUNIT='"$2"'/' "$SCRIPT_CONF"
		;;
		check)
			ALLOWANCEUNIT="$(_GetConfigParam_ ALLOWANCEUNIT 'G')"
			echo "${ALLOWANCEUNIT}B"
		;;
	esac
}

##----------------------------------------##
## Modified by Martinski W. [2025-Apr-27] ##
##----------------------------------------##
Reset_Allowance_Warnings()
{
	if { [ $# -gt 0 ] && [ "$1" = "force" ] ; } || \
	   [ "$(date +%d | awk '{printf("%s", $1+1);}')" -eq "$(AllowanceStartDay check)" ]
	then
		rm -f "$SCRIPT_STORAGE_DIR/.warning75"
		rm -f "$SCRIPT_STORAGE_DIR/.warning90"
		rm -f "$SCRIPT_STORAGE_DIR/.warning100"
	fi
}

##-------------------------------------##
## Added by Martinski W. [2025-Jun-21] ##
##-------------------------------------##
_GetBandwidthUsageStringFromFile_()
{
   if [ ! -s "$SCRIPT_STORAGE_DIR/.vnstatusage" ]
   then echo "No Data" ; return 1
   fi
   grep "^var usagestring =" "$SCRIPT_STORAGE_DIR/.vnstatusage" | awk -F "['\"]" '{print $2}'
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-30] ##
##----------------------------------------##
Check_Bandwidth_Usage()
{
	if [ ! -f /opt/bin/jq ]
	then
		opkg update
		opkg install jq
	fi
	TZ="$(cat /etc/TZ)"
	export TZ

	interface="$(_GetInterfaceNameFromConfig_)"
	if [ -z "$interface" ]
	then
		Print_Output true "**ERROR** No Interface ID found. Unable to check bandwidth usage" "$CRIT"
		return 1
	fi

	rawbandwidthused="$($VNSTAT_COMMAND -i "$interface" --json m | jq -r '.interfaces[].traffic.month[-1] | .rx + .tx')"
	userLimit="$(BandwidthAllowance check)"

	bandwidthused="$(echo "$rawbandwidthused" | awk '{printf("%.2f\n", $1/(1000*1000*1000));}')"
	if AllowanceUnit check | grep -q T
	then
		bandwidthused="$(echo "$rawbandwidthused" | awk '{printf("%.2f\n", $1/(1000*1000*1000*1000));}')"
	fi

	bandwidthPercentage=""
	bwUsageStr=""
	if [ "$(echo "$userLimit 0" | awk '{print ($1 == $2)}')" -eq 1 ]
	then
		bandwidthPercentage="N/A"
		bwUsageStr="You have used ${bandwidthused}$(AllowanceUnit check) of data this cycle; the next cycle starts on day $(AllowanceStartDay check) of the month."
	else
		bandwidthPercentage="$(echo "$bandwidthused $userLimit" | awk '{printf("%.2f\n", $1*100/$2);}')"
		bwUsageStr="You have used ${bandwidthPercentage}% (${bandwidthused}$(AllowanceUnit check)) of your ${userLimit}$(AllowanceUnit check) cycle allowance; the next cycle starts on day $(AllowanceStartDay check) of the month."
	fi

	local isVerbose=false
	if [ $# -eq 0 ] || [ -z "$1" ]
	then
		isVerbose=true
		Print_Output false "$bwUsageStr" "$PASS"
	fi

	if [ "$bandwidthPercentage" = "N/A" ] || \
	   [ "$(echo "$bandwidthPercentage 75" | awk '{print ($1 < $2)}')" -eq 1 ]
	then
		{
		   echo "var usagethreshold = false;"
		   echo "var thresholdstring = '';"
		} > "$SCRIPT_STORAGE_DIR/.vnstatusage"
	elif [ "$(echo "$bandwidthPercentage 75" | awk '{print ($1 >= $2)}')" -eq 1 ] && \
	     [ "$(echo "$bandwidthPercentage 90" | awk '{print ($1 < $2)}')" -eq 1 ]
	then
		"$isVerbose" && Print_Output false "Data use is at or above 75%" "$WARN"
		{
		   echo "var usagethreshold = true;"
		   echo "var thresholdstring = 'Data use is at or above 75%';"
		} > "$SCRIPT_STORAGE_DIR/.vnstatusage"
		if UsageEmail check && [ ! -f "$SCRIPT_STORAGE_DIR/.warning75" ]
		then
			if "$isVerbose"
			then Generate_Email usage "75%" "$bwUsageStr"
			else Generate_Email usage "75%" "$bwUsageStr" silent
			fi
			touch "$SCRIPT_STORAGE_DIR/.warning75"
		fi
	elif [ "$(echo "$bandwidthPercentage 90" | awk '{print ($1 >= $2)}')" -eq 1 ] && \
	     [ "$(echo "$bandwidthPercentage 100" | awk '{print ($1 < $2)}')" -eq 1 ]
	then
		"$isVerbose" && Print_Output false "Data use is at or above 90%" "$ERR"
		{
		   echo "var usagethreshold = true;"
		   echo "var thresholdstring = 'Data use is at or above 90%';"
		} > "$SCRIPT_STORAGE_DIR/.vnstatusage"
		if UsageEmail check && [ ! -f "$SCRIPT_STORAGE_DIR/.warning90" ]
		then
			if "$isVerbose"
			then Generate_Email usage "90%" "$bwUsageStr"
			else Generate_Email usage "90%" "$bwUsageStr" silent
			fi
			touch "$SCRIPT_STORAGE_DIR/.warning90"
		fi
	elif [ "$(echo "$bandwidthPercentage 100" | awk '{print ($1 >= $2)}')" -eq 1 ]
	then
		"$isVerbose" && Print_Output false "Data use is at or above 100%" "$CRIT"
		{
		   echo "var usagethreshold = true;"
		   echo "var thresholdstring = 'Data use is at or above 100%';"
		} > "$SCRIPT_STORAGE_DIR/.vnstatusage"
		if UsageEmail check && [ ! -f "$SCRIPT_STORAGE_DIR/.warning100" ]
		then
			if "$isVerbose"
			then Generate_Email usage "100%" "$bwUsageStr"
			else Generate_Email usage "100%" "$bwUsageStr" silent
			fi
			touch "$SCRIPT_STORAGE_DIR/.warning100"
		fi
	fi
	{
	   printf "var usagestring = '%s';\n" "$bwUsageStr"
	   printf "var daterefreshed = '%s';\n" "$(date +'%Y-%m-%d %T')"
	} >> "$SCRIPT_STORAGE_DIR/.vnstatusage"

	_UpdateDatabaseFileSizeInfo_
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-30] ##
##----------------------------------------##
Process_Upgrade()
{
	local restartvnstat=false

	if [ ! -f "$SCRIPT_STORAGE_DIR/.vnstatusage" ]
	then
		{
		   echo "var usagethreshold = false;"
		   echo "var thresholdstring = '';"
		   echo "var usagestring = 'Not enough data gathered by vnstat';"
		   echo "var sqlDatabaseFileSize = '0 Bytes';"
		   echo "var jffsAvailableSpaceLow = 'OK';"
		   echo "var jffsAvailableSpaceStr = '0 Bytes';"
		} > "$SCRIPT_STORAGE_DIR/.vnstatusage"
	##
	elif grep -q "^var daterefeshed = .*" "$SCRIPT_STORAGE_DIR/.vnstatusage"
	then
		sed -i 's/var daterefeshed =/var daterefreshed =/' "$SCRIPT_STORAGE_DIR/.vnstatusage"
	fi

	if ! grep -q "^UseUTC 0" "$VNSTAT_CONFIG"
	then
		sed -i "/^DatabaseSynchronous/a\\\n# Enable or disable using UTC as timezone in the database for all entries.\n# When enabled, all entries added to the database will use UTC regardless of\n# the configured system timezone. When disabled, the configured system timezone\n# will be used. Changing this setting will not result in already existing data to be modified.\n# 1 = enabled, 0 = disabled.\nUseUTC 0" "$VNSTAT_CONFIG"
		restartvnstat=true
	fi

	if [ "$restartvnstat" = "true" ]
	then
		/opt/etc/init.d/S33vnstat restart >/dev/null 2>&1
		Generate_Images silent
		Generate_Stats silent
		Check_Bandwidth_Usage silent
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
ScriptHeader()
{
	clear
	printf "\n"
	printf "${BOLD}##############################################################${CLEARFORMAT}\n"
	printf "${BOLD}##                                                          ##${CLEARFORMAT}\n"
	printf "${BOLD}##                     vnStat on Merlin                     ##${CLEARFORMAT}\n"
	printf "${BOLD}##                for AsusWRT-Merlin routers                ##${CLEARFORMAT}\n"
	printf "${BOLD}##                                                          ##${CLEARFORMAT}\n"
	printf "${BOLD}##                %9s on %-18s           ##${CLEARFORMAT}\n" "$SCRIPT_VERSION" "$ROUTER_MODEL"
	printf "${BOLD}##                                                          ## ${CLEARFORMAT}\n"
	printf "${BOLD}##       https://github.com/AMTM-OSR/vnstat-on-merlin       ##${CLEARFORMAT}\n"
	printf "${BOLD}## Forked from https://github.com/de-vnull/vnstat-on-merlin ##${CLEARFORMAT}\n"
	printf "${BOLD}##                                                          ##${CLEARFORMAT}\n"
	printf "${BOLD}##############################################################${CLEARFORMAT}\n"
	printf "\n"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-03] ##
##----------------------------------------##
MainMenu()
{
	local menuOption  storageLocStr
	local jffsFreeSpace  jffsFreeSpaceStr  jffsSpaceMsgTag

	MENU_DAILYEMAIL="$(DailyEmail check)"
	if [ "$MENU_DAILYEMAIL" = "html" ]; then
		MENU_DAILYEMAIL="${PASS}ENABLED - HTML"
	elif [ "$MENU_DAILYEMAIL" = "text" ]; then
		MENU_DAILYEMAIL="${PASS}ENABLED - TEXT"
	elif [ "$MENU_DAILYEMAIL" = "none" ]; then
		MENU_DAILYEMAIL="${ERR}DISABLED"
	fi

	local MENU_USAGE_ENABLED
	if UsageEmail check
	then MENU_USAGE_ENABLED="${PASS}ENABLED"
	else MENU_USAGE_ENABLED="${ERR}DISABLED"
	fi

	local bandwidthDataUnit="$(AllowanceUnit check)"
	local bandwidthAllowance="$(BandwidthAllowance check)"
	local MENU_BANDWIDTHALLOWANCE
	if [ "$(echo "$bandwidthAllowance 0" | awk '{print ($1 == $2)}')" -eq 1 ]
	then MENU_BANDWIDTHALLOWANCE="UNLIMITED"
	else MENU_BANDWIDTHALLOWANCE="${bandwidthAllowance} ${bandwidthDataUnit}ytes"
	fi

	storageLocStr="$(ScriptStorageLocation check | tr 'a-z' 'A-Z')"

	_UpdateJFFS_FreeSpaceInfo_
	jffsFreeSpace="$(_Get_JFFS_Space_ FREE HRx | sed 's/%/%%/')"
	if ! echo "$JFFS_LowFreeSpaceStatus" | grep -E "^WARNING[0-9]$"
	then
		jffsFreeSpaceStr="${SETTING}$jffsFreeSpace"
	else
		if [ "$storageLocStr" = "JFFS" ]
		then jffsSpaceMsgTag="${CritBREDct} <<< WARNING! "
		else jffsSpaceMsgTag="${WarnBMGNct} <<< NOTICE! "
		fi
		jffsFreeSpaceStr="${WarnBYLWct} $jffsFreeSpace ${CLRct}  ${jffsSpaceMsgTag}${CLRct}"
	fi

	printf "WebUI for %s is available at:\n${SETTING}%s${CLEARFORMAT}\n\n" "$SCRIPT_NAME" "$(Get_WebUI_URL)"

	printf "1.    Update stats now\n"
	printf "      Database size: ${SETTING}%s${CLEARFORMAT}\n\n" "$(_GetFileSize_ "$(_GetVNStatDatabaseFilePath_)" HRx)"
	printf "2.    Toggle emails for daily summary stats\n"
	printf "      Currently: ${BOLD}$MENU_DAILYEMAIL${CLEARFORMAT}\n\n"
	printf "3.    Toggle emails for data usage warnings\n"
	printf "      Currently: ${BOLD}$MENU_USAGE_ENABLED${CLEARFORMAT}\n\n"
	printf "4.    Set bandwidth allowance for data usage warnings\n"
	printf "      Currently: ${SETTING}%s${CLEARFORMAT}\n\n" "$MENU_BANDWIDTHALLOWANCE"
	printf "5.    Set unit for bandwidth allowance\n"
	printf "      Currently: ${SETTING}%s${CLEARFORMAT}\n\n" "$(AllowanceUnit check)"
	printf "6.    Set start day of cycle for bandwidth allowance\n"
	printf "      Currently: ${SETTING}%s${CLEARFORMAT}\n\n" "Day $(AllowanceStartDay check) of month"
	printf "b.    Check bandwidth usage now\n"
	printf "      ${SETTING}%s${CLEARFORMAT}\n\n" "$(_GetBandwidthUsageStringFromFile_)"
	printf "v.    Edit vnstat config\n\n"
	printf "t.    Toggle time output mode\n"
	printf "      Currently ${SETTING}%s${CLEARFORMAT} time values will be used for CSV exports\n\n" "$(OutputTimeMode check)"
	printf "s.    Toggle storage location for stats and config\n"
	printf "      Current location: ${SETTING}%s${CLEARFORMAT}\n" "$storageLocStr"
	printf "      JFFS Available: ${jffsFreeSpaceStr}${CLEARFORMAT}\n\n"
	printf "u.    Check for updates\n"
	printf "uf.   Force update %s with latest version\n\n" "$SCRIPT_NAME"
	printf "e.    Exit %s\n\n" "$SCRIPT_NAME"
	printf "z.    Uninstall %s\n" "$SCRIPT_NAME"
	printf "\n"
	printf "${BOLD}##################################################${CLEARFORMAT}\n"
	printf "\n"

	while true
	do
		printf "Choose an option:  "
		read -r menuOption
		case "$menuOption" in
			1)
				printf "\n"
				VNStat_ServiceCheck
				if Check_Lock menu
				then
					Generate_Images
					Generate_Stats
					Generate_CSVs
					Clear_Lock
				fi
				PressEnter
				break
			;;
			2)
				printf "\n"
				if [ "$(DailyEmail check)" != "none" ]; then
					DailyEmail disable
				elif [ "$(DailyEmail check)" = "none" ]; then
					DailyEmail enable
				fi
				PressEnter
				break
			;;
			3)
				printf "\n"
				if UsageEmail check; then
					UsageEmail disable
				elif ! UsageEmail check; then
					UsageEmail enable
				fi
				PressEnter
				break
			;;
			4)
				printf "\n"
				if Check_Lock menu; then
					Menu_BandwidthAllowance
				fi
				PressEnter
				break
			;;
			5)
				printf "\n"
				if Check_Lock menu; then
					Menu_AllowanceUnit
				fi
				PressEnter
				break
			;;
			6)
				printf "\n"
				if Check_Lock menu; then
					Menu_AllowanceStartDay
				fi
				PressEnter
				break
			;;
			b)
				printf "\n"
				if Check_Lock menu; then
					Check_Bandwidth_Usage
					Clear_Lock
				fi
				PressEnter
				break
			;;
			v)
				printf "\n"
				if Check_Lock menu; then
					Menu_Edit
				fi
				break
			;;
			t)
				printf "\n"
				if [ "$(OutputTimeMode check)" = "unix" ]; then
					OutputTimeMode non-unix
				elif [ "$(OutputTimeMode check)" = "non-unix" ]; then
					OutputTimeMode unix
				fi
				break
			;;
			s)
				printf "\n"
				if Check_Lock menu
				then
					if [ "$(ScriptStorageLocation check)" = "jffs" ]
					then
					    ScriptStorageLocation usb
					elif [ "$(ScriptStorageLocation check)" = "usb" ]
					then
					    if ! _Check_JFFS_SpaceAvailable_ "$SCRIPT_STORAGE_DIR"
					    then
					        Clear_Lock
					        PressEnter
					        break
					    fi
					    ScriptStorageLocation jffs
					fi
					Create_Symlinks
					Clear_Lock
				fi
				break
			;;
			u)
				printf "\n"
				if Check_Lock menu; then
					Update_Version
					Clear_Lock
				fi
				PressEnter
				break
			;;
			uf)
				printf "\n"
				if Check_Lock menu; then
					Update_Version force
					Clear_Lock
				fi
				PressEnter
				break
			;;
			e)
				ScriptHeader
				printf "\n${BOLD}Thanks for using %s!${CLEARFORMAT}\n\n\n" "$SCRIPT_NAME"
				exit 0
			;;
			z)
				while true
				do
					printf "\n${BOLD}Are you sure you want to uninstall %s? (y/n)${CLEARFORMAT}  " "$SCRIPT_NAME"
					read -r confirm
					case "$confirm" in
						y|Y)
							Menu_Uninstall
							exit 0
						;;
						*) break ;;
					esac
				done
			;;
			*)
				[ -n "$menuOption" ] && \
				printf "\n${REDct}INVALID input [$menuOption]${CLEARFORMAT}"
				printf "\nPlease choose a valid option.\n\n"
				PressEnter
				break
			;;
		esac
	done

	ScriptHeader
	MainMenu
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-30] ##
##----------------------------------------##
Menu_Install()
{
	ScriptHeader
	Print_Output true "Welcome to $SCRIPT_NAME $SCRIPT_VERSION, a script by dev_null and Jack Yaz" "$PASS"
	sleep 1

	Print_Output false "Checking your router meets the requirements for $SCRIPT_NAME" "$PASS"

	if ! Check_Requirements
	then
		Print_Output false "Requirements for $SCRIPT_NAME not met, please see above for the reason(s)" "$CRIT"
		PressEnter
		Clear_Lock
		rm -f "/jffs/scripts/$SCRIPT_NAME" 2>/dev/null
		exit 1
	fi

	WAN_IFACE=""
	printf "\n${BOLD}WAN Interface detected as ${GRNct}%s${CLEARFORMAT}\n" "$(Get_WAN_IFace)"
	while true
	do
		printf "\n${BOLD}Is this correct? (y/n)${CLEARFORMAT}  "
		read -r confirm
		case "$confirm" in
			y|Y)
				WAN_IFACE="$(Get_WAN_IFace)"
				break
			;;
			n|N)
				while true
				do
					printf "\n${BOLD}Please enter correct interface:${CLEARFORMAT}  "
					read -r iface
					iface_lower="$(echo "$iface" | tr "A-Z" "a-z")"
					if [ "$iface" = "e" ]
					then
						Clear_Lock
						rm -f "/jffs/scripts/$SCRIPT_NAME" 2>/dev/null
						exit 1
					elif [ ! -f "/sys/class/net/$iface_lower/operstate" ] || \
					     [ "$(cat "/sys/class/net/$iface_lower/operstate")" = "down" ]
					then
						printf "\n${ERR}Input is not a valid interface or interface not up, please try again.${CLEARFORMAT}\n"
					else
						WAN_IFACE="$iface_lower"
						break
					fi
				done
			;;
			*)
				:
			;;
		esac
	done
	printf "\n"

	Create_Dirs
	Conf_Exists
	Set_Version_Custom_Settings local "$SCRIPT_VERSION"
	Set_Version_Custom_Settings server "$SCRIPT_VERSION"
	ScriptStorageLocation load
	Create_Symlinks

	Update_File vnstat.conf
	sed -i 's/^Interface .*$/Interface "'"$WAN_IFACE"'"/' "$VNSTAT_CONFIG"

	Update_File vnstat-ui.asp
	Update_File shared-jy.tar.gz
	Update_File S33vnstat

	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Shortcut_Script create

	if [ ! -f "$SCRIPT_STORAGE_DIR/.vnstatusage" ]
	then
		{
		   echo "var usagethreshold = false;"
		   echo "var thresholdstring = '';"
		   echo "var usagestring = 'Not enough data gathered by vnstat';"
		   echo "var sqlDatabaseFileSize = '0 Bytes';"
		   echo "var jffsAvailableSpaceLow = 'OK';"
		   echo "var jffsAvailableSpaceStr = '0 Bytes';"
		} > "$SCRIPT_STORAGE_DIR/.vnstatusage"
	fi

	if [ -n "$(pidof vnstatd)" ]
	then
		Print_Output true "Sleeping for 60 secs before generating initial stats..." "$WARN"
		sleep 60
		Generate_Images
		Generate_Stats
		Check_Bandwidth_Usage silent
		Generate_CSVs
	else
		Print_Output true "**ERROR**: vnstatd service NOT running, check system log" "$ERR"
	fi

	Clear_Lock
	ScriptHeader
	MainMenu
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-03] ##
##----------------------------------------##
Menu_Startup()
{
	if [ $# -eq 0 ] || [ -z "$1" ]
	then
		Print_Output true "Missing argument for startup, not starting $SCRIPT_NAME" "$ERR"
		exit 1
	elif [ "$1" != "force" ]
	then
		if [ ! -f "${1}/entware/bin/opkg" ]
		then
			Print_Output true "$1 does NOT contain Entware, not starting $SCRIPT_NAME" "$CRIT"
			exit 1
		else
			Print_Output true "$1 contains Entware, $SCRIPT_NAME $SCRIPT_VERSION starting up" "$PASS"
		fi
	fi

	NTP_Ready startup
	Check_Lock

	if [ "$1" != "force" ]; then
		sleep 5
	fi
	Create_Dirs
	Conf_Exists
	ScriptStorageLocation load true
	Create_Symlinks
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Set_Version_Custom_Settings local "$SCRIPT_VERSION"
	Shortcut_Script create
	Mount_WebUI
	VNStat_ServiceCheck
	Clear_Lock
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
Menu_BandwidthAllowance()
{
	local exitmenu="false"
	local bwDataUnit="$(AllowanceUnit check)"
	local bwDataAllowance="$(BandwidthAllowance check)"
	local bwDataAllowanceStr

	if [ "$(echo "$bwDataAllowance 0" | awk '{print ($1 == $2)}')" -eq 1 ]
	then bwDataAllowanceStr="UNLIMITED"
	else bwDataAllowanceStr="${bwDataAllowance} ${bwDataUnit}ytes"
	fi

	while true
	do
		ScriptHeader
		printf "${BOLD}Current monthly bandwidth allowance: ${GRNct}${bwDataAllowanceStr}${CLRct}\n\n"
		printf "${BOLD}Enter your monthly bandwidth allowance in ${GRNct}%s${CLRct} units\n" "${bwDataUnit}yte"
		printf "(0 = Unlimited, max. 2 decimal places):${CLEARFORMAT}  "
		read -r allowance

		if [ "$allowance" = "e" ]
		then
			exitmenu="exit"
			printf "\n"
			break
		elif ! Validate_Bandwidth "$allowance"
		then
			printf "\n${ERR}Please enter a valid number (0 = unlimited, max. 2 decimal places)${CLEARFORMAT}\n"
			PressEnter
		else
			bwDataAllowance="$allowance"
			printf "\n"
			break
		fi
	done

	if [ "$exitmenu" != "exit" ]; then
		BandwidthAllowance update "$bwDataAllowance"
	fi

	Clear_Lock
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
Menu_AllowanceUnit()
{
	exitmenu="false"
	allowanceunit=""
	prevallowanceunit="$(AllowanceUnit check)"
	unitsuffix="$(AllowanceUnit check | sed 's/T//;s/G//;')"

	while true
	do
		ScriptHeader
		printf "\n${BOLD}Please select the unit to use for bandwidth allowance:${CLEARFORMAT}\n"
		printf " 1.  G%s\n" "$unitsuffix"
		printf " 2.  T%s\n\n" "$unitsuffix"
		printf " Choose an option:  "
		read -r unitchoice
		case "$unitchoice" in
			1)
				allowanceunit="G"
				printf "\n"
				break
			;;
			2)
				allowanceunit="T"
				printf "\n"
				break
			;;
			e)
				exitmenu="exit"
				printf "\n"
				break
			;;
			*)
				printf "\n${ERR}Please choose a valid option [1-2]${CLEARFORMAT}\n"
				PressEnter
			;;
		esac
	done

	if [ "$exitmenu" != "exit" ]
	then
		AllowanceUnit update "$allowanceunit"

		allowanceunit="$(AllowanceUnit check)"
		if [ "$prevallowanceunit" != "$allowanceunit" ]
		then
			scalefactor=1000

			scaletype="none"
			if [ "$prevallowanceunit" != "$(AllowanceUnit check)" ]
			then
				if echo "$prevallowanceunit" | grep -q G && AllowanceUnit check | grep -q T; then
					scaletype="divide"
				elif echo "$prevallowanceunit" | grep -q T && AllowanceUnit check | grep -q G; then
					scaletype="multiply"
				fi
			fi

			if [ "$scaletype" != "none" ]
			then
				bandwidthAllowance="$(BandwidthAllowance check)"
				if [ "$scaletype" = "multiply" ]
				then
					bandwidthAllowance="$(echo "$(BandwidthAllowance check) $scalefactor" | awk '{printf("%.2f\n", $1*$2);}')"
				elif [ "$scaletype" = "divide" ]
				then
					bandwidthAllowance="$(echo "$(BandwidthAllowance check) $scalefactor" | awk '{printf("%.2f\n", $1/$2);}')"
				fi
				BandwidthAllowance update "$bandwidthAllowance" noreset
			fi
		fi
	fi

	Clear_Lock
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
Menu_AllowanceStartDay()
{
	exitmenu="false"
	allowancestartday=""

	while true
	do
		ScriptHeader
		printf "\n${BOLD}Please enter day of month that your bandwidth allowance\nresets [1-28]:${CLEARFORMAT}  "
		read -r startday

		if [ "$startday" = "e" ]
		then
			exitmenu="exit"
			printf "\n"
			break
		elif ! Validate_Number "$startday"
		then
			printf "\n${ERR}Please enter a valid number [1-28]${CLEARFORMAT}\n"
			PressEnter
		else
			if [ "$startday" -lt 1 ] || [ "$startday" -gt 28 ]
			then
				printf "\n${ERR}Please enter a number between 1 and 28${CLEARFORMAT}\n"
				PressEnter
			else
				allowancestartday="$startday"
				printf "\n"
				break
			fi
		fi
	done

	if [ "$exitmenu" != "exit" ]; then
		AllowanceStartDay update "$allowancestartday"
	fi

	Clear_Lock
}

##----------------------------------------##
## Modified by Martinski W. [2025-Apr-28] ##
##----------------------------------------##
Menu_Edit()
{
	texteditor=""
	exitmenu="false"

	printf "\n${BOLD}A choice of text editors is available:${CLEARFORMAT}\n"
	printf " 1.  nano (recommended for beginners)\n"
	printf " 2.  vi\n\n"
	printf " e.  Exit to main menu\n"

	while true
	do
		printf "\n${BOLD}Choose an option:${CLEARFORMAT}  "
		read -r editor
		case "$editor" in
			1)
				texteditor="nano -K"
				break
			;;
			2)
				texteditor="vi"
				break
			;;
			e)
				exitmenu="true"
				break
			;;
			*)
				printf "\nPlease choose a valid option\n\n"
			;;
		esac
	done

	if [ "$exitmenu" != "true" ]
	then
		oldmd5="$(md5sum "$VNSTAT_CONFIG" | awk '{print $1}')"
		$texteditor "$VNSTAT_CONFIG"
		newmd5="$(md5sum "$VNSTAT_CONFIG" | awk '{print $1}')"
		if [ "$oldmd5" != "$newmd5" ]
		then
			/opt/etc/init.d/S33vnstat restart >/dev/null 2>&1
			TZ=$(cat /etc/TZ)
			export TZ
			Check_Bandwidth_Usage silent
			Clear_Lock
			printf "\n"
			PressEnter
		fi
	fi
	Clear_Lock
}

##-------------------------------------##
## Added by Martinski W. [2025-Apr-27] ##
##-------------------------------------##
_RemoveMenuAddOnsSection_()
{
   if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ] || \
      ! echo "$1" | grep -qE "^[1-9][0-9]*$" || \
      ! echo "$2" | grep -qE "^[1-9][0-9]*$" || \
      [ "$1" -ge "$2" ]
   then return 1 ; fi
   local BEGINnum="$1"  ENDINnum="$2"

   if [ -n "$(sed -E "${BEGINnum},${ENDINnum}!d;/${webPageLineTabExp}/!d" "$TEMP_MENU_TREE")" ]
   then return 1
   fi
   sed -i "${BEGINnum},${ENDINnum}d" "$TEMP_MENU_TREE"
   return 0
}

##-------------------------------------##
## Added by Martinski W. [2025-Apr-27] ##
##-------------------------------------##
_FindandRemoveMenuAddOnsSection_()
{
   local BEGINnum  ENDINnum  retCode=1

   if grep -qE "^${BEGIN_MenuAddOnsTag}$" "$TEMP_MENU_TREE" && \
      grep -qE "^${ENDIN_MenuAddOnsTag}$" "$TEMP_MENU_TREE"
   then
       BEGINnum="$(grep -nE "^${BEGIN_MenuAddOnsTag}$" "$TEMP_MENU_TREE" | awk -F ':' '{print $1}')"
       ENDINnum="$(grep -nE "^${ENDIN_MenuAddOnsTag}$" "$TEMP_MENU_TREE" | awk -F ':' '{print $1}')"
       _RemoveMenuAddOnsSection_ "$BEGINnum" "$ENDINnum" && retCode=0
   fi

   if grep -qE "^${webPageMenuAddons}$" "$TEMP_MENU_TREE" && \
      grep -qE "${webPageHelpSupprt}$" "$TEMP_MENU_TREE"
   then
       BEGINnum="$(grep -nE "^${webPageMenuAddons}$" "$TEMP_MENU_TREE" | awk -F ':' '{print $1}')"
       ENDINnum="$(grep -nE "${webPageHelpSupprt}$" "$TEMP_MENU_TREE" | awk -F ':' '{print $1}')"
       if [ -n "$BEGINnum" ] && [ -n "$ENDINnum" ] && [ "$BEGINnum" -lt "$ENDINnum" ]
       then
           BEGINnum="$((BEGINnum - 2))" ; ENDINnum="$((ENDINnum + 3))"
           if [ "$(sed -n "${BEGINnum}p" "$TEMP_MENU_TREE")" = "," ] && \
              [ "$(sed -n "${ENDINnum}p" "$TEMP_MENU_TREE")" = "}" ]
           then
               _RemoveMenuAddOnsSection_ "$BEGINnum" "$ENDINnum" && retCode=0
           fi
       fi
   fi
   return "$retCode"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-03] ##
##----------------------------------------##
Menu_Uninstall()
{
	if [ -n "$PPID" ]
	then
		ps | grep -v grep | grep -v $$ | grep -v "$PPID" | grep -i "$SCRIPT_NAME" | grep generate | awk '{print $1}' | xargs kill -9 >/dev/null 2>&1
	else
		ps | grep -v grep | grep -v $$ | grep -i "$SCRIPT_NAME" | grep generate | awk '{print $1}' | xargs kill -9 >/dev/null 2>&1
	fi
	Print_Output true "Removing $SCRIPT_NAME..." "$PASS"
	Auto_Startup delete 2>/dev/null
	Auto_Cron delete 2>/dev/null
	Auto_ServiceEvent delete 2>/dev/null
	Shortcut_Script delete

	LOCKFILE=/tmp/addonwebui.lock
	FD=386
	eval exec "$FD>$LOCKFILE"
	flock -x "$FD"

	Get_WebUI_Page "$SCRIPT_DIR/vnstat-ui.asp"
	if [ -n "$MyWebPage" ] && \
	   [ "$MyWebPage" != "NONE" ] && \
	   [ -f "$TEMP_MENU_TREE" ]
	then
		sed -i "\\~$MyWebPage~d" "$TEMP_MENU_TREE"
		rm -f "$SCRIPT_WEBPAGE_DIR/$MyWebPage"
		rm -f "$SCRIPT_WEBPAGE_DIR/$(echo "$MyWebPage" | cut -f1 -d'.').title"
		_FindandRemoveMenuAddOnsSection_
		umount /www/require/modules/menuTree.js 2>/dev/null
		mount -o bind "$TEMP_MENU_TREE" /www/require/modules/menuTree.js
	fi

	flock -u "$FD"
	rm -f "$SCRIPT_DIR/vnstat-ui.asp"
	rm -rf "$SCRIPT_WEB_DIR" 2>/dev/null

	if [ -f /opt/etc/init.d/S33vnstat ]
	then
		/opt/etc/init.d/S33vnstat stop >/dev/null 2>&1
		sleep 2 ; killall -q vnstatd ; sleep 1
	fi
	touch /opt/etc/vnstat.conf
	opkg remove --autoremove vnstati2
	opkg remove --autoremove vnstat2

	rm -f /opt/etc/init.d/S33vnstat
	rm -f /opt/etc/vnstat.conf
    rm -f "$SCRIPT_DIR/S33vnstat"

	Reset_Allowance_Warnings force
	rm -f "$SCRIPT_STORAGE_DIR/.vnstatusage"
	rm -f "$SCRIPT_STORAGE_DIR/.v2upgraded"
	rm -rf "$IMAGE_OUTPUT_DIR"
	rm -rf "$CSV_OUTPUT_DIR"

	SETTINGSFILE="/jffs/addons/custom_settings.txt"
	sed -i '/dnvnstat_version_local/d' "$SETTINGSFILE"
	sed -i '/dnvnstat_version_server/d' "$SETTINGSFILE"

	printf "\n${BOLD}Would you like to keep the vnstat\ndata files and configuration? (y/n)${CLEARFORMAT}  "
	read -r confirm
	case "$confirm" in
		y|Y)
			:
		;;
		*)
			rm -rf "$SCRIPT_DIR" 2>/dev/null
			rm -rf "$SCRIPT_STORAGE_DIR" 2>/dev/null
			rm -rf /opt/var/lib/vnstat
			rm -f /opt/etc/vnstat.conf
		;;
	esac

	rm -f "/jffs/scripts/$SCRIPT_NAME"
	Clear_Lock
	Print_Output true "Uninstall completed" "$PASS"
}

##----------------------------------------##
## Modified by Martinski W. [2025-Apr-13] ##
##----------------------------------------##
NTP_Ready()
{
	if [ "$(nvram get ntp_ready)" -eq 1 ]
	then
		if [ $# -gt 0 ] && [ "$1" = "startup" ]
		then
			Print_Output true "NTP is synced." "$PASS"
			/opt/etc/init.d/S33vnstat start >/dev/null 2>&1
		fi
		return 0
	fi

	local theSleepDelay=15  ntpMaxWaitSecs=600  ntpWaitSecs

	if [ "$(nvram get ntp_ready)" -eq 0 ]
	then
		Check_Lock
		ntpWaitSecs=0
		Print_Output true "Waiting for NTP to sync..." "$WARN"

		while [ "$(nvram get ntp_ready)" -eq 0 ] && [ "$ntpWaitSecs" -lt "$ntpMaxWaitSecs" ]
		do
			if [ "$ntpWaitSecs" -gt 0 ] && [ "$((ntpWaitSecs % 30))" -eq 0 ]
			then
			    Print_Output true "Waiting for NTP to sync [$ntpWaitSecs secs]..." "$WARN"
			fi
			sleep "$theSleepDelay"
			ntpWaitSecs="$((ntpWaitSecs + theSleepDelay))"
		done

		if [ "$ntpWaitSecs" -ge "$ntpMaxWaitSecs" ]
		then
			Print_Output true "NTP failed to sync after 10 minutes. Please resolve!" "$CRIT"
			Clear_Lock
			exit 1
		else
			Print_Output true "NTP has synced [$ntpWaitSecs secs]. $SCRIPT_NAME will now continue." "$PASS"
			/opt/etc/init.d/S33vnstat start >/dev/null 2>&1
			Clear_Lock
		fi
	fi
}

### function based on @Adamm00's Skynet USB wait function ###
##----------------------------------------##
## Modified by Martinski W. [2025-Jul-27] ##
##----------------------------------------##
Entware_Ready()
{
	local theSleepDelay=5  maxSleepTimer=120  sleepTimerSecs

	if [ ! -f /opt/bin/opkg ]
	then
		Check_Lock
		sleepTimerSecs=0

		while [ ! -f /opt/bin/opkg ] && [ "$sleepTimerSecs" -lt "$maxSleepTimer" ]
		do
			if [ "$((sleepTimerSecs % 10))" -eq 0 ]
			then
			    Print_Output true "Entware NOT found. Wait for Entware to be ready [$sleepTimerSecs secs]..." "$WARN"
			fi
			sleep "$theSleepDelay"
			sleepTimerSecs="$((sleepTimerSecs + theSleepDelay))"
		done

		if [ ! -f /opt/bin/opkg ]
		then
			Print_Output true "Entware NOT found and is required for $SCRIPT_NAME to run, please resolve!" "$CRIT"
			Clear_Lock
			exit 1
		else
			Print_Output true "Entware found [$sleepTimerSecs secs]. $SCRIPT_NAME will now continue." "$PASS"
			Clear_Lock
		fi
	fi
}

##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
Show_About()
{
	printf "About ${MGNTct}${SCRIPT_VERS_INFO}${CLRct}\n"
	cat <<EOF
  $SCRIPT_NAME is an implementation of vnStat for AsusWRT-Merlin
  to enable measurement of internet data usage and store results
  in a local database, with hourly, daily, and monthly summaries.
  Daily notification with email summaries can also be configured.

License
  $SCRIPT_NAME is free to use under the GNU General Public License
  version 3 (GPL-3.0) https://opensource.org/licenses/GPL-3.0

Help & Support
  https://www.snbforums.com/forums/asuswrt-merlin-addons.60/?prefix_id=22

Source code
  https://github.com/AMTM-OSR/vnstat-on-merlin
EOF
	printf "\n"
}

### function based on @dave14305's FlexQoS show_help function ###
##----------------------------------------##
## Modified by Martinski W. [2025-Jun-16] ##
##----------------------------------------##
Show_Help()
{
	printf "HELP ${MGNTct}${SCRIPT_VERS_INFO}${CLRct}\n"
	cat <<EOF
Available commands:
  $SCRIPT_NAME about            explains functionality
  $SCRIPT_NAME update           checks for updates
  $SCRIPT_NAME forceupdate      updates to latest version (force update)
  $SCRIPT_NAME startup force    runs startup actions such as mount WebUI tab
  $SCRIPT_NAME install          installs script
  $SCRIPT_NAME uninstall        uninstalls script
  $SCRIPT_NAME generate         get latest data from vnstat. also runs outputcsv
  $SCRIPT_NAME summary          get daily summary data from vnstat. runs automatically at end of day. also runs outputcsv
  $SCRIPT_NAME outputcsv        create CSVs from database, used by WebUI and export
  $SCRIPT_NAME develop          switch to development branch version
  $SCRIPT_NAME stable           switch to stable/production branch version
EOF
	printf "\n"
}

##-------------------------------------##
## Added by Martinski W. [2025-Apr-27] ##
##-------------------------------------##
TMPDIR="$SHARE_TEMP_DIR"
SQLITE_TMPDIR="$TMPDIR"
export SQLITE_TMPDIR TMPDIR

if [ -d "$TMPDIR" ]
then sqlDBLogFilePath="${TMPDIR}/$sqlDBLogFileName"
else sqlDBLogFilePath="/tmp/var/tmp/$sqlDBLogFileName"
fi
_SQLCheckDBLogFileSize_

if [ -f "/opt/share/$SCRIPT_NAME.d/config" ]
then SCRIPT_STORAGE_DIR="/opt/share/$SCRIPT_NAME.d"
else SCRIPT_STORAGE_DIR="/jffs/addons/$SCRIPT_NAME.d"
fi

SCRIPT_CONF="$SCRIPT_STORAGE_DIR/config"
CSV_OUTPUT_DIR="$SCRIPT_STORAGE_DIR/csv"
IMAGE_OUTPUT_DIR="$SCRIPT_STORAGE_DIR/images"
VNSTAT_CONFIG="$SCRIPT_STORAGE_DIR/vnstat.conf"
VNSTAT_DBASE="$(_GetVNStatDatabaseFilePath_)"
VNSTAT_COMMAND="vnstat --config $VNSTAT_CONFIG"
VNSTATI_COMMAND="vnstati --config $VNSTAT_CONFIG"
VNSTAT_OUTPUT_FILE="$SCRIPT_STORAGE_DIR/vnstat.txt"
JFFS_LowFreeSpaceStatus="OK"
updateJFFS_SpaceInfo=false

if [ "$SCRIPT_BRANCH" = "main" ]
then SCRIPT_VERS_INFO="[$branchx_TAG]"
else SCRIPT_VERS_INFO="[$version_TAG, $branchx_TAG]"
fi

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-04] ##
##----------------------------------------##
if [ $# -eq 0 ] || [ -z "$1" ]
then
	NTP_Ready
	Entware_Ready

	if [ ! -d "$SCRIPT_DIR" ] || \
	   [ ! -d "$SCRIPT_STORAGE_DIR" ] ||
	   [ ! -f "$VNSTAT_CONFIG"  ]
	then
	    printf "\n${ERR}**ERROR**: $SCRIPT_NAME is NOT found installed.${CLRct}\n"
	    printf "\n${SETTING}To install $SCRIPT_NAME use this command:${CLRct}"
	    printf "\n${MGNTct}$0 install${CLRct}\n\n"
	    PressEnter
	    printf "\n${ERR}Exiting...${CLRct}\n\n"
	    Clear_Lock
	    exit 1
	fi

	Create_Dirs
	Conf_Exists
	ScriptStorageLocation load
	Create_Symlinks
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Auto_ServiceEvent create 2>/dev/null
	Shortcut_Script create
	_CheckFor_WebGUI_Page_
	Process_Upgrade
	ScriptHeader
	MainMenu
	exit 0
fi

##----------------------------------------##
## Modified by Martinski W. [2025-Aug-03] ##
##----------------------------------------##
case "$1" in
	install)
		Check_Lock
		Menu_Install
		exit 0
	;;
	startup)
		Menu_Startup "$2"
		exit 0
	;;
	generate)
		NTP_Ready
		Entware_Ready
		VNStat_ServiceCheck false
		Check_Lock
		Generate_Images silent
		Generate_Stats silent
		Check_Bandwidth_Usage silent
		Generate_CSVs
		Clear_Lock
		exit 0
	;;
	summary)
		NTP_Ready
		Entware_Ready
		Reset_Allowance_Warnings
		Generate_Images silent
		Generate_Stats silent
		Check_Bandwidth_Usage silent
		if [ "$(DailyEmail check)" != "none" ]; then
			Generate_Email daily
		fi
		exit 0
	;;
	outputcsv)
		NTP_Ready
		Entware_Ready
		Generate_CSVs
		exit 0
	;;
	service_event)
		updateJFFS_SpaceInfo=true
		if [ "$2" = "start" ] && [ "$3" = "$SCRIPT_NAME" ]
		then
			rm -f /tmp/detect_vnstat.js
			VNStat_ServiceCheck
			Check_Lock webui
			sleep 3
			echo 'var vnstatstatus = "InProgress";' > /tmp/detect_vnstat.js
			Generate_Images silent
			Generate_Stats silent
			Check_Bandwidth_Usage silent
			Generate_CSVs
			echo 'var vnstatstatus = "Done";' > /tmp/detect_vnstat.js
			updateJFFS_SpaceInfo=false
			Clear_Lock
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}config" ]
		then
			Check_Lock webui
			echo 'var savestatus = "InProgress";' > "$SCRIPT_WEB_DIR/detect_save.js"
			sleep 1
			Conf_FromSettings
			echo 'var savestatus = "Success";' > "$SCRIPT_WEB_DIR/detect_save.js"
			Clear_Lock
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}checkupdate" ]
		then
			Update_Check
		elif [ "$2" = "start" ] && [ "$3" = "${SCRIPT_NAME}doupdate" ]
		then
			Update_Version force unattended
		fi
		"$updateJFFS_SpaceInfo" && _UpdateJFFS_FreeSpaceInfo_
		exit 0
	;;
	update)
		Update_Version
		exit 0
	;;
	forceupdate)
		Update_Version force
		exit 0
	;;
	postupdate)
		Create_Dirs
		Conf_Exists
		ScriptStorageLocation load true
		Create_Symlinks
		Auto_Startup create 2>/dev/null
		Auto_Cron create 2>/dev/null
		Auto_ServiceEvent create 2>/dev/null
		Shortcut_Script create
		Process_Upgrade
		Generate_Images silent
		Generate_Stats silent
		Check_Bandwidth_Usage silent
		Generate_CSVs
		Clear_Lock
		exit 0
	;;
	uninstall)
		Menu_Uninstall
		exit 0
	;;
	about)
		ScriptHeader
		Show_About
		exit 0
	;;
	help)
		ScriptHeader
		Show_Help
		exit 0
	;;
	develop)
		SCRIPT_BRANCH="develop"
		SCRIPT_REPO="https://raw.githubusercontent.com/AMTM-OSR/vnstat-on-merlin/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	stable)
		SCRIPT_BRANCH="main"
		SCRIPT_REPO="https://raw.githubusercontent.com/AMTM-OSR/vnstat-on-merlin/$SCRIPT_BRANCH"
		Update_Version force
		exit 0
	;;
	*)
		ScriptHeader
		Print_Output false "Parameter [$*] is NOT recognised." "$ERR"
		Print_Output false "For a list of available commands run: $SCRIPT_NAME help" "$SETTING"
		exit 1
	;;
esac
