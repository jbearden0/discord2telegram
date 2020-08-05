#!/usr/bin/perl -w

use strict;
use Config::Simple;
use Getopt::Long;
use JSON::XS;
use LWP::UserAgent;
use POSIX;
use Try::Tiny;

# Very simple script to repeat Discord server messages to a Telegram user.
# Discord provides an async method of doing this using websockets, but this
# script uses the regular API to batch download messages with a bot account.
# Message timestamps are ignored so this script needs to be run often with
# cron for the timestamps on Telegram to be a reasonable approximation.
# Note1: Find your Telegram user ID by messaging @chatid_echo_bot
# Note2: You have to authorize your telegram bot by starting a conversation

my $RunFile = '/var/run/discord2telegram';
my $ConfigFile = '/etc/discord2telegram.conf';
my $LogFile = '';
my $LogLevel = 3;
my $Verbose = 0;
my $DiscordBot = '';
my $DiscordSvr = 0;
my $TelegramBot = '';
my $TelegramUsr = 0;

GetOptions('verbose|v'     => \$Verbose,
           'help|h'        => \&Help
  );

my ($Error, $LastInfo);
if ($Verbose) { $LogLevel = 5; }
if (open(FILE, "<", $RunFile)) {
  read(FILE, $LastInfo, -s FILE);
  close(FILE);
}
if ($LastInfo) { $LastInfo = DecodeJSON($LastInfo); } else { $LastInfo = {}; }

my $cfg = new Config::Simple($ConfigFile);
if (!$cfg || !$cfg->param('DISCORDBOT') || !$cfg->param('DISCORDID') ||
    !$cfg->param('TELEGRAMBOT') || !$cfg->param('TELEGRAMID')) {
  NeoUtil::LogThis("Invalid configuration file! ($ConfigFile)",1);
} else  {
  $DiscordBot = $cfg->param('DISCORDBOT'); # Discord bot token
  $DiscordSvr = $cfg->param('DISCORDID'); # Discord service ID
  $TelegramBot = $cfg->param('TELEGRAMBOT'); # Telegram bot token
  $TelegramUsr = $cfg->param('TELEGRAMID'); # Telegram user ID
  if ($cfg->param('RUNFILE')) { $RunFile = $cfg->param('RUNFILE'); }
  if ($cfg->param('CONFFILE')) { $ConfigFile = $cfg->param('CONFFILE'); }
  if ($cfg->param('LOGFILE')) { $LogFile = $cfg->param('LOGFILE'); }
  if ($cfg->param('LOGLEVEL')) { $LogLevel = $cfg->param('LOGLEVEL'); }
}

LogThis("Getting channel list for server...", 4);
my $Target = 'https://discord.com/api' . '/guilds/' . $DiscordSvr . '/channels';
my $Res = WebGet($Target, {Authorization => "Bot $DiscordBot"});
if ($Res && $Res->is_success) {
  LogThis("Getting messages for channels...", 4);
  my $Messages;
  for my $Channel (@{DecodeJSON($Res->decoded_content)}) {
    if ($Channel->{type} == 0) {
      if ($LastInfo && $LastInfo->{$Channel->{id}}) {
        $Target = 'https://discord.com/api' . '/channels/' . $Channel->{id} .
          '/messages?after=' . $LastInfo->{$Channel->{id}};
        $Res = WebGet($Target, {Authorization => "Bot $DiscordBot"});
        if ($Res && $Res->is_success) {
          for my $Msg (@{DecodeJSON($Res->decoded_content)}) {
            my @Embeds;
            my $Author = $Msg->{author}->{username};
            for my $Embed (@{$Msg->{embeds}}) {
              push(@Embeds, $Embed->{description});
            }
            $Messages->{$Msg->{id}} = $Channel->{name} . ' ' .
              $Author . ': ' . join("\n", @Embeds);
          }
        } else {
          $Error = "Get messages failed. ($Channel->{name}, " . $Res->code .
            ', ' . $Res->message . ')';
        }
      }
      $LastInfo->{$Channel->{id}} = $Channel->{last_message_id};
    }
  }

  if (open(FILE, ">", $RunFile)) {
    print(FILE EncodeJSON($LastInfo));
    close(FILE);
  }

  LogThis("Posting messages...", 4);
  $Target = 'https://api.telegram.org/bot' . $TelegramBot . '/sendMessage';
  for my $Msg (sort keys %$Messages) {
    my $Values = { chat_id => $TelegramUsr, text => $Messages->{$Msg} };
    $Res = WebPostVals($Target, $Values);
    if (!$Res || !$Res->is_success) {
      $Error = "Post message failed. (" . $Res->code . ', ' .
        $Res->message . ')';
    }
  }
} else {
  $Error = "Get channels failed. (" . $Res->code . ', ' . $Res->message . ')';
}

if ($Error) { LogThis($Error, 2); } else { LogThis("Process completed.", 4); }

#------------------------------------------------------------------------------
sub WebPostVals {
  my ($Target, $Values, $Headers) = @_;

  # Content-Type is hard coded by UserAgent when posting :-(
  my $TheseHeaders = HTTP::Headers->new(
    'Accept'        => 'application/json',
    'Content-Type'  => 'application/x-www-form-urlencoded',
    );

  if ($Headers) {
    for my $Header (keys %$Headers) {
      $TheseHeaders->header($Header => $Headers->{$Header});
    }
  }

  my $UA = LWP::UserAgent->new();
  $UA->timeout(30);
  $UA->default_headers($TheseHeaders);

#  $UA->add_handler("request_send",  sub { shift->dump; return });
#  $UA->add_handler("response_done", sub { shift->dump; return });

  return $UA->post($Target, $Values);
}
#------------------------------------------------------------------------------
sub WebGet {
  my ($Target, $Headers) = @_;

  my $TheseHeaders = HTTP::Headers->new(
    'Accept'        => 'application/json',
    'Content-Type'  => 'application/json;charset=UTF-8',
    );

  if ($Headers) {
    for my $Header (keys %$Headers) {
      $TheseHeaders->header($Header => $Headers->{$Header});
    }
  }

  my $UA = LWP::UserAgent->new();
  $UA->timeout(30);
  $UA->default_headers($TheseHeaders);

  return $UA->get($Target);
}
#------------------------------------------------------------------------------
sub DecodeJSON {
  my ($Data, $Quiet) = @_;

  my $Result;
  if ($Data) {
    try {
      my $Coder = JSON::XS->new->allow_nonref->latin1;
      $Result = $Coder->decode($Data);
    } catch { LogThis("DecodeJSON: Error decoding data: $_", 2); };
  } elsif (!$Quiet) { LogThis("DecodeJSON: No JSON to decode!", 2); };

  return $Result;
}
#------------------------------------------------------------------------------
sub EncodeJSON {
  my ($Data) = @_;

  my $Result;
  try {
    my $Coder = JSON::XS->new->allow_nonref->latin1->allow_blessed(1);
    $Result = $Coder->encode($Data);
  } catch { LogThis("EncodeJSON: Error encoding data: $_", 2); };

  return $Result;
}
#------------------------------------------------------------------------------
sub LogThis {
  my ($Text, $Level) = @_;

  my $Levels = { 1 => 'FATAL', 2 => 'ERROR', 3 => ' WARN',
                 4 => ' INFO', 5 => 'DEBUG' };

  if (!$Level) { $Level = 4; }
  if ($Text && $Level <= $LogLevel) {
    my $Lines = '';
    my $Prefix = POSIX::strftime("%Y-%m-%dT%H:%M:%S [$Levels->{$Level}] ",
                                 localtime());
    for my $Line (split(/\n/, $Text)) { $Lines .= $Prefix . $Line . "\n"; }

    if ($LogFile) {
      try {
        if (open(LOG, ">>" . $LogFile)) {
          print(LOG $Lines);
          close(LOG);
        } else { print("Unable to open log file! ($Text)\n"); };
      } catch { print("Unable to to log to file! ($Text)\n"); };
    } else { print($Lines); }
  }

  if ($Level < 2 || $Level > 5) { exit($Level); }

  return undef;
}
#------------------------------------------------------------------------------
sub Help {
  # Print a helpful message when requested

  print STDERR <<"EO_Help";

usage: $0 [flags]

Where flags are these:

  Long       Short  Meaning
  --verbose     -v  Provide verbose output to STDOUT
  --help        -h  Print this message on STDERR

EO_Help
exit(0);
}
