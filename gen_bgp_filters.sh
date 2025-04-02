#!/bin/sh
if which bgpq4  >/dev/null
then 
	echo "! BGPQ4 found" >/dev/null
else
	echo "!BGPQ4 not found please install it"
	exit 1
fi

if which ipcalc >/dev/null
then
	echo "! ipcalc found" >/dev/null
else
	echo "!ipcalc not found please install it"
	exit 1
fi

RC=1 #Exit status by default
ZEROOUTPUT=0 #no Zero output by default 
ZEROWORK=0 # by deafult will be 0
NO4BYTE="0" #Do not add AS23456 by default
DEBUG=0 #Debug is off by default
LEGEND="!Use:
!	-n for 4Byte AS support (Adding AS23456 to the as-path list)
!	-d Print debug output
!	-R for allow more specific routes up to masklen
!	-i for interactive input OR: 
!		-A - peer or client AS-SET or AS
!		-S - peer AUTONOMUS SYSTEM number
!		-F - as-path list number 
!		-P - prefix list name
!		-U - URPF standard acl number
!		-G - Extended in ACL name on interface
!		-L - Link network x.x.x.x/y
!	Example: gen_bgp_filters.sh -n -R 24 -A AS-DSIJSC -S 8345 -F 11 -P prefix-dsi-in -U 1800 -G acl-dsi-in -L 10.10.10.10/30"

ipnetcalc () {
	if ipcalc $LNETIN | grep -q 'INVALID' >/dev/null
		then
			echo "!ERROR INVALID INPUT:"
			echo "!"`ipcalc $LNETIN| grep 'INVALID'`
			echo "!PLEASE INPUT AGAIN"
		else
			if [ $DEBUG != 0 ];then
			echo "!Link network from input: $LNETIN"
			fi
			LNET=`ipcalc $LNETIN | grep Network | awk -F "   " '{print $2}' | awk -F "/" '{print $1}'`
			RC="$?"
			decho "!Link network zero address calculated: $LNET"
			if [ "$RC" != "0" ]; then
				echo "Ipcalc error! Exit!"
				exit 1
			fi
			LWSUBNET=`ipcalc $LNETIN | grep Wildcard |awk -F "  " '{print $2}'`
			RC="$?"
			decho "!Link networ mask calculated: $LWSUBNET"
			if [ "$RC" != "0" ]; then
				echo "Ipcalc error! Exit!"
				exit 1
			fi
	fi
}

decho () {
if [ $DEBUG != 0 ];then
	echo $1
fi
}

cisco_as_path () {

	if [ -n "$ASPATH" ]; then
		case $NO4BYTE in
			"0" )	
				ASPATHPR=`bgpq4 -f $AS -l $ASPATH -3 $ASSET `
				RC="$?"
				if [ "$RC" != "0" ]; then
					decho "!Recive error from bgpq4"
					exit 1
				fi
				if echo "$ASPATHPR" | grep -q 'permit' >/dev/null; then
					echo "$ASPATHPR"
					ZEROWORK=1
				else 
					ZEROOUTPUT=1
					decho "!Empty result found, exit status will be 1"
					decho "!$ASPATHPR"
				fi
				echo "!";;
			"1" )
				ASPATHPR=`bgpq4 -f $AS -l $ASPATH $ASSET`
				RC="$?"
				if [ "$RC" != "0" ]; then
					decho "!Recive error from bgpq4"
					exit 1
				fi
				if echo "$ASPATHPR" | grep -q 'permit' >/dev/null; then
					echo "$ASPATHPR"
					ZEROWORK=1
				else
					ZEROOUTPUT=1
					decho "!Empty result found, exit status will be 1"
					decho "!$ASPATHPR"
				fi
				echo "!"
		esac
	else
		decho "!"
		decho "! Name of as-path list not defined, can not create it"
		decho "!"
	fi
}

cisco_ip_prefix () {
	
	if [ -n  "$ALLMASK" ]; then
		PREFIXPR=`bgpq4 -A -l $PREFIX -R $ALLMASK $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			decho "!Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -q 'permit' >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			decho "!Empty result found, exit status will be 1"
			decho "!$PREFIXPR"
		fi
		echo "!" 
	else
		PREFIXPR=`bgpq4 -A -l $PREFIX $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			decho "!Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -q 'permit' >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			decho "!Empty result found, exit status will be 1"
			decho "!$PREFIXPR"
		fi
		echo "!"
	fi
}

cisco_in_acl () {

    ACCESSLISTPR=`bgpq4 -F " permit ip %n %i any\n" -A -R 24 -l $ACL $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		decho "!Recive error from bgpq4"
                exit 1
        fi
	if echo "$ACCESSLISTPR" | grep -q 'permit' >/dev/null; then
		echo "no ip access-list extended $ACL"
		echo "ip access-list extended $ACL"
		echo "$ACCESSLISTPR"
		echo " permit ip $LNET $LWSUBNET any"
		echo "exit"
		echo "!"

		ZEROWORK=1
	else
		ZEROOUTPUT=1
		decho "!Empty result found, exit status will be 1"
		decho "no ip access-list extended $ACL"
                decho "ip access-list extended $ACL"
		decho "!$ACCESSLISTPR"
		decho " permit ip $LNET $LWSUBNET any"
		decho "!exit"
		decho "!"
	fi
}

cisco_urpf_acl () {

	URPFLIST=`bgpq4 -F " permit %n %i\n" -A -R 24 -l $URPF $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		decho "!Recive error from bgpq"
		exit 1
	fi
	if echo "$URPFLIST" | grep -q 'permit' >/dev/null; then
		echo "no access-list $URPF"
		echo "access-list $URPF remark * URPF loose for $ASSET *"
		echo "$URPFLIST"
		echo "exit"
		echo "!"
		ZEROWORK=1
	else
		ZEROOUTPUT=1
		decho "!Empty result found, exit status will be 1"
		decho "no access-list $URPF"
                decho "access-list $URPF remark * URPF loose for $ASSET *"
                decho "$URPFLIST"
                decho "exit"
                decho "!"
	fi
}

while getopts ":indR:A:S:F:P:U:G:L:" optname
do
	case $optname in
	"i" ) 	echo "!AS-SET or AS:"
		read ASSET
		echo "!AUTONOMUS SYSTEM:"
		read AS
		echo "!as-path list:"
		read ASPATH
		echo "!Prefixlist:"
		read PREFIX
		echo "!Access list for URPF"
		read URPF
		echo "!Name of Input access list for interface(extended):"
		read ACL
		echo "!Link network(x.x.x.x/y):"
		while [ -z "$LNET" ]
		do
		read LNETIN
		ipnetcalc
		done;;
	"d" )	DEBUG=1;;
	"n" )	NO4BYTE="1";;
	"R" )	ALLMASK="$OPTARG";;
	"A" )	ASSET=$OPTARG;;
	"S" )	AS=$OPTARG;;
	"F" )	ASPATH=$OPTARG;;
	"P" )	PREFIX=$OPTARG;;
	"U" )	URPF=$OPTARG;;
	"G" )	ACL=$OPTARG;;
	"L" )	LNETIN=$OPTARG
		ipnetcalc
		if echo $LNETIN | grep -q '\/' > /dev/null ; then
		echo "!"	
		else
		echo "!ERROR / - not found in link network"
			exit 1
		fi
		if [ -z "$LNET" ];then
			echo "!ERROR Incorrect link network"
			exit 1
		fi;;
	":" )	echo "$LEGEND"
		exit 1;;
	"?" )	echo "$LEGEND"
		exit 1;;
	* )	echo "$LEGEND" 
		exit 1;;
	esac
done

if [ -z "$ASSET" ]; then 
	echo '
!ERROR: Please define AS-SET or AS
'
	echo "$LEGEND"
	exit 1
fi

if [ $DEBUG != 0 ];then
	echo '!
!conf t'
else
	echo '!
conf t'
fi

if [ -n "$AS" ]; then
	cisco_as_path
else
	decho "!"
	decho "! AUTONOMUS SYSTEM not defined, can not create as-path list"
	decho "!"
fi

if [ -n "$PREFIX" ]; then
	cisco_ip_prefix
else 
	decho "!"
	decho "! Prefix list name not defined, can not create prefix-list"
	decho "!"
fi

if [ -n "$ACL" ]; then
	
	if [ -n "$LNETIN" ]; then
		cisco_in_acl
	else 
		decho "!"
		decho "! Link network not defined, can not create access-list"
		decho "!"	
	fi
else
	decho "!"
	decho "! Access list name not defined, can not create access-list"
	decho "!"
fi

if [ -n "$URPF" ]; then
	cisco_urpf_acl
else
	decho "!"
	decho "! URPF list name not defined, can not create access-list for URPF"
	decho "!"
fi

if [ $DEBUG != 0 ];then
        echo '!
!end
!'
else
        echo '!
end
!'
fi

if [ $ZEROOUTPUT != 0 ];then
	exit 1
fi

if [ $ZEROWORK = 0 ];then
	decho "!No one list caculated. Will be exit status 1"
	exit 1
fi

exit 0
