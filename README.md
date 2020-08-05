# discord2telegram.pl
This is a very simple perl script to repeat Discord server messages to a Telegram user.
Discord provides an async method of doing this using websockets, but this
script uses the regular API to batch download messages with a bot account.
Message timestamps are ignored so this script needs to be run often with
cron for the timestamps on Telegram to be a reasonable approximation.

NOTES:
* Find your Telegram user ID by messaging @chatid_echo_bot
* You have to authorize your telegram bot by starting a conversation with it
