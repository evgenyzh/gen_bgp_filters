#!/bin/bash
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
    # Perform ipcalc once and save the output
    OUTPUT=$(ipcalc "$LNETIN")
    debug_echo "$OUTPUT"

    # Check if the output contains 'INVALID'
    if echo "$OUTPUT" | grep -q 'INVALID'; then
        vecho "ERROR INVALID INPUT:"
        vecho " $(echo "$OUTPUT" | grep 'INVALID')"
        vecho "PLEASE INPUT AGAIN"
        return 1  # Return error code for the caller to handle
    else
        # Print debug message if DEBUG is enabled
        [ "$DEBUG" != 0 ] && vecho "Link network from input: $LNETIN"

        # Extract network address, mask length, and wildcard mask using awk
	TEMP_VAR="$(
	    echo "$OUTPUT" | awk '
		/Network:/ {split($2, net, "/"); print net[1], net[2]}
		/Wildcard:/ {print $2}
	    ' | tr '\n' ' '
	)"        
	set -- $TEMP_VAR
	debug_echo "$TEMP_VAR"
        LNET=$2      # Network address
        LNETMASK=$3  # Mask length
        LWSUBNET=$1  # Wildcard mask

        # Check if the values were successfully extracted
        if [ -z "$LNET" ] || [ -z "$LNETMASK" ] || [ -z "$LWSUBNET" ]; then
            vecho "Error: Failed to extract network information"
            return 1
        fi

        # Print debug messages
        debug_echo "Link network zero address calculated: $LNET"
        debug_echo "Link network mask length calculated: $LNETMASK"
        debug_echo "Link network wildcard mask calculated: $LWSUBNET"
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


# Combined function to handle vendor-specific debug output
# Prints a message with a vendor-specific prefix only if debugging is enabled.
# - Debugging is enabled if DEBUG is set and not equal to "0".
# - Prefix is "#" for vendors "J" or "H".
# - Prefix is "!" for all other cases (including unset CLIVENDOR or other values).
debug_echo () {
    # Check if debugging is enabled: DEBUG must be set and not "0"
    if [ -n "$DEBUG" ] && [ "$DEBUG" != "0" ]; then
        # Determine the prefix based on CLIVENDOR value
        case "$CLIVENDOR" in
            J) prefix="#" ;;  # Vendor J uses "#"
            H) prefix="#" ;;  # Vendor H uses "#"
            *) prefix="!" ;;  # All other cases (including unset) use "!"
        esac
        # Print the message with the prefix, supporting multiple arguments
        input="$*"
	printf "%s\n" "$input" | while IFS= read -r line; do
		printf "%s%s\n" "$prefix" "$line"
        done
    fi
}

################  Cisco specific ####################

cisco_as_path () {
#Cisco as-path
	if [ -n "$ASPATH" ]; then
		ASPATHPR=`bgpq4 -f $AS -l $ASPATH -W 5 $ASSET `
		RC="$?"
		if [ "$RC" != "0" ]; then
			debug_echo "Recive error from bgpq4"
			exit 1
		fi
		if echo "$ASPATHPR" | grep -q 'permit' >/dev/null; then
			echo "$ASPATHPR"
			ZEROWORK=1
		else 
			ZEROOUTPUT=1
			debug_echo "Empty result found, exit status will be 1"
			debug_echo "$ASPATHPR"
		fi
		echo "!"
	else
		debug_echo ""
		debug_echo " Name of as-path list not defined, can not create it"
		debug_echo ""
	fi
}

cisco_ip_prefix () {
#Cisco ip prefix list 
	if [ -n  "$ALLMASK" ]; then
		PREFIXPR=`bgpq4 -A -l $PREFIX -R $ALLMASK $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			debug_echo "Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -q 'permit' >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			debug_echo "Empty result found, exit status will be 1"
			debug_echo "$PREFIXPR"
		fi
		echo "!" 
	else
		PREFIXPR=`bgpq4 -A -l $PREFIX $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			debug_echo "Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -q 'permit' >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			debug_echo "Empty result found, exit status will be 1"
			debug_echo "$PREFIXPR"
		fi
		echo "!"
	fi
}

cisco_in_acl () {
#Cisco extended acl
    ACCESSLISTPR=`bgpq4 -F " permit ip %n %i any\n" -A -R 24 -l $ACL $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		debug_echo "Recive error from bgpq4"
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
		debug_echo "Empty result found, exit status will be 1"
		debug_echo "no ip access-list extended $ACL"
                debug_echo "ip access-list extended $ACL"
		debug_echo "$ACCESSLISTPR"
		debug_echo " permit ip $LNET $LWSUBNET any"
		debug_echo "exit"
		debug_echo ""
	fi
}

cisco_urpf_acl () {
#Cisco acl for urpf loose
	URPFLIST=`bgpq4 -F " permit %n %i\n" -A -R 24 -l $URPF $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		debug_echo "Recive error from bgpq"
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
		debug_echo "Empty result found, exit status will be 1"
		debug_echo "no access-list $URPF"
                debug_echo "access-list $URPF remark * URPF loose for $ASSET *"
                debug_echo "$URPFLIST"
                debug_echo "exit"
                debug_echo ""
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
	debug_echo ""
	debug_echo " AUTONOMUS SYSTEM not defined, can not create as-path list"
	debug_echo ""
fi

if [ -n "$PREFIX" ]; then
	cisco_ip_prefix
else 
	debug_echo ""
	debug_echo " Prefix list name not defined, can not create prefix-list"
	debug_echo ""
fi

if [ -n "$ACL" ]; then
	
	if [ -n "$LNETIN" ]; then
		cisco_in_acl
	else 
		debug_echo ""
		debug_echo " Link network not defined, can not create access-list"
		debug_echo ""	
	fi
else
	debug_echo ""
	debug_echo " Access list name not defined, can not create access-list"
	debug_echo ""
fi

if [ -n "$URPF" ]; then
	cisco_urpf_acl
else
	debug_echo ""
	debug_echo " URPF list name not defined, can not create access-list for URPF"
	debug_echo ""
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
			debug_echo "Recive error from bgpq4"
			exit 1
		fi
		if echo "$ASPATHPR" | grep -q 'as-path' >/dev/null; then
			echo "$ASPATHPR"
			ZEROWORK=1
		else 
			ZEROOUTPUT=1
			debug_echo "Empty result found, exit status will be 1"
			debug_echo "$ASPATHPR"
		fi
		echo "#"
	else
		debug_echo '
Name of as-path list not defined, can not create it"
'
	fi
}

juniper_route_filter () {
#Juniper route-filter-list 
	if [ -n  "$ALLMASK" ]; then
		PREFIXPR=`bgpq4 -J -z -A -l $PREFIX -R $ALLMASK $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			debug_echo "Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -qE "upto|exact|prefix-length-range" >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			debug_echo "Empty result found, exit status will be 1"
			debug_echo "$PREFIXPR"
		fi
		echo "#" 
	else
		PREFIXPR=`bgpq4 -J -z -A -l $PREFIX $ASSET`
		RC="$?"
		if [ "$RC" != "0" ]; then
			debug_echo "Recive error from bgpq4"
			exit 1
		fi
		if echo "$PREFIXPR" | grep -qE "upto|exact|prefix-length-range" >/dev/null; then
			echo "$PREFIXPR"
			ZEROWORK=1
		else
			ZEROOUTPUT=1
			debug_echo "Empty result found, exit status will be 1"
			debug_echo "$PREFIXPR"
		fi
		echo "#"
	fi
}

juniper_filter () {
#Juniper firewall inbound filter 
	FWFILTER=`bgpq4 -F "                        %n\/%l;\n" -A -R 24 $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		debug_echo "Recive error from bgpq4"
                exit 1
        fi
	if echo "$FWFILTER" | grep -q '[0-9]' >/dev/null; then
		echo "firewall {
    family inet {
        replace:
        filter $ACL {
            term TRUSTED-SOURCE {
                from {
                    source-address {
$FWFILTER
			$LNET/$LNETMASK;
                    }
                }
                then {
                    accept;
                }
	}
            term DEFAULT {
                then discard;
            }
        }
    }
}"

		ZEROWORK=1
	else
		ZEROOUTPUT=1
		debug_echo "firewall {
    family inet {
       replace:
       filter $ACL {
            term TRUSTED-SOURCE {
                from {
                    source-address {
$FWFILTER
                        $LNET/$LNETMASK;
                    }
                }
                then {
                    accept;
                }
            }    
            term DEFAULT {
                then discard;
            }
        }
    }
}"
	fi
}


juniper_urpf_filter () {
#Cisco acl for urpf loose
	URPFLIST=`bgpq4 -F "                    	%n\/%l;\n" -A -R 24 $ASSET`
	RC="$?"
	if [ "$RC" != "0" ]; then
		debug_echo "Recive error from bgpq"
		exit 1
	fi
	if echo "$URPFLIST" | grep -q '[0-9]' >/dev/null; then
		echo "firewall {
    family inet {
        replace:
        filter $URPF {
        /* URPF loose for $ASSET */
            term TRUSTED-SOURCE-URPF {
                from {
                    source-address {
$URPFLIST
                    }
                }
                then {
                    accept;
                }
	    }
            term DEFAULT {
                then discard;
            }
        }
    }
}"

		ZEROWORK=1
	else
		ZEROOUTPUT=1
		debug_echo "firewall {
    family inet {
        replace:
        filter $URPF {
        /* URPF loose for $ASSET */
            term TRUSTED-SOURCE-URPF {
                from {
                    source-address {
$URPFLIST
                    }
                }
                then {
                    accept;
                }
	    }
            term DEFAULT {
                then discard;
            }
        }
    }
}"
	fi
}


juniper () {
#Junos specific output
if [ $DEBUG != 0 ];then
	echo '#
#configure
#
#load replace terminal
#'
else
         echo '#
#configure
#
#load replace terminal
#
#'
fi

if [ -n "$AS" ]; then
	juniper_as_path
	echo "#"
else
	debug_echo ""
	debug_echo " AUTONOMUS SYSTEM not defined, can not create as-path-group "
	debug_echo ""
fi

if [ -n "$PREFIX" ]; then
	juniper_route_filter
	echo "#"
else 
	debug_echo ""
	debug_echo " Prefix list name not defined, can not create route-filter-list"
	debug_echo ""
fi

if [ -n "$ACL" ]; then
	
	if [ -n "$LNETIN" ]; then
		juniper_filter
		echo "#"
	else 
		debug_echo ""
		debug_echo " Link network not defined, can not create inbound filter"
		debug_echo ""	
	fi
else
	debug_echo ""
	debug_echo " Access list name not defined, can not create inbound filter"
	debug_echo ""
fi

if [ -n "$URPF" ]; then
	juniper_urpf_filter
	echo "#"
else
	debug_echo ""
	debug_echo " URPF list name not defined, can not create access-list for URPF filter"
	debug_echo ""
fi

if [ $DEBUG != 0 ];then
        echo '#
#
#'
else
        echo '# Press Ctrl+D
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
	debug_echo "No one list caculated. Will be exit status 1"
	exit 1
fi

exit 0
