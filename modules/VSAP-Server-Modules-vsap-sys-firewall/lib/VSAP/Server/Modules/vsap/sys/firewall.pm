package VSAP::Server::Modules::vsap::sys::firewall;

use 5.008004;
use strict;
use warnings;

use VSAP::Server::Modules::vsap::logger;

our $VERSION = '0.1';

our %_ERR = (
    ERR_NOTAUTHORIZED => 100,
    ERR_NOTSUPPORTED  => 101,
    ERR_MISSING_FIELD => 102,
    ERR_INVALID_FIELD => 103,
    ERR_PLATFORM      => 104,
);

our $fwlevelsDir = "/etc/fwlevels";

##############################################################################

sub _do_set_fwlevel
{
    my($vsap, $level, $type) = @_;

    local $> = $) = 0;  ## regain privileges for a moment
    if ($vsap->is_cloud) {
        &_do_reset_firewall($vsap);

        # Stop the iptables service if it's running
        if (system("service iptables status >/dev/null 2>&1") == 0 ||
            system("ps -e | grep iptables >/dev/null 2>&1") == 0) {
            system "service iptables stop >/dev/null 2>&1";
        }

        # Create the first part of the rules config file
        my $defaultPolicy = $level <= 1 ? "ACCEPT" : "DROP";
        my $serverType =
            $type eq 'm' ? "mail server" :
            $type eq 'w' ? "web server" :
            "web and mail server";

        my @rules = ("# Generated by _do_set_fwlevel",
                     "# Do not remove the following 2 lines",
                     "# securityLevel=$level",
                     "# serverCode=" . ($type || ''),
                     "# Rule set for a $serverType",
                     "",
                     "*filter",
                     ":INPUT $defaultPolicy [0:0]",
                     ":FORWARD $defaultPolicy [0:0]",
                     ":OUTPUT ACCEPT [0:0]",
                     "");

        # The header files create specialized chains
        if ($level == 1) {
            push @rules, &_read_rules("iptables.1.h");
        } elsif ($level > 1) {
            push @rules, &_read_rules("iptables.2.h");
        }

        # Let's create the rules that are common to all rule sets
        push @rules, &_read_rules("iptables.0");
        push @rules, &_read_rules("iptables.1")
            if $level > 0;

        # Add the fules for higher rule sets
        if ($level > 1) {
            if ($type) {
                push @rules, &_read_rules("iptables.$level.$type");
            } else {
                push @rules, &_read_rules("iptables.$level.m");
                push @rules, &_read_rules("iptables.$level.w");
            }
            # put the common rules in place
            push @rules, &_read_rules("iptables.$level.c");
        }

        # Put the final rules in place
        push @rules, &_read_rules("iptables.f");

        # Write the rules file
        open my $rfh, '>', '/etc/sysconfig/iptables';
        grep print($rfh "$_\n"), @rules;
        close $rfh
            or return "write iptables: $!";

        # Start iptables up again
        system("service iptables start >$fwlevelsDir/error 2>&1") == 0
            or return "iptables start, exit code" . ($? >> 8);
    } else {
        system('/usr/local/sbin/set_fwlevel', $level, $type) == 0
            or return "exit code" . ($? >> 8);
    }
    return;
}

sub _read_rules
{
    my($fname) = @_;

    open my $rfh, "$fwlevelsDir/$fname";
    my @rules = <$rfh>;
    chomp @rules;
    close $rfh;
    return @rules;
}

##############################################################################

sub _do_reset_firewall
{
    my($vsap) = @_;

    local $> = $) = 0;  ## regain privileges for a moment
    if ($vsap->is_cloud) {
        # Save rules in a format that shows command-line args
        my $backupdir = "/root/.iptables";
        mkdir $backupdir, 0700;
        my $ext;
        for ($ext = 0; -e "$backupdir/iptablesBK.$ext"; $ext++) {}
        my $backup_file = "$backupdir/iptablesBK.$ext";
        my $save_cmd = "iptables-save > $backup_file";
        system($save_cmd) == 0
            or return "iptables-save, exit code" . ($? >> 8);
        chmod 0600, $backup_file;

        # Flush all tables and chains
        system("iptables -t filter -F") == 0
            && system("iptables -t filter -X") == 0
            && system("iptables -t nat -F") == 0
            && system("iptables -t nat -X") == 0
            && system("iptables -t mangle -F") == 0
            && system("iptables -t mangle -X") == 0
            or return "iptables flush, exit code" . ($? >> 8);

        # Insure table/chain policies are set to ACCEPT
        system("iptables -t filter -P INPUT ACCEPT") == 0
            && system("iptables -t filter -P OUTPUT ACCEPT") == 0
            && system("iptables -t filter -P FORWARD ACCEPT") == 0
            && system("iptables -t nat -P PREROUTING ACCEPT") == 0
            && system("iptables -t nat -P POSTROUTING ACCEPT") == 0
            && system("iptables -t nat -P OUTPUT ACCEPT") == 0
            && system("iptables -t mangle -P PREROUTING ACCEPT") == 0
            && system("iptables -t mangle -P POSTROUTING ACCEPT") == 0
            && system("iptables -t mangle -P INPUT ACCEPT") == 0
            && system("iptables -t mangle -P OUTPUT ACCEPT") == 0
            && system("iptables -t mangle -P FORWARD ACCEPT") == 0
            or return "iptables accept exit code" . ($? >> 8);

        # Continue to block IRC ports even when "off"
        system("iptables -A OUTPUT -p tcp --dport 6660:6669 -j DROP") == 0
            or return "iptables block IRC, exit code" . ($? >> 8);

        # Back up the current config file
        my $configdir = "/etc/sysconfig";
        for ($ext = 0; -e "$configdir/iptables.bk.$ext"; $ext++) {}
        rename "$configdir/iptables", "$configdir/iptables.bk.$ext";
    } else {
        system('/usr/local/sbin/reset_firewall') == 0
            or return "exit code" . ($? >> 8);
    }
    return;
}

##############################################################################

package VSAP::Server::Modules::vsap::sys::firewall::get;

sub handler
{
    my $vsap   = shift;
    my $xmlobj = shift;
    my $dom    = shift || $vsap->{_result_dom};

    my $root = $dom->createElement('vsap');
    $root->setAttribute(type => 'sys:firewall:get');

    ## check for server type
    unless ($vsap->is_linux() or $vsap->is_freebsd6()) {
        $vsap->error($_ERR{ERR_NOTSUPPORTED} => "Not supported on this platform");
        return;
    }

    ## check for server admin
    unless ($vsap->{server_admin}) {
        $vsap->error($_ERR{ERR_NOTAUTHORIZED} => "Not authorized to set firewall");
        return;
    }

    ## get firewall
    my $level = '0';
    my $type = '';
    my $ipt_limit = 0;  # note: 0 == unlimited

    my $file;
    if($vsap->is_linux()) {
      $file = "/etc/sysconfig/iptables";
    }
    elsif($vsap->is_freebsd6()) {
      if(-e "/etc/ipf6.rules") {
        $file = "/etc/ipf6.rules";
      }
      else {
        $file = "/etc/ipf.rules";
      }
    }

    if (-e $file) {
        REWT: {
            local $> = $) = 0;  ## regain privileges for a moment
            if (open INFILE, $file) {
                while( <INFILE> ) {
                    $level = $1 if (/securityLevel=(.*)$/);
                    $type = $1 if (/serverCode=(.*)$/);
                }
                close INFILE;
            }
        }
    }

    ## check allowance (limit of IPtable entries)
    REWT: {
        local $> = $) = 0;  ## regain privileges for a moment
        if ($vsap->is_cloud()) {
            # do nothing (no ip table limit)
        }
        elsif ($vsap->is_linux()) {
            my @dump = `cat /proc/user_beancounters`;
            my $numiptent = (grep(/numiptent/, @dump))[0];
            $numiptent =~ s/\s+/:/g;
            $ipt_limit = (split(/:/, $numiptent))[4] || 0;
        }
        else {
            my @dump = `/usr/local/sbin/sinfo`;
            my $numiptent = (grep(/numiptent/, @dump))[0];
            $numiptent =~ s/\s+//g;
            $ipt_limit = (split(/:/, $numiptent))[1] || 0;
        }
    }

    $root->appendTextChild('level', $level);
    $root->appendTextChild('type', $type);
    my $rules_node = $root->appendChild($dom->createElement('rules'));
    $rules_node->appendTextChild('limit', $ipt_limit);
    if ($ipt_limit) {
        # run the following commands to get low rule count
        #
        #   /usr/local/sbin/set_fwlevel 1
        #
        #   linux: grep -ce '^[:-]' /etc/sysconfig/iptables
        #   fbsd6: grep -cve '^\s*$\|^#' /etc/ipf.rules
        #
        my $low_count = ($vsap->is_linux()) ? 39 : 25;
        $rules_node->appendTextChild('low', $low_count);

        # run the following commands to get medium rule count
        #
        #   /usr/local/sbin/set_fwlevel 2
        #
        #   linux: grep -ce '^[:-]' /etc/sysconfig/iptables
        #   fbsd6: grep -cve '^\s*$\|^#' /etc/ipf.rules
        #
        my $medium_count = ($vsap->is_linux()) ? 74 : 63;
        $rules_node->appendTextChild('medium', $medium_count);

        # run the following commands to get high rule count
        #
        #   /usr/local/sbin/set_fwlevel 3
        #
        #   linux: grep -ce '^[:-]' /etc/sysconfig/iptables
        #   fbsd6: grep -cve '^\s*$\|^#' /etc/ipf.rules
        #
        my $high_count = ($vsap->is_linux()) ? 65 : 51;
        $rules_node->appendTextChild('high', $high_count);
    }

    $dom->documentElement->appendChild($root);
    return;
}

##############################################################################

package VSAP::Server::Modules::vsap::sys::firewall::reset;

sub handler
{
    my $vsap   = shift;
    my $xmlobj = shift;
    my $dom    = shift || $vsap->{_result_dom};

    my $root = $dom->createElement('vsap');
    $root->setAttribute(type => 'sys:firewall:reset');

    ## check for server type
    unless ($vsap->is_linux() or $vsap->is_freebsd6()) {
        $vsap->error($_ERR{ERR_NOTSUPPORTED} => "Not supported on this platform");
        return;
    }

    ## check for server admin
    unless ($vsap->{server_admin}) {
        $vsap->error($_ERR{ERR_NOTAUTHORIZED} => "Not authorized to reset firewall");
        return;
    }

    ## reset firewall
    my $e = VSAP::Server::Modules::vsap::sys::firewall::_do_reset_firewall($vsap);
    if ($e) {
        warn ("_do_reset_firewall failed ($e)");
        $vsap->error($_ERR{'ERR_PLATFORM'} => "reset failed: $e");
    }

    # add a trace to the message log
    VSAP::Server::Modules::vsap::logger::log_message("$vsap->{username} reset firewall");

    $dom->documentElement->appendChild($root);
    return;
}

##############################################################################

package VSAP::Server::Modules::vsap::sys::firewall::set;

sub handler
{
    my $vsap   = shift;
    my $xmlobj = shift;
    my $dom    = shift || $vsap->{_result_dom};

    my $level = ( $xmlobj->child('level')
                  && length $xmlobj->child('level')->value
                  ? $xmlobj->child('level')->value
                  : '' );

    my $type = ( $xmlobj->child('type')
                 && $xmlobj->child('type')->value
                 ? $xmlobj->child('type')->value
                 : '' );

    my $root = $dom->createElement('vsap');
    $root->setAttribute(type => 'sys:firewall:set');

    ## check for server type
    unless ($vsap->is_linux() or $vsap->is_freebsd6()) {
        $vsap->error($_ERR{ERR_NOTSUPPORTED} => "Not supported on this platform");
        return;
    }

    ## check for server admin
    unless ($vsap->{server_admin}) {
        $vsap->error($_ERR{ERR_NOTAUTHORIZED} => "Not authorized to set firewall");
        return;
    }

    ## check for level
    unless (length $level) {
      $vsap->error($_ERR{ERR_MISSING_FIELD} => "Empty or missing level");
      return;
    }

    ## validate level
    unless ($level =~ /^[0-3]$/) {
        $vsap->error($_ERR{ERR_INVALID_FIELD} => "Invalid value for level");
        return;
    }

    ## validate type
    unless ($type =~ /^[wm]?$/) {
        $vsap->error($_ERR{ERR_INVALID_FIELD} => "Invalid value for type");
        return;
    }

    ## set firewall
    my $e = VSAP::Server::Modules::vsap::sys::firewall::_do_set_fwlevel($vsap, $level, $type);
    if ($e) {
        warn ("_do_set_fwlevel failed ($e)");
        $vsap->error($_ERR{'ERR_PLATFORM'} => "set failed: $e");
    }

    # add a trace to the message log
    my $args = "level => $level";
    $args .= ", type => $type" if ($type);
    VSAP::Server::Modules::vsap::logger::log_message("$vsap->{username} changed firewall level ($args)");


    $root->appendTextChild('level', $level);
    $root->appendTextChild('type', $type) if ($type);

    $dom->documentElement->appendChild($root);
    return;
}

##############################################################################

1;
__END__

=head1 NAME

VSAP::Server::Modules::vsap::sys::firewall - Perl extension to manage system firewall

=head1 SYNOPSIS

use VSAP::Server::Modules::vsap::sys::firewall;

=head2 sys:firewall:get

call:
 <vsap type="sys:firewall:get"/>

return:
 <vsap type="sys:firewall:get">
  <level>0</level>
  <type>w</type>
  <rules>
   <limit>0</limit>
  </rules>
 </vsap>

=head2 sys:firewall:set

call:
 <vsap type="sys:firewall:set">
  <level>3</level>
  <type>w</type>
 </vsap>

return:
 <vsap type="sys:firewall:set">
  <level>3</level>
  <type>w</type>
 </vsap>

=head 2sys:firewall:reset

call:
 <vsap type="sys:firewall:reset"/>

return:
 <vsap type="sys:firewall:reset"/>

=head1 DESCRIPTION

Package providing the vsap methods to manage the system firewall.

=head2 sys:firewall:get

Gets the current system firewall level. The platform currently supports packaged firewall rules:
  0 = Off, 1 = Low, 2 = Medium, 3 = High
Also, gets the current system firewall type. The platform currently supports:
  w = Web Server Only, m = Mail Server Only, <empty> = Web & Mail Servers

=head2 sys:firewall:set

Sets the system firewall level. The platform currently supports packaged firewall rules:
  0 = Off, 1 = Low, 2 = Medium, 3 = High
Can be called with an optional server type parameter. The platform currently supports:
  w = Web Server Only, m = Mail Server Only

=head2 sys:firewall:reset

Resets all firewall rules in the event that the current settings has locked out
the account.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by MYNAMESERVER, LLC

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.4 or,
at your option, any later version of Perl 5 you may have available.

=cut
