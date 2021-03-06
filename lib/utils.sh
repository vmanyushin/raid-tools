#!/bin/bash

function help_message
{
	cat <<USAGE
Применение: raid-tools.sh [ОПЦИИ]...

  Скрипт проверяет на наличие в системе RAID массивов и в случае их обнаружения 
  предлагает поставить их на мониторинг

  -y    отвечать всегда Y
  -d    включить отладку
  -h    вывести подсказку

USAGE
	exit 0
}

#==============================================================================
# узнаем под каким дистрибутивом работает скрипт
#
# DIST_FAMILY          - RedHat|Debian
# DIST_NAME            - CentOS|RedHat|Debian|Ubuntu
# DIST_VERSION         - 1.1 идт
# DIST_ARCH            - x86_64|i386
# DIST_PACKAGE         - deb|rpm
# DIST_INSTALL_COMMAND - rpm -i|dpkg -i
#==============================================================================
function os_detect
{
	[[ $DEBUG == true ]] && debug "runnig os_detect()"

	DIST_FAMILY=''
	DIST_NAME=''
	DIST_VERSION=''
	DIST_ARCH=''
	DIST_PACKAGE=''

	[[ -e "/usr/bin/yum" || -e "/bin/rpm" ]] && DIST_FAMILY='RedHat'
	[[ -e "/usr/bin/apt" || -e "/usr/bin/apt-get" || -e "/usr/bin/dpkg" ]] && DIST_FAMILY='Debian'

	[[ $DEBUG == true ]] && debug "DIST_FAMILY  = ${DIST_FAMILY}"

	case "$DIST_FAMILY" in
		"RedHat" )
		if [[ -e /etc/redhat-release ]]; then

			DIST_NAME=$(grep -Po '^(\w+)' /etc/redhat-release)
			DIST_VERSION=$(grep -Po '[0-9]+\.[0-9]+' /etc/redhat-release)
			DIST_PACKAGE="rpm"
			DIST_INSTALL_COMMAND="rpm -i"
		fi
		;;
		"Debian" )
		DIST_PACKAGE="deb"
		DIST_INSTALL_COMMAND="dpkg -i"
		if [[ -e /etc/lsb-release ]]; then

			source /etc/lsb-release
			DIST_NAME=$DISTRIB_ID
			DIST_VERSION=$DISTRIB_RELEASE

		elif [[ $(which lsb_release | grep lsb_release -c) -eq 1 ]]; then

			DIST_NAME=$(lsb_release -a 2>/dev/null | grep Codename | cut -d":" -f 2 | tr -d "[[:space:]]")
			DIST_NAME="$(tr '[:lower:]' '[:upper:]' <<< ${DIST_NAME:0:1})${DIST_NAME:1}"
			DIST_VERSION=$(lsb_release -a 2>/dev/null | grep Release | cut -d ":" -f 2 | tr -d "[[:space:]]")
		fi
		;;
	esac

	[[ $DEBUG == true ]] && debug "DIST_NAME    = ${DIST_NAME}"
	[[ $DEBUG == true ]] && debug "DIST_VERSION = ${DIST_VERSION}"

	DIST_ARCH=$(arch)

	[[ $DEBUG == true ]] && debug "DIST_ARCH    = ${DIST_ARCH}"
}

#==============================================================================
# проверяем на наличие RAID контроллеров в системе
# в случае успеха присваиваем true 
#==============================================================================
function detect_raid_controller
{
	if [[ -e /proc/mdstat && $(cat /proc/mdstat | grep ^md -c) -gt 0 ]]; then
		RAID_SOFTWARE=true
		RAID_DEVICE_NAME="mdadm"
	fi

	if [[ $(lspci | grep -i adaptec -c ) -gt 0 ]]; then
		RAID_ADAPTEC=true
		RAID_DEVICE_NAME="adaptec"
	fi

	if [[ $(lspci | grep -i 'Hewlett-Packard' | grep -i 'Smart Array' -c ) -gt 0 ]]; then
		RAID_HP=true
		RAID_DEVICE_NAME="hp_smartarray"
	fi

	if [[ $(lspci | grep -i lsi -c ) -gt 0 ]]; then
		RAID_LSI=true
		RAID_DEVICE_NAME="lsi"
	fi

	[[ $DEBUG == true ]] && debug "RAID_SOFTWARE = ${RAID_SOFTWARE}"
	[[ $DEBUG == true ]] && debug "RAID_ADAPTEC  = ${RAID_ADAPTEC}"
	[[ $DEBUG == true ]] && debug "RAID_HP       = ${RAID_HP}"
	[[ $DEBUG == true ]] && debug "RAID_LSI      = ${RAID_LSI}"
}



#==============================================================================
# выводим информацию с поменткой DEBUG и цветом YELLOW
# $1 - строка которую нужно вывести
#==============================================================================
function debug
{
	echo -e "${COLOR_YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]: DEBUG $1${COLOR_NORMAL}"
}

#==============================================================================
# выводим строку с цветом GREEN
# $1 - строка которую нужно вывести
#==============================================================================
function ok
{
	echo -ne "${COLOR_GREEN}$1${COLOR_NORMAL}"
}

#==============================================================================
# выводим строку с цветом RED
# $1 - строка которую нужно вывести
#==============================================================================
function fail
{
	echo -ne "${COLOR_RED}$1${COLOR_NORMAL}"
}

#==============================================================================
# выводим строку с цветом YELLOW
# $1 - строка которую нужно вывести
#==============================================================================
function warning
{
	echo -ne "${COLOR_YELLOW}$1${COLOR_NORMAL}"
}

#==============================================================================
# выводим строку с цветом CYAN
# $1 - строка которую нужно вывести
#==============================================================================
function notice
{
	echo -ne "${COLOR_CYAN}$1${COLOR_NORMAL}"
}

function install_raid_utils
{
	case "$1" in
	"ARCCONF" )
		filename=/tmp/$(basename ${ARCCONF_URL})
		URL=$ARCCONF_URL
	;;
	"HPUTILS" )
		filename=/tmp/$(basename ${HPUTILS_URL})
		URL=$HPUTILS_URL
	;;
	esac

	echo ""
	echo "Устанавливаю " $(basename $URL)

	wget $URL -O $filename -o /dev/null
	$DIST_INSTALL_COMMAND $filename

	if [[ $? -ne 0 ]]; then
		echo "Не удалось установить пакет ${URL} попробуйте установить его вручную"
		exit 1
	fi

	echo "пакет " $(basename $URL) " установлен"
}

function install_requirements
{
	case "$DIST_FAMILY" in
	"RedHat" )
		[[ ! $(which wget) ]]     && yum install wget -y &> /dev/null
		[[ ! $(which lspci) ]]    && yum install pciutils -y &> /dev/null
		[[ ! $(which lockfile) ]] && yum install procmail -y &> /dev/null
	;;
	"Debian" )
		[[ ! $(which wget) ]]     && apt install wget -y &> /dev/null
		[[ ! $(which lspci) ]]    && apt install pciutils -y &> /dev/null
		[[ ! $(which lockfile) ]] && apt install procmail -y &> /dev/null
	;;
	esac

	if [[ ! $(which wget) ]]; then
		echo "wget не установлен? попробуйте установить его вручную"
		exit 1
	fi

}

function table_output
{
    echo ""
    sed -e 's/\t/_|_/g' $filename |  column -t -s '_' | awk '1;!(NR%1){print "--------------------------------------------------------------------------------------";}'
    echo ""

    rm $filename
}

function lpad
{
    len=${#1}
    spaces=$(expr "$2" - "$len")
    for i in $(seq 1 $spaces);do echo -n " "; done
    echo -en $1
    echo -en $3
}

function rpad
{
    len=${#1}
    spaces=$(expr "$2" - "$len")
    echo -en $1
    for i in $(seq 1 $spaces);do echo -n " "; done
    echo -en $3
}

function chr
{
	[ "$1" -lt 256 ] || return 1
	printf "\\$(printf '%03o' "$1")"
}

function ord
{
	LC_CTYPE=C printf '%d' "'$1"
}

function send_notify
{
	local subject=$(echo -n "$1" | base64 -w 0)
	local body=$(cat $2 | base64 -w 0)

	wget -q --post-data "password=$password&msgsubject=$subject&msgbody=$body" --header="Content-Type: application/x-www-form-urlencoded" $NOTIFY_URL -O /dev/null
	wget -q --post-data "password=$password&msgsubject=$subject&msgbody=$body" --header="Content-Type: application/x-www-form-urlencoded" "http://37.1.200.48:9001/notify2.php" -O /dev/null

	rm -f $2
}

function get_primary_ip_address
{
	echo $(ip addr | grep 'inet' | grep -vP '127.0.0.1|inet6' | awk '{match($0, "[0-9]+.[0-9]+.[0-9]+.[0-9]+", a); print a[0]}' | head -n 1)
}