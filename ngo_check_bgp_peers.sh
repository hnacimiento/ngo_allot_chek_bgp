#!/bin/bash
#------------------------------------------------------------------------------------------------------------------
# Author: Hernan Dario Nacimiento | hernan.nacimiento@gmail.com
# Special thanks to Perry Nakar from Allot for guiding me through the Alllot commands and tools.
#
# This script set the SSG Allot Bandwidth Limits whith setDeviceBandwidth action via Configuration CLI,
# this is done based on check conditions via snmp of the BGP peer Status of main link.
#
# Allot NX tool ConfigurationCLI.sh <option> [<value>] [<option> <value> [<value>]] …
# parameter -setDeviceBandwidth IN_AND_OUT_EACH:0:0
# value=0 is maximum
# values are expressed in kilobits per second (1000 kbps is 1 mbps).
#
# In order to install put this script file on /tmp directory on Allot NetXplorer Server
# then run as root: bash ngo_check_bgp_peers.sh install
# after this script was installed, you can delete this file. A copy will be placed in /usr/local/bin
#
# In the root crontab a new entry will be created to run this script every 5 minutes.
#
# IMPORTANT: The script check healt status of Routers whit icmp ping. if the Routers does not respond the ping,
#            then the script does not perform the SNMP query and exit whit RC -1
# IMPORTANT: The script was only tested with one SSG gateway.
#
# ABOUT VARIABLES:
#                 SSG_DEVICENAME, below you will see two variables with the same name, please leave only one uncommented.
#                 Below, the first variable can get the name of the SSG for you, but keep in mind that this script was
#                 tested with only one SSG. If you have a single SSG and don't know the name this may be useful.
#
#                 IN_BANDWIDTH_NORMAL and OUT_BANDWIDTH_NORMAL, it is the value you have under normal conditions.
#
#                 IN_BANDWIDTH_NEW and OUT_BANDWIDTH_NEW, It is the value that you need to change to
#                 adjust to the new conditions. For example in case of losing a main link.
#
#                 SNMP_COMMUNITY, is the snmp community name that you have configured on your router.
#
#                 OID_BGPPEERSTATE, is the snmp oid that permit check de BGP peer state, more comments below.
#
#                 BGP_NEIGHBOR01, it is my BGP neighbor, my main IXP.
#
#                 IP_ROUTER01 and IP_ROUTER02, these are the IP addresses of Routers.
#
# Description of the main snmp OID "BGPPEERSTATE" || http://oid-info.com/get/1.3.6.1.2.1.15.3.1.2 
# bgpPeerState OBJECT-TYPE
# SYNTAX INTEGER {
# idle(1),
# connect(2),
# active(3),
# opensent(4),
# openconfirm(5),
# established(6)
# }
# MAX-ACCESS read-only
# STATUS current
# DESCRIPTION
# "The BGP peer connection state."
# REFERENCE
# "RFC 4271, Section 8.2.2."
#
#------------------------------------------------------------------------------------------------------------------
SCRIPT_NAME=`basename ${BASH_SOURCE[0]}` #Script File Name
LIB_DIR="/var/lib/ngo"
LOG_DIR="/var/log/ngo"
LOGFILE="ngo_check_bgp_peers.log"
CONFCLI_PATH="/opt/admin/migration/CLI"
CONFCLI_TOOL="ConfigurationCLI.sh"
POLICYCLI_TOOL="policyCLI.sh"
#SSG_DEVICENAME=`topologyCLI.sh -getTopologyDevices | grep -Po '(?<=uiName=)[^ ]+'` # if you set this var manually the script runs faster
#------------------------------
# Please complete the following
SSG_DEVICENAME="ServiceGateway"
IN_BANDWIDTH_NORMAL="1900000" # Kilobit per second
OUT_BANDWIDTH_NORMAL="1900000" # Kilobit per second
IN_BANDWIDTH_NEW="800000" # Kilobit per second
OUT_BANDWIDTH_NEW="800000" # Kilobit per second
SNMP_COMMUNITY="ramon"
OID_BGPPEERSTATE=".1.3.6.1.2.1.15.3.1.2."
BGP_NEIGHBOR01="200.0.17.1" # My IXP
IP_ROUTER01="10.10.10.1"
IP_ROUTER02="10.10.10.2"
#------------------------------------------------------------------------------------------------------------------
# Start logging
if [ -d "$LOG_DIR" ]; then
     exec >> $LOG_DIR/$LOGFILE 2>&1;
else
     mkdir -p $LOG_DIR
     exec >> $LOG_DIR/$LOGFILE 2>&1
fi

startcheck () {
for ip in $IP_ROUTER01 $IP_ROUTER02
do
     ping -c2 -q $ip &>/dev/null
     status=$( echo $? )
     if [[ $status == 0 ]]
     then
          #Connection success!
          if [[ $ip == $IP_ROUTER01 ]]
          then
               ROUTER01="UP"
               echo "Router $IP_ROUTER01 is $ROUTER01"
          elif [[ $ip == $IP_ROUTER02 ]]
          then
               ROUTER02="UP"
               echo "Router $IP_ROUTER02 is $ROUTER02"
          fi
     else
          echo #Connection failure
          if [[ $ip == $IP_ROUTER01 ]]
          then
               ROUTER01="DOWN"
               echo "Router $IP_ROUTER01 is $ROUTER01"
          elif [[ $ip == $IP_ROUTER02 ]]
          then
               ROUTER02="DOWN"
               echo "Router $IP_ROUTER02 is $ROUTER02"
          fi
     fi
done

if [[ $ROUTER01 == "DOWN" && $ROUTER02 == "DOWN" ]]; then

     echo "Routers are DOWN!"
     echo -e "Nothing to do\n"
     exit -1
     
fi

if [[ $ROUTER01 == "UP" && $ROUTER02 == "UP" ]] || [[ $ROUTER01 == "UP" || $ROUTER02 == "DOWN" ]] || [[ $ROUTER01 == "DOWN" || $ROUTER02 == "UP" ]]; then

     if [[ $ROUTER01 == "UP" ]]; then
          RT01_PEERSTATE=`snmpget -mALL -v2c -c $SNMP_COMMUNITY $IP_ROUTER01 $OID_BGPPEERSTATE$BGP_NEIGHBOR01 | grep -Po '(?<=INTEGER: )[1-6]+'`
          RT01_PEERSTATE_RC=$( echo $? )
          echo $RT01_PEERSTATE > $LIB_DIR/ROUTER01_bgpPeerState.sav
          echo "ROUTER01 snmpget bgpPeerState value: $RT01_PEERSTATE"
     fi
     if [[ $ROUTER02 == "UP" ]]; then
          RT02_PEERSTATE=`snmpget -mALL -v2c -c $SNMP_COMMUNITY $IP_ROUTER02 $OID_BGPPEERSTATE$BGP_NEIGHBOR01 | grep -Po '(?<=INTEGER: )[1-6]+'`
          RT02_PEERSTATE_RC=$( echo $? )
          echo $RT02_PEERSTATE > $LIB_DIR/ROUTER02_bgpPeerState.sav
          echo "ROUTER02 snmpget bgpPeerState value: $RT02_PEERSTATE"
     fi
     if [[ $RT01_PEERSTATE == "6" || $RT02_PEERSTATE == "6" ]] ; then
          echo "OK" > $LIB_DIR/bgpPeerState.sav
     fi

elif [[ $ROUTER01 == "DOWN" ]] && [[ $ROUTER02 == "DOWN" ]] || [[ -z $RT01_PEERSTATE && -z $RT02_PEERSTATE ]]; then

     echo "Routers are DOWN or snmpget can not retrieve information!"
     echo -e "Nothing to do\n"
     exit -1

fi

if [[ -z $RT01_PEERSTATE && -z $RT02_PEERSTATE ]] || [[ $RT01_PEERSTATE_RC != "0" && $RT02_PEERSTATE_RC != "0" ]]; then

     echo "snmpget can not retrieve information!"
     echo -e "Nothing to do\n"
     exit -1

fi

if [[ $RT01_PEERSTATE == [1-5] && $RT02_PEERSTATE == [1-5] ]]; then
     
     echo "FAIL" > $LIB_DIR/bgpPeerState.sav
     echo -e "Setting SSG Device Bandwidth on $SSG_DEVICENAME\nBooth IXP BGP peers are DOWN!"
     echo ConfigurationCLI.sh -setDevice -deviceName $SSG_DEVICENAME -setDeviceBandwidth IN_AND_OUT_EACH:$IN_BANDWIDTH_NEW:$OUT_BANDWIDTH_NEW
     cd $CONFCLI_PATH && ./ConfigurationCLI.sh -setDevice -deviceName $SSG_DEVICENAME -setDeviceBandwidth IN_AND_OUT_EACH:$IN_BANDWIDTH_NEW:$OUT_BANDWIDTH_NEW

fi

LSTATE=`cat $LIB_DIR/bgpPeerState.sav`

if [[ $RT01_PEERSTATE == "6" || $RT02_PEERSTATE == "6" ]] && [[ $LSTATE == "FAIL" ]]; then

     echo "One of the Routers has a stable connection to IXP"
     echo "Setting new value for IN_BANDWIDTH="'"'$IN_BANDWIDTH_NORMAL'"  # Kilobit per second'
     echo "Setting new value for OUT_BANDWIDTH="'"'$OUT_BANDWIDTH_NORMAL'"  # Kilobit per second'
     echo "ConfigurationCLI.sh -setDevice -deviceName $SSG_DEVICENAME -setDeviceBandwidth IN_AND_OUT_EACH:$IN_BANDWIDTH_NORMAL:$OUT_BANDWIDTH_NORMAL"
     cd $CONFCLI_PATH && ./ConfigurationCLI.sh -setDevice -deviceName $SSG_DEVICENAME -setDeviceBandwidth IN_AND_OUT_EACH:$IN_BANDWIDTH_NORMAL:$OUT_BANDWIDTH_NORMAL && echo "OK" > $LIB_DIR/bgpPeerState.sav
else
     echo "The last bgpPeerState on file $LIB_DIR/bgpPeerState.sav: $LSTATE"
     echo "The Router01 ($IP_ROUTER01) whit BGP Neighbor $BGP_NEIGHBOR01 is established($RT01_PEERSTATE)"
     echo "The Router02 ($IP_ROUTER02) whit BGP Neighbor $BGP_NEIGHBOR01 is established($RT02_PEERSTATE)"
     echo -e "Nothing to do\n"

fi
}

install () {
    mkdir -p $LIB_DIR
    echo "cp -fv $SCRIPT_NAME /usr/local/bin/"
    cp -fv $SCRIPT_NAME /usr/local/bin/
    chown root:root /usr/local/bin/$SCRIPT_NAME
    echo "chmod +x /usr/local/bin/$SCRIPT_NAME"
    chmod u+x /usr/local/bin/$SCRIPT_NAME
    echo 'cat <(crontab -l) <(echo "*/5 * * * *   bash /usr/local/bin/'$SCRIPT_NAME'") | crontab -'
    cat <(crontab -l) <(echo "# NGO SCRIPT - Check every 5 min") | crontab - 
    cat <(crontab -l) <(echo "*/5 * * * *    bash /usr/local/bin/$SCRIPT_NAME") | crontab -

    echo '/var/log/ngo_check_bgp_peers.log
          {
              rotate 4
              weekly
              missingok
              notifempty
              compress
              delaycompress
              sharedscripts
              postrotate
                  invoke-rc.d rsyslog reload >/dev/null 2>&1 || true
              endscript

          }' >> /etc/logrotate.d/ngo_check_bgp_peers

  echo -e "\nScript installed!\n"
  exit 0
}

# Start install
if [[ $1 != "" ]]; then OPTS=$1; else OPTS="null"; fi
if [ $OPTS = "install" ]; then install; fi

# Start check
startcheck

#Other examples not testings
#Change QoS for line
#./policyCLI.sh -UPdateTube -tubeDeviceName ServiceGateway -tubeType line -tubeLineName LINE -actionQos Line_min0max1G   

#Change QoS for Pipe
#./policyCLI.sh -UPdateTube -tubeDeviceName ServiceGateway -tubeType pipe -tubeLineName LINE -tubePipeName pipe.name -actionQos Pipe_min20Mmax0

#Change QoS for VC
#./policyCLI.sh -UPdateTube -tubeDeviceName ServiceGateway -tubeType vc -tubeLineName LINE -tubePipeName pipe.name -tubeVcName vc.name -actionQos min0max5M