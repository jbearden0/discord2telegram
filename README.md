# discord2telegram.pl
This is a very simple perl script to repeat Discord server messages to a Telegram user.
Discord provides an async method of doing this using websockets, but this script uses 
the regular API to batch download messages with a bot account because my needs did not 
require the added complexity. Message timestamps are ignored so this script needs to be 
run often with cron for the timestamps on Telegram to be a reasonable approximation.

NOTES:
* Find your Telegram user ID by messaging @chatid_echo_bot .
* You have to authorize your telegram bot by starting a conversation with it.
* The sensitive information like bot tokens are stored in a separate file. (format of KEYNAME: VALUE)
* A run file is used to remember the latest message ID numbers, which must be writable by the user.
* The assumption is this script is run every five minutes by cron.
