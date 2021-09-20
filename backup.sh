#!/bin/bash
# backup script to send encrypted backup to remote host
# all include and exclude file lists come from files
# major customization is done through the included {config file}
# which is 1st argument (see example_config)

# copyright Stefan Pielmeier, 2001-2021
# LICENSE: GNU GPL v3
# 
# DISCLAIMER: it is the sole responsibility of the user of this code to
# ensure it fits any purpose. This code comes as it is, with no guarantee 
# for whatever function.

# customization in this code:
# cloudservice and folder might be changed below
# rclone tool might be changed below

# requirements on remote host
# - enough space for the backup
# - rclone tool installed and configured for the cloudservice for the user

expectedArgs=1
snapshot=""
include=""
exclude=""
sshurl=""
inc="0"
clouddrive_dir="onedrive:backup"

if [[ $# -lt $expectedArgs || $# -gt $expectedArgs ]]; then
  echo "usage: $0 {config file}"
  exit 1
fi

# start where we always have access
cd /tmp

# first we check for hanging jobs from earlier cron call
# this can be seen in a lockfile existing with $lockfilename
lockfile="/tmp/backup.lock"
echo checking for lockfiles: ${lockfile}
if [[ -e ${lockfile} ]]; then
  echo "[F]atal Error:found lockfile with pid"
  cat ${lockfile}
  echo "; another process is still running; exiting ..."
  echo "kill that process pid `cat ${lockfile}` or remove the file '${lockfile}', faithfully backup.sh" | mailx -s "`hostname`:$$:another backup process is still running" root@localhost
  exit 1
else
  echo "no lockfile found: good"
  # creating lockfile
  echo $$ > ${lockfile}
fi

function rem_lockfile {
  /bin/rm ${lockfile}
  if [ ! -e ${lockfile} ]; then
    echo removed lockfile ${lockfile}
  else
    echo "[E]rror: couldn't remove lockfile!"
    exit 1
  fi
}

# date
echo "[I]nfo: starting backup at `date`"

# the config file shall exist
# read all variables from the config file, these will overwrite defaults from above
if [[ -e $1 ]]; then
  echo "[I]nfo: reading all variables from '$1'"
  source $1 # here all commands from the config file get executed
  if [[ $? -ne 0 ]]; then
    echo "[F]atal:config file stopped with errors, see above."
    rem_lockfile
    exit 1
  fi
else
  echo "[F]atal: config file not found: '$1'"
  rem_lockfile
  exit 1
fi 

# the snapshot file name shall not be empty
if [[ $snapshot != "" ]]; then
  echo "[I]nfo: using snapshot file '${snapshot}'"
  snapshot_dir=$(dirname $snapshot)
  if [[ ! -d $snapshot_dir ]]; then
    echo "[W]arn: directory '$snapshot_dir' not existing, attempting to create it"
    mkdir $snapshot_dir
  fi 
  if [[ -e "${snapshot}" ]]; then
    echo "[I]nfo: found snapshot file already in place => this is an incremental backup"
    if [[ $snapcount != "" ]]; then
      echo "[I]nfo: using snapcount file '${snapcount}'"
      if [[ -e "${snapcount}" ]]; then
        inc=`cat $snapcount`
        echo "[I]nfo: last snapshot was number '${inc}', inc_max=${inc_max}"
        inc=$((inc + 1))
        if [[ $inc -gt $inc_max ]]; then
          echo "[I]nfo: starting with a fresh increment cycle"
          inc=0;
          rm ${snapshot}
        fi
        echo "[I]nfo: next backup is snapshot number '${inc}'"
      else
        echo "[W]arn: snapcount file '${snapcount}' does not exist"
        echo "        starting with a fresh increment cycle"
        rm ${snapshot}
      fi
    else
      echo "[F]atal: snapcount filename empty"
      rem_lockfile
      exit 1
    fi
  else
    echo "[I]nfo: starting new snapshot file"
  fi
else
  echo "[F]atal: snapshot file name is empty. check config. stopping."
  rem_lockfile
  exit 1
fi 

# finally set the incremental file name indicator
incremental="inc${inc}"   # default is that there is no incremental file found -> this is increment 0

# include list file shall not be empty and shall exist
if [[ $include != "" && -e $include ]]; then
  echo "[I]nfo: using include file '${include}'"
else
  echo "[F]atal: include file '$include' not found or empty string. check your config. stopping."
  rem_lockfile
  exit 1
fi

# exclude list file shall not be empty and shall exist
if [[ $exclude != "" && -e $exclude ]]; then
  echo "[I]nfo: using exclude file '${exclude}'"
else
  echo "[F]atal: exclude file '$exclude' not found. stopping."
  rem_lockfile
  exit 1
fi

# sshurl shall not be empty and shall exist
if [[ $sshurl != "" ]]; then
  echo "[I]nfo: using ssh command 'ssh ${sshurl}'"
else
  echo "[F]atal: sshurl '$sshurl' empty. stopping."
  rem_lockfile
  exit 1
fi

# determine if zip of archive is required
if [[ $zip == "" ]]; then
  echo "[I]nfo: zipping disabled"
  tar_ending="tar"
else
  if [[ $zip == "z" ]]; then
    echo "[I]nfo: zipping enabled"
    tar_ending="tgz"
  else
    echo "[F]atal: paramter zip='$zip' not recognized, can be 'z' or '', check your config. stopping."
    rem_lockfile
    exit 1
  fi
fi

# create the tar name
timestamp=`date +"%F_%H%M%S"`
hostname=`hostname`
tarname="backup_${hostname}_${timestamp}_${incremental}.${tar_ending}.crypt"
echo "[I]nfo: storing the archive under name '${tarname}'"

# determine target directory on remote host
if [[ $targetdir != "" ]]; then
  echo "[I]nfo: target directory on the remote host is: '${targetdir}'"
else
  echo "[F]atal: cannot work with an empty target directory. check your config. stopping here: '${targetdir}'"
  rem_lockfile
  exit 1
fi
echo "[I]nfo: storing the archive under ${sshurl}:${targetdir}"

# create space if needed, on remote host
echo "[I]nfo: removing old files on remotehost, if needed:"
echo "---"
ssh ${sshurl} "(/usr/local/bin/deloldest ${rm_num} ${space} ${targetdir} )"
echo "---"
echo "[I]nfo: clean-up on remote host done. Starting backup and transfer on the fly:"
if [[ $? -ne 0 ]]; then
  echo "[F]atal:cannot remote execute commands on remote host:'${sshurl}'"
  rem_lockfile
  exit 1
fi
# tar compressed to a pipe into remote host folder (no space needed here)
cd /
tar c${zip}f - --listed-incremental ${snapshot} --exclude-from ${exclude} ${tarattribs} --exclude-vcs --files-from ${include} | openssl enc -aes-256-cbc -salt -pass file:/usr/local/symlinux/config/ssl/symlinux/backup/passwd.txt | ssh ${sshurl} "(cd ${targetdir}; cat - > ${tarname})"
if [[ $? -ne 0 ]]; then
  echo "[F]atal: tar, encrypt or transfer failed, see output before this line. stopping."
  rem_lockfile
  exit 1
fi

# upload the newly generated file to cloud service
retry=0
while [[ $? -ne 0 && $retry -lt 5 || $retry -eq 0 ]]; do
  retry=$((retry + 1))
  echo "[I]nfo: retry number ${retry}"
  ssh ${sshurl} "(/usr/local/bin/rclone copy ${targetdir}/${tarname} ${clouddrive_dir}/${hostname}/)"
done
if [[ $? -ne 0 ]]; then
  echo "[W]arning: transfer to cloud drive failed, see output before this line."
fi

# finally note the increment in the snapcount file
echo ${inc} > ${snapcount}

# remove lockfile
rem_lockfile

# end
echo "[I]nfo: done"
