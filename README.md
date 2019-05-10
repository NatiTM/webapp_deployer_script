# Webapp Deployer Script For Tomcat
This script deploys a tomcat web app safely with database and app backups. Incase deployment fails it rolls back to the previous state by restoring the backed up database and application.

It generates detailed logs and notifies administrators after each run using email. It can be added on cron job to make nightly builds.

This script can be extended to make builds on platforms other than tomcat.
