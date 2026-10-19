#!/bin/bash
set -euo pipefail

ROOT=/root/qf-edge-iso/initrd-check/installer-root
OUT="$ROOT/usr/bin/quikefix-preinstaller"
V1="$OUT.V1-NONDESTRUCTIVE"

[ -d "$ROOT" ] || { echo "FAIL: installer root missing"; exit 1; }
[ -f "$V1" ] || { echo "FAIL: protected V1 backup missing"; exit 1; }

cat >"$OUT" <<'PERL'
#!/usr/bin/perl
use strict;
use warnings;
use Gtk3 '-init';
use JSON qw(decode_json);

my $udev_file = '/run/proxmox-installer/run-env-udev.json';
my $media_file = '/run/quikefix-installer-media-source';
my $answer_file = '/run/automatic-installer-answers';
my $selected_file = '/run/quikefix-selected-disk';
my $success = 0;

sub fatal {
    my ($msg) = @_;
    my $d = Gtk3::MessageDialog->new(undef, ['modal'], 'error', 'close', $msg);
    $d->run; $d->destroy; exit 1;
}

sub sh_capture {
    my (@cmd) = @_;
    open my $p, '-|', @cmd or return '';
    local $/; my $v = <$p> // ''; close $p; chomp $v; return $v;
}

sub parent_disk {
    my ($dev) = @_;
    return '' if !$dev || $dev !~ m{^/dev/([^/]+)$};
    my $name = $1;
    my $type = sh_capture('/usr/bin/lsblk','-dnro','TYPE',$dev);
    return $dev if $type eq 'disk';
    my $pk = sh_capture('/usr/bin/lsblk','-dnro','PKNAME',$dev);
    return $pk ? "/dev/$pk" : '';
}

sub toml_quote {
    my ($v) = @_;
    $v =~ s/\\/\\\\/g; $v =~ s/"/\\"/g;
    return '"'.$v.'"';
}

-f $udev_file or fatal('QuikeFix Edge could not read the installer disk inventory.');
open my $fh, '<', $udev_file or fatal('Unable to open disk inventory.');
local $/; my $raw = <$fh>; close $fh;
my $data = eval { decode_json($raw) };
fatal('Invalid installer disk inventory.') if !$data || ref($data->{disks}) ne 'HASH';

my $installer_media = '';
if (-f $media_file) {
    open my $mf, '<', $media_file or fatal('Unable to read installer-media protection marker.');
    $installer_media = <$mf> // ''; close $mf; chomp $installer_media;
}
my $protected_disk = parent_disk($installer_media);

my @rows;
my %short_count;
my %serial_count;
for my $idx (keys %{$data->{disks}}) {
    my $u = $data->{disks}{$idx} || {};
    $short_count{$u->{ID_SERIAL_SHORT}}++ if defined($u->{ID_SERIAL_SHORT}) && length($u->{ID_SERIAL_SHORT});
    $serial_count{$u->{ID_SERIAL}}++ if defined($u->{ID_SERIAL}) && length($u->{ID_SERIAL});
}

for my $idx (sort { $a <=> $b } keys %{$data->{disks}}) {
    my $u = $data->{disks}{$idx} || {};
    my $dev = $u->{DEVNAME} // '';
    next if !$dev;
    next if $protected_disk && parent_disk($dev) eq $protected_disk;

    my ($filter_key,$filter_value);
    if (($u->{ID_SERIAL_SHORT}//'') ne '' && ($short_count{$u->{ID_SERIAL_SHORT}}//0) == 1) {
        ($filter_key,$filter_value)=('ID_SERIAL_SHORT',$u->{ID_SERIAL_SHORT});
    } elsif (($u->{ID_SERIAL}//'') ne '' && ($serial_count{$u->{ID_SERIAL}}//0) == 1) {
        ($filter_key,$filter_value)=('ID_SERIAL',$u->{ID_SERIAL});
    } else {
        next;
    }

    my $model = $u->{ID_MODEL_FROM_DATABASE} // $u->{ID_MODEL} // 'Unknown Disk';
    my $serial = $u->{ID_SERIAL_SHORT} // $u->{ID_SERIAL} // 'Not available';
    my $bus = uc($u->{ID_BUS} // 'DISK');
    my $bytes=0;
    if ($dev =~ m{^/dev/([^/]+)$}) {
        if (open my $sf,'<',"/sys/class/block/$1/size") {
            my $sectors=<$sf>//0; close $sf; chomp $sectors;
            $bytes=$sectors*512 if $sectors =~ /^\d+$/;
        }
    }
    my $size=$bytes>=1024**4 ? sprintf('%.2f TB',$bytes/1024**4)
            : $bytes>=1024**3 ? sprintf('%.1f GB',$bytes/1024**3) : 'Unknown size';
    push @rows,{dev=>$dev,model=>$model,serial=>$serial,bus=>$bus,size=>$size,
                filter_key=>$filter_key,filter_value=>$filter_value};
}

fatal('No safe eligible installation disks were detected. Installer media and disks without a unique stable serial are protected.') if !@rows;

my $window=Gtk3::Window->new('toplevel');
$window->set_title('QuikeFix Edge Installation');
$window->set_default_size(820,540); $window->set_position('center'); $window->set_border_width(24);
$window->signal_connect(delete_event=>sub { Gtk3->main_quit; return 0; });
my $main=Gtk3::Box->new('vertical',14); $window->add($main);
my $title=Gtk3::Label->new; $title->set_markup('<span size="xx-large" weight="bold">QUIKEFIX EDGE SYSTEM</span>'); $title->set_xalign(0); $main->pack_start($title,0,0,0);
my $subtitle=Gtk3::Label->new('Select the storage device where QuikeFix Edge will be installed.'); $subtitle->set_xalign(0); $main->pack_start($subtitle,0,0,0);
my $warning=Gtk3::Label->new; $warning->set_markup('<span weight="bold">The selected disk will be erased during installation. Installer media is automatically protected.</span>'); $warning->set_xalign(0); $warning->set_line_wrap(1); $main->pack_start($warning,0,0,0);

my $store=Gtk3::ListStore->new(('Glib::String') x 7);
for my $r (@rows) { my $it=$store->append; $store->set($it,0=>$r->{model},1=>$r->{size},2=>$r->{serial},3=>$r->{bus},4=>$r->{dev},5=>$r->{filter_key},6=>$r->{filter_value}); }
my $tree=Gtk3::TreeView->new($store); $tree->set_headers_visible(1); $tree->get_selection->set_mode('single');
for my $c (['Storage Device',0],['Capacity',1],['Serial',2],['Connection',3]) { my($n,$i)=@$c; my $r=Gtk3::CellRendererText->new; my $col=Gtk3::TreeViewColumn->new_with_attributes($n,$r,text=>$i); $col->set_resizable(1); $tree->append_column($col); }
my $scroll=Gtk3::ScrolledWindow->new; $scroll->set_policy('automatic','automatic'); $scroll->add($tree); $main->pack_start($scroll,1,1,0);
my $status=Gtk3::Label->new('Choose one disk to continue.'); $status->set_xalign(0); $main->pack_start($status,0,0,0);
my $buttons=Gtk3::Box->new('horizontal',10); $main->pack_end($buttons,0,0,0);
my $continue=Gtk3::Button->new_with_label('Continue'); $continue->set_sensitive(0); $buttons->pack_end($continue,0,0,0);
my $cancel=Gtk3::Button->new_with_label('Cancel'); $buttons->pack_end($cancel,0,0,0);
$cancel->signal_connect(clicked=>sub { Gtk3->main_quit; });
$tree->get_selection->signal_connect(changed=>sub { my($s)=@_; my($m,$it)=$s->get_selected; if($it){$status->set_text('Selected: '.$m->get($it,0).' | '.$m->get($it,1).' | Serial: '.$m->get($it,2));$continue->set_sensitive(1)}else{$continue->set_sensitive(0)} });

$continue->signal_connect(clicked=>sub {
    my($m,$it)=$tree->get_selection->get_selected; return if !$it;
    my($name,$size,$serial,$dev,$fk,$fv)=map {$m->get($it,$_)} (0,1,2,4,5,6);
    my $d=Gtk3::MessageDialog->new($window,['modal'],'warning','yes-no',
        "FINAL STORAGE CONFIRMATION\n\n$name\nCapacity: $size\nSerial: $serial\n\nAll data on this selected disk will be erased when installation starts.\n\nContinue?");
    my $resp=$d->run; $d->destroy; return if $resp ne 'yes';

    # Revalidate that the exact stable identifier still maps to exactly one installer-recognized disk.
    my $matches=0;
    for my $idx (keys %{$data->{disks}}) { my $u=$data->{disks}{$idx}||{}; $matches++ if defined($u->{$fk}) && $u->{$fk} eq $fv; }
    fatal('Safety validation failed: selected disk identity is no longer unique.') if $matches != 1;
    fatal('Safety validation failed: installer media cannot be selected.') if $protected_disk && parent_disk($dev) eq $protected_disk;

    my $password=sh_capture('/usr/bin/python3','-c','import secrets; print(secrets.token_urlsafe(36))');
    fatal('Unable to generate temporary installation credential.') if !$password;
    my $hash='';
    if (open my $ph,'|-','/usr/bin/openssl','passwd','-6','-stdin') { print {$ph} "$password\n"; close $ph; }
    # Capture without command-line password exposure using a temporary 0600 pipe file instead.
    my $tmp='/run/quikefix-temp-password';
    open my $tf,'>',$tmp or fatal('Unable to prepare temporary credential.'); chmod 0600,$tmp; print {$tf} "$password\n"; close $tf;
    $hash=sh_capture('/usr/bin/openssl','passwd','-6','-in',$tmp); unlink $tmp; $password='';
    fatal('Unable to hash temporary installation credential.') if $hash !~ /^\$6\$/;

    open my $af,'>',$answer_file or fatal('Unable to create installation configuration.'); chmod 0600,$answer_file;
    print {$af} "[global]\nkeyboard = \"en-us\"\ncountry = \"za\"\nfqdn = \"edge.local\"\nmailto = \"support\@quikefix.com\"\ntimezone = \"Africa/Johannesburg\"\nroot-password-hashed = ".toml_quote($hash)."\n\n[first-boot]\nsource = \"from-iso\"\nordering = \"network-online\"\n\n[network]\nsource = \"from-dhcp\"\n\n[disk-setup]\nfilesystem = \"ext4\"\nfilter.$fk = ".toml_quote($fv)."\n";
    close $af;
    open my $sf,'>',$selected_file or fatal('Unable to record selected disk.'); chmod 0600,$selected_file; print {$sf} "$dev\n"; close $sf;
    $success=1; Gtk3->main_quit;
});

$window->show_all; Gtk3->main;
exit($success ? 0 : 2);
PERL

chmod 0755 "$OUT"

echo "======================================================"
echo " QUIKEFIX EDGE PREINSTALLER V2 - BUILD"
echo "======================================================"
ls -lh "$OUT"
sha256sum "$OUT"

echo
echo "=== SAFETY CHECK ==="
if grep -nE '\b(dd|wipefs|sgdisk|mkfs|pvremove|zpool|parted|fdisk)\b' "$OUT"; then
  echo "FAIL: destructive command found in V2 preinstaller"
  exit 1
fi
echo "PASS: no direct destructive disk command in V2 preinstaller"

echo
echo "=== REQUIRED FEATURES ==="
grep -q 'quikefix-installer-media-source' "$OUT"
grep -q 'ID_SERIAL_SHORT' "$OUT"
grep -q 'automatic-installer-answers' "$OUT"
grep -q 'FINAL STORAGE CONFIRMATION' "$OUT"
echo "PASS: media protection, unique serial selection, confirmation and dynamic answer generation present"

echo
echo "PASS: V2 generated. Installer handoff is NOT patched by this stage."
