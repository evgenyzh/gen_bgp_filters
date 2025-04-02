#!/bin/sh
#Chack for bgpq4 and ipcalc
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
DEBUG=0 #Debug is off by default
LEGEND="Usage:
	-d Print debug output
	-R for allow more specific routes up to masklen
	-i for interactive input OR:
		-V C|J|H - Vendor specific: C- Cisco (default), J - Juniper, H - Huawei		
		-A ASNAME - peer or client AS-SET or AS
		-S number - peer AUTONOMUS SYSTEM number
		-F name - as-path list number|name 
		-P name - prefix list name
		-U name - URPF standard acl number|name
		-G name - Extended in ACL number|name on interface
		-L network - Link network x.x.x.x/y

	Example: gen_bgp_filters.sh -R 24 -V C -A AS-DSIJSC -S 8345 -F 11 -P prefix-dsi-in -U 1800 -G acl-dsi-in -L 10.10.10.10/30"


get_options () {
	while getopts ":idR:V:A:S:F:P:U:G:L:" optname
	do
		case $optname in
		"i" ) 	echo "Vendor C|H|J:"
			read CLIVENDOR
			echo "AS-SET or AS:"
			read ASSET
			echo "AUTONOMUS SYSTEM:"
			read AS
			echo "as-path list:"
			read ASPATH
			echo "Prefixlist:"
			read PREFIX
			echo "Access list for URPF"
			read URPF
			echo "Name of Input access list for interface(extended):"
			read ACL
			echo "Link network(x.x.x.x/y):"
			while [ -z "$LNET" ]
			do
			read LNETIN
			ipnetcalc
			done;;
		"d" )	DEBUG=1;;
		"R" )	ALLMASK="$OPTARG";;
		"V" )	CLIVENDOR="$OPTARG";;
		"A" )	ASSET=$OPTARG;;
		"S" )	AS=$OPTARG;;
		"F" )	ASPATH=$OPTARG;;
		"P" )	PREFIX=$OPTARG;;
		"U" )	URPF=$OPTARG;;
		"G" )	ACL=$OPTARG;;
		"L" )	LNETIN=$OPTARG
			ipnetcalc
			if echo $LNETIN | grep -q '\/' > /dev/null ; then
			vecho ""	
			else
			vecho "ERROR / - not found in link network"
				exit 1
			fi
			if [ -z "$LNET" ];then
				vecho "ERROR Incorrect link network"
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
		vecho "ERROR: Please define AS-SET or AS"
		echo "$LEGEND"
		exit 1
	fi
}

ipnetcalc () {
#Perrform prefix check for correct lenth
	if ipcalc $LNETIN | grep -q 'INVALID' >/dev/null
		then
			vecho "ERROR INVALID INPUT:"
			vecho " "`ipcalc $LNETIN| grep 'INVALID'`
			vecho "PLEASE INPUT AGAIN"
		else
			if [ $DEBUG != 0 ];then
			vecho "Link network from input: $LNETIN"
			fi
			LNET=`ipcalc $LNETIN | grep Network | awk -F "   " '{print $2}' | awk -F "/" '{print $1}'`
			RC="$?"
			decho "Link network zero address calculated: $LNET"
			if [ "$RC" != "0" ]; then
				vecho "ipcalc error! Exit!"
				exit 1
			fi
			LWSUBNET=`ipcalc $LNETIN | grep Wildcard |awk -F "  " '{print $2}'`
			RC="$?"
			decho "Link networ mask calculated: $LWSUBNET"
			if [ "$RC" != "0" ]; then
				echo "Ipcalc error! Exit!"
				exit 1
			fi
	fi
}

vecho () {
#Add vendor specific comment at the begining of the output
	if [ -n "$CLIVENDOR" ];then
        	if [ "$CLIVENDOR" = "C" ];then
                	echo "!$1"
        	elif [ "$CLIVENDOR" = "J" ];then
                	echo "#$1"
        	elif [ "$CLIVENDOR" = "H" ];then
                	echo "#$1"
		fi

	else
        	echo "!$1"
	fi

}

decho () {
#Print debug output if enable
if [ $DEBUG != 0 ];then
	vecho "$1"
fi
}

################  Cisco specific ####################

cisco_as_path () {
#Cisco as-path
	if [ -n "$ASPATH" ]; then
		ASPATHPR=`bgpq4 -f $AS -l $ASPATH -W 5 $ASSET `
		RC="$?"
		if [ "$RC" != "0" ]; then
			decho "Recive error from bgpq4"
			exit 1
		fi
		if echo "$ASPATHPR" | grep -q 'permit' >/dev/null; then
			echo "$ASPATHPR"
			ZEROWORK=1
		else 
			ZEROOUTPUT=1
			decho "Empty result found, exit status will be 1"
			decho "$ASPATHPR"
		fi
		echo "!"
	else
		decho ""
		decho " Name of as-path list not defined, can not create it"
		decho ""
	fi
}

cisco_ip_prefix () {
#Cisco ip prefix list 
	if [ -n  "$ALLMASK" ]; then
		PREFIXPR=`bgpq4 -A -l $PREFIX -R $ALLMASK $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			decho "Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -q 'permit' >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			decho "Empty result found, exit status will be 1"
			decho "$PREFIXPR"
		fi
		echo "!" 
	else
		PREFIXPR=`bgpq4 -A -l $PREFIX $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			decho "Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -q 'permit' >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			decho "Empty result found, exit status will be 1"
			decho "$PREFIXPR"
		fi
		echo "!"
	fi
}

cisco_in_acl () {
#Cisco extended acl
    ACCESSLISTPR=`bgpq4 -F " permit ip %n %i any\n" -A -R 24 -l $ACL $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		decho "Recive error from bgpq4"
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
		decho "Empty result found, exit status will be 1"
		decho "no ip access-list extended $ACL"
                decho "ip access-list extended $ACL"
		decho "$ACCESSLISTPR"
		decho " permit ip $LNET $LWSUBNET any"
		decho "exit"
		decho ""
	fi
}

cisco_urpf_acl () {
#Cisco acl for urpf loose
	URPFLIST=`bgpq4 -F " permit %n %i\n" -A -R 24 -l $URPF $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		decho "Recive error from bgpq"
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
		decho "Empty result found, exit status will be 1"
		decho "no access-list $URPF"
                decho "access-list $URPF remark * URPF loose for $ASSET *"
                decho "$URPFLIST"
                decho "exit"
                decho ""
	fi
}


cisco () {
#Cisco specific output
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
	decho ""
	decho " AUTONOMUS SYSTEM not defined, can not create as-path list"
	decho ""
fi

if [ -n "$PREFIX" ]; then
	cisco_ip_prefix
else 
	decho ""
	decho " Prefix list name not defined, can not create prefix-list"
	decho ""
fi

if [ -n "$ACL" ]; then
	
	if [ -n "$LNETIN" ]; then
		cisco_in_acl
	else 
		decho ""
		decho " Link network not defined, can not create access-list"
		decho ""	
	fi
else
	decho ""
	decho " Access list name not defined, can not create access-list"
	decho ""
fi

if [ -n "$URPF" ]; then
	cisco_urpf_acl
else
	decho ""
	decho " URPF list name not defined, can not create access-list for URPF"
	decho ""
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

}

################### Juniper JunOS ####################

juniper_as_path () {
#Juniper as-path-group
	if [ -n "$ASPATH" ]; then
		ASPATHPR=`bgpq4 -J -f $AS -l $ASPATH -W 5 $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			decho "Recive error from bgpq4"
			exit 1
		fi
		if echo "$ASPATHPR" | grep -q 'as-path' >/dev/null; then
			echo "$ASPATHPR"
			ZEROWORK=1
		else 
			ZEROOUTPUT=1
			decho "Empty result found, exit status will be 1"
			decho "$ASPATHPR"
		fi
		echo "#"
	else
		decho "#"
		decho "# Name of as-path list not defined, can not create it"
		decho "#"
	fi
}

juniper_route_filter () {
#Juniper route-filter-list 
	if [ -n  "$ALLMASK" ]; then
		PREFIXPR=`bgpq4 -J -z -A -l $PREFIX -R $ALLMASK $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			decho "Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -qE "upto|exact|prefix-length-range" >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			decho "Empty result found, exit status will be 1"
			decho "$PREFIXPR"
		fi
		echo "#" 
	else
		PREFIXPR=`bgpq4 -J -z -A -l $PREFIX $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			decho "Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -qE "upto|exact|prefix-length-range" >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			decho "Empty result found, exit status will be 1"
			decho "$PREFIXPR"
		fi
		echo "#"
	fi
}

juniper_filter () {
#Juniper firewall inbound filter 
	FWFILTER=`bgpq4 -F "                    	%n\/%l;\n" -A -R 24 $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		decho "Recive error from bgpq4"
                exit 1
        fi
	if echo "$FWFILTER" | grep -q '[0-9]' >/dev/null; then
		echo 'firewall {
    family inet {'
		echo "        filter $ACL {"
		echo '            term TRUSTED-SOURCE {
                from {
                    source-address {'
		echo "$FWFILTER"
		echo "                        $LNETIN;"
		echo '                    }
                }
                then {
                    accept;
                }
            term DEFAULT {
                then discard;
            }
        }
    }
}'
		echo "#"

		ZEROWORK=1
	else
		ZEROOUTPUT=1
		decho 'firewall {
#    family inet {'
		decho "        filter $ACL {"
		decho '            term TRUSTED-SOURCE {
#                from {
#                    source-address {'
		decho "$FWFILTER"
		decho "                        $LNETIN;"
		decho '                    }
#                }
#                then {
#                    accept;
#                }
#            term DEFAULT {
#                then discard;
#            }
#        }
#    }
#}'
		decho ""
	fi
}


juniper_urpf_filter () {
#Cisco acl for urpf loose
	URPFLIST=`bgpq4 -F "                    	%n\/%l;\n" -A -R 24 $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		decho "Recive error from bgpq"
		exit 1
	fi
	if echo "$URPFLIST" | grep -q '[0-9]' >/dev/null; then
		echo 'firewall {
    family inet {'
		echo "        filter $URPF {"
		echo "        /* URPF loose for $ASSET */"
		echo '            term TRUSTED-SOURCE-URPF {
                from {
                    source-address {'
		echo "$URPFLIST"
		echo '                    }
                }
                then {
                    accept;
                }
            term DEFAULT {
                then discard;
            }
        }
    }
}'
		echo "#"
		ZEROWORK=1
	else
		ZEROOUTPUT=1
		decho 'firewall {
#    family inet {'
		decho "        filter $URPF {"
		decho "        /* URPF loose for $ASSET */"
		decho '            term TRUSTED-SOURCE-URPF {
#                from {
#                    source-address {'
		decho "$URPFLIST"
		decho '                    }
#                }
#                then {
#                    accept;
#                }
#            term DEFAULT {
#                then discard;
#            }
#        }
#    }
#}'
		decho ""
	fi
}


juniper () {
#Junos specific output
if [ $DEBUG != 0 ];then
	echo '#
	#configure
#load merge terminal'
else
	echo '#
configure
load merge terminal <<EOF'
fi

if [ -n "$AS" ]; then
	juniper_as_path
else
	decho ""
	decho " AUTONOMUS SYSTEM not defined, can not create as-path-group "
	decho ""
fi

if [ -n "$PREFIX" ]; then
	juniper_route_filter
else 
	decho ""
	decho " Prefix list name not defined, can not create route-filter-list"
	decho ""
fi

if [ -n "$ACL" ]; then
	
	if [ -n "$LNETIN" ]; then
		juniper_filter
	else 
		decho ""
		decho " Link network not defined, can not create inbound filter"
		decho ""	
	fi
else
	decho ""
	decho " Access list name not defined, can not create inbound filter"
	decho ""
fi

if [ -n "$URPF" ]; then
	juniper_urpf_filter
else
	decho ""
	decho " URPF list name not defined, can not create access-list for URPF filter"
	decho ""
fi

if [ $DEBUG != 0 ];then
        echo '#
#
#'
else
        echo 'EOF
#
#'
fi

}

get_options $*

if [ -n "$CLIVENDOR" ];then
	if [ "$CLIVENDOR" = "C" ];then
		echo "!Cisco IOS config:"
		cisco
	elif [ "$CLIVENDOR" = "J" ];then
		echo "#JunOS config:"
		juniper
	elif [ "$CLIVENDOR" = "H" ];then
		echo "#Huawei VRP config:"
	fi
else
	cisco
fi

if [ $ZEROOUTPUT != 0 ];then
	exit 1
fi

if [ $ZEROWORK = 0 ];then
	decho "No one list caculated. Will be exit status 1"
	exit 1
fi

exit 0
