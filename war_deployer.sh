#!/bin/bash

# # # # # # # # # # # # #  # # # # # # # # # # # # # # # # # # # #  # # # # # # # # # # # #  # # # # # # # #  # # # # 
# prepared by Nathan Tesfamichael
# 
# This bash script is used to deploy tomcat web app safely.
# It creates neccesary database and app backups.
# After deploying, it checks for the status of the deployment and if necessary it rollbacks to the previous version
#
# # # # # # # # #  # # # # # # # # # # # # # # # # # # # #  # # # # # # # # # # # # # # # # # # # #  # # # # # # # # 

# --> properties
# directories and files
SOURCE_DIR="/opt/hl/auto/source"
BKP_DIR="/opt/hl/auto/backup"
LOG_DIR="/opt/hl/auto/log"
LOG_FILE="$LOG_DIR/status.log"
DEPLOY_LOG="$LOG_DIR/deploy-$(date +"%d-%m-%Y").log"

#Location of tomcat root
WEBROOT="/opt/tomcat8"

#This is without extension. eg: app.war should be written as app
WAR_NAME='app'

#APP_URL is used to check the status of the website. 
APP_URL="localhost:8080/$WAR_NAME"

START_SCRIPT="$WEBROOT/bin/startup.sh"
SHUTDOWN_SCRIPT="$WEBROOT/bin/shutdown.sh"
SCRIPT_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )

DEPLOY_ERROR='Deploying war failed!'

#This are recipient emails
RECIPIENT_EMAIL='admin@gmail.com'
BCC_RECIPIENT_EMAIL='other_admin@gmail.com'

#Email username and password used by this script to send messages
CLIENT_EMAIL='some_email@gmail.com'
CLIENT_PASSWORD='client_password'

ORGANIZATION="ABC Organization"

#MySql username and password
DB_USER='user'
DB_PASS='password'
DB_NAME='dbname'

#The email clinet used on this script is different for Ubuntu and Centos. When using on ubuntu sendemail should be installed first.
SERVER='Ubuntu'		# for now 'Ubuntu' or 'Centos'

# this properties don't change
CUR_DATE=$(date +%Y-%m-%d-%H-%M)
TOMCAT='tomcat'
# <-- end of properties

#function that does some proper temination
terminateTask(){

   logMessage "$1" "$2"
   logMessage "*********************** TASK COMPLETED ***********************"

	logMessage "end time "$(date '+%Y-%m-%d %H:%M:%S')
	duration=$SECONDS
	logMessage "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

   sendEmail "$1" "$2" 
   exit
}

logMessage(){
	echo "$@" >> $LOG_FILE
	echo "$@" >> $DEPLOY_LOG
}


#function to initiate email message
sendEmail(){
        #prepare email header and footer
        emailHeader="Hi all!\n"
        emailFooter="\nPlease check the attached log for details.\n\nRegards.\n\n(sent by auto deploy tool)"

	if [ $SERVER == 'Ubuntu' ]
	then
			echo -e "$emailHeader$2$emailFooter" | sendemail -a "$DEPLOY_LOG" -f "$ORGANIZATION DeployBot <$CLIENT_EMAIL>" -u "$1 on $ORGANIZATION" -t $RECIPIENT_EMAIL -bcc $BCC_RECIPIENT_EMAIL -s "smtp.gmail.com:587" -o tls=yes -xu "$CLIENT_EMAIL" -xp "$CLIENT_PASSWORD"
    		# Use sendemail for ubuntu
	elif [ $SERVER == 'Centos' ]
	then
			echo -e "$emailHeader$2$emailFooter" | mail -s "$1 on $ORGANIZATION" -a $DEPLOY_LOG -b $BCC_RECIPIENT_EMAIL $RECIPIENT_EMAIL
			# use ssmtp for centos. It ssmtp has some configuration - sample is attached on bitbucket
	else
		logMessage "Server not known. Unable to use email client."
	fi
	#ABOVE $emailHeader$2$emailFooter is actually three variables $emailHeader $2 $emailFooter - > which we don't want to pring spaces between them.

	exitStatus=$?
        if [ ${exitStatus} == 0 ]
        then
            logMessage "---> NOTIFICATION EMAIL SENT SUCCESSFULLY" 
			rm $DEPLOY_LOG
        else
            logMessage "---> FAILED TO SEND NOTIFICATION EMAIL" 
        fi
}

stopTomcat() {
	#kill tomcat
	logMessage "stopping tomcat..."
#	$SHUTDOWN_SCRIPT
	/bin/kill -9 $(ps aux | grep $TOMCAT | grep -v 'grep' | awk '{print $2}')
	exitStatus=$?

    if [  $exitStatus != 0 ]
    then
	ERROR_MESSAGE="$TOMCAT cannot be killed, Maybe not running. Checking further if $TOMCAT is running."
        logMessage $ERROR_MESSAGE 
		intellicareRunning
		if [ "$?" -eq 0 ]; 		# if it is running grep returns 0
		then
			ERROR_MESSAGE="ERROR! $TOMCAT still runnning, cannot kill $TOMCAT. Stopping auto deploy..."
        	terminateTask "$DEPLOY_ERROR" "$ERROR_MESSAGE"	
		fi
	else
		logMessage "$TOMCAT killed successfuly."	
		
    fi
}


checkExitStatus (){
		if [ "$1" != 0 ]; 
		then
			ERROR_MESSAGE="ERROR! failed to $2 \n\n See the log file to check if the previous war is deployed."
			#if $3 is 1 it starts tomcat before it terminates
			if [ "$3" -eq 1 ]; 
			then
				startTomcat
				checkDeployStatus
			fi
        	terminateTask "$DEPLOY_ERROR" "$ERROR_MESSAGE"		
		fi
}

copyNewWar() {
	message=$(mv "$WEBROOT/webapps/$WAR_NAME.war" "$BKP_DIR/$WAR_NAME.war.old" 2>&1)
	#if $3 is 1 checkExitStatus starts tomcat before it terminates
	checkExitStatus $? "back up old war - $message" 1
	message=$(rm -r "$WEBROOT/webapps/$WAR_NAME" 2>&1)
    #if $3 is 1 checkExitStatus starts tomcat before it terminates
    checkExitStatus $? "remove $WAR_NAME folder - $message" 1
	message=$(cp "$SOURCE_DIR/$WAR_NAME.war" "$WEBROOT/webapps/$WAR_NAME.war" 2>&1)
	#if $3 is 1 checkExitStatus starts tomcat before it terminates
	checkExitStatus $? "copy new war to $WEBROOT/webapps/- $message"  1	
}

restoreOldWar() {
	message=$(rm "$WEBROOT/webapps/$WAR_NAME.war" 2>&1)
	checkExitStatus $? "remove new war from webapps - $message"
	message=$(mv "$BKP_DIR/$WAR_NAME.war.old" "$WEBROOT/webapps/$WAR_NAME.war" 2>&1)
	checkExitStatus $? "copy backed up war to webapps - $message"
	message=$(rm "$SOURCE_DIR/$WAR_NAME.war" 2>&1)
	checkExitStatus $? "removing new war from source dir - $message"
}

backupDatabase(){
	logMessage "backing up to $BKP_DIR/$CUR_DATE""_$DB_NAME.sql"
	message=$((mysqldump -u $DB_USER -p$DB_PASS $DB_NAME > "$BKP_DIR/$CUR_DATE""_$DB_NAME.sql")  2>&1)
	if [ $? -ne 0 ] ; then
		rm "$BKP_DIR/$CUR_DATE_$DB_NAME.sql"
		startTomcat
        terminateTask "mysqldump failed to create backup" "Terminating auto deploy. $message"
	else 
		logMessage "database backup created successfuly. file - $BKP_DIR/$CUR_DATE""_$DB_NAME.sql "
	fi
}

restoreDatabase(){
	echo "drop database $DB_NAME;" | mysql -u $DB_USER -p$DB_PASS
	echo "create database $DB_NAME;" | mysql -u $DB_USER -p$DB_PASS
	mysql -u $DB_USER -p$DB_PASS $DB_NAME < "$BKP_DIR/$CUR_DATE""_$DB_NAME.sql"
	
	if [ $? -ne 0 ] ; then
        terminateTask "mysql failed to restore backup" "Terminating auto deploy. $message. Please start tomcat manually. The backup created just before \
		auto deploy started is $BKP_DIR/$CUR_DATE""_$DB_NAME.sql"
	else 
		logMessage "database restored successfuly from $BKP_DIR/$CUR_DATE""_$DB_NAME.sql "
	fi
}

startTomcat(){
	logMessage "starting tomcat..."
	message=$($START_SCRIPT)
	logMessage "----------------------------------------"
	logMessage $message
	logMessage "----------------------------------------"
}

intellicareRunning (){
	wget -q -O- "$APP_URL" | grep -iq "IntelliCare" 
	return $?
}

checkDeployStatus () {
	# wait untill tomcat is started
	logMessage "checking if the war file is deployed successfully..." 
	sleep 5
	(tail -f "$WEBROOT/logs/catalina.out" &) | grep -iEq -m 1 "Server startup in [0-9]+ ms"
	wget -q -O- "$APP_URL" | grep -iq "IntelliCare"
	output=$?
	if [ "$output" -eq 0 ]; then
		logMessage "tomcat started successfully"
	fi
	return $output
}

createFolders () {

	message=$(mkdir -p "$LOG_DIR" 2>&1)
	if [ $? -ne 0 ] ; then
		terminateTask "$DEPLOY_ERROR" "$message"
	else
		logMessage "log folder created at $LOG_DIR"
	fi

	logMessage "tomcat web root folder $WEBROOT does not exits" 

    message=$(mkdir -p "$SOURCE_DIR" 2>&1)
	if [ $? -ne 0 ] ; then
        terminateTask "$DEPLOY_ERROR" "$message"
	else
		logMessage "source folder created at $SOURCE_DIR"
	fi

	message=$(mkdir -p "$BKP_DIR" 2>&1)
	if [ $? -ne 0 ] ; then
		terminateTask "$DEPLOY_ERROR" "$message"
	else
		logMessage "backup folder created at $BKP_DIR"
	fi
}

compressFiles(){

	logMessage "compressing war and database to $BKP_DIR/$CUR_DATE"".tar.gz"
	cd "$BKP_DIR"
	message=$(tar -czvf "$CUR_DATE"".tar.gz" "$CUR_DATE""_$DB_NAME.sql" "$CUR_DATE""_$WAR_NAME.war" 2>&1)
	logMessage $message
	logMessage "cleaning temporary files..."
	rm "$BKP_DIR/$CUR_DATE""_$DB_NAME.sql" "$BKP_DIR/""$CUR_DATE""_$WAR_NAME.war"
}

cleanAfterSucessfulDeploy(){
	logMessage "removing $SOURCE_DIR/$WAR_NAME.war"
	rm "$SOURCE_DIR/$WAR_NAME.war"
	logMessage "moving $BKP_DIR/$WAR_NAME.war.old to $BKP_DIR/$CUR_DATE""_$WAR_NAME.war"
	mv "$BKP_DIR/$WAR_NAME.war.old" "$BKP_DIR/""$CUR_DATE""_$WAR_NAME.war"
	compressFiles
}

deployNewWar(){
	stopTomcat
	copyNewWar
	backupDatabase
	startTomcat
}

deployOldWar(){
	#revert to the previous $WAR_NAME.war
	logMessage	#enter new line
	logMessage "$DEPLOY_ERROR"
	logMessage "$(date +%Y_%m_%d_%H) trying to revert to previous war..."
	stopTomcat
	restoreDatabase
	restoreOldWar
	compressFiles
	startTomcat
}

main () {

logMessage "start time "$(date '+%Y-%m-%d %H:%M:%S')
	SECONDS=0

	if [ -d "$SOURCE_DIR" ]; then 
		if [ -f "$SOURCE_DIR/$WAR_NAME.war" ]; then
			if [ -d "$WEBROOT" ]; then
				deployNewWar
				checkDeployStatus

				if [ "$?" -eq 0 ]; then
					cleanAfterSucessfulDeploy
					terminateTask "web app deployed successfully" "$(date '+%Y-%m-%d %H:%M:%S') - web app deployed successfully"
				else
					deployOldWar
					checkDeployStatus

					if [ "$?" -eq 0 ]; then
						terminateTask  "web app REVERTED to previous war successfuly" "$date - Auto deploy failed on $ORGANIZATION server. $date web app reverted to previous war successfully."
						
					else
						terminateTask "$DEPLOY_ERROR" "auto deploy at $date failed on $ORGANIZATION server. $date web app can not be reverted to previous war. Start tomcat manually!"
						
					fi
				fi
			else
				terminateTask "$DEPLOY_ERROR" "$WEBROOT not found! Configure correct tomcat root folder."
			fi
		else 
		    logMessage "$CUR_DATE $WAR_NAME.war not found. Nothing to deploy..." 
		fi
	else
		createFolders
	fi


	logMessage "end time "$(date '+%Y-%m-%d %H:%M:%S')
	duration=$SECONDS
	logMessage "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
	
}


# run main
main

