#!/system/bin/sh

# This script functions will be used in customize.sh, post-fs-data mode, services mode and uninstall mode
#

# Get the active audio policy configuration fille from the audioserever
function getActivePolicyFile()
{
    dumpsys media.audio_policy | awk ' 
        /^ Config source: / {
            print $3
        }' 
}

function stopDRC()
{
    # stopDRC has two args specifying a main audio policy configuration XML file (eg. audio_policy_configuration.xml) and its dummy one to be overridden

     if [ $# -eq 2  -a  -r "$1"  -a  -w "$2" ]; then
        # Copy and override an original audio_policy_configuration.xml to its dummy file
        cp -f "$1" "$2"
        # Change audio_policy_configuration.xml file to remove DRC
        sed -i 's/speaker_drc_enabled[:space:]*=[:space:]*"true"/speaker_drc_enabled="false"/' "$2"
    fi
}

function unsetHifiNetwork()
{
    # Delete wifi optimizations
    settings delete global wifi_suspend_optimizations_enabled

    # Stop higher bitrate (approx. 600kbps) for bluetooth SBC HD codec when conneted to bluetooth EDR 2Mbps devices
    #resetprop -p --delete persist.bluetooth.sbc_hd_higher_bitrate
}

function unsetVolumeMediaSteps()
{
    # Delete volume media steps key
    settings delete system volume_steps_music
}
function stopEnforcing()
{
    # Change SELinux enforcing mode to permissive mode
    setenforce 0
}

function stopMPDecision()
{
    # Stop the MPDecision (CPU hotplug)
    if [ "`getprop init.svc.mpdecision`" = "running" ]; then
        setprop ctl.stop mpdecision
    elif [ "`getprop init.svc.vendor.mpdecision`" = "running" ]; then
        setprop ctl.stop vendor.mpdecision
    fi
}

function stopThermalCoreControl()
{
    # Stop the thermal core control (for Qualcomm)
    if [ -w "/sys/module/msm_thermal/core_control/enabled" ]; then
        echo '0' >"/sys/module/msm_thermal/core_control/enabled"
    fi
    # Stop thermal server (for MediaTek)
    if [ "`getprop init.svc.thermal`" = "running" ]; then
        setprop ctl.stop thermal
    fi
}

function stopCameraService()
{
    # Stop the camera servers
    if [ "`getprop init.svc.qcamerasvr`" = "running" ]; then
        setprop ctl.stop qcamerasvr
    fi
    if [ "`getprop init.svc.vendor.qcamerasvr`" = "running" ]; then
        setprop ctl.stop vendor.qcamerasvr
    fi
    if [ "`getprop init.svc.cameraserver`" = "running" ]; then
        setprop ctl.stop cameraserver
    fi
    if [ "`getprop init.svc.camerasloganserver`" = "running" ]; then
        setprop ctl.stop camerasloganserver
    fi
    if [ "`getprop init.svc.camerahalserver`" = "running" ]; then
        setprop ctl.stop camerahalserver
    fi
}

function setHifiNetwork()
{
    # Reducing wifi jitter by suspend wifi optimizations
    settings put global wifi_suspend_optimizations_enabled 0
}

function setVolumeMediaSteps()
{
    # Volume medial steps to be 100 if a volume steps facility is used
    settings put system volume_steps_music 100
}

function forceIgnoreAudioEffects()
{
    if [ "`getprop persist.sys.phh.disable_audio_effects`" = "0" ]; then
        
        type resetprop 1>/dev/null 2>&1
        if [ $? -eq 0 ]; then
            resetprop ro.audio.ignore_effects true
        else
            type resetprop_phh 1>/dev/null 2>&1
            if [ $? -eq 0 ]; then
                resetprop_phh ro.audio.ignore_effects true
            else
                return 1
            fi
        fi
        
        if [ "`getprop init.svc.audioserver`" = "running" ]; then
            setprop ctl.restart audioserver
        fi
        
    elif [ "`getprop ro.system.build.version.release`" -ge "12" ]; then
        
        local audioHal
        setprop ctl.restart audioserver
        audioHal="$(getprop |sed -nE 's/.*init\.svc\.(.*audio-hal[^]]*).*/\1/p')"
        setprop ctl.restart "$audioHal" 1>"/dev/null" 2>&1
        setprop ctl.restart vendor.audio-hal-2-0 1>"/dev/null" 2>&1
        setprop ctl.restart audio-hal-2-0 1>"/dev/null" 2>&1
        
    fi
}

# choose the best I/O scheduler for very Hifi audio outputs, and output it into the standard output
function chooseBestIOScheduler() 
{
    if [ $# -eq 1  -a  -r "$1" ]; then
        local  x  scheds  ret_val=""
  
        scheds="`tr -d '[]' <\"$1\"`"
        for x in $scheds; do
            case "$x" in
                "deadline" ) ret_val="deadline"; break ;;
                "cfq" ) ret_val="cfq" ;;
                "noop" ) if [ "$ret_val" != "cfq" ]; then ret_val="noop"; fi ;;
                * ) ;;
            esac
        done
        echo "$ret_val"
        return 0
    else
        return 1
    fi
}

function setKernelTunables()
{
    local  i  sched

    # Set kernel tuables for CPU&GPU govenors, I/O scheduler, and Virtual memory
  
    # CPU governor
    # prevent CPU offline stuck by forcing online between double  governor writing 
    for i in `seq 0 9`; do
        if [ -e "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor" ]; then
            chmod 644 "/sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor"
            echo 'performance' >"/sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor"
            chmod 644 "/sys/devices/system/cpu/cpu$i/online"
            echo '1' >"/sys/devices/system/cpu/cpu$i/online"
            echo 'performance' >"/sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor"
        fi
    done
    
    # GPU governor
    if [ -w "/sys/class/kgsl/kgsl-3d0/pwrscale/trustzone/governor" ]; then
        # For old Qcomm GPU's
        echo 'performance' >"/sys/class/kgsl/kgsl-3d0/pwrscale/trustzone/governor"
        if [ -w "/sys/class/kgsl/kgsl-3d0/min_pwrlevel" ]; then
            # Set the min power level to be maximum
            echo "0" >"/sys/class/kgsl/kgsl-3d0/min_pwrlevel"
        fi
    elif [ -w "/sys/class/kgsl/kgsl-3d0/devfreq/governor" ]; then
        # For Qcomm GPU's
        echo 'performance' >"/sys/class/kgsl/kgsl-3d0/devfreq/governor"
        if [ -w "/sys/class/kgsl/kgsl-3d0/min_pwrlevel" ]; then
            # Set the min power level to be maximum
            echo "0" >"/sys/class/kgsl/kgsl-3d0/min_pwrlevel"
        fi
    elif [ -w "/proc/gpufreq/gpufreq_opp_freq"  -a  -r "/proc/gpufreq/gpufreq_opp_dump" ]; then
        # Maximum fixed frequency setting for MediaTek GPU's
        local x1 x2 x3 x4 x5 freq="" IFS=" ,"
        
        read x1 x2 x3 x4 x5 <"/proc/gpufreq/gpufreq_opp_dump"
        freq="$x4"
        if [ -n "$freq" ]; then
            echo "$freq" >"/proc/gpufreq/gpufreq_opp_freq"
        fi
    fi
    
    # I/O scheduler
    for i in sda mmcblk0 mmcblk1; do
        if [ -d "/sys/block/$i/queue" ]; then
            echo '10240' >"/sys/block/$i/queue/read_ahead_kb"
            echo '0' >"/sys/block/$i/queue/iostats"
            echo '0' >"/sys/block/$i/queue/add_random"
            echo '2' >"/sys/block/$i/queue/rq_affinity"
            echo '2' >"/sys/block/$i/queue/nomerges"
    
            # Optimized for bluetooth audio and so on.
            sched="`chooseBestIOScheduler \"/sys/block/$i/queue/scheduler\"`"
            case "$sched" in
                "deadline" )
                    echo 'deadline' >"/sys/block/$i/queue/scheduler"
                    echo '0' >"/sys/block/$i/queue/iosched/front_merges"
                    echo '0' >"/sys/block/$i/queue/iosched/writes_starved"
                    case "`getprop ro.board.platform`" in
                        sdm8* )
                            echo '37' >"/sys/block/$i/queue/iosched/fifo_batch"
                            echo '16' >"/sys/block/$i/queue/iosched/read_expire"
                            echo '480' >"/sys/block/$i/queue/iosched/write_expire"
                            echo '77600' >"/sys/block/$i/queue/nr_requests"
                            ;;
                        sdm* | msm* | sd* | exynos* )
                            echo '37' >"/sys/block/$i/queue/iosched/fifo_batch"
                            echo '16' >"/sys/block/$i/queue/iosched/read_expire"
                            echo '480' >"/sys/block/$i/queue/iosched/write_expire"
                            echo '77130' >"/sys/block/$i/queue/nr_requests"
                            ;;
                        mt* | * )
                            echo '37' >"/sys/block/$i/queue/iosched/fifo_batch"
                            echo '16' >"/sys/block/$i/queue/iosched/read_expire"
                            echo '480' >"/sys/block/$i/queue/iosched/write_expire"
                            echo '77500' >"/sys/block/$i/queue/nr_requests"
                            ;;
                    esac
                    ;;
                "cfq" )
                    echo 'cfq' >"/sys/block/$i/queue/scheduler"
                    echo '1' >"/sys/block/$i/queue/iosched/back_seek_penalty"
                    echo '3' >"/sys/block/$i/queue/iosched/fifo_expire_async"
                    echo '3' >"/sys/block/$i/queue/iosched/fifo_expire_sync"
                    echo '0' >"/sys/block/$i/queue/iosched/group_idle"
                    echo '1' >"/sys/block/$i/queue/iosched/low_latency"
                    echo '1' >"/sys/block/$i/queue/iosched/quantum"
                    echo '3' >"/sys/block/$i/queue/iosched/slice_async"
                    echo '25' >"/sys/block/$i/queue/iosched/slice_async_rq"
                    echo '0' >"/sys/block/$i/queue/iosched/slice_idle"
                    echo '3' >"/sys/block/$i/queue/iosched/slice_sync"
                    echo '3' >"/sys/block/$i/queue/iosched/target_latency"
                    echo '62375' >"/sys/block/$i/queue/nr_requests"
                    ;;
                "noop" )
                    echo 'noop' >"/sys/block/$i/queue/scheduler"
                    echo '61675' >"/sys/block/$i/queue/nr_requests"
                    ;;
                * )
                    #  an empty string or unknown I/O schedulers
                    ;;
            esac
        fi
    done
    
    # Virtual memory
    echo '0' >"/proc/sys/vm/swappiness"
    if [ -w "/proc/sys/vm/direct_swappiness" ]; then
        echo '0' >"/proc/sys/vm/direct_swappiness"
    fi
    echo '50' >"/proc/sys/vm/dirty_ratio"
    echo '25' >"/proc/sys/vm/dirty_background_ratio"
    echo '600000' >"/proc/sys/vm/dirty_expire_centisecs"
    echo '111000' >"/proc/sys/vm/dirty_writeback_centisecs"
    echo '1' >"/proc/sys/vm/laptop_mode"
    if [ -w "/proc/sys/vm/swap_ratio" ]; then
        echo '0' >"/proc/sys/vm/swap_ratio"
    fi
    if [ -w "/proc/sys/vm/swap_ratio_enable" ]; then
        echo '1' >"/proc/sys/vm/swap_ratio_enable"
    fi

    # For MediaTek CPUs, stop EAS+ scheduling to reduce jitters
    if [ -w "/proc/cpufreq/cpufreq_sched_disable" ]; then
        echo '1' >"/proc/cpufreq/cpufreq_sched_disable"
    fi
}

# Disable thermal core control, Camera service (interfering in jitters on audio outputs) and Selinux enforcing or not, respectively ("yes" or "no")
# Set default values for safety reasons
DefaultDisableThermalCoreControl="no"
DefaultDisableCameraService="no"
DefaultDisableSelinuxEnforcing="no"

# This function has usually two arguments
function optimizeOS()
{
    local a1=$DefaultDisableThermalCoreControl
    local a2=$DefaultDisableCameraService
    local a3=$DefaultDisableSelinuxEnforcing
  
    case $# in
        0 )
            ;;
        1 )
            a1=$1
            ;;
        2 )
            a1=$1
            a2=$2
            ;;
        3 )
            a1=$1
            a2=$2
            a3=$3
            ;;
        * )
            exit 1
            ;;
    esac

    if [ "$a1" = "yes" ]; then
        stopThermalCoreControl
    fi
    if [ "$a2" = "yes" ]; then
        stopCameraService
    fi
    if [ "$a3" = "yes" ]; then
        stopEnforcing
    fi
    stopMPDecision
    setKernelTunables
    setHifiNetwork
    setVolumeMediaSteps
    forceIgnoreAudioEffects
}
