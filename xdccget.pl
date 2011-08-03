#  2007, savrus
#
# Advanced downloader from xdcc bot. Independent on bot's language
#
# Based on XDCCget by Stefan "tommie" Tomanek
#
# Dustributed under GNU GPL v2 or higher

use vars qw($VERSION %IRSSI);
$VERSION = "20070321";
%IRSSI = (
    authors     => "savrus",
    contact     => "go to hell",
    name        => "xdccget",
    description => "auto download from xdcc bot",
    license     => "GPLv2",
    changed     => "$VERSION",
    commands    => "xdccget"
);

use Irssi;
use vars qw(@g_queue $g_nick $g_server $g_witem $g_timer);

sub show_help() {
    my $help="xdccget $VERSION
/xdccget queue Nickname  ...
    Queue the specified packs of the server 'Nickname'
/xdccget help
    Display this help
";
    print CLIENTCRAP $help;
}

sub sig_dcc_closed {
    my ($dcc) = @_;
    my ($dir,$file) = $dcc->{file} =~ m,(.*)/(.*),;

    return unless $dcc->{type} eq 'GET';
    return unless $dcc->{nick} eq $g_nick;

    if ($dcc->{transfd} < $dcc->{size}) {
        process_queue($dcc->{nick});
    }
    else {
#        rename $dcc->{file}, "/ircdone/$file";
        shift_queue($dcc->{nick});
        process_queue($dcc->{nick});
    }
}

sub cmd_xdccget {
    my ($args, $server, $witem) = @_;
    my @arg = split(/ /, $args);

    if ($arg[0] eq 'queue'){
        shift @arg;
        initialize_queue("@arg", $server, $witem);
    }
    elsif ($arg[0] eq 'add'){
        shift @arg;
        add_to_queue(@arg);
    }
    elsif ($arg[0] eq 'del'){
        dell_from_queue();
    }
    elsif ($arg[0] eq 'pause'){
        pause();
    }
    elsif ($arg[0] eq 'resume'){
        resume();
    }
    elsif ($arg[0] eq 'help') {
        show_help();
    }
    else {
        print CLIENTCRAP "xdccget: $g_nick @g_queue";
    }
}

sub pause {
    $nick = $g_nick;
    clean();
    $g_nick = $nick;
}

sub resume {
    process_queue();
}

sub shift_queue {
    shift @g_queue;
}

sub clean {
# Clean previous job
    if ($g_nick) {
        my $nick = $g_nick;
        $g_server->command("MSG $g_nick xdcc remove");
        $g_nick = "";
        $g_server->command("DCC close get $nick");
    }
    if ($g_timer) {
        Irssi::timeout_remove($g_timer);
    }
}

sub initialize_queue {
    my ($args, $server, $witem) = @_;
    my @args = split(/ /, $args);

    clean();

    $g_nick = $args[0];
    shift @args;
    @g_queue = @args;
    $g_server = $server;
    $g_witem = $witem;
    
    process_queue();
}
 
sub process_queue {
    while ((@g_queue[0] <= 0) && (scalar @g_queue > 0)) {
        shift @g_queue;
    }
    if (scalar @g_queue > 0) {
        $g_timer=Irssi::timeout_add(60 * 1000, 'transfer', undef);
    }
}    

sub transfer {
    Irssi::timeout_remove($g_timer);
    $g_server->command("MSG $g_nick xdcc send @g_queue[0]");
}

sub add_to_queue {
    my (@args) = @_;
    push @g_queue, @args;
}

sub dell_from_queue {
    pop @g_queue;
}

Irssi::signal_add('dcc closed', 'sig_dcc_closed');
#
# TODO: handle rejoining the channel (self disconnection + auto reconnection)
# Be careful: content may be changed in such situation.
#
#Irssi::signal_add('channel joined', 'sig_channel_joined');


## Used in a modified script for a bot that was always disconnecting from the channel.
## But be careful - usually this happens when bot owner shuffles the packlist

sub sig_message_join {
    my ($server, $channel, $nick, $addr) = @_;
    if ($nick eq $g_nick){
        print CLIENTCRAP "XDCCGET DEBUG: $nick joined channel (wait for $g_nick)";
        $g_server->command("MSG $g_nick xdcc remove");
        $g_server->command("DCC close get $g_nick");
        if ($g_timer) {
            Irssi::timeout_remove($g_timer);
        }
        resume();
    }
}
Irssi::signal_add_last('message join', 'sig_message_join');


Irssi::command_bind('xdccget', \&cmd_xdccget);

print CLIENTCRAP '%B>>%n '.$IRSSI{name}.' '.$VERSION.' loaded';

