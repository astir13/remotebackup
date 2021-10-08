# remotebackup
take backup of a machine, based on a config file defining commands, include and exclude files; build ecrypted backup file on remote machine; transfer to cloud service;

# what it does (requirements on the software provided)
- take backup of databases into file (like for MariaDB)
- build a tar.gz file of the files/folders given in include.txt
- encrypt on the fly
- transfer to a remote host with sufficient storage on the fly
- do not require significant storage on the host itself
- be able to run on ARM and i386 arch
- on remote hose: use rclone to transfer to cloud service (like Onedrive)
- use a user account which can have limited priviledges
- use ssh for all transfers to and actions on the remote host
- use ssh authorized_keys to automate remote login and being able to revoke priviledges on remote host if there is a problem
- create incremental backups for n days (configurable), to avoid using full size backup every day
- manage space on the remote host (delete older files on this backup cache)

# what you need (requirements on your host)
- the remote host, ideally a linux with ext. disk, i.e. raspberrypy + 1TB disk; can be the same host, if you do not have a small backup host in your setup
- the deloldest script in /usr/local/bin on the remotehost
- rclone in /usr/local/bin on the remote host (create a symbolical link to the executable)
- rclone configured for the backup user on the remote host
- ssh configured for the backup user on the remote host
- ensured that ssh from the host to be backed up to the remotehost works without password (use standard authorized_keys file on the remote and follow guides on the network of how to setup SSH with authorized keys on the net)
- a cloud storage account supported by rclone (many are)
- having mailx installed on the host to be backed up: for sending emails in case errors happen

# how backup files are decrypted
To decrypt the encrypted file, you just need 
- the backup file
- openssl 
- the keyfile
`openssl enc -d -aes-256-cbc -in /tmp/backupfile.tgz.crypt -out /tmp/backupfile.tgz -pass`
