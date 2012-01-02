# Advanced downloader from xdcc bot. Independent on bot's language
#
# Based on XDCCget by Stefan "tommie" Tomanek
#
# Copyright 2007-2011, savrus
# Dustributed under GNU GPL v2 or higher

use vars qw($VERSION %IRSSI);
$VERSION = "20110814";
%IRSSI = (
    authors     => "savrus",
    contact     => "http://code.google.com/p/xdccget",
    name        => "xdccget",
    description => "auto download from xdcc bot",
    license     => "GPLv2",
    changed     => "$VERSION",
    commands    => "xdccget"
);

use Irssi;
use vars qw(@g_queue $g_nick $g_gen @g_gen_queue $g_server $g_witem $g_timer $g_file);

sub show_help() {
    my $help="xdccget $VERSION
/xdccget queue Nickname  ...
    Queue the specified packs of the server 'Nickname'
/xdccget gen path_to_generator ...
    Executes external generator to receive server Nickname and packs, then queues them.
    Generator is also executed each time xdccget suspects of packlist shuffle.
    More than one generator can be given, in this case they form a queue.
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

    $time = time - $dcc->{starttime};
    if ($time eq 0) {
        print CLIENTCRAP "XDCCGET DEBUG: zero transfer time. Sending bot cancel message";
        message_stop();
    }

    if ($dcc->{transfd} == $dcc->{size}) {
        if (($file eq $g_file) or ($time eq 0)) {
            print CLIENTCRAP "XDCCGET DEBUG: shifting queue";

#           rename $dcc->{file}, "/ircdone/$file";
            $g_file = "";
            shift_queue($dcc->{nick});
        }
    }
    process_queue($dcc->{nick});
}

sub sig_dcc_get_receive {
    my ($dcc) = @_;
    my ($dir,$file) = $dcc->{file} =~ m,(.*)/(.*),;
    print CLIENTCRAP "XDCCGET DEBUG: get receive from $dcc->{nick} file $file";
    if (($dcc->{type} eq 'GET') and ($dcc->{nick} eq $g_nick)) {
        $g_file = $file;
    }
}

sub set_timer {
    my ($timeout, $handler) = @_;
    if ($g_timer) {
        #print CLIENTCRAP "XDCCGET CRITICAL: set timer while timer is activated. Removing old timer";
        #remove_timer();
        print CLIENTCRAP "XDCCGET CRITICAL: set timer while timer is activated. Keep old timer, set_timer is ignored";
        return;
    }
    print CLIENTCRAP "XDCCGET DEBUG: set timeout $timeout msec for '$handler'";
    $g_timer=Irssi::timeout_add($timeout, $handler, undef);
}

sub remove_timer {
    if ($g_timer) {
        Irssi::timeout_remove($g_timer);
        $g_timer = 0;
    }
}

sub cmd_xdccget {
    my ($args, $server, $witem) = @_;
    $args =~ s/^\s+//;
    my @arg = split(/\s+/, $args);

    if ($arg[0] eq 'queue'){
        shift @arg;
        initialize_queue("@arg", $server, $witem);
    }
    elsif ($arg[0] eq 'gen'){
        shift @arg;
        initialize_gen("@arg", $server, $witem);
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
    elsif ($arg[0]) {
        print CLIENTCRAP "xdccget: unknown command '$arg[0]'";
    }
    else {
        print CLIENTCRAP "xdccget: $g_nick @g_queue";
        print CLIENTCRAP "xdccget remained generators: @g_gen_queue";
        if ($g_timer) {
            print CLIENTCRAP "XDCCGET DEBUG: timer is set";
        } else {
            print CLIENTCRAP "XDCCGET DEBUG: timer is not set";
        }
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
    remove_timer();
    if ($g_nick) {
        $g_file = "";
        message_stop();
        $nick = $g_nick;
        $g_nick = "";
        print CLIENTCRAP "XDCCGET DEBUG: forcing dcc transfer to stop";
        $g_server->command("DCC close get $nick");
        $g_nick = $nick
    }
}

sub transfer_after_init {
    my ($oldnick) = @_;
    if ($oldnick eq $g_nick) {
        print CLIENTCRAP "XDCCGET DEBUG: initializing for the same nick ($oldnick). Will wait to avoid flooding";
        process_queue();
    } else {
        transfer();
    }
}


sub initialize_queue {
    my ($args, $server, $witem) = @_;
    my @args = split(/\s+/, $args);

    $oldnick = $g_nick;
    clean();

    $g_gen = 0;
    $g_nick = $args[0];
    shift @args;
    @g_queue = @args;
    $g_server = $server;
    $g_witem = $witem;
    
    while ((@g_queue[0] <= 0) && (scalar @g_queue > 0)) {
        shift @g_queue;
    }
    transfer_after_init($oldnick);
}

sub update_queue_by_gen {
    if ($g_gen) {
        $packs = `$g_gen 2>/dev/null`;
        $packs =~ s/^\s+//;
        @packs = split(/\s+/,$packs);
        $g_nick = @packs[0];
        shift @packs;
        print CLIENTCRAP "XDCCGET DEBUG: gen queue $g_nick @packs";
        @g_queue = @packs;
    }
}

sub process_gen_queue() {
    if ($g_gen and $g_gen_queue[0]) {
        # wait to avoid clean() after zero-sized transfer and other crap
        set_timer(60*1000, 'activate_new_generator');
    } else {
        print CLIENTCRAP "XDCCGET DEBUG: no generator to continue";
    }
}

sub activate_new_generator {
    print CLIENTCRAP "XDCCGET DEBUG: processing gen queue";
    $oldnick = $g_nick;
    clean();
    $g_gen = $g_gen_queue[0];
    shift @g_gen_queue;
    if ($g_gen) {
        print CLIENTCRAP "XDCCGET DEBUG: working with generator '$g_gen'";
        update_queue_by_gen();
        transfer_after_init($oldnick)
    } else {
        print CLIENTCRAP "XDCCGET DEBUG: no generator to continue";
    }
}

sub initialize_gen {
    my ($args, $server, $witem) = @_;
    @g_gen_queue = split(/\s+/, $args);

    $g_server = $server;
    $g_witem = $witem;

    activate_new_generator();
}
 
sub process_queue {
    if ( $g_timer ) {
        #print CLIENTCRAP "XDCCGET CRITICAL: process queue while timer is activated. Removing old timer";
        #remove_timer();
        print CLIENTCRAP "XDCCGET CRITICAL: process queue while timer is activated. Keep old timer, process_queue is ignored.";
        return;
    }
    if (scalar @g_queue > 0) {
        set_timer(60*1000, 'transfer');
    } else {
        print CLIENTCRAP "XDCCGET DEBUG: packs queue ended";
        process_gen_queue();
    }
}    

sub message_stop {
    $nick = $g_nick;
    $g_nick = "";
    $g_server->command("MSG $nick xdcc remove");
    $g_server->command("MSG $nick xdcc cancel");
    $g_nick = $nick;
}

sub transfer {
    remove_timer();
    if (scalar @g_queue > 0) {
        message_stop();
        $g_server->command("MSG $g_nick xdcc send @g_queue[0]");
    } else {
        print CLIENTCRAP "XDCCGET DEBUG: empty packs queue";
        process_gen_queue();
    }
}

sub add_to_queue {
    my (@args) = @_;
    push @g_queue, @args;
    if ((not $g_timer) and (not $g_file)) {
        transfer();
    }
}

sub dell_from_queue {
    pop @g_queue;
    if ((scalar @g_queue eq 0) and ($g_file)) {
        pause();
    }
}

sub resume_hard {
    pause();
    update_queue_by_gen();
    resume();
}

sub wait_resume_hard {
    remove_timer();
    if ($g_nick) {
        set_timer(5*60*1000, 'resume_hard');
    }
}

Irssi::signal_add_last('dcc get receive', 'sig_dcc_get_receive');
Irssi::signal_add_last('dcc closed', 'sig_dcc_closed');

sub sig_server_connected {
    my ($server) = @_;
    $g_server = $server;
    print CLIENTCRAP "XDCCGET DEBUG: server connected $server";
    wait_resume_hard();
}

Irssi::signal_add('server connected', 'sig_server_connected');

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
        print CLIENTCRAP "XDCCGET DEBUG: $nick joined channel";
        wait_resume_hard();
    }
}
Irssi::signal_add_last('message join', 'sig_message_join');


Irssi::command_bind('xdccget', \&cmd_xdccget);

print CLIENTCRAP '%B>>%n '.$IRSSI{name}.' '.$VERSION.' loaded';

