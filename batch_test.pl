#!/usr/bin/perl -w
# batch_test.pl

# ������  08.00
# ��������� (�������� ������������)

use strict;
use bytes;
use Encode;
use SSRP;
use DBI;
use Socket;
use Tk;
use Tk::Table;
use Tk::TableMatrix;
use Tk::Dialog;
use Tk::Balloon;
use IPC::SysV;
use IPC::Msg;
use AnyEvent;

# ������ ������� ������� ������ � �������: �����_������� => ������_�_��������
my $hide_char='X'; # ������ ������������ ��� ���������
my $skip_char='-'; # ������ ������������ ��� ������ � ��������������
my $name_len=15; # ������ ����� "������� ����� ��������� ��� ������ � ��������
my $Ip='��!'; # ������ ��������� ��������� � �������������� �����
my $Sp='��!'; # ������ ��������� ��������� � ��������� �����
my $Rp='��!'; # ���������� �������
my $MaxRange='max'; # ����������� ����. ������� � ���

chomp(my $dir_name=$ENV{HOME});
$dir_name.='/cmk';
chdir $dir_name;
my $mysql_db=$dir_name=ltok($ENV{HOME});
unless ( -d '/mnt/Data/TestDescriptors' ) {
	system ('mkdir /mnt/Data/TestDescriptors'); system('chmod 0775 /mnt/Data/TestDescriptors') }
unless ( -d '/mnt/Data/CDfiles' ) {
	system ('mkdir /mnt/Data/CDfiles'); system('chmod 0775 /mnt/Data/CDfiles') }
unless ( -d "/mnt/Data/TestDescriptors/$dir_name") {
	system ("mkdir /mnt/Data/TestDescriptors/$dir_name"); system("chmod 0775 /mnt/Data/TestDescriptors/$dir_name") }
unless ( -d "/mnt/Data/CDfiles/$dir_name") {
	system ("mkdir /mnt/Data/CDfiles/$dir_name"); system("chmod 0775 /mnt/Data/CDfiles/$dir_name") }

# ��������� ini-�����
open (INI,'ssrp.ini');
my @err=<INI>;
close (INI);
my %INI=();
#my $log; if (substr($INI{log},16,1) eq '1') { $log=1; } else { $log=0 }
#my $log_trs; if (substr($INI{log},17,1) eq '1') { $log_trs=1; } else { $log_trs=0 }
my ($str,$hole,$name,$value);
foreach (@err) { 
	chomp;
	if (substr($_,0,1) eq '#') { next }
	if (!$_) { next }
	($str,$hole)=split(/;/,$_,2);
	($name,$value)=split(/=/,$str,2);
	$INI{$name}=$value }

open (INI,'/mnt/NFS/commonCMK/pl/batch_err.txt');
@err=<INI>; close (INI); 

# ���������� �������������
my $my_host=StationAtt();
my $my_station=substr($my_host,2);
my ($mysql_usr, $mntr_pid, $shmem, $shmsg, $stored_umask);
my @mes;  # for message packing

#my $done = AnyEvent->condvar; # condvar

if ($INI{UnderMonitor}) { # ���������� shmem, ���������� $mysql_usr
	unless (-e '/tmp/ssrp.pid') { NoShare() }
  open (PF,'/tmp/ssrp.pid');
	$shmsg=new IPC::Msg( 0x72746e6d,	0001666 );
	RestoreShmem(); 
	$SIG{USR2} = \&Suicide }
else { $mysql_usr=$INI{mysql_usr} }

# ���������� mySQL
my $dbh=DBI->connect_cached("DBI:mysql:cmk:$ENV{MYSQLHOST}",'CMKtest',undef) || die $DBI::errstr; #Volkov
my $is_host=$dbh->selectcol_arrayref(qq(SELECT is_host.ip FROM is_host,host,user
        WHERE user.name="$mysql_db" AND user.parent=host.stand_base
        AND host.id_host=is_host.base_host_id)); # ��� ������ ��;
unshift(@$is_host,$ENV{VMEHOST}); # ������ � � 0-���. $is_host->[$crate]= ip_address #Volkov

$dbh = DBI->connect_cached("DBI:mysql:$mysql_db:$ENV{MYSQLHOST}","$mysql_usr",undef) || die $DBI::errstr;

# ��������� ������� �� ����� � ��������� ������� ��������� ����������
use constant ID => 0;
use constant VPI=> 1;
use constant NAM=> 2;
use constant CHA=> 3;
use constant UNT=> 4;
use constant VT => 5;
use constant NDG=> 6;
use constant FSB=> 7;
use constant LSB=> 8;
use constant NC => 9;

my $prm=$dbh->selectall_arrayref(qq(SELECT
	id_parm,vme_prm_id,name,chan_addr,units,v_type,NDIG,FSTBIT,LSTBIT,NC
	FROM parm WHERE target&3)); # ��������� �� ������ ��������� ���� ����������
my %prm_atr; # ��� ���������� �� ��������� � ������� ��������� ����������
for my $i (0..$#{$prm}) { # ������ � ��������
	$prm_atr{$prm->[$i][ID]} = $i } # ���������: <atr value> = $prm->[$prm_atr{<prm id>}][<atr cnst>]

my $sys=$dbh->selectall_arrayref(qq(SELECT id_system,n_r_s,name,n_s_s FROM system));
my %sys_atr;
for my $i (0..$#{$sys}) { # ������ � ��������
	$sys_atr{$sys->[$i][ID]} = $i } # �������: <atr value> = $sys->[$sys_atr{<sys id>}][<atr cnst>]
# ��������: $name=$sys->[$sys_atr{$sys_id}][NAM]; $n_r_s=$sys->[$sys_atr{$sys_id}][NRS];

my $row=$dbh->selectall_arrayref(qq(SELECT id_system,avail
	FROM compl WHERE sim=0 ORDER BY id_system,num_compl)); # ��������� ��ɣ������
my %cmpl_r; # ��� ���������� �������� ������� ���������� ��������� ��ɣ������
my $sys_cur=0; for my $i (0..$#{$row}) { # ������ � ����� �������:
	if ($sys_cur!=$row->[$i][0]) { # next system
		$sys_cur=$row->[$i][0]; $cmpl_r{$sys_cur}=() } # <avail> = ${$cmpl_r{sys id}}[<num compl> - 1] - ��� ��ɣ�����
	push @{$cmpl_r{$sys_cur}},$row->[$i][1] }

$row=$dbh->selectall_arrayref(qq(SELECT id_system,avail
	FROM compl WHERE sim ORDER BY id_system,num_compl)); # ��������� ����������
my %cmpl_s; $sys_cur=0;
for my $i (0..$#{$row}) { # ������ � ����� �������:
	if ($sys_cur!=$row->[$i][0]) { # next system
		$sys_cur=$row->[$i][0]; $cmpl_s{$sys_cur}=() } # <avail> = ${$cmpl_s{sys id}}[<num compl> - 1] - ��� ���������
	push @{$cmpl_s{$sys_cur}},$row->[$i][1] }

$row=$dbh->selectcol_arrayref(qq(SELECT id_system FROM system ORDER BY v_id));
my @sys_v_id;
for my $i (0..$#{$row}) { # ������� ���������� � ������� @sys_v_id ������������� v_id ������
	push @sys_v_id,$row->[$i] } # ������� - id �������

my %prm_v_id;
foreach my $i (@sys_v_id) {
	$prm_v_id{$i}=[];
	$row=$dbh->selectcol_arrayref(qq(SELECT id_parm FROM parm WHERE id_system=$i AND target&3 ORDER BY v_id));
	for my $j (0..$#{$row}) { # ������� ���������� � ������� @$prm_v_id{sys id} ������������� v_id ����������
		push @{$prm_v_id{$i}},$row->[$j] } } # ���� ���� - �������, ������� - id ���������

#������� ��� �� ����� ���������� �����������, ��� ����������� ������������ ������������� � ������� ����������
#my %stor=();
my $stor;
my $rowp=$dbh->selectall_arrayref(qq(SELECT vme_prm_id,id_system,num_compl,id_parm,twin,mask,crate FROM imi WHERE target&2));
for my $i ( 0 .. $#{$rowp} ) {
my $imi_key=Key($rowp->[$i][1],$rowp->[$i][2],$rowp->[$i][3]);
$stor->{$imi_key}[0]=$rowp->[$i][0]; $stor->{$imi_key}[3]=$rowp->[$i][4]; $stor->{$imi_key}[4]=$rowp->[$i][5]; $stor->{$imi_key}[5]=$rowp->[$i][6] }

#���������� ������������ ��� ��������� � ������� ��� ����������� ������� �� ���������� ���������� � �������
my $all_id=$dbh->selectcol_arrayref(qq(SELECT id_parm FROM parm));
my %all_prm=(); my %all_sys=();
foreach my $id (@$all_id) { $all_prm{$id}=''  }
$all_id=$dbh->selectcol_arrayref(qq(SELECT id_system FROM system));
foreach my $id (@$all_id) { $all_sys{$id}=''  }
#foreach my $key (keys %all_sys) { print "$key\n" }
undef $all_id;
#

# ���������� ������������ �������� ������
my (%out_str,%out_key, %out_val)=(); my $out_id; # ���� ������ ������ � ���������� �������� ������ OUTPUT_TO_VME. 
#� ������ � ���. out_val - ��� ������ ������, �� ������� ����� ��� ��, ��� ��������� ������ ���������� � ��������
my @mkt; my $mkt_id; # ������ ���������� �� ������� ������ ������ � ��� ������
my %send_crate = (); #��� ������� �������, ������� �������� �������� vme_prm_id ����������
my (@crate_reg, @crate_tot, @crate_imi); #Macc��� ������� ������� ��� �����������, ��������������, 
#� ����� ������ "������" ������� �������� ������ � ������� ������ ������ 
my @sys_imi; # ������ ������, ���������� "�������"
my ($rpt,$aftr); # ����������� ���������� �� �������
my %imi_avail; # ��� �������� vme_prm_id ��������� ����������
my $success_flag;
my %v_test=();
my %rcnt; #���������� ������� ��� ���������� �� �������
my %buf_cr;
my @buf_length; #������ ���� ������� �� �������
my @max_buf_length; #������������ ����� ������
# ���������� ������� ���� ��������������
my $started_flag=my $paused_flag=my $vme_crash=0; 
my $descrow=100; # ����� � ��������� ���������
my $descr={}; # ��� ��� ������� ��������� ���������, ���� - ������, �������
my $descrtab; # ������ ������� ��������� ���������
my $descfile=[]; # ������ ����� ������ ��������� ���������
my @IN=[]; # ������ ����� ����� ��������� ��������� �� ���������
my $cmnt=my $usr=1; #����� ���������� ���� � ��� ���������� ���������
my $cmnt_do=my $usr_do=1; #����� ����������� ���� � ��� ������ ��
my $batch_name="";# ��� ������������ ���������
my (%pack)=(); # ������ ��� pack
my $pack=my $tmpl_cmnt=''; # ����� ��� ����������, ����������� � ���������� ������
my $base_width='870x'; #������ �������� ���� ���������
my $CD_width='1200x'; #������ ���� ���
my $DO_width='640x'; #������ ���� �� ������� �������� ���������
my $stand_name=$ENV{USER}; 
my @Operators_data=[];
# ���������� ���� source
my $srcwin; my $srctab; # ���� � ������� ���������� �������
my $src={}; # ��� ������� ���������� �������
my $srcrow=[]; # �������� ������ ���� ������
my $srccmnd=[]; # �������� ������� (��� �������� ����������)
my $CD; # ��������� �� ��� ������� ������

my $log; if (substr($INI{log},16,1) eq '1') { $log=1; } else { $log=0 }
my $log_trs; if (substr($INI{log},17,1) eq '1') { $log_trs=1 } else { $log_trs=0 }


if ($log or $log_trs) {$row='>./log/B'.time.'.log';  open (Log, "$row") }
open (Prot, '>./log/Batch.log');

my ($proto, %templ_ids, %set_ids, @iaddr, @sin_to, @sin_to_imi, $sin_from, @S_OUT, @S_IN, $S_IN_UN, $S_RCV,@S_SND, $S_SND_I, $rout, $rin); #Volkov
my %host_crate=(); #��� � �������� �������, ������� �������� �������� ������ ������ 
my ($port_vme_to,$port_vme_from); # ����� ��������� ������
# ���������� ���� ��� ������ � ���������
my $sock_in_wtchr; #������ ��������� ������
my $time_wtchr; #������ �������
open (INI,"/mnt/Data/DBoperations/$mysql_db/vme_config_file");
 my @ini=<INI>; close (INI);
 my $port_vme_to_imi;
 foreach (@ini) {
         if (/^DYN\s+\S+\s+(\S+)\s+RT\s+A/) { $port_vme_to_imi=$1; last } }
         @ini=();

unless (CheckFreeVMEport()) { # ���� ��� ��������� vme ������
	WarnBusyVMEport(); # �������� �� ���� � ������������ ���������� �����
	exit } # �����.
	
$dbh->do(qq(INSERT INTO packs (id,user,p_type,host,PID,sock_in) VALUES (0,"$mysql_usr","I","$my_host","$$","$port_vme_to")));
my $packID=$dbh->{'mysql_insertid'};   # ����� $packID

if ($INI{UnderMonitor}) { $mes[0]=$packID; $mes[1]='born'; $mes[2]='I'; PageMonitor() }

my ($base, $pixpath);
if ($INI{SmallButtons}) { $pixpath='/usr/share/pixmaps/ssrp/small/' }
else { $pixpath='/usr/share/pixmaps/ssrp/' }

#Volkov
#������������ ��������/����������� ������� ��� �����/��������
sub PrepSockets {
@iaddr=@sin_to=@sin_to_imi=@S_SND=();
socket($S_RCV,PF_INET, SOCK_DGRAM, $proto);
$sin_from = sockaddr_in( $port_vme_from, INADDR_ANY );
bind($S_RCV, $sin_from);
$rin=''; vec($rin, fileno( $S_RCV ), 1) = 1;
#socket($S_SND, PF_INET, SOCK_DGRAM, $proto);
socket($S_SND_I, PF_INET, SOCK_DGRAM, $proto);
foreach my $crate (0 .. 3) { # ��� ���� �������
  $iaddr[$crate]=gethostbyname($is_host->[$crate]); # �������� ����c
        $host_crate{inet_ntoa($iaddr[$crate])}=$crate;
	$sin_to_imi[$crate] = sockaddr_in( $port_vme_to_imi,$iaddr[$crate] );
        socket($S_SND[$crate], PF_INET, SOCK_DGRAM, $proto);
	$sin_to[$crate] = sockaddr_in( $port_vme_to, $iaddr[$crate] ) } }
	
#Volkov

$proto = getprotobyname('udp');

PrepSockets();
#Volkov ������� � ��������� ��������� ����� ��� ������� ������
sub CreateBuffers {
for my $crate (0 .. 3) {
        $S_OUT[$crate]=pack 'I', 0x200; # ��� �������� - ������ � ��
        $S_OUT[$crate].=pack 'I', 0; # total length, shift - 4
        $S_OUT[$crate].=pack 'a4','A1'; # ������������� ��������, shift - 8
        $S_OUT[$crate].=pack 'a4','CP0'; # ������������� ����������, shift - 12
        $S_OUT[$crate].=pack 'I', 0; # ������ ������ � ��� ��� ����. ������, shift - 16
        $S_OUT[$crate].=chr(0)x20; # �� ������������
        $S_OUT[$crate].=pack 'I', 0; # total_of_records, shift - 40
        $S_OUT[$crate].=$mysql_db; # ��� ������ - � ���������
        my $l=20-length($mysql_db);
        $S_OUT[$crate].=chr(0)x$l;}  # ����������� ������ �� ������������� ��-�� ���������
} # �� ������������
CreateBuffers();
#Volkov

$|=1;

my (@Tl_att)=(-borderwidth=>1, -relief=>'flat', -takefocus=>0); # Toplevel attributes

$base = MainWindow->new(@Tl_att);
$base->title(decode('koi8r',"���������")); my $test_name='';
my $winheight=$base->screenheight / 2;
$base->geometry($base_width.$winheight); #��������� ������ �������� ����
#$base->geometry('570x'.$winheight);
my $rmenu = $base->Frame(-borderwidth=> 2, -relief=>  "groove");
$rmenu->pack(-anchor=> 'center', -expand=> 0, -fill=> 'x', -side=> 'top');
my $rmenu_n=$base->Frame(-borderwidth=> 2, -relief=>  "groove");
$rmenu_n->pack(-anchor=> 'center', -expand=> 0, -fill=> 'x', -side=> 'top');
my $bln=$rmenu->Balloon(-state=>'balloon', -initwait=>100);
my $bckg=$base->cget('-background');
my $log_timeS='00:00:00'; my $log_time=0;

$base->Pixmap('new',-file=>$pixpath.'new.xpm');
$base->Pixmap('open',-file=>$pixpath.'open.xpm');
$base->Pixmap('save',-file=>$pixpath.'save.xpm');
$base->Pixmap('add',-file=>$pixpath.'url.xpm');
$base->Pixmap('run',-file=>$pixpath.'resume.xpm');
$base->Pixmap('stop',-file=>$pixpath.'stop.xpm');
$base->Pixmap('print',-file=>$pixpath.'print.xpm');
$base->Pixmap('clear_prot',-file=>$pixpath.'new_wp.xpm');
$base->Pixmap('load',-file=>$pixpath.'search.xpm');
my $b_new=$rmenu->Button(-image=>'new',-relief=>'flat',-command=>sub {
	$test_name=''; $log_timeS='00:00:00'; $descfile=[];  @IN=[]; $descrtab->configure(-padx=>$descrtab->cget(-padx));
	foreach my $key (keys %$descr) { delete $descr->{$key} } $descrtab->selectionClear('all');
	$descrtab->clearTags(); $descrtab->tagCell('Target','0,0'); $descrtab->tagCol('DAT',0);
	$batch_name="";
	CheckLoadButton();
	foreach my $key (keys %templ_ids) { delete $templ_ids{$key} }
	foreach my $key (keys %set_ids) { delete $set_ids{$key} } }
	)->pack(-side=>'left',-padx=>$INI{bpx});
my $b_open=$rmenu->Button(-image=>'open',-relief=>'flat',-command=>sub {
	my $file_list=`ls /mnt/Data/TestDescriptors/$dir_name/ 2>/dev/null`;
	my @file_arr=split /\n/,$file_list;
	my @file;
	my $file_counter = 0;
	foreach my $i (0..$#file_arr) {
		my $check_log= grep(/\.log/, $file_arr[$i]);
		if ($check_log) {next}
		elsif (-d "/mnt/Data/TestDescriptors/$dir_name/$file_arr[$i]") {
			#$file_arr[$i]=decode('koi8r', $file_arr[$i]);
			$file[$file_counter]=$file_arr[$i];
			$file_counter++;}}
	Choice('�������� ���������:',\@file,sub{
		$descfile=[];  @IN=[];
		foreach my $key (keys %templ_ids) {
			$templ_ids{$key}=0;}
		foreach my $key (keys %set_ids) {
                        $set_ids{$key}=0;}
		my (@templ_array, @set_array); my ($templ_string, $set_string); my $idx=shift; 
		if (-e "/mnt/Data/TestDescriptors/$dir_name/$file[$idx]/$file[$idx]") {
		open (IN,"/mnt/Data/TestDescriptors/$dir_name/$file[$idx]/$file[$idx]"); @IN=<IN>;
		$batch_name=$file[$idx]; #@$descfile=@IN; 
		CheckLoadButton();
		close (IN);}
		else {
		my $err_text = "����������� ���� ��������� \"";
		$err_text.="$file[$idx]\"";
		my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
                        $er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
                        $er_base->Message(-anchor=>'center',-font=>$INI{err_font},-foreground=>"$INI{err_forg}",-justify=>'center',-padx=>35,-pady=>10, 
			 -text=>decode ('koi8r',"$err_text"), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
                        $base->bell;
 return}

		#�������� �� ������ ������ ��������� ������ � �������� ������� ������ � �������
		foreach my $i (0..($#IN)){chomp($IN[$i]);
			if ((($IN[$i] eq "templ_ids")||($IN[$i] eq "set_ids"))||($IN[$i] eq "")) {last}
			else  { 
			$descfile->[$i]=$IN[$i];}}
		#��������� ����, ��������� �������� ��������������� ������� � ��������� ���������� $templ_string,
		#�������� ������� ������� ������ ���������� � ���������� set_string. ������������� ����� �������� ����� templ_ids � set_ids ��������������
		foreach my $i(0..$#IN) {chomp ($IN[$i]);
			if ($IN[$i] eq "templ_ids"){
			$templ_string=$IN[$i+1]; }
			elsif ($IN[$i] eq "set_ids"){
			$set_string=$IN[$i+1]; }}
		#��������� ���������� �������� �������������� ������� � ������� ������ � ��������������� �������� �������� templ_array � set_array
		if (defined $templ_string) {
		@templ_array = split(/\s+/,$templ_string);}
		if (defined $set_string) {
		@set_array = split(/\s+/,$set_string);}
		my @templ_comment;
		my @set_comment;
		#����������� � �� ����� ������� ������ � ������� (�� ������������ � �� ����������������, ��������� �������� ��������������� ������ � ����, ������� �������� �������� ��� �����
		foreach my $i (0..$#templ_array) {
		$templ_comment[$i]=$dbh->selectall_arrayref(qq(SELECT comment FROM templ WHERE id=$templ_array[$i]));
		$templ_ids{$templ_comment[$i]->[0][0]}=$templ_array[$i]; }
		foreach my $i (0..$#set_array) {
                $set_comment[$i]=$dbh->selectall_arrayref(qq(SELECT comment FROM sets WHERE id=$set_array[$i]));
                $set_ids{$set_comment[$i]->[0][0]}=$set_array[$i];
		}
		RefreshDescr(); $test_name=decode('koi8r',$file[$idx]); $log_timeS='00:00:00';
		$descrtab->clearTags(); $descrtab->tagCell('Target','0,0'); $descrtab->tagCol('DAT',0); },
		sub { my $idx=shift; `rm -r "/mnt/Data/TestDescriptors/$dir_name/$file[$idx]"` 
		#unlink "/mnt/Data/TestDescriptors/$dir_name/$file[$idx]"  
		},
		sub { my $idx=shift; ViewTD("$file[$idx]/$file[$idx]") } );
		CheckLoadButton();
	})->pack(-side=>'left',-padx=>$INI{bpx});
my $b_save=$rmenu->Button(-image=>'save',-relief=>'flat',-command=>sub {
	my $file=$test_name;
	my $m_base = $base->Toplevel(@Tl_att,-title=>decode('koi8r','��������� ���������:')); $m_base->geometry($INI{StandXY});
	$m_base->Message(-anchor=>'center',-padx=>5,-pady=>2,-font=>$INI{ld_font},-width=>600,
		-text=>decode('koi8r',"������� ��� ���������:"))
		->pack(-fill=>'x', -side=>'top', -ipadx=>20, -ipady=>10);
	my $m_entry=$m_base->Entry(-font=>$INI{ld_font}, -fg=>"$INI{d_forg}", -bg=>"$INI{d_back}",-textvariable=>\$file,-width=>50)
		->pack(-padx=>20);
	my $write_file=sub{
		for my $i (0..$#{$descfile}) { print OUT "$descfile->[$i]\n"; }
		print OUT "\ntempl_ids\n";
		foreach my $key (keys %templ_ids) {
			if ((defined $templ_ids{$key})&&($templ_ids{$key}!=0)) {
				print OUT "$templ_ids{$key} ";}}
		print OUT "\n\nset_ids\n";  
		foreach my $key (keys %set_ids) {
                        if ((defined $set_ids{$key})&&($set_ids{$key}!=0)) {
                                print OUT "$set_ids{$key} ";}}

		close (OUT); $m_base->destroy };
	my $hand=sub{
		my $file=shift;
		#$file = decode('koi8r', $file);
		#print "\n$file";
		#$file = encode('koi8r', $file);
		#print "\n$file\n";
		if ($file eq '') { ErrMessage($err[21]); return }
		if ($#{$descfile}==-1) { ErrMessage($err[22]); return }
		unless ( -d "/mnt/Data/TestDescriptors/$dir_name/$file") {
        	system ("mkdir \"/mnt/Data/TestDescriptors/$dir_name/$file/\""); system("chmod 0775 \"/mnt/Data/TestDescriptors/$dir_name/$file/\"");}
		if ($file ne $test_name and -e "/mnt/Data/TestDescriptors/$dir_name/$file/$file") { # ���� � ����� ������ ��� ����������
			my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>(decode('koi8r','��������!')),-text=>decode('koi8r',qq(���� � ������\n< $file >\n����������. ����������?)),
				-bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
			if ($ans eq 'No') { return } }
		$test_name=decode('koi8r', $file);
		my $ret=open (OUT,">/mnt/Data/TestDescriptors/$dir_name/$file/$file");
		unless (defined $ret) {
			my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
			$er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
			$er_base->Message(-anchor=>'center',-font=>$INI{err_font},-foreground=>"$INI{err_forg}",-justify=>'center',-padx=>35,-pady=>10,
				-text=>decode('koi8r','�� ������� ������� ���� � ����� ������. ��������, � ������������ ����� ������������ �����ݣ���� ������� ��� �� �� ������ ���������� ���� ������� ��� ������ � ������� /mnt/Data/TestDescriptors'),
				-width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
			$base->bell; return }
		&$write_file();
		$batch_name=$file; 
		 CheckLoadButton();};
	$m_entry->bind('<Return>'=>sub{ my $file=$m_entry->get; $file=encode('koi8r',$file); &$hand($file) });
	$m_base->Button(-font=>$INI{bd_font},-padx=>'3m', -width=>20,-text=>decode('koi8r','���������'),-command=>sub{ my $file=$m_entry->get; $file=encode('koi8r',$file); &$hand($file) })
		->pack(-anchor=>'center',-expand=>0,-fill=>'none',-pady=>20,-side=>'top');
	$m_base->bind('<Escape>', sub { $m_base->destroy } );
	$m_base->protocol('WM_DELETE_WINDOW', sub { $m_base->destroy } ); 
	$m_base->waitVisibility; $m_base->grab; $m_entry->focus; $m_entry->eventGenerate('<1>');
	CheckLoadButton();
	})->pack(-side=>'left',-padx=>$INI{bpx});

my $b_add=$rmenu->Button(-image=>'add',-relief=>'flat',-command=>sub { unless (Exists($srcwin)) { CreateAddTbl() }
	} )->pack(-side=>'left',-padx=>$INI{bpx});
my $b_run=$rmenu->Button(-image=>'run',-relief=>'flat',-command=>sub {
	if ($#{$descfile}==-1) { ErrMessage($err[23]); return }
	unless ( PrepareData() ) { return } # ��������� ����������/�������� ������
	my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq(������ ��������� ������� �������������.\n��������� ���������?)),
		-bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
	if ($ans eq 'No') { return } # ���� ��� - �����
	$log_timeS='00:00:00'; $log_time=$vme_crash=$success_flag=0;
	my $timer=$base->repeat(1000,sub{ $log_time++; $log_timeS=TimeS($log_time) } ); # ��������� "����"
	RunTest(); $timer->cancel;
	if ($success_flag) { print Prot "\n��������� ��������� � ��������\n"; }
	else { print Prot "\n��������� ��������� ��� ������\n" }
	my $prot='./log/Batch.log';
	ViewProt($prot) } )->pack(-side=>'left',-padx=>$INI{bpx});
my $b_clear_prot=$rmenu->Button(-image=>'clear_prot',-relief=>'flat',-command=>sub {
	close(Prot); open (Prot, '>./log/Batch.log') } )->pack(-side=>'right',-padx=>$INI{bpx});
my $b_load_prot=$rmenu->Button(-image=>'load', -relief=>'flat', -command=>sub {my $file_list=`ls "/mnt/Data/TestDescriptors/$dir_name/$batch_name"`; &load_prot_file_list($file_list)})->pack(-side=>'right',-padx=>$INI{bpx});

#####����������� ������, ���� ����������� ����� ����������
CheckLoadButton();

my $l_test_time=$rmenu->Label(-font=>$INI{ri_font}, -bg=>"$INI{back}", -fg=>"$INI{forg}", -padx=>1,-pady=>1,-borderwidth=>2,-textvariable=>\$log_timeS, -width=>8)->pack(-side=>'left',-padx=>$INI{bpx});
my $l_test_name=$rmenu_n->Label(-font=>$INI{ri_font},-bg=>"$INI{back}", -fg=>"$INI{forg}", -padx=>1,-pady=>1,-borderwidth=>2,-textvariable=>\$test_name,-anchor=>'w')->pack(-side=>'top',-padx=>$INI{bpx},-expand=>1,-fill=>'x');
$bln->attach($b_new,-msg=>decode('koi8r','������� ����� ���������'));
$bln->attach($b_open,-msg=>decode('koi8r','��������� ���������'));
$bln->attach($b_add,-msg=>decode('koi8r','�������� ������'));
$bln->attach($b_save,-msg=>decode('koi8r','��������� ���������'));
$bln->attach($b_load_prot,-msg=>decode('koi8r','��������� �������� ���������'));
$bln->attach($l_test_name,-msg=>decode('koi8r','��� ���������'));
$bln->attach($b_run,-msg=>decode('koi8r','��������� ���������'));
$bln->attach($l_test_time,-msg=>decode('koi8r','����������������� ���������'));
$bln->attach($b_clear_prot,-msg=>decode('koi8r','�������� ��������'));

my $rdat=$base->Frame(-borderwidth=>2,-relief=>"groove")->pack(-anchor=>'center',-side=>'top', -fill=>'x');
$descrtab=$rdat->Scrolled('TableMatrix',-scrollbars=>'e',-rows=>$descrow, -cols=>1, -height=>$descrow,
	-variable=>$descr, -font=>$INI{sys_font}, -bg=>'white',
	-roworigin=>0, -colorigin=>0,
	-colwidth=>160, -state=>'disabled',
	-selectmode=>'single',-cursor=>'top_left_arrow');
$descrtab->tagConfigure('Target',-bg=>'gray85',-anchor=>'w');
$descrtab->tagConfigure('Run',-bg=>'black',-fg=>'green');
$descrtab->tagConfigure('Err',-bg=>'black',-fg=>'red');
$descrtab->tagConfigure('DAT', -anchor=>'w');
$descrtab->tagConfigure('Hole',-bg=>'black',-fg=>'yellow');
$descrtab->tagCol('DAT',0);
$descrtab->tagCell('Target','0,0');
$descrtab->pack(-fill=>'x');
$descrtab->bind('<1>', sub {
	my $w=shift; my $Ev=$w->XEvent; $w->selectionClear('all'); my $ct=$w->tagCell('Target');
	$w->tagCell('',$ct->[0]); $w->tagCell('Target','@'.$Ev->x.','.$Ev->y);
	$ct=$w->tagCell('Run'); if (defined $ct) { $w->tagCell('',$ct->[0]) }; Tk->break } );
$descrtab->bind('<3>', sub {
	my $w=shift; my $Ev=$w->XEvent;	$w->selectionClear('all'); my $ct=$w->tagCell('Target');
	$w->tagCell('',$ct->[0]); $w->tagCell('Target','@'.$Ev->x.','.$Ev->y);
	$ct=$w->tagCell('Run'); if (defined $ct) { $w->tagCell('',$ct->[0]) };
	my $r=$w->index('@'.$Ev->x.','.$Ev->y,'row');
	unless (exists $descr->{"$r,0"}) { Tk->break }; my $t=$base->geometry(); (undef,$t,my $s)=split /\+/,$t;
	$w->tagCell('',$ct->[0]); $w->tagCell('Target','@'.$Ev->x.','.$Ev->y);
	my $popup=$w->Menu('-tearoff'=>0,-font=>$INI{but_menu_font});
	unless ($descfile->[$r]=~/����������������_�������/) { # ��� ���� ������, ����� ������ � ��������
		$popup->command(-label=>decode('koi8r','������������� �������'),-bg =>'gray85',-command=>sub {
			my @cmnd=split /\s+/,$descfile->[$r]; if (substr($cmnd[1],0,1) eq '[') { for my $i (2..$#cmnd) { $cmnd[1].=' '.$cmnd[$i] } }
			my ($m_base,$m_entry,$m_entry_p,$m_but,$row);
			if ($cmnd[0] eq '�����') {
				my $p_hand=sub {
					if ($value eq '') { ErrMessage($err[0]); return }
					if ($value=~/[^.1234567890]/) { ErrMessage($err[1]); $base->bell; return }
					$descfile->[$r]=$cmnd[0].' '.$value;  RefreshDescr(); $m_base->destroy };
				$m_base = $base->Toplevel(@Tl_att,-title=>decode('koi8r','��������:')); $m_base->geometry("+$t+$s"); $value=$cmnd[1];
				$m_base->Message(-anchor=>'center',-padx=>5,-pady=>2,-font=>$INI{ld_font},-width=>600,
					-text=>decode('koi8r',"������� ����������������� ����� � ��������:"))
					->pack(-fill=>'x', -side=>'top', -ipadx=>20, -ipady=>10);
				$m_entry=$m_base->Entry(-font=>$INI{ld_font},-fg=>"$INI{d_forg}",-textvariable=>\$value,-bg=>"$INI{d_back}",-width=>10,-justify=>'center')
					->pack(-padx=>20);
				$m_entry->focus; $m_entry->eventGenerate('<1>');
				$m_entry->bind('<Return>'=>sub{ $value=$m_entry->get; &$p_hand } );
				$m_base->Button(-font=>$INI{bd_font},-padx=>'3m', -width=>20,-text=>decode('koi8r','Ok!'),-command=>sub{ $value=$m_entry->get; &$p_hand } )
					->pack(-anchor=>'center',-expand=>0,-fill=>'none',-pady=>20,-side=>'top');
				$m_base->bind('<Escape>', sub { $m_base->destroy } );
				$m_base->protocol('WM_DELETE_WINDOW', sub { $m_base->destroy } );
				$m_base->waitVisibility; $m_base->grab }
			elsif ($cmnd[0] eq '���������_�����') {
				$row=$dbh->selectcol_arrayref(qq(SELECT comment FROM templ WHERE p_type='R' ORDER BY comment));
				my $templ_id=$dbh->selectcol_arrayref(qq(SELECT id FROM templ WHERE p_type ='R' ORDER BY comment));
				Choice('�������� ����� ��� ���������:',$row,sub{
					my $idx=shift; 
			                (my $valid)=$dbh->selectrow_array(qq(SELECT valid FROM templ WHERE id=$templ_id->[$idx]));
                unless ($valid) { # invalid templ
                        unless ($dbh->selectrow_array(qq(SELECT id FROM invalidTS WHERE id_obj=$templ_id->[$idx] AND type_obj='T'))) {
                                $dbh->do(qq(INSERT INTO invalidTS (id,id_obj,type_obj,date) VALUES (0,$templ_id->[$idx],'T',NOW()))) }
                        my $mes="����� �������� ������������ ������. ���������� � ��������������.\n����� ������������� ������ ������� ��������������� ���� ����������� ������ (���� ������� ������������)";
                        my @koiYN=(decode('koi8r','������������ � ����������'),decode('koi8r','���������� �� ��������'));
                        my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq($mes)),
                                -bitmap=>'question',-buttons=>\@koiYN ); my $ans=$dlg->Show(-global);
                        if ($ans eq $koiYN[1]) { return } }

					(undef,my $templcomment)=split /\s+/,$descfile->[$r],2; $templcomment=~s/\[//; $templcomment=~s/\]//;
                                        $templ_ids{$templcomment}=0;

					$templ_ids{$row->[$idx]}=$templ_id->[$idx];
					$descfile->[$r]=$cmnd[0].' ['.$row->[$idx].']'; $cmnd[1]=~s/\[//; $cmnd[1]=~s/\]//;
					if ($row->[$idx] ne $cmnd[1]) { # another maket
						$r++; while ($r<=$#{$descfile}) {
							if ($descfile->[$r]=~/^��������_�_������������_�������/) { $descfile->[$r]='��������_�_������������_������� [CD]'; $descrtab->tagCell('Hole',"$r,0"); $base->bell }
							if ($descfile->[$r]=~/^���������_�����/) { last } else { $r++ } } }
					RefreshDescr() },undef,
					sub{ my $idx=shift; ViewMaket($row->[$idx]) } ) }
			elsif ($cmnd[0] eq '������_�����_������_�_��') {
				$row=$dbh->selectcol_arrayref(qq(SELECT comment FROM sets WHERE target='S' ORDER BY comment));
				my $set_id=$dbh->selectcol_arrayref(qq(SELECT id FROM sets WHERE target='S' ORDER BY comment));
				Choice('�������� ����� ������:',$row,
					sub{ my $idx=shift;  my (@ar, @undef_prm); my ($key,$val); my $str;
						$set_ids{$row->[$idx]}=$set_id->[$idx];
						(my $file, my $valid)=$dbh->selectrow_array(qq(SELECT data,valid FROM sets WHERE id=$set_id->[$idx]));
				                unless ($valid) { # invalid set
                        			unless ($dbh->selectrow_array(qq(SELECT id FROM invalidTS WHERE id_obj=$set_id->[$idx] AND type_obj='S'))) {
                                		$dbh->do(qq(INSERT INTO invalidTS (id,id_obj,type_obj,date) VALUES (0,$set_id->[$idx],'S',NOW()))) }
                        			my $mes="����� �������� ������������ ������. ���������� � ��������������";
                        			my @koiYN=(decode('koi8r','������������ � ����������'),decode('koi8r','���������� �� ��������'));
                        			my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq($mes)),
                                -bitmap=>'question',-buttons=>\@koiYN ); my $ans=$dlg->Show(-global);
                        if ($ans eq $koiYN[1]) { return } }
						(undef,my $setcomment)=split /\s+/,$descfile->[$r],2; $setcomment=~s/\[//; $setcomment=~s/\]//;
						$set_ids{$setcomment}=0;
						$descfile->[$r]=$cmnd[0].' ['.$row->[$idx].']'; 
						RefreshDescr() },undef,
					sub{ my $idx=shift; ViewSet($row->[$idx]) } ) }
			elsif ($cmnd[0] eq '������_������_��_��') {
				my $DT=$cmnd[2]; $DT=~s/DT=//; my $T=$cmnd[3]; $T=~s/T=//; my $Z='��'; if ($cmnd[1]=~/NOT/) { $Z='���' }
				$m_base = $base->Toplevel(@Tl_att,-title=>decode('koi8r','��������:')); $m_base->geometry("+$t+$s");
				$m_base->Label(-relief=>'ridge',-anchor=>'w',-padx=>10,-pady=>3,-font=>$INI{h_sys_font},-text=>decode('koi8r','������ ������ �� ��'))
					->grid(-columnspan=>3,-row=>0,-column=>0,-ipady=>10,-sticky=>'we');
				$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','� ���������� (0.02..10.0)'))
					->grid(-row=>1,-column=>0,-sticky=>'w');
				$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','� ������� (0 - ����������)'))
					->grid(-row=>2,-column=>0,-sticky=>'w');
				$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','� ���������� ��� ��ɣ�����:'))
					->grid(-row=>3,-column=>0,-sticky=>'w');
				$m_entry=$m_base->Entry(-justify=>'center',-font=>$INI{ld_font},-width=>10,-fg=>"$INI{d_forg}",-bg=>"$INI{d_back}",-textvariable=>\$DT)
					->grid(-row=>1,-column=>1,-padx=>10);
				$m_entry_p=$m_base->Entry(-justify=>'center',-font=>$INI{ld_font},-width=>10,-fg=>"$INI{d_forg}",-bg=>"$INI{d_back}",-textvariable=>\$T)
					->grid(-row=>2,-column=>1,-padx=>10);
				$m_but=$m_base->Button(-font=>$INI{but_menu_font},-width=>8,-text=>decode('koi8r',$Z),-command=>sub{
					if ($m_but->cget('-text') eq (decode('koi8r','��'))) { $m_but->configure(-text=>decode('koi8r','���')) }
					else { $m_but->configure(-text=>decode('koi8r','��')) } } )->grid(-row=>3,-column=>1,-padx=>10);
				$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','���'))->grid(-row=>1,-column=>2,-sticky=>'w');
				$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','���'))->grid(-row=>2,-column=>2,-sticky=>'w');
				$m_base->Button(-font=>$INI{bd_font},-text=>decode('koi8r','Ok!'),-padx=>'3m',-width=>20,-command=>sub{
					$value=$m_entry->get;
					if ($value eq '') { ErrMessage($err[2]); $base->bell; return }
					if ($value=~/[^.1234567890]/) { ErrMessage($err[3]); $base->bell; return }
					if ($value<0.02) { ErrMessage($err[4]); $base->bell; return }
					$value=$m_entry_p->get;
					if ($value=~/[^.1234567890]/) { ErrMessage($err[5]); $base->bell; return }
					if ($value eq '') { $cmnd[3]=0 }
					if ($m_but->cget('-text') eq (decode('koi8r','��'))) { $descfile->[$r]=$cmnd[0].' CLR ' } else { $descfile->[$r]=$cmnd[0].' NOT_CLR' }
					$descfile->[$r].=" DT=$DT T=$T"; $m_base->destroy; RefreshDescr() } )->grid(-columnspan=>3,-row=>4,-column=>0,-pady=>5);
					$m_entry->focus; $m_entry->eventGenerate('<1>');
					$m_entry->bind('<Return>'=>sub{ $m_entry_p->focus; $m_entry_p->eventGenerate('<1>') } );
					$m_entry_p->bind('<Return>'=>sub{ $m_but->focus } );
					$m_base->bind('<Escape>', sub { $m_base->destroy } );
					$m_base->protocol('WM_DELETE_WINDOW', sub { $m_base->destroy } );
					$m_base->waitVisibility; $m_base->grab }
			elsif ($cmnd[0] eq '��������_�_������������_�������') {
				my $rmaket=$r; while ($rmaket>-1) { if ($descfile->[$rmaket]=~/���������_�����/) { last }; $rmaket-- }
				(undef,my $templcomment)=split /\s+/,$descfile->[$rmaket],2; $templcomment=~s/\[//; $templcomment=~s/\]//;
				my $templ_id=$dbh->selectrow_array(qq(SELECT id FROM templ WHERE comment="$templcomment")); # ������� CD �����
				my $file=$cmnd[1]; $file=~s/\[//; $file=~s/\, �����.+//;
				my $file_list=`ls /mnt/Data/CDfiles/$dir_name/$templ_id#* 2>/dev/null`;
				my @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
				Choice('�������� ���� ����������� ������:',\@file,
					sub{ my $idx=shift; $descfile->[$r]=$cmnd[0]." [$file[$idx], �����: $templcomment]"; RefreshDescr() },
					sub{ my $idx=shift; unlink "/mnt/Data/CDfiles/$dir_name/$templ_id#$file[$idx]";
						if ($file eq $file[$idx]) { $descfile->[$r]='��������_�_������������_������� [CD]'; $descrtab->tagCell('Hole',"$r,0"); $base->bell; RefreshDescr() } },
					sub{ my $idx=shift; ViewCD("$templ_id#$file[$idx]") } ) }
			elsif ($cmnd[0] eq '��������_���������'){ 
				my $file_list=`ls /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
				my $redODC_flag=1;
                		my @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
                		OperatorDataChoice('�������� ���� � �������� �������� ���������:',\@file,\$descfile->[$r], $r, $redODC_flag
                		); RefreshDescr()}
 } ) } 
	$popup->command(-label=>decode('koi8r','������� �������'),-bg =>'gray85',-command=>sub {
		my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r','������������� �������?'),
			-bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
		if ($ans eq 'No') { return }
		my $desc_temp=$descfile->[$r];
		my $s=splice @$descfile,$r,1; 
		if ($s=~/^���������_�����/) { 
			(undef,my $templcomment)=split /\s+/,$s,2; $templcomment=~s/\s$//; $templcomment=~s/\[//; $templcomment=~s/\]//; 
			$templ_ids{$templcomment}=0;
			while ($r<=$#{$descfile}) { # ��� ����� ������ �� ����. LOAD_MAKET
				if ($descfile->[$r]=~/^��������_�_������������_�������/) { $descfile->[$r]='��������_�_������������_������� [CD]'; $descrtab->tagCell('Hole',"$r,0");
					$base->bell }
				if ($descfile->[$r]=~/^���������_�����/) { last } else { $r++ } } }; 
			if ($s=~/^������_�����_������_�_��/) {
                        	(undef,my $setcomment)=split /\s+/,$s,2; $setcomment=~s/\s$//;  $setcomment=~s/\[//; $setcomment=~s/\]//;
				$set_ids{$setcomment}=0;}
			RefreshDescr(); Tk->break });
	if ($descfile->[$r]=~/^���������_�����/) {
		$popup->command(-label=>decode('koi8r','�������� ������'),-bg =>'gray85',-command=>sub {
			(undef,my $templcomment)=split /\s+/,$descfile->[$r],2; $templcomment=~s/\[//; $templcomment=~s/\]//;
			ViewMaket($templcomment) } ) }
	if ($descfile->[$r]=~/^������_�����_������_�_��/) {
		$popup->command(-label=>decode('koi8r','�������� ������'),-bg =>'gray85',-command=>sub {
			(undef,my $templcomment)=split /\s+/,$descfile->[$r],2; $templcomment=~s/\[//; $templcomment=~s/\]//;
			ViewSet($templcomment) } ) }
	if ($descfile->[$r]=~/���������_�����/) {
		$popup->command(-label=>decode('koi8r','������� ���� �����. ������'),-bg =>'gray85',-command=>sub {  CreateCDfile($r) } );
		$popup->command(-label=>decode('koi8r','������� ���� �����. ������'),-bg =>'gray85',-command=>sub {
			(undef,my $templcomment)=split /\s+/,$descfile->[$r],2; $templcomment=~s/\s$//; $templcomment=~s/\[//; $templcomment=~s/\]//;
			my $templ_id=$dbh->selectrow_array(qq(SELECT id FROM templ WHERE comment="$templcomment")); # ������� CD �����
			my $file_list=`ls /mnt/Data/CDfiles/$dir_name/$templ_id#* 2>/dev/null`;
			my @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
			Choice('�������� ������ ����������� ������:',\@file,
				sub{ my $idx=shift;
					my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r','������������� ������� ����?'),
						-bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
					if ($ans eq 'No') { return }
					unlink "/mnt/Data/CDfiles/$dir_name/$templ_id#$file[$idx]" },undef,
				sub{ my $idx=shift; ViewCD("$templ_id#$file[$idx]") } ) } ) }
	if ($descfile->[$r]=~/^��������_�_������������_�������/ and not $descfile->[$r]=~/\[CD\]$/) {
		$popup->command(-label=>decode('koi8r','������������� ���� �����. ������'),-bg =>'gray85',-command=>sub { EditCDfile($r) } ) }
	$popup->Popup(-popover=>'cursor',-popanchor=>'nw'); Tk->break } );

$base->bind('<F1>'=> \&HelpPage);
$base->protocol('WM_DELETE_WINDOW',\&Suicide);

MainLoop;

sub ViewMaket {
(my $t)=shift; my $dat=$dbh->selectrow_array(qq(SELECT dat FROM templ WHERE comment="$t"));
unless (defined $dat) { ErrMessage($err[6],$t); return }
my $txt=''; my (@el,@k); my $name; my %dat=split /:/,$dat; # �������� �� �������
foreach my $s_id (@sys_v_id) { # ��� ���� ������������ ������
	unless (exists $dat{$s_id}) { next } # ���� ������� �� ������ � �����
	$txt.="\n*** $sys->[$sys_atr{$s_id}][NAM] �������� ";
	@el=split /,/,$dat{$s_id}; # ��� �������� ��������� �������
	@k=grep(/(k\d)/, @el); foreach (@k) { s/k// }; # ������ ������ ����������
	$txt.="@k ***\n";
	while ($el[0]=~/k/) { shift @el } # ����� ��������� - ������ ���������
	foreach my $i (@{$prm_v_id{$s_id}}) { # ��� ���� ����������
		unless (grep { $i==$_ } @el) { next } # ���� ��������� ��� ����� �����������
		$txt.="$prm->[$prm_atr{$i}][CHA] $prm->[$prm_atr{$i}][NAM]\n" } }
ViewX(\$txt,"����� [$t]") }

sub ViewSet {
(my $t)=shift; my $file=$dbh->selectrow_array(qq(SELECT data FROM sets WHERE comment="$t"));
if (length($file)==0) { ErrMessage($err[7],$t); return }
#unless (defined $file) { ErrMessage($err[7],$t); return }
my @ar=split /\n/,$file;
my ($key,$value); my %set; my $valueb;
for my $i (0..$#ar) { chomp ($ar[$i]); ($key,$value,$valueb)=split /:/,$ar[$i];  $set{$key}=$value }
my $txt=''; my ($sys_num,$set_num,$prm_id,$name); my $c_sys_num=my $c_set_num=0; my (@txt,@value);
my $print_prm=sub { foreach (@txt) { $txt.=$_.(' ' x (maxlen(\@txt)-length($_))).' '.shift(@value)."\n" } };
foreach my $key (sort keys %set) { # ��� ���� ���������� � ������
	$key=~/(\d\d\d)(\d)(\d+)/; $sys_num=$1+0; $set_num=$2+0; $prm_id=$3+0;
	if ($sys_num!=$c_sys_num or $set_num!=$c_set_num) { # ����� ���������������
		if ($c_sys_num) { &$print_prm() } # �� ������ �������
		$txt.="\n*** $sys->[$sys_atr{$sys_num}][NAM] �������� $set_num ***\n";
		@txt=@value=(); $c_sys_num=$sys_num; $c_set_num=$set_num }
	push @txt,"$prm->[$prm_atr{$prm_id}][CHA] $prm->[$prm_atr{$prm_id}][NAM]";
  $value=hex($set{$key}); $valueb=prepPV($prm_id,$value); BinView(\$valueb);
	$value=prepVV($prm_id,hex($set{$key}),1); push @value,qq($valueb ($value)) }; &$print_prm();
ViewX(\$txt,"����� [$t]") }
	
sub ViewCD {
(my $file, my $dflag)=@_;
unless (defined $dflag) { $file="/mnt/Data/CDfiles/$dir_name/$file" }
open (IN,"$file"); my @ar=<IN>; close(IN);
(undef,$file)=split /#/,$file; my $txt=''; my (@txt,@value); my ($key,$value,$range); my $c_sys_num=my $c_set_num=0;
my $print_prm=sub { foreach (@txt) { $txt.=$_.(' ' x (maxlen(\@txt)-length($_))).' '.shift(@value)."\n" } };
my $s_id; my $cnum; my $p_id; foreach my $line (@ar) {
	chomp($line); ($key,$value)=split /:/,$line; $key=~/(\d\d\d)(\d)(\d+)/; $s_id=$1+0; $cnum=$2; $p_id=$3+0;
	if ($value=~/;/) { ($value,$range)=split /;/,$value } else { $range=undef }
	if ($s_id!=$c_sys_num or $cnum!=$c_set_num) { # ����� ���������������
		if ($c_sys_num) { &$print_prm() } # �� ������ �������
		$txt.="\n*** $sys->[$sys_atr{$s_id}][NAM] �������� $cnum ***\n";
		@txt=@value=(); $c_sys_num=$s_id; $c_set_num=$cnum }
	push @txt,"$prm->[$prm_atr{$p_id}][CHA] $prm->[$prm_atr{$p_id}][NAM]";
	BinView(\$value);	$value='<'.$value.'> ('.prepCVV($p_id,$value,$range).')';
	push @value,$value };
&$print_prm(); ViewX(\$txt,"���� �� [$file]")}

sub ViewTD {
(my $file)=shift; open (IN,"/mnt/Data/TestDescriptors/$dir_name/$file"); my @ar=<IN>; close(IN);
my $txt=''; foreach my $line (@ar) { $txt.=$line }
ViewX(\$txt,"��������� [$file]") }

sub ViewX {
my ($txt,$title)=@_; my $vw=$base->Toplevel(@Tl_att, -title=>decode('koi8r',$title));
my $vt=$vw->Scrolled('Text',-scrollbars=>'osoe',wrap=>'none',-tabs=>[qw/0.5c 5c 6.5c 12c/],-spacing1=>5,-font=>$INI{mono_font})->pack(-expand=>1, -fill=>'both');
$vt->insert('1.0',decode('koi8r',$$txt)); $vt->configure(-state=>'disabled');
$vt->tagConfigure('CMND',-font=>$INI{mono_font}.' '.'bold'); my $i='1.0'; my ($l,$c);
while (1) {
	$i=$vt->search('***',$i,'end'); unless ($i) { last }
	$vt->tagAdd('CMND',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0' } }

sub RefreshDescr {
foreach my $key (keys %$descr) { delete $descr->{$key} } 
for my $i (0..$#{$descfile}) { chomp($descfile->[$i]); $descr->{"$i,0"}=decode('koi8r',$descfile->[$i]) }
$descrtab->configure(-padx=>$descrtab->cget(-padx)) }

sub EditCDfile {
(my $r)=@_; my $rm=$r-1;
while ($rm>=0) { if ($descfile->[$rm]=~/(^���������_�����)/) { last } else { $rm-- } }
if ($rm<0) { ErrMessage($err[8]); return }
(undef,my $templcomment)=split /\s+/,$descfile->[$rm],2; $templcomment=~s/\[//; $templcomment=~s/\]//;
my $templ_id=$dbh->selectrow_array(qq(SELECT id FROM templ WHERE comment="$templcomment")); # ������� CD �����
(undef,my $file)=split /\s+/,$descfile->[$r],2; $file=~s/\[//; $file=~s/\, �����.+//;
unless (-e "/mnt/Data/CDfiles/$dir_name/$templ_id#$file") { ErrMessage($err[9],$file); return }
open (IN,"/mnt/Data/CDfiles/$dir_name/$templ_id#$file");
my @ar=<IN>; close(IN); my ($key,$value,$s_id,$cnum,$p_id,$range); my %CD; my $row_i=0; my $cd=[];
my $sname; foreach my $line (@ar) {
	chomp($line); ($key,$value)=split /:/,$line; $key=~/(\d\d\d)(\d)(\d+)/; $s_id=$1+0; $cnum=$2; $p_id=$3+0;
	if ($value=~/;/) { ($value,$range)=split /;/,$value } else { $range=undef }
	$sname=$sys->[$sys_atr{$s_id}][NAM];
	$CD->{"$row_i,0"}="$sname �.$cnum $prm->[$prm_atr{$p_id}][CHA] $prm->[$prm_atr{$p_id}][NAM]";
#	$CD->{"$row_i,0"}="$sname �.$cnum $prm->[$prm_atr{$p_id}][CHA] $prm->[$prm_atr{$p_id}][NAM] ($prm->[$prm_atr{$p_id}][UNT])";
	$CD->{"$row_i,1"}=$value; BinView(\$CD->{"$row_i,1"});
	$CD->{"$row_i,2"}=$p_id; # ��������� prm_id ���������
	if (defined $range) { $CD->{"$row_i,3"}=$range } else { $CD->{"$row_i,3"}=undef }
	push @$cd,Key($s_id,$cnum,$p_id); $row_i++ }
CDfile($file,$CD,$cd,$templ_id) }

sub CreateCDfile {
(my $r)=@_; 
(undef,my $templcomment)=split /\s+/,$descfile->[$r],2; $templcomment=~s/\s$//; $templcomment=~s/\[//; $templcomment=~s/\]//;
(my $templ_id,my $dat)=$dbh->selectrow_array(qq(SELECT id,dat FROM templ WHERE comment="$templcomment")); # ������� CD �����
unless (defined $dat) { ErrMessage($err[6],$templcomment); return }
my $row_i=0; my (@el,@k); my ($sname,$dsi,$value); my $cd=[]; $CD={}; my %dat=split /:/,$dat; # �������� �� �������
foreach my $s_id (@sys_v_id) { # ��� ���� ������������ ������
	unless (exists $dat{$s_id}) { next } # ���� ������� �� ������ � �����
	$sname=$sys->[$sys_atr{$s_id}][NAM];
	@el=split /,/,$dat{$s_id}; # ��� �������� ��������� �������
	@k=grep(/(k\d)/, @el); foreach (@k) { s/k// }; while ($el[0]=~/k/) { shift @el } # ����� ��������� - ������ ���������
	foreach my $cnum (@k) { # ��� ���� ����������
		unless (${$cmpl_r{$s_id}}[$cnum - 1]) { next } # �������� ��ɣ����� �����������
		foreach my $i (@{$prm_v_id{$s_id}}) { # ��� ���� ����������
			unless (grep { $i==$_ } @el) { next } # ���� ��������� ��� ����� �����������
			$CD->{"$row_i,0"}="$sname �.$cnum $prm->[$prm_atr{$i}][CHA] $prm->[$prm_atr{$i}][NAM]";
			$value=0;
			if ($prm->[$prm_atr{$i}][VT] < RK) { # ���� ���
				$value=revbit(oct($prm->[$prm_atr{$i}][CHA]));
				mtrxs($prm->[$prm_atr{$i}][VT],3,\$value);
				if ($prm->[$prm_atr{$i}][FSB] > 10) { # FSTBIT>10
					$value&=0xFFFFFCFF; # �������� ��.9,10
					if ($prm->[$prm_atr{$i}][NAM]=~/\s(k|�|�|K)\.(1|2|3|4)$/) { # � ������������ dsi (data sourse identificator)
						$dsi=substr $prm->[$prm_atr{$i}][NAM],-1,1; $dsi&=0x3; $value|=($dsi<<8) } # ���������� dsi
					else { $value|=(($cnum&3)<<8) } } }
			$CD->{"$row_i,1"}=prepCV($i,$value); BinView(\$CD->{"$row_i,1"}); # ���������� �������
			$CD->{"$row_i,2"}=$i; # ��������� prm_id ���������
			push @$cd,Key($s_id,$cnum,$i); $row_i++ } } }
CDfile('����� ���� ����������� ������',$CD,$cd,$templ_id) }

sub prepCV { # Control View
(my $prm_id, my $value)=@_; my $ret;
if ($prm->[$prm_atr{$prm_id}][VT] == RK) { # �������
	#$ret=($skip_char x (32-$prm->[$prm_atr{$prm_id}][LSB])).'0'.($skip_char x ($prm->[$prm_atr{$prm_id}][LSB]-1));
   	$value=sprintf "%032b",$value;
	$value=substr($value,(32-$prm->[$prm_atr{$prm_id}][LSB]),1);
	$ret=($skip_char x (32-$prm->[$prm_atr{$prm_id}][LSB])).$value.($skip_char x ($prm->[$prm_atr{$prm_id}][LSB]-1));
	}
elsif ($prm->[$prm_atr{$prm_id}][VT] == AS) { # ������
	$ret=($skip_char x 16).('0' x 16) }
else { # ���������
	$ret=sprintf "%032b",$value; substr($ret,0,1,$hide_char) }
return $ret }

sub prepPV { # Protocol View
(my $prm_id, my $value)=@_; my $ret; my ($n,$s);
my $vt=$prm->[$prm_atr{$prm_id}][VT];
$ret=sprintf "%032b",$value;
if ($vt == 10) { # �������
	$n=32-$prm->[$prm_atr{$prm_id}][LSB]; $s=$skip_char x (32-$prm->[$prm_atr{$prm_id}][LSB]); $ret=~s/^\w{$n}/$s/;
	$n=$prm->[$prm_atr{$prm_id}][LSB]-1; $s=$skip_char x ($prm->[$prm_atr{$prm_id}][LSB]-1); $ret=~s/\w{$n}$/$s/ }
elsif ($vt == 15) { # ������
	$n=16; $s=$skip_char x 16; $ret=~s/^\w{$n}/$s/ }
return $ret }
	
sub prepCVV { # Control Value View
(my $prm_id, my $valuec, my $range)=@_; my $kd=0; $valuec=~s/\s//g; my $ret;
for my $i (0..31) { if (substr($valuec,$i,1) eq '1') { $kd|=0x80000000>>$i } } # ��. ������������� ��
my $str_kd=prepVV($prm_id,$kd,0); 
#if (defined $range and $range!=0) {
if (defined $range) {
	if ($range eq $MaxRange) {
		if ($prm->[$prm_atr{$prm_id}][VT]==GMS) { $range=$prm->[$prm_atr{$prm_id}][NC] * 60 * 60 * 2 }
		else { $range=$prm->[$prm_atr{$prm_id}][NC] * 2 } }
	if ($prm->[$prm_atr{$prm_id}][VT]==DK) {
		if ($prm->[$prm_atr{$prm_id}][NC]==90 and 180>=($str_kd-$range) and 180<=($str_kd+$range)) { # 180 - � �������
			$ret=$str_kd-$range; $ret.='; '; $str_kd+=$range; $str_kd-=360; $ret.=$str_kd }
		elsif ($prm->[$prm_atr{$prm_id}][NC]==90  and -180>=($str_kd-$range) and -180<=($str_kd+$range)) { # -180 - � �������
			$ret=$str_kd-$range+360; $ret.='; '; $str_kd+=$range; $ret.=$str_kd }
		else { $ret=$str_kd-$range; $ret.='; '; $str_kd+=$range; $ret.=$str_kd } }
	elsif ($prm->[$prm_atr{$prm_id}][VT]==GMS) {
		if (648000>=(gms2sec($str_kd)-$range) and 648000<=(gms2sec($str_kd)+$range)) { # 180 - � �������
			$ret=sec2gms(gms2sec($str_kd)-$range); $ret.='; '; $ret.=sec2gms(gms2sec($str_kd)+$range-648000*2) }
		elsif (-648000>=(gms2sec($str_kd)-$range) and -648000<=(gms2sec($str_kd)+$range)) { # -180 - � �������
			$ret=sec2gms(gms2sec($str_kd)-$range+648000*2); $ret.='; '; $ret.=sec2gms(gms2sec($str_kd)+$range) } 
		else { $ret=sec2gms(gms2sec($str_kd)-$range); $ret.='; '; $ret.=sec2gms(gms2sec($str_kd)+$range) } }
	else { $ret=$str_kd-$range; $ret.='; '; $str_kd+=$range; $ret.=$str_kd } 
	if (length($prm->[$prm_atr{$prm_id}][UNT])) { $ret.=" $prm->[$prm_atr{$prm_id}][UNT]" } }
else { $ret=prepVV($prm_id,$kd,1) }
return $ret }

sub prepVV { # Value View
(my $prm_id, my $val, my $unit_flag)=@_;
my $ret=bin2ascii($prm->[$prm_atr{$prm_id}][VT], $prm->[$prm_atr{$prm_id}][FSB], $prm->[$prm_atr{$prm_id}][LSB],
	getNDIG($prm->[$prm_atr{$prm_id}][VT],$prm->[$prm_atr{$prm_id}][NDG]), $prm->[$prm_atr{$prm_id}][NC],$val,'1');
$ret=~s/\s//g;
if ($unit_flag and length($prm->[$prm_atr{$prm_id}][UNT])) { $ret.=" $prm->[$prm_atr{$prm_id}][UNT]" };
return $ret }

sub CDfile {
my ($title,$CD,$cd,$templ_id)=@_;
for my $i(0..$#$cd) { $CD->{"$i,0"}=decode('koi8r',$CD->{"$i,0"}) }
my $CDwin=$base->Toplevel(@Tl_att,-title=>decode('koi8r',$title) );
$CDwin->geometry($INI{StandXY});
#$CDwin->geometry("+1500+300");
$CDwin->geometry($CD_width.$winheight);
my $CDtab;
my $FileFr=$CDwin->Frame(-borderwidth=> 2, -relief=>  "groove");
$FileFr->pack(-anchor=> 'center', -expand=> 0, -fill=> 'x', -side=> 'top');
$FileFr->Button(-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','��������� ����'),-command=>sub{
	my $title=$CDwin->cget(-title); my $file=($title eq decode('koi8r','����� ���� ����������� ������'))?'':$title;
	my $m_base = $base->Toplevel(@Tl_att,-title=>decode('koi8r','��������� ���� ����������� ������:')); $m_base->geometry($INI{StandXY});
	$m_base->Message(-anchor=>'center',-padx=>5,-pady=>2,-font=>$INI{ld_font},-width=>600,
		-text=>decode('koi8r',"������� ��� ����� ����������� ������:"))
		->pack(-fill=>'x', -side=>'top', -ipadx=>20, -ipady=>10);
	my $file_u=decode('utf8',$file);
	my $m_entry=$m_base->Entry(-font=>$INI{ld_font},-fg=>"$INI{d_forg}",-bg=>"$INI{d_back}",-textvariable=>\$file_u,-width=>50)
		->pack(-padx=>20);
	my $write_file=sub{
		my $wospc; for my $i(0..$#$cd) {
			$wospc=$CD->{"$i,1"}; $wospc=~s/\s//g; print OUT qq($cd->[$i]:$wospc);
			if (defined $CD->{"$i,3"}) { print OUT qq(;$CD->{"$i,3"}) }
			print OUT "\n" }
		close (OUT); $m_base->destroy };
	my $hand=sub{
		my $file=shift; if ($file eq '') { ErrMessage($err[21]); return }
		if ($#{$cd}==-1) { ErrMessage($err[22]); return }
		my $ffile=$templ_id.'#'.$file;
		if (-e "/mnt/Data/CDfiles/$dir_name/$ffile") { # ���� � ����� ������ ��� ����������
			my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq(���� � ������\n< $file >\n����������. ����������?)),
				-bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
		if ($ans eq 'No') { return } }
		my $ret=open (OUT,">/mnt/Data/CDfiles/$dir_name/$ffile");
		unless (defined $ret) {
			my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
			$er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
			$er_base->Message(-anchor=>'center',-font=>$INI{err_font},-foreground=>"$INI{err_forg}",-justify=>'center',-padx=>35,-pady=>10,
				-text=>decode('koi8r','�� ������� ������� ���� � ����� ������. ��������, � ������������ ����� ������������ �����ݣ���� ������� ��� �� �� ������ ���������� ���� ������� ��� ������ � ������� /mnt/Data/CDfiles'),
				-width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
			$base->bell; return }
			$CDwin->configure(-title=>decode('koi8r',"$file")); &$write_file() };
	$m_entry->bind('<Return>'=>sub{ $file=$m_entry->get; my $file_k=encode('koi8r', $file); &$hand($file_k) });
	$m_base->Button(-font=>$INI{bd_font},-padx=>'3m', -width=>20,-text=>decode('koi8r','���������'),-command=>sub{ $file=$m_entry->get; my $file_k=encode('koi8r', $file); &$hand($file_k) })
		->pack(-anchor=>'center',-expand=>0,-fill=>'none',-pady=>20,-side=>'top');
	$m_base->bind('<Escape>', sub { $m_base->destroy } );
	$m_base->protocol('WM_DELETE_WINDOW', sub { $m_base->destroy } );
	$m_base->waitVisibility; $m_base->grab; $m_entry->focus; $m_entry->eventGenerate('<1>') } )->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>10,-side=>'left');
my $proc_selection;
$FileFr->Button(-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','������ �� ������'),-command=>sub{
	$row=$dbh->selectcol_arrayref(qq(SELECT comment FROM sets WHERE target='S' ORDER BY comment));
	Choice('�������� ����� ������:',$row,
		sub{ my $idx=shift; my $prm_id; my $file=$dbh->selectrow_array(qq(SELECT data FROM sets WHERE comment="$row->[$idx]")); 
			my @ar=split /\n/,$file; my ($key,$value); my %set;
			foreach (@ar) { chomp; ($key,$value)=split /:/; 
			#��� ��� ������ ����������� �� �� �������������� ��������� �� ������������� ���������������, ���������� ��� ��������
			#��� (� �� ��� �������� ������ ����� 4 �������� ���� ���������� ������ �����, � ��� �� ����� �� ��������������� ��������������
			#�������� Keys, � ������� ��� ���� ���������), �� ��������� ���������� ������ �� ��� ����� (keys 1 � keys2), � � �����, ����������
			#�� ������������� ��������� () ��������� ������ �������� �����, ��� ���� ����� ��������  
			my $key2=substr($key,4); 
			my $key1=substr($key,0,4); 
			$key2=sprintf('%i',$key2);
			$key1.=$key2; 
			$set{$key1}=$value;} 
			for my $i (0..$#$cd) {# ��� ���� ���������� CD �����
			if (exists $set{$cd->[$i]}) { # �������� ������ ���� ����� �������� � ��
					$cd->[$i]=~/(\d\d\d)(\d)(\d+)/; $prm_id=$3+0; $value=hex($set{$cd->[$i]});  
					$value=prepCV($prm_id,$value); BinView(\$value); $CD->{"$i,1"}=$value } }
			$CDtab->configure(-padx=>$CDtab->cget(-padx));
			&$proc_selection() }, undef,
		sub{ my $idx=shift; ViewSet($row->[$idx]) } ) } )->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>10,-side=>'left');
$FileFr->Button(-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','������ �� ���'),-command=>sub{
	my $file_list=`ls /mnt/Data/CDfiles/$dir_name/* 2>/dev/null`;
	my @ffile=split /\n/,$file_list; my @file=@ffile; foreach (@file) { chomp; s/(^\S+#)// }
	Choice('�������� ���:',\@file,
		sub{ my $idx=shift; open (F,"$ffile[$idx]"); my @ar=<F>; close(F); my ($key,$value,$range); my %set; my %range;
			foreach (@ar) { chomp; ($key,$value)=split /:/;
				if ($value=~/;/) { ($value,$range)=split /;/,$value }; $set{$key}=$value; if (defined $range) { $range{$key}=$range } }
			for my $i (0..$#$cd) { # ��� ���� ���������� CD �����
				if (exists $set{$cd->[$i]}) { # �������� ��� ���� ����� ��������
					$CD->{"$i,1"}=$set{$cd->[$i]}; BinView(\$CD->{"$i,1"});
					if (defined $range{$cd->[$i]}) { $CD->{"$i,3"}=$range{$cd->[$i]} } } }
			$CDtab->configure(-padx=>$CDtab->cget(-padx)); my $title=$CDwin->cget('-title');
			if ($title eq decode('koi8r','����� ���� ����������� ������')) { (undef,$title)=split /#/,$ffile[$idx]; $CDwin->configure(-title=>decode('koi8r',$title)) }

			&$proc_selection() }, undef,
			sub{ my $idx=shift; ViewCD("$ffile[$idx]",1) } ) } )->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>10,-side=>'left');
$FileFr->Button(-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','�����'),-command=>sub{ $CDwin->destroy } )
	->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>10,-side=>'right');
my $PrmFr=$CDwin->Frame(-borderwidth=> 2, -relief=>  "groove");
$PrmFr->pack(-anchor=> 'center', -expand=>0, -fill=> 'x', -side=> 'top');
my $PrmFr1=$PrmFr->Frame(-relief=>"flat")->pack(-fill=> 'x', -side=> 'top' );
my $PrmFr2=$PrmFr->Frame(-relief=>"flat")->pack(-fill=> 'x', -side=> 'top', -padx=>160 );
my $TabFr=$CDwin->Frame(-borderwidth=> 2, -relief=>  "groove");
$TabFr->pack(-anchor=> 'center', -expand=> 1, -fill=> 'both', -side=> 'top');
$CDtab=$TabFr->Scrolled('TableMatrix',-scrollbars=>'osoe',-rows=>$#{$cd}+1, -cols=>2,
	-variable=>$CD, -font=>'courrier 12', -bg=>'white',
	-roworigin=>0, -colorigin=>0, -state=>'disabled', -padx=>10,
	-selectmode=>'single',	-cursor=>'top_left_arrow', -resizeborders=>'both', );

my $PrmName=$PrmFr1->Label(-font=>$INI{bd_font},-padx=>'5m',-anchor=>'w')->pack(-side=>'left');
my ($ed_bin,$ed_value,$ed_unit,$ed_range);
my (@wbit,@bit); for my $i (0..31) { $bit[$i]=0 }
my $bit2value=sub{ $ed_bin=0;
	for my $i (0..31) { $ed_bin<<=1; if ($bit[$i] eq '1') { $ed_bin|=1 } }
	my $as=$CDtab->tagCell('Target'); (my $r, my $c)=split(/\,/, $as->[0]); my $prm_id=$CD->{"$r,2"};
	for my $j (0..31) {
		if ((32-$j)<$prm->[$prm_atr{$prm_id}][FSB] or (32-$j)>$prm->[$prm_atr{$prm_id}][LSB]) { $wbit[$j]->configure(-fg=>$INI{forgR}) }
		else {  $wbit[$j]->configure(-fg=>$INI{forg}) } }
	$ed_value=bin2ascii($prm->[$prm_atr{$prm_id}][VT],
		$prm->[$prm_atr{$prm_id}][FSB],
		$prm->[$prm_atr{$prm_id}][LSB],
		getNDIG($prm->[$prm_atr{$prm_id}][VT],$prm->[$prm_atr{$prm_id}][NDG]),
		$prm->[$prm_atr{$prm_id}][NC],$ed_bin,'1'); $ed_unit=decode('koi8r',"$prm->[$prm_atr{$prm_id}][UNT]") };
my $PrmUnit=$PrmFr1->Label(-font=>$INI{bd_font},-width=>7,-textvariable=>\$ed_unit,-anchor=>'w')->pack(-side=>'right');
my $PrmRange=$PrmFr1->Entry(-font=>$INI{bd_font},-width=>12,-textvariable=>\$ed_range,-justify=>'left')->pack(-side=>'right');
$PrmFr1->Label(-font=>$INI{bd_font},-text=>chr(0xB1))->pack(-side=>'right');
my $PrmVal=$PrmFr1->Entry(-font=>$INI{bd_font},-width=>12,-textvariable=>\$ed_value,-justify=>'right')->pack(-side=>'right');

$PrmRange->bind('<Return>'=>sub {
	my $as=$CDtab->tagCell('Target'); (my $r, my $c)=split(/\,/, $as->[0]); my $prm_id=$CD->{"$r,2"};
	$ed_range=~s/\s//g; $ed_range=~s/\,/\./;
#���� ���������� ��������
my $vt=$prm->[$prm_atr{$prm_id}][VT];
if ($vt eq '00' or $vt eq '03' or $vt eq '15') {
	if ($ed_range=~/[mM��]/) { $ed_range=$MaxRange }
	if ($prm->[$prm_atr{$prm_id}][VT]==GMS) {
		if ($ed_range eq $MaxRange) { $CD->{"$r,3"}=$prm->[$prm_atr{$prm_id}][NC]*60*60 }
		else { $CD->{"$r,3"}=gms2sec($ed_range) } } # ��:��:��
	else { $CD->{"$r,3"}=$ed_range } }
else { #�� ���������� �������� 
	my $str='';
	my $bit_num=32;
	if ($ed_range=~/[mM��]/) {
	#��������� ��� ���� �� �������� �� ��������  
	for my $i ($prm->[$prm_atr{$prm_id}][FSB]..$prm->[$prm_atr{$prm_id}][LSB]) {
                my $num=$bit_num-$i; 
		$bit[$num]= $hide_char;
		}
		for my $i (0..31) {$str.=$bit[$i];}; BinView(\$str);
	        $CD->{"$r,1"}=$str; $CDtab->configure(-padx=>$CDtab->cget(-padx)); &$bit2value();
	        $ed_range=$MaxRange ;
		$CD->{"$r,3"}=$ed_range;	
		}
	else {	$ed_range ='';}}}  );
$PrmVal->bind('<Return>'=>sub {
	my ($x,$msk);
	my $as=$CDtab->tagCell('Target'); (my $r, my $c)=split(/\,/, $as->[0]);
	my $prm_id=$CD->{"$r,2"};
	if ($prm->[$prm_atr{$prm_id}][VT]<RK) { # ��� ���
		if ($prm->[$prm_atr{$prm_id}][FSB]==9) { $msk=0x000000FF } # ���� ���-�� ��.9,10
		else { $msk=0x000003FF } # ����� - ��������� � ���� ���������
		unless ($prm->[$prm_atr{$prm_id}][VT]==DDK or $prm->[$prm_atr{$prm_id}][VT]==DDK100) { $msk|=0x60000000 } # ��� ��� �-�� �����. �� �����
		$x=$ed_bin&$msk } # ���������� ����
	$ed_value=~s/\s//g; $ed_value=~s/\,/\./;
	$ed_bin=ascii2bin($prm->[$prm_atr{$prm_id}][VT], $prm->[$prm_atr{$prm_id}][FSB], $prm->[$prm_atr{$prm_id}][LSB],
		getNDIG($prm->[$prm_atr{$prm_id}][VT],$prm->[$prm_atr{$prm_id}][NDG]), $prm->[$prm_atr{$prm_id}][NC],$ed_value,$ed_bin);
	if ($prm->[$prm_atr{$prm_id}][VT]<RK) { $ed_bin|=$x }
	$msk=0x80000000; my $str='';
	for my $i (0..31) {
		if ($bit[$i] eq $hide_char) { $msk>>=1; next }
		if ($bit[$i] eq $skip_char) { $msk>>=1; next }
		if ($msk&$ed_bin) { $bit[$i]='1' } else { $bit[$i]='0' }; $msk>>=1 };
	for my $i (0..31) { $str.=$bit[$i] }; BinView(\$str);
	$CD->{"$r,1"}=$str; $CDtab->configure(-padx=>$CDtab->cget(-padx)); &$bit2value();
	&$bit2value() } );
my $f2=$PrmFr2->Table( -scrollbars=>'',-rows=>2,-columns=>38); $f2->pack(-anchor=>'center'); # ��� 'e'
my @Lo=(-anchor=>'nw',-font=>$INI{ri_font},-relief=>'flat',-bg=>"$INI{back}",-fg=>"$INI{forg}",-borderwidth=>0,-padx=>0,-pady=>1);
for my $i (0..31) { $wbit[$i]=$f2->Button(@Lo,-command=>[sub{
	my $i=shift; my $str='';
	if ($bit[$$i] eq $skip_char) { return }
	my $as=$CDtab->tagCell('Target'); (my $r, my $c)=split(/\,/, $as->[0]); my $prm_id=$CD->{"$r,2"};
	my $vt=$prm->[$prm_atr{$prm_id}][VT]; my $color=$wbit[$$i]->cget('-fg');
	if ($bit[$$i] eq '1') {$bit[$$i]='0'}
	elsif ($bit[$$i] eq '0') {
		if (($vt eq '00' or $vt eq '03' or $vt eq '15') and $color eq $INI{forg}) {$bit[$$i]='1'} else {$bit[$$i]=$hide_char} }
	elsif ($bit[$$i] eq $hide_char) {$bit[$$i]='1'}
	for my $i (0..31) { $str.=$bit[$i] }; BinView(\$str);
	$CD->{"$r,1"}=$str; $CDtab->configure(-padx=>$CDtab->cget(-padx)); &$bit2value();
	},Ev($i)],-textvariable=>\$bit[$i]) }
my $j=0;
for my $i (0..31) {
	$f2->put(0,$j++,$wbit[$i]);
	if ($j==1 or $j==4 or $j==10 or $j==19 or $j==26 or $j==29) { $f2->put(0,$j++,' ') } }
my $nmb='32   29 25 24    17 16  11  9 8      1';
my @txt; for my $i (0..37) { $txt[$i]=$f2->Label(-font=>$INI{but_menu_font},-text=>substr($nmb,$i,1)) }
for my $i (0..37) { $f2->put(1,$i,$txt[$i]) }
$j=0; for my $i (0..$#{$cd}) { $j=(length($CD->{"$i,0"})>$j)?length($CD->{"$i,0"}):$j }
$CDtab->colWidth(0=>($j/1.6), 1=>50);
$CDtab->tagConfigure('TXT', -anchor=>'w');
$CDtab->tagCol('TXT',0);
$CDtab->tagConfigure('Target',-bg=>'gray85');
$CDtab->tagConfigure('Data',-font=>$INI{data_font});
$CDtab->tagCol('Data',1);
$proc_selection=sub{
	my $as=$CDtab->tagCell('Target'); (my $r, my $c)=split(/\,/, $as->[0]);
	my $name=$CDtab->get("$r,0"); my $value=$CDtab->get("$r,1");
	my $prm_id=$CD->{"$r,2"}; my @gms;
	my $vt=$prm->[$prm_atr{$prm_id}][VT];
	if (defined $CD->{"$r,3"}) {
		if ($vt eq '03') { $ed_range=sec2gms($CD->{"$r,3"}) }
		else { $ed_range=$CD->{"$r,3"} } }
	else { $ed_range='' }
	if ($vt eq '00' or $vt eq '03' or $vt eq '15') {
		$PrmRange->configure(-state=>'normal') }
	####else { $PrmRange->configure(-state=>'disabled') }
	$PrmName->configure(-text=>$name); my $j=0;
	my $ch; for my $i (0..37) { $ch=substr $value,$i,1; if ($ch ne ' ') { $bit[$j++]=$ch } }
	&$bit2value() };
$CDtab->bind('<1>', sub {
	my $w=shift; my $Ev=$w->XEvent; my $ct=$w->tagCell('Target'); $w->tagCell('',$ct->[0]); 
	$w->tagCell('Target','@'.$Ev->x.','.$Ev->y); &$proc_selection(); Tk->break } );
$CDwin->bind('<Down>'=>sub{
	my $as=$CDtab->tagCell('Target'); (my $r, my $c)=split(/\,/,$as->[0]); $CDtab->tagCell('',$as->[0]);
	$r++; if ($r>$#{$cd}) { $r=0 }; $CDtab->tagCell('Target',"$r,$c"); &$proc_selection(); Tk->break } );
$CDwin->bind('<Up>'=>sub{
	my $as=$CDtab->tagCell('Target'); (my $r, my $c)=split(/\,/,$as->[0]); $CDtab->tagCell('',$as->[0]);
	$r--; if ($r==-1) { $r=$#{$cd} } $CDtab->tagCell('Target',"$r,$c"); &$proc_selection(); Tk->break } );
$CDwin->bind('<Control-Insert>'=>sub{ # copy to clipboard
	my $as=$CDtab->tagCell('Target'); (my $r,undef)=split(/\,/,$as->[0]); my $value=$CDtab->get("$r,1");
	open(CLIP,'>clip'); print CLIP $CDtab->get("$r,1");
	if (defined $CD->{"$r,3"}) { print CLIP qq(;$CD->{"$r,3"}) }
	print CLIP "\n"; close(CLIP); Tk->break } );
$CDwin->bind('<Shift-Insert>'=>sub{ # paste from clipboard
	my @as=$CDtab->tagCell('Target'); (my $r,undef)=split(/\,/,$as[0]);
	open(CLIP,'clip'); @as=<CLIP>; close(CLIP); chomp($as[0]); (my $value,my $range)=split /;/,$as[0];
	$CD->{"$r,1"}=$value; if (defined $range) { $CD->{"$r,3"}=$range } else { undef $CD->{"$r,3"} }
	$CDtab->configure(-padx=>$CDtab->cget(-padx)); &$proc_selection(); Tk->break } );
$CDtab->pack(-expand=>1, -fill=>'both');
$CDtab->tagCell('Target','0,0'); $CDtab->tagCol('TXT',0); &$proc_selection();
$CDwin->protocol('WM_DELETE_WINDOW', sub { $CDwin->destroy } ) }

sub gms2sec {
(my $str)=@_; my $sign=1;
if ($str=~/-/) { $str=~s/-//; $sign=-1 }; my @gms=split /:/,$str;
for my $i (0..$#gms) {
	if ($i==1) { $gms[$#gms]+=$gms[$#gms-$i]*60 }
	elsif ($i==2) { $gms[$#gms]+=$gms[$#gms-$i]*3600 } }
return $sign*$gms[$#gms] }

sub sec2gms {
(my $val)=@_; my @gms; my $sign='';
if ($val<0) { $sign='-'; $val=abs($val) }
$gms[0]=$val%60; $gms[1]=($val/60)%60; $gms[2]=$val/3600;
my $str=sprintf"%i:%02i:%02i",$gms[2],$gms[1],$gms[0];
return $sign.$str }

sub CreateAddTbl {
if ($#{$srcrow} < 0) { # ������� batch_src.txt
	open (IN,'/mnt/NFS/tmp/FtoDKPerl/batch_src.txt');
	@$srcrow=<IN>; close (IN);
	for my $i (0..$#{$srcrow}) {
		chomp($srcrow->[$i]);
		($srccmnd->[$i],$srcrow->[$i])=split /#/,$srcrow->[$i];
		$src->{"$i,0"}=decode('koi8r',$srcrow->[$i]) } }
my $t=$base->geometry(); (undef,$t,my $s)=split /\+/,$t;
$srcwin=$base->Toplevel(@Tl_att,-title=>decode('koi8r','�������� ������� � ���������:'));
$srctab=$srcwin->Scrolled('TableMatrix',-scrollbars=>'osoe',-rows=>$#{$srcrow}+1, -cols=>1,
	-variable=>$src, -font=>$INI{sys_font}, -bg=>'white',
	-roworigin=>0, -colorigin=>0, -state=>'disabled',
	-colwidth=>50, -selectmode=>'single',
	-cursor=>'top_left_arrow', -resizeborders=>'both');
$srctab->tagConfigure('DAT', -anchor=>'w');
$srctab->tagCol('DAT',0);
$srctab->pack(-expand=>0, -fill=>'both');
$srctab->bind('<1>', sub {
	my $ct=$descrtab->tagCell('Run'); if (defined $ct) { $descrtab->tagCell('',$ct->[0]) }; my $rd; # ����� 'Run', ���� �� ����
	$ct=$descrtab->tagCell('Target'); ($rd,undef)=split /,/,$ct->[0]; # ����� �������� ������
	unless (defined $rd) { $rd=$#{$descfile}+1; $descrtab->tagCell('Target',"$rd,0") } # ��� ��������� ������� ������ ������
	if ($rd and not defined $descfile->[$rd-1]) { ErrMessage($err[19]); return }
	my $w=shift; my @as=$w->curselection();
	(my $r, undef)=split(/\,/, $as[0]);
	my ($m_base,$m_entry,$m_entry_p,$m_but,$value,$value2,$row);
	my $final_value=$srccmnd->[$r];
	my $finish=sub {
		splice @$descfile,$rd,0,$final_value; RefreshDescr();
		$rd++; $descrtab->clearTags(); $descrtab->tagCell('Target',"$rd,0"); $descrtab->tagCol('DAT',0) };
	if ($final_value=~/^���������_�����/) {
		$row=$dbh->selectcol_arrayref(qq(SELECT comment FROM templ WHERE p_type='R' ORDER BY comment));
		my $templ_id=$dbh->selectcol_arrayref(qq(SELECT id FROM templ WHERE p_type='R' ORDER BY comment));
		Choice('�������� ����� ��� ���������:',$row,
		sub{ my $idx=shift; 
		(my $valid)=$dbh->selectrow_array(qq(SELECT valid FROM templ WHERE id=$templ_id->[$idx]));
                unless ($valid) { # invalid templ
                unless ($dbh->selectrow_array(qq(SELECT id FROM invalidTS WHERE id_obj=$templ_id->[$idx] AND type_obj='T'))) {
	                $dbh->do(qq(INSERT INTO invalidTS (id,id_obj,type_obj,date) VALUES (0,$templ_id->[$idx],'T',NOW()))) }
                my $mes="����� �������� ������������ ������. ���������� � ��������������.\n����� ������������� ������ ������� ��������������� ���� ����������� ������ (���� ������� ������������)";
                my @koiYN=(decode('koi8r','������������ � ����������'),decode('koi8r','���������� �� ��������'));
                my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq($mes)),
                                -bitmap=>'question',-buttons=>\@koiYN ); my $ans=$dlg->Show(-global);
                if ($ans eq $koiYN[1]) { return } }
		$final_value=~s/\[MAKET\]/[$row->[$idx]]/;  
		$templ_ids{$row->[$idx]}=$templ_id->[$idx];
		&$finish() },undef,
		sub{ my $idx=shift; ViewMaket($row->[$idx]) } ) }
	elsif ($final_value=~/^�����/) {
		my $p_hand=sub {
			if ($value eq '') { ErrMessage($err[0]); return }
			if ($value=~/[^.1234567890]/) { ErrMessage($err[1]); $base->bell; return }
			$final_value=~s/\[PAUSE\]/$value/; &$finish();
			$m_base->after(100,sub{$m_base->eventGenerate('<KeyPress-Escape>')}); Tk->break };
		$m_base = $base->Toplevel(@Tl_att,-title=>decode('koi8r','��������:')); $m_base->geometry("+$t+$s");
		$m_base->Message(-anchor=>'center',-padx=>5,-pady=>2,-font=>$INI{ld_font},-width=>600,
			-text=>decode('koi8r',"������� ����������������� ����� � ��������:"))
			->pack(-fill=>'x', -side=>'top', -ipadx=>20, -ipady=>10);
		$m_entry=$m_base->Entry(-font=>$INI{ld_font},-fg=>"$INI{d_forg}",-bg=>"$INI{d_back}",-width=>10,-justify=>'center')
			->pack(-padx=>20);
		$m_entry->focus; $m_entry->eventGenerate('<1>');
		$m_entry->bind('<Return>'=>sub{ $value=$m_entry->get; &$p_hand() } );
		$m_base->Button(-font=>$INI{bd_font},-padx=>'3m', -width=>20,-text=>decode('koi8r','Ok!'),-command=>sub{ $value=$m_entry->get; &$p_hand() } )
			->pack(-anchor=>'center',-expand=>0,-fill=>'none',-pady=>20,-side=>'top');
		$m_base->bind('<Escape>', sub { $m_base->destroy } );
		$m_base->protocol('WM_DELETE_WINDOW', sub { $m_base->destroy } );
		$m_base->waitVisibility; $m_base->grab }
	elsif ($final_value=~/^������_�����_������_�_��/) {
		$row=$dbh->selectcol_arrayref(qq(SELECT comment FROM sets WHERE target='S' ORDER BY comment));
		my $sets_id=$dbh->selectcol_arrayref(qq(SELECT id FROM sets WHERE target ='S' ORDER BY comment ));
		Choice('�������� ����� ������:',$row,
			sub{ my $str; my ($key,$val); my @undef_prm; my $idx=shift; $final_value=~s/\[DATASET\]/[$row->[$idx]]/; 
			 	$set_ids{$row->[$idx]}=$sets_id->[$idx];
				(my $valid)=$dbh->selectrow_array(qq(SELECT valid FROM sets WHERE id=$sets_id->[$idx]));
                unless ($valid) { # invalid set
			        unless ($dbh->selectrow_array(qq(SELECT id FROM invalidTS WHERE id_obj=$sets_id->[$idx] AND type_obj='S'))) {
                                $dbh->do(qq(INSERT INTO invalidTS (id,id_obj,type_obj,date) VALUES (0,$sets_id->[$idx],'S',NOW()))); }
                        my $mes="����� �������� ������������ ������. ���������� � ��������������";
                        my @koiYN=(decode('koi8r','������������ � ����������'),decode('koi8r','���������� �� ��������'));
                        my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq($mes)),
                                -bitmap=>'question',-buttons=>\@koiYN ); my $ans=$dlg->Show(-global);
                        if ($ans eq $koiYN[1]) { return } }

				&$finish() },undef,
			sub{ my $idx=shift; ViewSet($row->[$idx]) } ) }
	elsif ($final_value=~/^������_������_��_��/) {
		$m_base = $base->Toplevel(@Tl_att,-title=>decode('koi8r','��������:')); $m_base->geometry("+$t+$s");
		$m_base->Label(-relief=>'ridge',-anchor=>'w',-padx=>10,-pady=>3,-font=>$INI{h_sys_font},-text=>decode('koi8r','������ ������ �� ��'))
			->grid(-columnspan=>3,-row=>0,-column=>0,-ipady=>10,-sticky=>'we');
		$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','� ���������� (0.02..10.0)'))
			->grid(-row=>1,-column=>0,-sticky=>'w');
		$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','� ������� (0 - ����������)'))
			->grid(-row=>2,-column=>0,-sticky=>'w');
		$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','� ���������� ��� ��ɣ�����:'))
			->grid(-row=>3,-column=>0,-sticky=>'w');
		$m_entry=$m_base->Entry(-justify=>'center',-font=>$INI{ld_font},-width=>10,-fg=>"$INI{d_forg}",-bg=>"$INI{d_back}")
			->grid(-row=>1,-column=>1,-padx=>10);
		$m_entry_p=$m_base->Entry(-justify=>'center',-font=>$INI{ld_font},-width=>10,-fg=>"$INI{d_forg}",-bg=>"$INI{d_back}")
			->grid(-row=>2,-column=>1,-padx=>10);
		$m_but=$m_base->Button(-font=>$INI{but_menu_font},-width=>8,-text=>decode('koi8r','��'),-command=>sub{
			if ($m_but->cget('-text') eq (decode('koi8r','��'))) { $m_but->configure(-text=>decode('koi8r','���')) }
			else { $m_but->configure(-text=>decode('koi8r','��')) } } )->grid(-row=>3,-column=>1,-padx=>10);
		$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','���'))
			->grid(-row=>1,-column=>2,-sticky=>'w');
		$m_base->Label(-anchor=>'w',-padx=>10,-font=>$INI{ld_font},-text=>decode('koi8r','���'))
			->grid(-row=>2,-column=>2,-sticky=>'w');
		$m_base->Button(-font=>$INI{bd_font},-text=>decode('koi8r','Ok!'),-padx=>'3m',-width=>20,-command=>sub{
			$value=$m_entry->get;
			if ($value eq '') { ErrMessage($err[2]); return }
			if ($value=~/[^.1234567890]/) { ErrMessage($err[3]); return }
			if ($value<0.02) { ErrMessage($err[4]); return }
			$final_value=~s/\[T\]/DT=$value/; $value=$m_entry_p->get;
			if ($value=~/[^.1234567890]/) { ErrMessage($err[5]); return }
			if ($value eq '') { $value=0 } $final_value=~s/\[P\]/T=$value/;
			if ($m_but->cget('-text') eq (decode('koi8r','��'))) { $final_value=~s/\[Z\]/CLR/ }
			else { $final_value=~s/\[Z\]/NOT_CLR/}
			$m_base->destroy; &$finish() } )->grid(-columnspan=>3,-row=>4,-column=>0,-pady=>5);
		$m_entry->focus; $m_entry->eventGenerate('<1>');
		$m_entry->bind('<Return>'=>sub{ $m_entry_p->focus; $m_entry_p->eventGenerate('<1>') } );
		$m_entry_p->bind('<Return>'=>sub{ $m_but->focus } );
		$m_base->bind('<Escape>', sub { $m_base->destroy } );
		$m_base->protocol('WM_DELETE_WINDOW', sub { $m_base->destroy } );
		$m_base->waitVisibility; $m_base->grab }
	elsif ($final_value=~/^��������_�_������������_�������/) {
		my $as=$descrtab->tagCell('Target');
		(my $r,undef)=split /,/,$as->[0]; $r--;
		while ($r>-1) { if ($descfile->[$r]=~/���������_�����/) { last }; $r-- }
		if ($r==-1) { ErrMessage($err[10]); return }
		(undef,my $templcomment)=split /\s+/,$descfile->[$r],2; $templcomment=~s/\s$//; $templcomment=~s/\[//; $templcomment=~s/\]//;
		my $templ_id=$dbh->selectrow_array(qq(SELECT id FROM templ WHERE comment="$templcomment")); # ������� CD �����
		my $file_list=`ls /mnt/Data/CDfiles/$dir_name/$templ_id#* 2>/dev/null`;
		my @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
		Choice('�������� ���� ����������� ������:',\@file,
			sub{ my $idx=shift; $final_value=~s/\[CD\]/[$file[$idx], �����: $templcomment]/; &$finish() }, # �����
			sub{ my $idx=shift; unlink "/mnt/Data/CDfiles/$dir_name/$templ_id#$file[$idx]" }, # ��������
			sub{ my $idx=shift; ViewCD("$templ_id#$file[$idx]") } ) } # ��������
	 elsif ($final_value=~/^��������_���������/) {
		my $file_list=`ls /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
                my @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
		my $redODC_flag=0;
                OperatorDataChoice('�������� ���� � �������� �������� ���������:',\@file,\$final_value, $rd, $redODC_flag
      		);} 
		
	

	else { &$finish() } } );
$srctab->bind('<Motion>', sub {
	my $w=shift; my $Ev=$w->XEvent;  $w->selectionClear('all');
	$w->selectionSet('@'.$Ev->x.','.$Ev->y);  Tk->break } );
$srcwin->bind('<Escape>', sub { $srcwin->destroy } );
$srcwin->protocol('WM_DELETE_WINDOW', sub { $srcwin->destroy } ) }

sub Choice {
my ($title,$point,$hand,$del_hand,$show_hand)=@_;
my $selwin=$base->Toplevel(@Tl_att);
my $t=$base->geometry(); (undef,$t,my $s)=split /\+/,$t;
$selwin->geometry("+$t+$s");
$selwin->title(decode('koi8r',$title));
my $selvarlist={};
for my $i (0...$#{$point}) { $selvarlist->{"$i,0"}=decode('koi8r',$point->[$i]) }
my $seldat=$selwin->Scrolled('TableMatrix',-scrollbars=>'osoe',-rows=>($#{$point}+1), -cols=>1,
  -variable=>$selvarlist, -font=>$INI{sys_font}, -bg=>'white',
  -roworigin=>0, -colorigin=>0, -state=>'disabled',
  -colwidth=>50, -selectmode=>'single',
  -cursor=>'top_left_arrow', -resizeborders=>'both');
$seldat->tagConfigure('DAT', -anchor=>'w');
$seldat->tagCol('DAT',0);
$seldat->pack(-expand=>1, -fill=>'both');
$seldat->bind('<3>', sub {
	my $w=shift; my @as=$w->curselection(); my $popup;
	(my $r, undef)=split(/\,/, $as[0]);
	if (defined $show_hand) {
		$popup=$w->Menu('-tearoff'=>0,-font=>$INI{but_menu_font});
		$popup->command(-label=>decode('koi8r','��������'),-bg =>'gray85',-command=> sub{ &$show_hand($r) }) }
	if (defined $del_hand) {
		unless (defined $popup) { $popup=$w->Menu('-tearoff'=>0,-font=>$INI{but_menu_font}) }
		$popup->command(-label=>decode('koi8r','�������'),-bg =>'gray85',-command=> sub{
			my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r','������������� �������?'),
				-bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
			if ($ans eq 'No') { return }
			&$del_hand($r); splice @$point,$r,1;
			$seldat->configure(-state=>'normal'); $seldat->deleteRows($r); $seldat->configure(-state=>'disabled') } ) }
	if (defined $popup) {	$popup->Popup(-popover=>'cursor',-popanchor=>'nw') }
	Tk->break } );
$seldat->bind('<1>', sub {
	my $w=shift; my @as=$w->curselection();
	(my $r, undef)=split(/\,/, $as[0]); if ($selvarlist->{"$r,0"} eq '') { $base->bell; return } else { &$hand($r) };
	$selwin->after(200,sub{ $selwin->destroy }); Tk->break } );
$seldat->bind('<Motion>', sub {
   my $w=shift; my $Ev=$w->XEvent;  $w->selectionClear('all');
	 $w->selectionSet('@'.$Ev->x.','.$Ev->y);  Tk->break } );
$selwin->bind('<Escape>', sub { $selwin->destroy } );
$selwin->protocol('WM_DELETE_WINDOW', sub { $selwin->destroy } );
$selwin->waitVisibility; $selwin->grab; }

sub OperatorDataChoice {
my ($title,$point,$final_value,$rd,$redODC_flag)=@_;
my $redac_flag=0; #����, ����������� �� ����
my $f_name ='';
my @file_arr;
my @file_scr;
my $file_counter=0;
my $finish=sub {
                if ($redODC_flag==1) {splice @$descfile,$rd,1,$$final_value;}
		else {splice @$descfile,$rd,0,$$final_value;} 
		RefreshDescr(); 
                $rd++;
	        $descrtab->clearTags(); $descrtab->tagCell('Target',"$rd,0"); $descrtab->tagCol('DAT',0);
		 };
my $selwin=$base->Toplevel(@Tl_att);
my $t=$base->geometry(); (undef,$t,my $s)=split /\+/,$t;
my $seldat;

$selwin->geometry("+$t+$s");
$selwin->title(decode('koi8r',$title));
my $selvarlist;

my $tab_redraw = sub {

%$selvarlist=();
$file_counter=0;
@file_scr=();
foreach my $i (0..$#{$point}) {
		$file_arr[$i]=decode('koi8r', $point->[$i]);
		$file_scr[$file_counter][0]=$file_arr[$i];
		 my ($list,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("/mnt/Data/TestDescriptors/$dir_name/$point->[$i]");
                 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
                 my @time=localtime($ctime);
                 $year=1900+$time[5];
                 $year=sprintf ("%02d", $year);
                 my $month = 1+$time[4];
                 $month = sprintf ("%02d", $month);
                 my $day=sprintf ("%02d", $time[3]);
                 $hour=$time[2];
                 $min=$time[1];
                 $file_scr[$file_counter][1]=sprintf ($day.".".$month.".".$year) ;
                 $file_counter++;}


$seldat->configure(-rows=>($#file_scr+2));
for my $i (0...$#file_scr) { $selvarlist->{"$i,0"}= $file_scr[$i][0]; $selvarlist->{"$i,0"}=~s/.do//; 
$selvarlist->{"$i,1"}=decode('koi8r',$file_scr[$i][1]); }
$selvarlist->{'-1,0'} =decode ('koi8r', '��� �����'); $selvarlist->{'-1,1'} = decode ('koi8r','���� ��������');
$seldat->configure(-padx=>$seldat->cget(-padx));
};
my $SaveDO = sub {
my $t=$base->geometry(); (undef,$t,my $s)=split /\+/,$t;
my ($final_value, $rd, $redac_flag, $f_name, $redODC_flag)=@_;
my @file_txt='';
my $text_value='';
open (FILE, "/mnt/Data/TestDescriptors/$dir_name/$f_name");
@file_txt = <FILE>;
close FILE;
for my $i (0..$#file_txt) {$file_txt[$i]=decode('koi8r',$file_txt[$i]);};
        my $m_base = $base->Toplevel(@Tl_att,-title=>decode('koi8r','��������:')); $m_base->geometry("+$t+$s"); #������� ����� ����
        $m_base->Message(-anchor=>'center',-padx=>5,-pady=>2,-font=>"Times 14",-width=>800,
           -text=>decode('koi8r',"������� �������� ��������, ������� ������\n��������� �������� ��� ����������� ���������:"))
           ->pack(-fill=>'x', -side=>'top', -ipadx=>20, -ipady=>10);
        my $m_entry=$m_base->Text(-font=>"Times 15",-fg=>"$INI{d_forg}",-bg=>"$INI{d_back}", -width=>60, -height=>6)->pack(-padx=>20);
        $m_entry->focus; $m_entry->eventGenerate('<1>');  $m_base->bind('<Escape>', sub { $m_base->destroy } );
        $m_base->protocol('WM_DELETE_WINDOW', sub {
        my $file_list=`ls /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
        my @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
        $m_base->destroy } );
        $m_base->grab ;
        if ($redac_flag==1) {for my $i (0..$#file_txt) {#���� �/� ������� ��������������� �����, �� ������� ��� ���������� � ��������� ��� ����� �����
        #��� ������ ��� � ���� entry 
                        $m_entry->insert('end',$file_txt[$i]);
                        $text_value=decode('koi8r',$f_name);
                        $text_value=~s/.do//;}}
                        $m_base->Button(-font=>"Times 12 bold",-padx=>'3m', -width=>20,-text=>decode('koi8r','���������'),-command=>sub{
                                $value=$m_entry->get('1.0','end-1c'); $value=encode ('koi8r', $value);
                                 my $save_do;
                                 my $n_base=$base->Toplevel(@Tl_att,-title=>decode('koi8r','��������:'));
                                 $n_base->Message(-anchor=>'center',-padx=>5,-pady=>2,-font=>$INI{ld_font},-width=>800,
                                     -text=>decode('koi8r',"������� ��� �����:"))
                                     ->pack(-fill=>'x', -side=>'top', -ipadx=>20, -ipady=>10);
                                     my $n_entry=$n_base->Entry(-font=>$INI{ld_font}, -fg=>"$INI{d_forg}",-textvariable=>\$text_value, -bg=>"$INI{d_back}",-width=>50)->pack(-padx=>20);
				 $n_entry->focus; $n_entry->eventGenerate('<1>');
                                 $n_entry->bind('<Return>'=>sub{ my $file_name=$n_entry->get; $file_name=encode('koi8r', $file_name); &$save_do($file_name,$value); } );
                                 my $save_button=$n_base->Button (-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','���������'),
					-command=>sub{my $file_name=$n_entry->get; $file_name=encode('koi8r', $file_name); &$save_do($file_name, $value)})->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>10,-side=>'bottom');
                                 $save_do = sub {
					my $file_name= $_[0]; #tut
                                        if ($file_name eq '') { ErrMessage($err[21]); return }
                                        if (-e "/mnt/Data/TestDescriptors/$dir_name/$file_name.do") { # ���� � ����� ������ ��� ����������
                                                my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>(decode('koi8r','��������!')),-text=>decode('koi8r',qq(���� � ������\n< $file_name >\n����������. ����������?)),-bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
                                                if ($ans eq 'No') { return }}
                                                my $ret=open (OUT,">/mnt/Data/TestDescriptors/$dir_name/$file_name.do");
                                                unless (defined $ret) {
                                                        my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
                                                        $er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
                                                        $er_base->Message(-anchor=>'center',-font=>$INI{err_font},-foreground=>"$INI{err_forg}",-justify=>'center',-padx=>35,-pady=>10, -text=>decode('koi8r','�� ������� ������� ���� � ����� ������. ��������, � ������������ ����� ������������ �����ݣ���� ������� ��� �� �� ������ ���������� ���� ������� ��� ������ � ������� /mnt/Data/TestDescriptors'), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
                                                        $base->bell; return }
                                                my $data =$_[1];
                                                print OUT "$data"; close OUT;
                                                $n_base->destroy;
				                my $file_list=`ls /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
                                                my @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// } 
						$point=\@file; &$tab_redraw(); };
                        $n_base->bind('<Escape>', sub { $n_base->destroy } );
                        $n_base->protocol('WM_DELETE_WINDOW', sub {
                                $n_base->destroy } );
                                $n_base->waitVisibility; $n_base->grab;
                                $m_base->destroy;
        })->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>20,-pady=>20,-side=>'bottom');
        };


foreach my $i (0..$#{$point}) {
                $file_arr[$i]=decode('koi8r', $point->[$i]);
                $file_scr[$file_counter][0]=$file_arr[$i];
                my ($list,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("/mnt/Data/TestDescriptors/$dir_name/$point->[$i]");
                 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
                 my @time=localtime($ctime);
                 $year=1900+$time[5];
                 $year=sprintf ("%02d", $year);
                 my $month = 1+$time[4];
                 $month = sprintf ("%02d", $month);
                 my $day=sprintf ("%02d", $time[3]);
                 $hour=$time[2];
                 $min=$time[1];
                 $file_scr[$file_counter][1]=sprintf ($day.".".$month.".".$year) ;
                 $file_counter++;}


for my $i (0...$#file_scr) { $selvarlist->{"$i,0"}= $file_scr[$i][0]; $selvarlist->{"$i,0"}=~s/.do//; 
$selvarlist->{"$i,1"}=decode('koi8r',$file_scr[$i][1]); }
$selvarlist->{'-1,0'} =decode ('koi8r', '��� �����'); $selvarlist->{'-1,1'} = decode ('koi8r','���� ��������');

$seldat=$selwin->Scrolled('TableMatrix',-scrollbars=>'osoe',-rows=>($#file_scr+2), -cols=>2,
  -variable=>$selvarlist, -font=>$INI{sys_font}, -bg=>'white',
  -roworigin=>-1, -titlerows=>1, -colorigin=>0, -state=>'disabled', -selecttitles=>1,
  -selectmode=>'single', -pady=>10, -padx=>10, -height=>6,
  -cursor=>'top_left_arrow', -resizeborders=>'both');
$seldat->colWidth(0=>50, 1=>25);
$seldat->tagConfigure('title',-relief=>'raised');

$seldat->tagConfigure('NAME', -anchor=>'w');
$seldat->tagCol('NAME',0);
$seldat->pack(-expand=>1,-side=>"top", -fill=>'both');

my $save_button=$selwin->Button(-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','������� ����� ����'),-command=>sub{my $idx=shift; &$SaveDO($final_value, $rd, $redac_flag, $f_name, $redODC_flag); })
->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>20,-pady=>15,-side=>'bottom');
my $del_hand;
$del_hand=sub {my ($idx, $point)=@_; my @file; for my $i (0...$#{$point}) {$file[$i]=$point->[$i]; };   unlink "/mnt/Data/TestDescriptors/$dir_name/$file[$idx]";
};

my $hand;
$hand = sub{  
	     my ($idx, $point)=@_;
	     my @file; for my $i (0...$#{$point}) {$file[$i]=$point->[$i]}; 
	     $file[$idx]=~s/\.do//;
             #$$final_value=~s/\[DO\]/[$file[$idx]]/; 
	     $$final_value="��������_��������� [$file[$idx]]";
	     &$finish() };
$seldat->pack(-expand=>1, -fill=>'x', -ipady=>10);
$seldat->bind('<3>', sub {
        my $w=shift; my @as=$w->curselection(); my $popup;
        (my $r, my $c)=split(/\,/, $as[0]);
	if ($r>=0) {
        unless (defined $popup) { $popup=$w->Menu('-tearoff'=>0,-font=>$INI{but_menu_font}) };
         $popup->command(-label=>decode('koi8r','�������������'),-bg =>'gray85',-command=> sub{
	 my $idx=shift; $redac_flag=1; &$SaveDO($final_value, $rd, $redac_flag, $point->[$r], $redODC_flag); }); 
	 $popup->command(-label=>decode('koi8r','�������'),-bg =>'gray85',-command=> sub{
         my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r','������������� �������?'),
          -bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
                        if ($ans eq 'No') { return }
                        &$del_hand($r, $point); splice @$point,$r,1;
			@file_scr=();
			$cmnt_do=1;
			my $file_list=`ls /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
			my @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// };
			$point=\@file;
			$seldat->configure(-state=>'normal'); $seldat->deleteRows($r); $seldat->configure(-state=>'disabled');
			&$tab_redraw();
 } );
        if (defined $popup) {   $popup->Popup(-popover=>'cursor',-popanchor=>'nw') }
        Tk->break }} );
$seldat->bind('<1>', sub {

        my $w = shift; my $Ev = $w->XEvent;
        my $r = $w->index('@'.$Ev->x.','.$Ev->y); ($r,my $c) = split /\,/,$r;
	my $file_list=''; #���������� ��� ���������� ������ ���� ������
	my @file=''; #������ ��� ���������� ������ ���� ������
 
	if ($r>=0) {
	if ($selvarlist->{"$r,0"} eq '' ) { 
		$base->bell; return } 
	else { &$hand($r, $point) }; $selwin->destroy;}
        else {
		@file=();
            if ($c==0) { # ������������
            if ($cmnt_do==1) {  
	        $file_list=`ls -r /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
        	@file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
        	#$redODC_flag = 0;
        	$cmnt_do=0 ;}
            else {  
                $file_list=`ls /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
                @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
                #$redODC_flag = 0; 
		$cmnt_do=1;}
		$point=\@file;
                &$tab_redraw();
		}
         elsif ($c==1) { #����
            if ($usr_do==0) {  $file_list=`ls -tr /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
                @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
                #$redODC_flag = 0;
 		$usr_do=1 }
            else {  $file_list=`ls -t /mnt/Data/TestDescriptors/$dir_name/|(grep .do) 2>/dev/null`;
                 @file=split /\n/,$file_list; foreach (@file) { chomp; s/(^\S+#)// }
                # $redODC_flag = 0;
		$usr_do=0 }
                $point=\@file;
	       	&$tab_redraw();
               #$selwin->destroy; 
}
                 };

	Tk->break } );
$seldat->bind('<Motion>', sub {
   my $w=shift; my $Ev=$w->XEvent;  $w->selectionClear('all');
         $w->selectionSet('@'.$Ev->x.','.$Ev->y);  Tk->break } );
$selwin->bind('<Escape>', sub { $selwin->destroy } );
$selwin->protocol('WM_DELETE_WINDOW', sub { $selwin->destroy } );
$selwin->waitVisibility; $selwin->grab; }


sub HelpPage {
my $HW=$base->Toplevel(@Tl_att, -title=>'Help');
my $H=$HW->Scrolled('Text',-scrollbars=>'osoe',-spacing1=>5,-font=>$INI{sys_font})->pack(-expand=>1, -fill=>'both');
my $hlp_file='/mnt/NFS/commonCMK/pl/batch_test.txt';
my $txt=`cat $hlp_file`;
$H->insert('0.0',decode('koi8r',$txt));
$HW->bind('<F12>'=>sub{ open (NHF,">batch_test.txt"); print NHF $H->get(1.1-1,'end'); close(NHF) } ) }

sub Suicide {
undef $sock_in_wtchr, undef $time_wtchr;
$paused_flag=0;
#$done->send();
#Volkov �������� ������ ��������� � ������ �����, ��������� ������ � ������� ���� ���������
shutdown($S_RCV,2); close($S_RCV);
foreach my $crate(0 .. 3) {
my $S_stop=substr( $S_OUT[$crate],0,64);
substr( $S_stop,0,4,pack "I",0x250 ); substr( $S_stop,4,4,pack "I",64 ); substr( $S_stop,40,4,pack "I",0 );
#if (scalar @{$Scyc[$crate]}) { #����� �� ����� ����? Volkov
if ($crate_tot[$crate]) { shutdown($S_SND[$crate],2); close($S_SND[$crate]) }
	#send($S_SND[$crate], $S_stop, 0, $sin_to[$crate]); 
	if ($log_trs) { PrintSock(\$S_stop, $crate) }

}

#if (defined $rpt) { $rpt->cancel }
$dbh->do(qq(UPDATE cmtr_chnl set busy=0 WHERE busy=$packID));
$dbh->do(qq(UPDATE vme_ports set busy=0 WHERE port_in=$port_vme_to));
$dbh->do(qq(DELETE from packs WHERE id=$packID));
$dbh->do(qq(UPDATE imi SET busy=0,busy_type=NULL WHERE busy=$$));
if ($INI{UnderMonitor}) { $mes[0]=$packID; $mes[1]='kill'; PageMonitor() }
if ($log or $log_trs) { close(Log) }
close(Prot);
close($S_SND_I);
$base->destroy;
exit }

sub CheckFreeVMEport {
(my $id_port,$port_vme_to)=$dbh->selectrow_array(qq(SELECT id,port_in from vme_ports WHERE host="$my_host" and !busy ));
if (defined $id_port) { # ���� ���� ��������� ����
	$dbh->do(qq(UPDATE vme_ports set busy=1 WHERE id=$id_port)); # ����������� ���
	$port_vme_from=$port_vme_to+1; return 1 }
else { return 0 } }

sub WarnBusyVMEport {
my $base = MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
$base->title(decode('koi8r',"��������:"));
$base->Message(-anchor=>'center', -font=>$INI{err_font}, -foreground=>"$INI{err_forg}", -justify=>'center', -padx=>35, -pady=>10, -text=>decode('koi8r',qq(� ��������� ������ ��� ����� ������� ��� ��������� ������ vme.\n�� ������ ������� �����-�� �� ��� ���������� �������������� ���������� - � ������� ������ ���ͣ� �������������� ����\n��� ��������� �������.)), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
$base->Button(-command=>sub{ $base->destroy; exit(0); }, -state=>'normal', -borderwidth=>3, -font=>"$INI{but_menu_font}", -text=>decode('koi8r','OK '))->pack(-anchor=>'center', -pady=>10, -side=>'top');
$base->grab; MainLoop }

sub PageMonitor {
my $c='';
foreach (@mes) { $c.=$_.'|' }
chop $c;
# �������� ������ � ����������� ������� ���������
$shmsg->snd(1, $c) or warn "choice to shmsg failed...\n";
# ������������� ��������
my $res=kill 'USR1', $mntr_pid;
if ($res!=1) { $base->bell; warn "choice: kill return $res" } }

sub NoShare {
my $base = MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
$base->title(decode('koi8r',"������:"));
$base->Message(-anchor=>'center', -font=>$INI{err_font}, -foreground=>"$INI{err_forg}", -justify=>'center', -padx=>35, -pady=>10, -text=>decode('koi8r',qq(������������ �� ���������������:\n��-��������, �� ��������� "����".\n��������� "���� ����/����" \n� - �����������������.)), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
$base->Button(-command=>sub{ $base->destroy; exit(0); }, -state=>'normal', -borderwidth=>3, -font=>$INI{but_menu_font}, -text=>decode('koi8r','OK '))->pack(-anchor=>'center', -pady=>10, -side=>'top');
$base->protocol('WM_DELETE_WINDOW',sub{ $base->destroy; exit(0); } );
$base->grab;
MainLoop; }

sub RestoreShmem {
my @shmem=<PF>; close(PF);
($mysql_usr, $mntr_pid)=split(/\|/,$shmem[0]);}

sub StationAtt {
my ($hostname,$name,$aliases,$station);
chop($hostname = `hostname`);
($name,$aliases,undef,undef,undef) = gethostbyname($hostname);
my @al=split /\s+/,$aliases;
unshift @al,$name;
foreach my $ws (@al) { if ($ws=~/ws\d+$/) { $station=$ws; last } }
return $station }

#* �/�� ���������� ������ *#
sub RunTest {
my ($cmnd,$comment,$var0,$var1,$var_key,$var_val,$sock_err,$sec,$pause,$ch,$k,$l,$msk_hide,$kv);
my ($sys_num,$set_num,$c_sys_num,$c_set_num,$prm_id,$var_ctrl,$value,$valuec,$print_prm,$range);
my $block_key;
#$S_IN=chr(0)x64;
$S_IN_UN=chr(0)x64;
$mkt_id=$out_id=-1; my $var_id; my $err_flag=0; my (@txt,@value);
foreach my $sys_id (@sys_imi) { # ��������� ��� ����������� �������
	$dbh->do(qq(UPDATE imi SET busy=$$,busy_type='Q' WHERE id_system=$sys_id AND target&2 AND (!busy OR busy_type!='D'))) }
$value=`date '+%-e %-B %-Y %X'`; my $koi_test_name=encode('koi8r',$test_name);
print Prot "\n��� ������: $stand_name\n���������: $koi_test_name\n����:$value";
for my $i (0..$#{$descfile}) {
	if ($vme_crash) { last }
	$descrtab->clearTags(); $descrtab->tagCell('Run',"$i,0"); $descrtab->tagCol('DAT',0);
	($cmnd,$comment)=split /\s+/,$descfile->[$i],2; $comment=~s/\[//; $comment=~s/\]//;
	if ($descfile->[$i]=~/^������_�����_������_�_��/) {
		#CreateBuffers();
		$out_id++; #����������� ������� ������ (�� -1)
		for my $crate (0 .. 3) {
		$block_key=$crate.$out_id; #������� ���� ��� ���� out_str Volkov
		if (!defined ($out_str{$block_key})) {next; }#���� ������ ���� ������ ��� �������� ������ ����, ��������� � ����������
		$S_OUT[$crate]=substr($S_OUT[$crate],0,64);
		$S_OUT[$crate].=$out_str{$block_key}; 
		substr($S_OUT[$crate],0,4,pack "I",0x200); # �������
		substr($S_OUT[$crate],4,4,(pack 'I',(length $S_OUT[$crate]))); # ����� ������ � ����������
		#substr($S_OUT[$crate],16,4,pack "I",0); # ������ ����.������ - 0
		#substr($S_OUT[$crate],40,4,(pack 'I',(((length $S_OUT[$crate])-64)>>3)));  # ������� �������
		substr($S_OUT[$crate],40,4,(pack 'I', $rcnt{$block_key}));
##		if (0) {
		if (!defined send($S_SND_I, $S_OUT[$crate], 0, $sin_to[$crate])) { # ������ � ����, �������?
			$base->bell; if ($log) { print Log "send fail\n" } }
		else { if ($log_trs) { PrintSock(\$S_OUT[$crate], $crate)
		 } } }}
	elsif ($descfile->[$i]=~/^���������_�����/) {
		$mkt_id++; $var0=$mkt[$mkt_id]; $var_id=1 
		}
	elsif ($descfile->[$i]=~/^������_������_��_��/) {
		my $cicle_flag=0; #����, �������� �� ����������� ������
		undef $sock_in_wtchr;
		$var_key=$var0->[1]; $var_id++; $var_val=$var0->[$var_id];
	        #CreateBuffers();
	        for my $crate (0 .. 3) { if ($crate_tot[$crate]){   #Volkov crate_tot -> ���� ������� ������ � ������� ������
		$S_OUT[$crate]=substr($S_OUT[$crate],0,64); #$comment=~/ DT=([.1234567890]+) /; $sec=$1; $comment=~/( T=)([.1234567890]+)/; $pause=$2+0;
		}}#Volkov
		foreach my $vme_prm_id (@$var_key)  {$S_OUT[$send_crate{$vme_prm_id}].=pack 'I',$vme_prm_id ; } # ��������� $S_OUT �� ������ @$var_key 
		for my $crate (0 .. 3) {
		if ($crate_tot[$crate]){
		$comment=~/ DT=([.1234567890]+) /; $sec=$1; $comment=~/( T=)([.1234567890]+)/; $pause=$2+0; 
		if ($comment=~/^CLR /) { # � ����������
			if ($pause) {$cicle_flag=1; substr $S_OUT[$crate],0,4,pack "I",0x220 } # ����������
			else { substr $S_OUT[$crate],0,4,pack "I",0x240 } } # ����������
		else { # ��� ���������
			if ($pause) {$cicle_flag=1; substr $S_OUT[$crate],0,4,pack "I",0x210 } # ����������
			else { substr $S_OUT[$crate],0,4,(pack "I",0x230) } } # ����������
		substr($S_OUT[$crate],4,4,(pack 'I',(length $S_OUT[$crate]))); # ����� ������ � ����������
		substr( $S_OUT[$crate],16,4,pack "I", int($sec*1000000) ); # ������ ����.������ (���) - � S_OUT
		substr($S_OUT[$crate],40,4,(pack 'I',(((length $S_OUT[$crate])-64)>>2))); # ������� �������
		$sock_err=$vme_crash=0; unless ($pause) { $pause=$sec*2 } # ��� ������������ ������ �����=��������*2
		#$sec*=1000; $sec-=2;
		$buf_length[$crate]=length $S_OUT[$crate]; }}
		$sec*=1000; $sec-=2;
 # "������������" �������� ������������ ������
##		
###=cut
##if (0) {
#Volkov ������� �������� ����� 
 		$sock_in_wtchr=AnyEvent->io(fh=>\*$S_RCV, poll=>"r", cb=>sub{recvVME($i, $sock_err, $mkt_id)} );
		foreach my $crate (0 .. 3) {
			if ($crate_tot[$crate]) {
				if (!defined send($S_SND[$crate], $S_OUT[$crate], 0, $sin_to[$crate])) {# ������ � VME, �������?
					$base->bell; if ($log) { print Log "send fail\n" } } # ���
			else { # �������  
				if ($log_trs) { PrintSock(\$S_OUT[$crate], $crate) }
                        	}}}
		#$sock_in_wtchr=AnyEvent->io(fh=>\*$S_RCV, poll=>"r", cb=>sub{recvVME($i, $sock_err, $mkt_id)} );
		#$rpt=$base->repeat($sec, \$recvVME); # next read - ����� ���.��������
			#&$recvVME() }
		$paused_flag=1; $pause*=1000; 
		#$time_wtchr=AnyEvent->timer(after=>$pause, cb=>sub{$paused_flag = 0;} ); 
		$aftr=$base->after($pause,sub{ $paused_flag=0 } );
		#$done->recv();
		$base->waitVariable(\$paused_flag); # ����� �����
## comment next 3 lines for local
		if ($cicle_flag==1) {
		foreach my $crate (0 .. 3) {
		if ($crate_tot[$crate]) {
	     	$S_OUT[$crate]=substr($S_OUT[$crate],0,64);
		substr( $S_OUT[$crate],0,4,pack "I",0x250 ); substr( $S_OUT[$crate],4,4,pack "I",64 ); substr( $S_OUT[$crate],40,4,pack "I",0 );
		send($S_SND[$crate], $S_OUT[$crate], 0, $sin_to[$crate]); if ($log_trs) { PrintSock(\$S_OUT[$crate], $crate) }}}}; #$rpt->cancel ����������
		for my $j (0..$#{$var_key}) {# ��������� ���������� ���������� ������ � @$var_val
##			$value=unpack 'I', substr($S_OUT,$j*4+64,4); # 32 ���� - ��������
			$value=unpack 'I', substr($S_IN[$mkt_id],$j*4+64,4); # 32 ���� - ��������
			$var_val->[$j]=$value }} 
	elsif ($descfile->[$i]=~/^��������_�_������������_�������/) {
		$var_key=$var0->[0]; # ��� ����� ������ ����������
		$var_val=$var0->[$var_id]; # ��� ����� �������������� INPUT_FROM_VME
		$var_id++; $var_ctrl=$var0->[$var_id]; # ��� ����� ����������� ��������
		print Prot "\n*** ���������� ��������� ($descfile->[$i]) ***\n"; $err_flag=$c_sys_num=$c_set_num=0;
		$print_prm=sub { # ������ ���� ����������
			if ((defined $descfile->[$i+1]) and ($descfile->[$i+1]=~/^����������������_�������/)) { return }
			if ($#txt==-1) { print Prot "��� ������\n"; return }
			my $txt; foreach (@txt) { # ��� ���� ��������� @txt
			$txt=$_.(' ' x (maxlen(\@txt)-length($_))).' <'.shift(@value); # ��������� ����� + ������� + ��������
			print Prot "$txt\n" } }; # ����� � ��������
		foreach my $j (0..$#{$var_key}) { # ��� ���� ��������� (� �����������) ��������
			$var_key->[$j]=~/(\d\d\d)(\d)(\d+)/; $sys_num=$1+0; $set_num=$2+0; $prm_id=$3+0;
			if ($sys_num!=$c_sys_num or $set_num!=$c_set_num) { # ��������� ��������
				if ($c_sys_num) { &$print_prm() }
				unless ((defined $descfile->[$i+1]) and ($descfile->[$i+1]=~/^����������������_�������/)) {
					print Prot "\n$sys->[$sys_atr{$sys_num}][NAM] �������� $set_num\n" } # ��������� �������
				@txt=@value=(); $c_sys_num=$sys_num; $c_set_num=$set_num } # ������� - �����
			# ������� �������� ������ ������ (�� ������ ������)
			push @txt,qq($prm->[$prm_atr{$prm_id}][CHA] $prm->[$prm_atr{$prm_id}][NAM]);
			#my $value11=($prm->[$prm_atr{$prm_id}][VT]==RK)?0|~$var_val->[$j]:$var_val->[$j];
			if ($prm->[$prm_atr{$prm_id}][VT]==RK) {
				$value=(~$var_val->[$j]);
		                my $buff32 = pack 'I', $value;
				$value = unpack "I", substr($buff32, 0, 4);
			}
			else {
				$value=$var_val->[$j];}
			
			$valuec=prepPV($prm_id,$value); BinView(\$valuec); $valuec.='> ('.prepVV($prm_id,$value,1).')'; # �������� 1-� ������
			push @value,$valuec;
			$valuec=$var_ctrl->[$j]; $msk_hide=$kv=0;
			if ($valuec=~/;/) { ($valuec,$range)=split /;/,$valuec } else { undef $range }
			for my $k (0..31) { if (substr($valuec,$k,1) eq '1') { $kv|=0x80000000>>$k } }
			for my $k (0..31) { $ch=substr($valuec,$k,1);
				if ($ch eq $hide_char or $ch eq $skip_char) { $msk_hide|=0x80000000>>$k } }
			if ((0+$value|$msk_hide) != (0+$kv|$msk_hide)) {
				$ch=CheckPlus($prm_id,$value,$kv,$msk_hide,$range);
				if ($ch&1) { $value[$#value].=' !' }
				if ($ch&2) { $value[$#value].=$Ip }
				if ($ch&4) { $value[$#value].=$Sp }
				if ($ch&8) { $value[$#value].=$Rp } }
			else { $ch=0 } # ��� ������ ����������
			BinView(\$valuec); push @txt,'';
			$valuec.='> ('.prepCVV($prm_id,$valuec,$range).')';
			if ($ch) { # �� ���������
				push @value,$valuec; $err_flag++ }
			else { # ���������
				pop @txt; pop @txt; pop @value } }
		&$print_prm(); # ����������� ��� @txt, @value

		if ($err_flag) { print Prot "������������������ ������ �� ��������� � ������������\n"; $success_flag++ }
		else { print Prot "������������������ ������ ��������� � ������������\n" } }
	elsif ($descfile->[$i]=~/^�����/) {
		$paused_flag=1; 
		#$time_wtchr=AnyEvent->timer(after=>$comment, cb=>sub{$paused_flag = 0; $done->send() } );
		#$done->recv();
		$comment*=1000; $base->after($comment,sub{ $paused_flag=0 } );
		$base->waitVariable(\$paused_flag) 
		}
	elsif ($descfile->[$i]=~/^��������_���������/){
		  $paused_flag=1;
		  (undef,my $file_do)=split /\s+/,$descfile->[$i],2; $file_do=~s/\s$//; $file_do=~s/\[//; $file_do=~s/\]//;
		  open (FILE, "/mnt/Data/TestDescriptors/$dir_name/$file_do.do");
		  my @file_txt = <FILE>;
		  close FILE;
		  my $file_str='';
		  for my $i(0..$#file_txt) {
		  $file_str.=$file_txt[$i];
		  } 
		  my $title="�������� ���������";
		  my $selwin=$base->Toplevel(@Tl_att);
		  my $t=$base->geometry(); (undef,$t,my $s)=split /\+/,$t;
		  $selwin->geometry("+$t+$s");
		  $selwin->title(decode('koi8r',$title));
		  $selwin->Message(-anchor=>'center',-padx=>20,-pady=>2,-font=>"$INI{err_font}",-width=>1000,
                -text=>decode('koi8r',"������� ��������� �������������!\n�������� ������ ��������� ��������� ��������:"))
                ->pack(-fill=>'x', -side=>'top', -ipadx=>10, -ipady=>10);
		  #$selwin->Message(-anchor=>'w',-padx=>20,-pady=>2,-font=>"Times 15 italic", -width=>450,
                #-text=>decode('koi8r', $file_str))
                #->pack(-fill=>'x', -side=>'top', -ipadx=>20, -ipady=>10);
                  my $m_entry=$selwin->Text(-font=>"Times 15",-fg=>"$INI{d_forg}",-bg=>"$INI{d_back}", -width=>60, -height=>6)->pack(-padx=>25,-expand=>1, -fill=>'both');
		  $file_str=decode('koi8r', $file_str);
		  $m_entry->insert('1.0',$file_str); 
		  #my $ys = $m_entry->Scrollbar(-orient =>'vertical', -command=> [$m_entry, "yview"]);
		  #$ys->pack(-padx=>0, -side=>'right', -fill=>'y' );
		  $m_entry->configure(-state=>"disabled");
		  $selwin->Message(-anchor=>'center',-padx=>20,-pady=>2,-font=>"$INI{err_font}",-width=>1000,
                -text=>decode('koi8r', "��� ����������� ��������� ������ ������ \"����������\""))
                ->pack(-fill=>'x', -side=>'top', -ipadx=>10, -ipady=>10);


		  my $cotinue_button=$selwin->Button(-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','����������'),
		  -command=>sub{$paused_flag=0; $selwin->destroy})
		  ->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>20,-pady=>15,-side=>'bottom');
		  $selwin->bind('<Escape>', sub {$paused_flag=0; $selwin->destroy } );
		  $selwin->protocol('WM_DELETE_WINDOW', sub { $paused_flag=0; $selwin->destroy } );
		  $selwin->waitVisibility; $selwin->grab;
 		  $base->waitVariable(\$paused_flag)
 }
 

	elsif ($descfile->[$i]=~/^����������������_�������/) {
		($cmnd,undef)=split /\s+/,$descfile->[$i-1],2; $c_sys_num=$c_set_num=0;
		if ($cmnd eq '�����' or $cmnd eq '����������������_�������') { next }
		print Prot "\n*** $descfile->[$i] ($descfile->[$i-1]) ***";
		if ($cmnd eq '���������_�����') {
			$var_key=$var0->[0];
			foreach my $key (@$var_key) {
				$key=~/(\d\d\d)(\d)(\d+)/; $sys_num=$1+0; $set_num=$2+0; $prm_id=$3+0;
				if ($sys_num!=$c_sys_num or $set_num!=$c_set_num) { # ����� ���������������
					$c_sys_num=$sys_num; $c_set_num=$set_num;
					print Prot "\n$sys->[$sys_atr{$sys_num}][NAM] �������� $set_num\n" }
				print Prot "$prm->[$prm_atr{$prm_id}][CHA] $prm->[$prm_atr{$prm_id}][NAM]\n" } }
		elsif ($cmnd eq '������_�����_������_�_��') {
                        my (@var_val_output)=();
			$var_key=\@{$out_key{$out_id}};
			$print_prm=sub { my $txt; foreach (@txt) { $txt=$_.(' ' x (maxlen(\@txt)-length($_))).' '.shift(@value); print Prot "$txt\n" } };
			for my $j (0..$#{$var_key}) {
				$var_key->[$j]=~/(\d\d\d)(\d)(\d+)/; $sys_num=$1+0; $set_num=$2+0; $prm_id=$3+0;
				$var_val.=$out_val{$var_key->[$j]};
				if ($sys_num!=$c_sys_num or $set_num!=$c_set_num) { # ����� ���������������
					if ($c_sys_num) { &$print_prm() } # �� ������ �������
					print Prot "\n$sys->[$sys_atr{$sys_num}][NAM] �������� $set_num\n";
					@txt=@value=(); $c_sys_num=$sys_num; $c_set_num=$set_num }
				push @txt,qq($prm->[$prm_atr{$prm_id}][CHA] $prm->[$prm_atr{$prm_id}][NAM]);
				#$value=($prm->[$prm_atr{$prm_id}][VT]==RK)?0|~(unpack 'I',substr($var_val,$j*8+4,4)):(unpack 'I',substr($var_val,$j*8+4,4));
				$value=unpack 'I', substr($var_val,$j*8+4,4);
				$valuec=prepPV($prm_id,$value);
				#$valuec=sprintf "%032b",$value; 
				BinView(\$valuec);
				$value=bin2ascii($prm->[$prm_atr{$prm_id}][VT], $prm->[$prm_atr{$prm_id}][FSB],
					$prm->[$prm_atr{$prm_id}][LSB], getNDIG($prm->[$prm_atr{$prm_id}][VT],$prm->[$prm_atr{$prm_id}][NDG]),
					$prm->[$prm_atr{$prm_id}][NC],$value,'1');
				$value=~s/\s//g; push @value,qq($valuec  ($value $prm->[$prm_atr{$prm_id}][UNT])) }; &$print_prm() }
		elsif ($cmnd eq '��������_�_������������_�������') {
		$var_key=$var0->[0]; $var_val=$var0->[$var_id-1]; $var_ctrl=$var0->[$var_id];
			$print_prm=sub { # ������ ���� ����������
				my $txt; foreach (@txt) { # ��� ���� ��������� @txt
					$txt=$_.(' ' x (maxlen(\@txt)-length($_))).' <'.shift(@value); # ��������� ����� + ������� + ��������
					print Prot "$txt\n" } }; # ����� � ��������
			foreach my $j (0..$#{$var_key}) { # ��� ���� ��������� (� �����������) ��������
				$var_key->[$j]=~/(\d\d\d)(\d)(\d+)/; $sys_num=$1+0; $set_num=$2+0; $prm_id=$3+0;
				if ($sys_num!=$c_sys_num or $set_num!=$c_set_num) { # ��������� ��������
					if ($c_sys_num) { &$print_prm() }
					print Prot "\n$sys->[$sys_atr{$sys_num}][NAM] �������� $set_num\n"; # ��������� �������
					@txt=@value=(); $c_sys_num=$sys_num; $c_set_num=$set_num } # ������� - �����
				# ������� �������� ������ ������
				push @txt,qq($prm->[$prm_atr{$prm_id}][CHA] $prm->[$prm_atr{$prm_id}][NAM]); # ��������� ����� 1-� ������
				#$value=($prm->[$prm_atr{$prm_id}][VT]==RK)?0|~$var_val->[$j]:$var_val->[$j];
			        if ($prm->[$prm_atr{$prm_id}][VT]==RK) {
                                $value=(~$var_val->[$j]);
                                my $buff32 = pack 'I', $value;
                                $value = unpack "I", substr($buff32, 0, 4);
	                        }
        	                else {
                                $value=$var_val->[$j];}
				$valuec=prepPV($prm_id,$value); BinView(\$valuec); $valuec.='> ('.prepVV($prm_id,$value,1).')'; # �������� 1-� ������
				push @value,$valuec; # ��� �� - � ������ ��������
				# ����������� �������� ������ ������, ������� �������� ������ ������
				$valuec=$var_ctrl->[$j]; $msk_hide=$kv=0;
				if ($valuec=~/;/) { ($valuec,$range)=split /;/,$valuec } else { undef $range }
				for my $i (0..31) { if (substr($valuec,$i,1) eq '1') { $kv|=0x80000000>>$i } } # ��. ������������� ��
				for my $i (0..31) { $ch=substr($valuec,$i,1);
					if ($ch eq $hide_char or $ch eq $skip_char) { $msk_hide|=0x80000000>>$i } } # �����
				if ((0+$value|$msk_hide) != (0+$kv|$msk_hide)) {
					$ch=CheckPlus($prm_id,$value,$kv,$msk_hide,$range);
					if ($ch&1) { $value[$#value].=' !' }
					if ($ch&2) { $value[$#value].=$Ip }
					if ($ch&4) { $value[$#value].=$Sp }
					if ($ch&8) { $value[$#value].=$Rp } }
				BinView(\$valuec); push @txt,''; # ��������� ����� 2-� ������
				$valuec.='> ('.prepCVV($prm_id,$valuec,$range).')'; # �������� 2-� ������
				push @value,$valuec } # ��� �� - � ������ ��������
				# ����������� �������� ������ ������
			&$print_prm() } # ����������� ��� @txt, @value


		elsif ($cmnd eq '������_������_��_��') {
			$var_key=$var0->[0]; $var_val=$var0->[$var_id];  
			foreach my $j (0..$#{$var_key}) { # ��� ���� ��������� ��������
				$var_key->[$j]=~/(\d\d\d)(\d)(\d+)/; $sys_num=$1+0; $set_num=$2+0; $prm_id=$3+0;
				$print_prm=sub { my $txt; foreach (@txt) { $txt=$_.(' ' x (maxlen(\@txt)-length($_))).' '.shift(@value); print Prot "$txt\n" } };
				if ($sys_num!=$c_sys_num or $set_num!=$c_set_num) {
					if ($c_sys_num) { &$print_prm() }
					print Prot "\n$sys->[$sys_atr{$sys_num}][NAM] �������� $set_num\n";
					@txt=@value=(); $c_sys_num=$sys_num; $c_set_num=$set_num }
				push @txt,qq($prm->[$prm_atr{$prm_id}][CHA] $prm->[$prm_atr{$prm_id}][NAM]);
				#$value=($prm->[$prm_atr{$prm_id}][VT]==RK)?0|~$var_val->[$j]:$var_val->[$j];
				if ($prm->[$prm_atr{$prm_id}][VT]==RK) {
                                	$value=(~$var_val->[$j]);
                                	my $buff32 = pack 'I', $value;
                                	$value = unpack "I", substr($buff32, 0, 4);
                                }
                                else {
	                                $value=$var_val->[$j];}
				$valuec=prepPV($prm_id,$value); BinView(\$valuec); 
				$value=bin2ascii($prm->[$prm_atr{$prm_id}][VT], $prm->[$prm_atr{$prm_id}][FSB],
					$prm->[$prm_atr{$prm_id}][LSB], getNDIG($prm->[$prm_atr{$prm_id}][VT],$prm->[$prm_atr{$prm_id}][NDG]),
					$prm->[$prm_atr{$prm_id}][NC],$value,1);
				$value=~s/\s//g; push @value,qq($valuec  ($value $prm->[$prm_atr{$prm_id}][UNT])) }; &$print_prm() } } }
undef $time_wtchr; undef $sock_in_wtchr;
$dbh->do(qq(UPDATE imi SET busy=0,busy_type=NULL WHERE busy=$$)) } # ���������� ��� ����������� �������

sub CheckPlus {
my ($prm_id,$pv,$kv,$msk_hide,$range)=@_; my ($xr,$xc);
my $vt=$prm->[$prm_atr{$prm_id}][VT]; my $ret=0; my $msk_i=my $msk_s=0;
for my $i ($prm->[$prm_atr{$prm_id}][FSB]..$prm->[$prm_atr{$prm_id}][LSB]) { $msk_i|=0x00000001<<($i-1) } # ����� ���. �����
unless (defined $range) { $range=0 }; $msk_s=0|~$msk_i; # ����� ��. �����
if ($range eq $MaxRange) {
	if ($vt==GMS) { $range=$prm->[$prm_atr{$prm_id}][NC]*60*60 }
	else { $range=$prm->[$prm_atr{$prm_id}][NC] *2 } }
if ($vt==RK) { $ret=1 }
elsif ($vt==DDK or $vt==DDK100 or $vt==DS00 or $vt==DS11 or $vt==INT00 or $vt==INT11) { # ���, ��, "��������"
	if ((0+$pv&$msk_s|$msk_hide) == (0+$kv&$msk_s|$msk_hide)) { $ret=2 } # ��!
	else { if ((0+$pv&$msk_i|$msk_hide) == (0+$kv&$msk_i|$msk_hide)) { $ret=4 } # ��!
				 else { $ret=4+2 } } } # ��!��!
elsif ($vt==DK or $vt==GMS or $vt==AS) { # 00, 03, 15
	$xr=bin2ascii($vt,$prm->[$prm_atr{$prm_id}][FSB],$prm->[$prm_atr{$prm_id}][LSB],
		getNDIG($vt,$prm->[$prm_atr{$prm_id}][NDG]),$prm->[$prm_atr{$prm_id}][NC],$pv,1); # ��������
	$xc=bin2ascii($vt,$prm->[$prm_atr{$prm_id}][FSB],$prm->[$prm_atr{$prm_id}][LSB],
		getNDIG($vt,$prm->[$prm_atr{$prm_id}][NDG]),$prm->[$prm_atr{$prm_id}][NC],$kv,1); # ��������
	if ($vt==GMS) { $xr=gms2sec($xr); $xc=gms2sec($xc) } # ��:��:��
	if ((0+$pv&$msk_s|$msk_hide) == (0+$kv&$msk_s|$msk_hide)) { # ����==����
		if ($xr>=($xc-$range) and $xr<=($xc+$range)) { $ret=0 } # ������������ � ������
		else {
			if ($vt==DK and $prm->[$prm_atr{$prm_id}][NC]==90 # NC == 90 ��� ���� 00
				and 180>=($xc-$range) and 180<=($xc+$range) # 180 - � �������
				and $xr>=-180 and $xr<=($xc+$range-360) ) { $ret=0 } # ������������ � ������ ��� NC=90
			elsif ($vt==DK and $prm->[$prm_atr{$prm_id}][NC]==90
				and -180>=($xc-$range) and -180<=($xc+$range) # -180 - � �������
				and $xr>=($xc-$range+360) and $xr<=180) { $ret=0 }
			elsif ($vt==GMS # ��� ���� 03, 180 - � �������
				and 648000>=($xc-$range) and 648000<=($xc+$range)
				and $xr>=-648000 and $xr<=($xc+$range-648000*2) ) { $ret=0 }
			elsif ($vt==GMS # ��� ���� 03, -180 - � �������
				and -648000>=($xc-$range) and -648000<=($xc+$range)
				and $xr>=($xc-$range+648000*2) and $xr<=648000) { $ret=0 } 
			else { $ret=8 } } } # ��!
	else { # ����!=����
		if ($xr>=($xc-$range) and $xr<=($xc+$range)) { $ret=4 } # ��!
		else { $ret=4+8 } } } # ��!��!
return $ret }

#* �/�� ���������� ������ *#
sub PrepareData {
@mkt=@sys_imi=();%out_val=(); %out_str=(); %out_key=();  %imi_avail=(); my @for_crate_imi; my $ret=1; my ($var0,$var_key,$var_val);
my ($comment,@file,$val,$key,$value,@dat,$id,$sys_id,$c_sys,$sysset); my (@ar,@el,@k); my (%set,%dat); 
my %out_crate=(); #��� ������� ������� 
my @crate_imi=();
my $block_key; #���� ����� ������ ������ � out_key, ����� �����_������.�����_�����
my $block_counter = 0; #������� ������ ������ (���������� ������� OUTPUT_TO_VME) 
my $load_maket_counter = 0;
my %v_type = (); #��� ����� ����������
my %mask = (); #��� ����� ����������
%send_crate = (); #��� ������� �������, ������� �������� �������� vme_prm_id ����������
$row=$dbh->selectall_arrayref(qq(SELECT id_system,num_compl,id_parm,vme_prm_id, crate, v_type, mask FROM imi  
	WHERE target&2 AND (!busy OR busy_type='S') ORDER BY id_system,num_compl,id_parm)); # ��������� ��� ��������� ��������� ##���� �������� crate  Volkov
for my $i (0..$#{$row}) { # ��� ���� ��������� ����������
	$key=Key($row->[$i][0],$row->[$i][1],$row->[$i][2]); $imi_avail{$key}=$row->[$i][3]; $send_crate{$row->[$i][3]}=$row->[$i][4]; 
	$out_crate{$key}=$row->[$i][4]; $v_type{$key}=$row->[$i][5]; $v_test{$row->[$i][3]}=$row->[$i][5]; $mask{$key}=$row->[$i][6]; push (@for_crate_imi, $row->[$i][4]);} 
	for my $i (0 .. 3) { $crate_imi[$i]=grep(/$i/,@for_crate_imi); }
	
for my $num (0..$#{$descfile}) { 
	(undef,$comment)=split /\s+/,$descfile->[$num],2; $comment=~s/\[//; $comment=~s/\]//;
	if ($descfile->[$num]=~/^������_�����_������_�_��/) {
		#�������� �� ������������� ���������
		my @undef_prm;
		my $file=$dbh->selectrow_array(qq(SELECT data FROM sets WHERE comment="$comment"));
		(my $set_id, my $valid)=$dbh->selectrow_array(qq(SELECT id, valid FROM sets WHERE comment="$comment"));
	        unless ($valid) { # invalid set
                        unless ($dbh->selectrow_array(qq(SELECT id FROM invalidTS WHERE id_obj=$set_id AND type_obj='S'))) {
                                $dbh->do(qq(INSERT INTO invalidTS (id,id_obj,type_obj,date) VALUES (0,$set_id,'S',NOW()))) }
                        my $comment_msg=$comment;
	                $comment_msg=~ s/\s+$//g;
			my $mes="����� \"$comment_msg\" �������� ������������ ������. ���������� � ��������������";
                        my @koiYN=(decode('koi8r','������������ � ����������'),decode('koi8r','���������� �� ��������'));
                        my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq($mes)),
                                -bitmap=>'question',-buttons=>\@koiYN ); my $ans=$dlg->Show(-global);
                        if ($ans eq $koiYN[1]) { return } }
		my @ar_r=split /\n/,$file;
		foreach $str (@ar_r) {
			chomp $str; ($key,$val)=split /:/,$str; $key=~/(....)(.+)/m; $key=$1.($2+0);
			unless (exists $stor->{$key}) { $key=~/(...)(.)(.+)/m; $key=$1.' '.$2.' '.$3; push @undef_prm,$key; $str='foo' } }
		@ar_r=grep { $_ ne 'foo' } @ar_r;
		if (scalar @undef_prm) {
			my $mes.="� ������ $comment ������ �������������� ���������\n(sss k parmid):\n";
		        foreach (@undef_prm) { $mes.=$_.' '; $mes.="\n" }
		        my @koiYN=(decode('koi8r','����������'),decode('koi8r','�� ����������'));
		        my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq($mes)),
		         -bitmap=>'question',-buttons=>\@koiYN ); my $ans=$dlg->Show(-global);
		        if ($ans eq $koiYN[1]) { return } };
		#����� ��������
		for my $i (0..3) {
		$rcnt{$i.$block_counter}=0;} #�������� �������� ����� ���������� ��� ���������� 
		$file[$block_counter]=$dbh->selectrow_array(qq(SELECT data FROM sets WHERE comment="$comment"));
		if (length($file[$block_counter])==0) { ErrMessage($err[7],$comment); SetErrTag($num); $ret=0; last }
#		unless ( defined $file ) { ErrMessage($err[7],$comment); SetErrTag($num); $ret=0; last }
#		unless ( -e "/mnt/Data/Sets/$dir_name/$file" ) { ErrMessage($err[17],$comment); SetErrTag($num); $ret=0; last }
		@ar=split /\n/,$file[$block_counter]; %set=();
		for my $i (0..$#ar) { chomp ($ar[$i]); ($key,$value)=split /:/,$ar[$i]; $key=~/(....)(.+)/m; $key=$1.($2+0); $set{$key}=hex($value) }
		$val=''; $sys_id=0; $var_key=[]; 
		foreach my $key (sort keys %set) { # ��� ���� ���������� � ������
			if (exists $imi_avail{$key}) { # �������� ��������
				$key=~/(\d\d\d)(\d)(\d+)/; $c_sys=$1+0; $sysset=$2; $id=$3+0;
				if ($c_sys!=$sys_id) { $sys_id=$c_sys; unless (grep {$sys_id==$_} @sys_imi) {
					push @sys_imi,$sys_id } } # ������ ����� ������� ������� � @sys_imi
				$block_key=$out_crate{$key}.$block_counter;
				push @$var_key,$key; # ��������� ����
				if ($v_type{$key}==10) { #RK 
				$rcnt{$block_key}++;
				$out_str{$block_key}.=pack 'I',($imi_avail{$key}|0x80000000); 
                                $out_str{$block_key}.=pack 'I',$set{$key}; 
                                $out_str{$block_key}.=pack 'I',$mask{$key};
				$out_val{$key}.=pack 'I',($imi_avail{$key}|0x80000000);
                                $out_val{$key}.=pack 'I',$set{$key};
 				}
				else {
				$rcnt{$block_key}++;
				$out_str{$block_key}.=pack 'I',$imi_avail{$key}; # vme_prm_id
				$out_str{$block_key}.=pack 'I',$set{$key};			
				$out_val{$key}.=pack 'I',$imi_avail{$key}; # vme_prm_id
                                $out_val{$key}.=pack 'I',$set{$key};
				
 } # value
				delete $set{$key} } }
				#$max_buf_length= length ($S_IN);
                        push (@{$out_key{$block_counter}}, @$var_key);
                        $block_counter++; 
			if (scalar %set) { # � ������ ���������� ����������� ���������
			if ($log) { print Log '��� �������� ������ ',"$comment",'���������� ����������� ���������:',"\n";
				print Log 'sys k prm_id',"\n";
				foreach my $key (sort keys %set) { $key=~/(\d\d\d)(\d)(\d+)/; print Log "$1 $2 $3\n" } } } }
	elsif ($descfile->[$num]=~/^���������_�����/) { 
		$dat[$load_maket_counter]=$dbh->selectrow_array(qq(SELECT dat FROM templ WHERE comment="$comment")); # ������� �����
		#�������� ������� ��������� ���������� � ������
                ($pack,$tmpl_cmnt)=$dbh->selectrow_array(qq(SELECT dat,comment FROM templ WHERE comment="$comment"));
                #$bln->attach($SaveT,-msg=>decode('koi8r',$tmpl_cmnt));
                (my $templ_id, my $valid)=$dbh->selectrow_array(qq(SELECT id, valid FROM templ WHERE comment="$comment"));
                unless ($valid) { # invalid templ
                unless ($dbh->selectrow_array(qq(SELECT id FROM invalidTS WHERE id_obj=$templ_id AND type_obj='T'))) {
                        $dbh->do(qq(INSERT INTO invalidTS (id,id_obj,type_obj,date) VALUES (0,$templ_id,'T',NOW()))) }
                my $comment_msg=$comment;
		$comment_msg=~ s/\s+$//g;
		my $mes="����� \"$comment_msg\" �������� ������������ ������. ���������� � ��������������.\n����� ������������� ������ ������� ��������������� ���� ����������� ������ (���� ������� ������������)";
	        my @koiYN=(decode('koi8r','������������ � ����������'),decode('koi8r','���������� �� ��������'));
                my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq($mes)),
                                -bitmap=>'question',-buttons=>\@koiYN ); my $ans=$dlg->Show(-global);
                if ($ans eq $koiYN[1]) { return } }

		my @undef_prm=(); my @undef_sys=();
		%pack=split(/:/,$pack); my @prm=();
                foreach my $sys (keys %pack) {
                        unless (exists $all_sys{$sys}) { push @undef_sys,$sys; delete $pack{$sys}; next }
                        @prm=split(/,/,$pack{$sys});
                        foreach my $tok (@prm) {
                                if ($tok=~/^k/) { next }
                                unless (exists $all_prm{$tok}) { push @undef_prm,($sys.' '.$tok); $tok='000' } }
                        if (scalar @undef_prm) { $pack{$sys}='';
                                foreach my $tok (@prm) {
                                        if ($tok eq '000') { next }
                                        else { $pack{$sys}.=$tok.',' } }
                                $pack{$sys}=~s/,$// } }
                my $mes='';
                if (scalar @undef_sys) {
                        $mes.="� ������ $comment ������ �������������� �������:\n";
                        foreach (@undef_sys) { $mes.=$_.' ' }; $mes.="\n"}
                if (scalar @undef_prm) {
                        $mes.="� ������ $comment ������ �������������� ���������:\n";
                        foreach (@undef_prm) { $mes.=$_.' '; $mes.="\n" } }
                if ($mes ne '') {
                        my @koiYN=(decode('koi8r','����������'),decode('koi8r','�� ����������'));
                        my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>decode('koi8r','��������!'),-text=>decode('koi8r',qq($mes)),
                                -bitmap=>'question',-buttons=>\@koiYN ); my $ans=$dlg->Show(-global);
                        if ($ans eq $koiYN[1]) { return } }
		#����� ��������
		unless (defined $dat[$load_maket_counter]) { ErrMessage($err[6],$comment); SetErrTag($num); $ret=0; last }
		%dat=split /:/,$dat[$load_maket_counter]; # �������� �� �������
		$var0=[]; push @mkt,$var0; # ����� �����: ������ ���������� ��������
		$var_key=[]; push @$var0,$var_key; # ��������� ��������� ������� ������ ������ (������ 0-�������)
		$var_val=[]; push @$var0,$var_val; # ��������� ��������� ������� vme_prm_id ������ (������ 1-�������)
		for my $i (0 .. 3) { $buf_cr{$i.$load_maket_counter}=[] }
		foreach my $s_id (@sys_v_id) { # ��� ���� ������������ ������
			unless (exists $dat{$s_id}) { next } # ���� ������� �� ������ � �����
			@el=split /,/,$dat{$s_id}; # ��� �������� ��������� �������
			@k=grep(/(k\d)/, @el); foreach (@k) { s/k// }; # ������ ������ ����������
			while ($el[0]=~/k/) { shift @el } # ����� ��������� - ������ ���������
			foreach my $cmpl (@k) { # ��� ���� ����������
				unless (${$cmpl_r{$s_id}}[$cmpl - 1]) { next }; # ���� �������� ����������
				foreach my $id (@{$prm_v_id{$s_id}}) { # ��� ���� ����������
					unless (grep { $id==$_ } @el) { next } # ���� ��������� ��� ����� �����������
					$key=Key($s_id,$cmpl,$id); push @$var_key,$key; # ������ ������ ������
					$value=$prm->[$prm_atr{$id}][VPI]+$cmpl-1; # ������ vme_prm_id ������
					my $reg_crate= $dbh->selectall_arrayref(qq(SELECT crate FROM reg WHERE vme_prm_id=$value));
					$send_crate{$value}=$reg_crate->[0][0];
					push @$var_val,$value; # vme_prm_id ��� ��������������� ���������
					push @crate_reg, $reg_crate->[0][0];
					 } } }
					@crate_tot=();
					for my $i (0 .. 3) { $crate_tot[$i]=grep(/$i/,@crate_reg); }
					foreach my $i (0..$#{$var_val}) {
					push @{$buf_cr{$send_crate{$var_val->[$i]}.$load_maket_counter}}, $i; 
					}
					$S_IN[$load_maket_counter]=chr(0)x64;
					for my $i (0..$#{$var_val}) { 
						my $type= $dbh->selectall_arrayref(qq(SELECT parm.v_type FROM parm, reg  WHERE parm.id_parm=reg.id_parm AND reg.vme_prm_id=$var_val->[$i])); 
						if ($type->[0][0]==10) { $S_IN[$load_maket_counter].=pack 'I',0xFFFFFFFF } else { $S_IN[$load_maket_counter].=pack 'I',0 } } # ���������� ��. ������
					
				#	foreach (@$signvme) { $S_IN.=pack 'I',0 }
					
					$max_buf_length[$load_maket_counter]=length $S_IN[$load_maket_counter];
					$load_maket_counter++;
					 }
					
	elsif ($descfile->[$num]=~/^������_������_��_��/) {
		my $r=$num-1; while ($r>-1) { if ($descfile->[$r]=~/^���������_�����/) { last }; $r-- }
		if ($r==-1) { ErrMessage($err[12]); SetErrTag($num); $ret=0; last }
		$var0=$mkt[$#mkt]; # ��������� �������� ������
		$var_key=[]; push @$var0,$var_key } # ��������� ������� ��������� ������
	elsif ($descfile->[$num]=~/^��������_�_������������_�������/) {
		my $r=$num-1; 
		while ($r>-1) {	if ($descfile->[$r]=~/^������_������_��_��/) { last }; $r-- }
		if ($r==-1) { ErrMessage($err[16]); SetErrTag($num); $ret=0; last }
		$r=$num-1; while ($r>-1) { if ($descfile->[$r]=~/^���������_�����/) { last }; $r-- }
		if ($r==-1) { ErrMessage($err[8]); SetErrTag($num); $ret=0; last }
		$file[$block_counter]=$comment; $file[$block_counter]=~s/\, �����.+//; # ��� ����� �� �������
		(undef,my $comment)=split /\s+/,$descfile->[$r],2; $comment=~s/\[//; $comment=~s/\]//;
		$id=$dbh->selectrow_array(qq(SELECT id FROM templ WHERE comment="$comment")); # ������� CD �����
		unless (-e "/mnt/Data/CDfiles/$dir_name/$id#$file[$block_counter]") { # ���� � ����� ������ �� ����������
			ErrMessage($err[9],$file[$block_counter]); SetErrTag($num); $ret=0; last }
		open (IN,"/mnt/Data/CDfiles/$dir_name/$id#$file[$block_counter]"); @ar=<IN>; close(IN); %set=();
		foreach (@ar) { chomp; ($key,$value)=split /:/;  $set{$key}=$value } # ��� ������
		$var0=$mkt[$#mkt]; $var_key=$var0->[0]; $var_val=[]; push @$var0,$var_val; $id=0;
		foreach my $key (@$var_key) { if (exists $set{$key}) { push @$var_val,$set{$key} } else { $id++ } }
		if ($id) { ErrMessage($err[20],$file[$block_counter]); SetErrTag($num); $ret=0; last } }
		
	elsif ($descfile->[$num]=~/^��������_���������/) {
		(undef,my $file_name)=split /\s+/,$descfile->[$num],2; $file_name=~s/\[//; $file_name=~s/\]//; $file_name.='.do'; 
		unless (-e "/mnt/Data/TestDescriptors/$dir_name/$file_name") { # ���� � ����� ������ �� ����������
			my $message="���� �������� ��������� $file_name �� ����������.";
                        ErrMessage($message); SetErrTag($num); $ret=0; last } next;}}
            
return  $ret}

sub ErrMessage {
my ($txt,$r1,$r2)=@_;
my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
$er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
if (defined $r1) { $txt=~s/%1/$r1/ }
if (defined $r2) { $txt=~s/%2/$r2/ }
$er_base->Message(-anchor=>'center', -font=>$INI{err_font}, -foreground=>"$INI{err_forg}", -justify=>'center', -padx=>35, -pady=>10, -text=>decode('koi8r',$txt), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
$base->bell }

sub PrintSock {
my ($sock, my $crate)=@_;
if (defined $crate) { printf Log "crate N $crate\n"}
my $c;
my $cmnd=unpack 'I', substr($$sock,0,4);
printf Log "command: 0x%03X\n", $cmnd;
printf Log "total length[4]: %i\n", (unpack 'I', substr($$sock,4,4));
printf Log "time_stamp(���)[16]: %i\n", (unpack 'I', substr($$sock,16,4));
my $cnt=unpack 'I', substr($$sock,40,4);
printf Log "total_of_records[40]: %i\n", $cnt;
$cnt--;
if ( $cmnd>0x200 and $cmnd<0x250 ) { # ��� ������ ��������
	for my $i (0..$cnt) {
		$c=unpack 'I', substr($$sock,64+$i*4,4);
		printf Log "prm_id: %u // 0x%X\n", $c, $c; } }
elsif ( $cmnd==0x200 ) { # ������ ������ � ��
	for my $i (0..$cnt) {
		$c=unpack 'I', substr($$sock,64+$i*8,4);
		printf Log "prm_id: %u // 0x%X\t", $c, $c;
		$c=unpack 'I', substr($$sock,68+$i*8,4);
		printf Log "value: 0x%08X\n", $c; } }
elsif ( $cmnd==0x260 ) { # ��ɣ� �� vme
	for my $i (0..$cnt) {
		$c=unpack 'I', substr($$sock,64+$i*4,4); 
		printf Log "value: 0x%08X\n", $c; } }
print Log "------------------\n" }

sub TimeS {
my ($s)=@_;
return sprintf "%02u:%02u:%02u", int((int($s/60))/60), (int($s/60))%60, $s%60 }

sub Key {
my ($sys,$set,$prm)=@_;
return (sprintf('%03i',$sys).$set.sprintf('%i',$prm)) }

sub BinView {
(my $idx)=@_;
substr $$idx,1,0,' '; substr $$idx,4,0,' '; substr $$idx,10,0,' ';
substr $$idx,19,0,' '; substr $$idx,26,0,' '; substr $$idx,29,0,' ' }

sub SetErrTag {
(my $r)=@_;
$descrtab->clearTags(); $descrtab->tagCell('Err',"$r,0"); $descrtab->tagCol('DAT',0) }

sub ViewProt {
my $prot=$_[0];
my $prot_name=$_[1];
my $title=decode('koi8r','�������� ��������� ');
$title=$title.$batch_name;
if (!defined $prot_name) {$prot_name="";}
my $Wlog=$base->Toplevel(@Tl_att, -title=>(decode('koi8r',"�������� ��������� \"$prot_name\"")));
my $HWcmnd=$Wlog->Frame(-borderwidth=> 2, -relief=>  "groove")->pack(-fill=>'x',-side=> 'top'); #�������� ������ �� ������� ����������� ������, ���� ���� ��������� ��� �������� �����
$HWcmnd->Button(-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','�����������'),-command=>sub{
	`gedit $prot`;
	} )->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>10,-side=>'left');
	$HWcmnd->Button(-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','���������'),-command=>sub{
	if ($batch_name eq "") {
        my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
                        $er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
                        $er_base->Message(-anchor=>'center',-font=>$INI{err_font},-foreground=>"$INI{err_forg}",-justify=>'center',-padx=>35,-pady=>10, -text=>decode('koi8r','�� ������� ��������� ���� ���������. �������� �� ���� �������������� ��������� ������� ���������'), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
                        $base->bell;
 return}

        my $m_base = $base->Toplevel(@Tl_att,-title=>decode('koi8r','��������� ��������')); $m_base->geometry($INI{StandXY});
        $m_base->Message(-anchor=>'center',-padx=>5,-pady=>2,-font=>$INI{ld_font},-width=>450,
                -text=>decode('koi8r',"������� ��� ��������� ���������:"))
                ->pack(-fill=>'x', -side=>'top', -ipadx=>20, -ipady=>10);
        my $file_name="log00";
        my @count = `ls "/mnt/Data/TestDescriptors/$dir_name/$batch_name/"`; 
	for my $i (0..($#count)) {
		$file_name="log$i";
		if (-e "/mnt/Data/TestDescriptors/$dir_name/$batch_name/$file_name.log") {
			$i++;}
		else {
			$file_name="log$i";
			last}}
		
        my $save_prot;
	my $m_entry=$m_base->Entry(-font=>$INI{ld_font}, -fg=>"$INI{d_forg}", -bg=>"$INI{d_back}",-textvariable=>\$file_name,-width=>50)->pack(-padx=>20);
        $m_entry->bind('<Return>'=>sub{ my $file_name=$m_entry->get; $file_name=encode('koi8r', $file_name); &$save_prot($file_name,$prot); } );
	my $save_button=$m_base->Button (-font=>$INI{bd_font},-padx=>'3m',-text=>decode('koi8r','���������'),-command=>sub{my $file_name=$m_entry->get; $file_name=encode('koi8r', $file_name); &$save_prot($file_name, $prot)})->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>10,-side=>'bottom');

	$save_prot = sub {
	if ($batch_name eq"") {
	my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
                        $er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
                        $er_base->Message(-anchor=>'center',-font=>$INI{err_font},-foreground=>"$INI{err_forg}",-justify=>'center',-padx=>35,-pady=>10, -text=>decode('koi8r','�� ������� ��������� ���� ���������. �������� �� ���� �������������� ��������� ������� ���������'), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
                        $base->bell; 	
 return}
        #my $file_name=decode('koi8r', $_[0]); #tut
        my $file_name=$_[0];
	if ($file_name eq '') { ErrMessage($err[21]); return }
                if (-e "/mnt/Data/TestDescriptors/$dir_name/$batch_name/$file_name.log") { # ���� � ����� ������ ��� ����������
                        my $dlg=$base->Dialog(-font=>$INI{li_font},-title=>(decode('koi8r','��������!')),-text=>decode('koi8r',qq(���� � ������\n< $file_name >\n����������. ����������?)),-bitmap=>'question',-buttons=>[qw/Yes No/] ); my $ans=$dlg->Show(-global);
                        if ($ans eq 'No') { return } }
                        my $ret=open (OUT,">/mnt/Data/TestDescriptors/$dir_name/$batch_name/$file_name.log");
                unless (defined $ret) {
                        my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
                        $er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
                        $er_base->Message(-anchor=>'center',-font=>$INI{err_font},-foreground=>"$INI{err_forg}",-justify=>'center',-padx=>35,-pady=>10, -text=>decode('koi8r','�� ������� ������� ���� � ����� ������. ��������, � ������������ ����� ������������ �����ݣ���� ������� ��� �� �� ������ ���������� ���� ������� ��� ������ � ������� /mnt/Data/TestDescriptors'), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
                        $base->bell; return }
        #my $prot_file='./log/Batch.log';
        my $prot_file=$_[1]; #�������� ��� �����-��������� (�� ������ ���� ��������������� ��� ����������� ����)
	my $data=`cat "$prot_file"`;
        print OUT "$data"; close OUT; $b_load_prot->configure(-state=>'active');
        $m_base->destroy;};
})->pack(-anchor=>'center',-expand=>0,-fill=>'none',-padx=>10,-side=>'left');
        my $HWlog=$Wlog->Frame(-relief=>"flat")->pack(-fill=> 'x', -side=> 'top');
my $Hlog=$HWlog->Scrolled('Text',-scrollbars=>'osoe',wrap=>'none',-tabs=>[qw/0.5c 5c 6.5c 12c/],-spacing1=>5,-font=>$INI{mono_font})->pack(-expand=>1, -fill=>'both');
my $log_file;
$log_file=$_[0];
my $txt=`cat "$log_file"`;
$Hlog->insert('1.0',decode('koi8r',$txt));
my (@font)=split / /,$INI{mono_font}; # �������: terminus 14 medium
$font[2]='bold'; my $font; foreach (@font) { $font.=$_.' ' }; # ��������� ����� Bold
$Hlog->tagConfigure('CMND',-font=>$font);
$Hlog->tagConfigure('ERR',-foreground=>'red');
$Hlog->tagConfigure('ERR2',-foreground=>'red',-font=>$font);
my ($l,$c); my $i='1.0'; while (1) {
	$i=$Hlog->search(' �������� ',$i,'end'); unless ($i) { last }
	$Hlog->tagAdd('CMND',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0' }
$i='1.0'; while (1) {
	$i=$Hlog->search(-regexp,'^���������:',$i,'end'); unless ($i) { last }
	$Hlog->tagAdd('CMND',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0' }
$i='1.0'; while (1) {
	$i=$Hlog->search(-regexp,'^����:',$i,'end'); unless ($i) { last }
	$Hlog->tagAdd('CMND',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0' }
$i='1.0'; while (1) {
	$i=$Hlog->search('***',$i,'end'); unless ($i) { last }
	$Hlog->tagAdd('CMND',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0' }
$i='1.0'; while (1) {
	$i=$Hlog->search('�� ��������� � ������������',$i,'end'); unless ($i) { last }
	$Hlog->tagAdd('ERR',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0'; }
$i='1.0'; while (1) {
	$i=$Hlog->search('� ��������',$i,'end'); unless ($i) { last }
	$Hlog->tagAdd('ERR2',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0'; }
$i='1.0'; while (1) {
	$i=$Hlog->search('��� ������',$i,'end'); unless ($i) { last }
	$Hlog->tagAdd('CMND',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0'; }
$i='1.0'; while (1) {
	$i=$Hlog->search(-regexp,'!$',$i,'end'); unless ($i) { last }
	$Hlog->tagAdd('ERR',"$i linestart","$i lineend");
	($l,$c)=split /\./,$i; $l+=1; $i=$l.'.0'; }
$Hlog->configure(-state=>'disabled'); $Hlog->see('end') }

sub maxlen {
(my $ar)=@_; my $len=my $clen=0;
foreach my $str (@$ar) {
	$clen=length($str); $len=($clen>$len)?$clen:$len }
return $len }

sub load_prot_file_list {
my $file_list=$_[0];
        my @file_arr=split /\n/,$file_list;
        my @file;
        my $file_counter = 0;
	my $prot;
        foreach my $i (0..$#file_arr) {
           my $check_log= grep(/\.log/, $file_arr[$i]);
              if ($check_log){
		 #$file_arr[$i]=decode('koi8r', $file_arr[$i]);
		    $file[$file_counter][0]=$file_arr[$i];
                    my ($list,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("/mnt/Data/TestDescriptors/$dir_name/$batch_name/$file_arr[$i]");
		    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
		    my @time=localtime($ctime);
  		    $year=1900+$time[5];
		    $year=sprintf ("%02d", $year);
		    my $month = 1+$time[4];
		    $month = sprintf ("%02d", $month);
		    my $day=sprintf ("%02d", $time[3]);
			 $hour=$time[2];
			 $min=$time[1];
		    $file[$file_counter][1]=sprintf ($day.".".$month.".".$year) ;

			$file_counter++;}}
	&load_prot(@file);}


sub load_prot {
#####################
my @file=@_;        
my $selwin=$base->Toplevel(@Tl_att);
my $t=$base->geometry(); (undef,$t,my $s)=split /\+/,$t;
$selwin->geometry("+$t+$s");
$selwin->title(decode('koi8r','����� ��������� ���������'));
my $protwin=$selwin->Frame(@Tl_att);
$protwin->pack(-anchor => 'center', -expand=>0, -padx => 25, -pady => 20, -fill => 'both', -side => 'top');

my $selvarlist={};
for my $i (0...$#file) { $selvarlist->{"$i,0"}=$file[$i][0];
$selvarlist->{"$i,1"}=decode('koi8r',$file[$i][1]); }
$selvarlist->{'-1,0'} = '������������ ���������'; $selvarlist->{'-1,1'} = '���� ��������';
foreach my $key (keys %$selvarlist) { $selvarlist->{$key} = decode('koi8r', $selvarlist->{$key}) };
my $seldat=$protwin->Scrolled('TableMatrix',-scrollbars=>'osoe',-rows=>($#file+2), -cols=>2,
  -variable=>$selvarlist, -font=>$INI{sys_font}, -bg=>'white',
  -roworigin=>-1, -colorigin=>0, -state=>'disabled', -selecttitles=>1,
  -colwidth=>50, -selectmode=>'sinigle', -titlerows=>1,
  -cursor=>'top_left_arrow', -resizeborders=>'both');
$seldat->tagConfigure('NAME', -anchor=>'w');
$seldat->tagCol('NAME',0);
$seldat->colWidth(0 => 25, 1 => 20);
$seldat->pack(-expand=>1, -fill=>'both');
$seldat->bind('<3>', sub {
   my $w = shift; my $Ev = $w->XEvent;
   $w->selectionClear('all'); my $ct=$w->tagCell('Target');
        $w->tagCell('',$ct->[0]); $w->tagCell('Target','@'.$Ev->x.','.$Ev->y);
        $ct=$w->tagCell('Run'); if (defined $ct) { $w->tagCell('',$ct->[0]) };
        my $r=$w->index('@'.$Ev->x.','.$Ev->y,'row');
        unless (exists $selvarlist->{"$r,0"}) { Tk->break }; my $t=$base->geometry(); (undef,$t,my $s)=split /\+/,$t;
        $w->tagCell('',$ct->[0]); $w->tagCell('Target','@'.$Ev->x.','.$Ev->y);
        my $popup=$w->Menu('-tearoff'=>0,-font=>$INI{but_menu_font});
 
  if ($r!=(-1)) {
  $popup->command(-label=>decode('koi8r','�������'),-bg =>'gray85',-command=> sub{
  my $base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
  $base->title(decode('koi8r', "������� ��������"));
  $base->protocol('WM_DELETE_WINDOW', sub{ $base->destroy;});
  $base->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35,
  -pady => 7, -text => decode('koi8r',qq(������� ���� ��������� $file[$r][0]?)),
  -width => 300)->pack(-anchor => 'center', -pady => 7, -side => 'top', -fill=>'x');
   $base->Button(-command => sub{$base->destroy;  `rm "/mnt/Data/TestDescriptors/$dir_name/$batch_name/$file[$r][0]"`; 
  
   my $file_list=`ls "/mnt/Data/TestDescriptors/$dir_name/$batch_name"`;
      
CheckLoadButton();

   $selwin->destroy; 
   &load_prot_file_list($file_list); }, -state => 'normal', -borderwidth => 3,
   -font => $INI{but_menu_font}, -text => decode('koi8r', qq(��)))->pack(-anchor => 'w', -pady => 10, -padx => 10, -fill => 'x' ,-side => 'left');
$base->Button(-command => sub{$base->destroy;  return; }, -state => 'normal', -borderwidth => 3,
   -font => $INI{but_menu_font}, -text => decode('koi8r', qq(������)))->pack(-anchor => 'w', -pady => 10, -padx => 10, -fill => 'x' ,-side => 'right');

});
}
if (defined $popup) { $popup->Popup(-popover=>'cursor',-popanchor=>'nw');}
});

$seldat->bind('<1>', sub {
        my $prot;
	my $file_list;
	my $w = shift; my $Ev = $w->XEvent;
	my $r = $w->index('@'.$Ev->x.','.$Ev->y); ($r,my $c) = split /\,/,$r;
		if ($r >= 0) { # ���� ������ �������
			$prot= "/mnt/Data/TestDescriptors/$dir_name/$batch_name/$file[$r][0]";
			my $prot_name=$file[$r][0];
			ViewProt($prot, $prot_name);
			$selwin->destroy;}
		else {
		 	 if ($c==0) { # ������������
            if ($cmnt==1) { $file_list=`ls -r "/mnt/Data/TestDescriptors/$dir_name/$batch_name"`; $cmnt=0 }
            else { $file_list=`ls "/mnt/Data/TestDescriptors/$dir_name/$batch_name"`; $cmnt=1 }
                    &load_prot_file_list($file_list); 
		$selwin->destroy;
}
         elsif ($c==1) { #����
            if ($usr==0) { $file_list=`ls -tr "/mnt/Data/TestDescriptors/$dir_name/$batch_name"`; $usr=1 }
            else { $file_list=`ls -t "/mnt/Data/TestDescriptors/$dir_name/$batch_name"`; $usr=0 }
                   &load_prot_file_list($file_list);
		$selwin->destroy; }
            	 };
        Tk->break } );
$seldat->bind('<Motion>', sub {
   my $w=shift; my $Ev=$w->XEvent;  $w->selectionClear('all');
         $w->selectionSet('@'.$Ev->x.','.$Ev->y);  Tk->break } );
$selwin->bind('<Escape>', sub { $selwin->destroy } );
$selwin->protocol('WM_DELETE_WINDOW', sub { $selwin->destroy } );
$selwin->waitVisibility; $selwin->grab; }




sub CheckLoadButton {
   my $file_list=`ls "/mnt/Data/TestDescriptors/$dir_name/$batch_name"`;
   my @file_arr=split /\n/,$file_list;
   my @file;
   my $file_counter=0;
   foreach my $i (0..$#file_arr) {
      my $check_log= grep(/\.log/, $file_arr[$i]);
      if ($check_log){
        $file[$file_counter][0]=$file_arr[$i];
        $file_counter++;}}
   if (($#file==-1)||($batch_name eq '')) {$b_load_prot->configure(-state=>'disabled');}
   else {$b_load_prot->configure(-state=>'active');}}	

#####################
          
sub recvVME { # ������ �� �����������
                my $descr = $_[0];
		my $s_err = $_[1];
		my $mkt_id = $_[2];
		my $S_CR='';
                my $shCR=''; my $shBUF='';
                my $sock_cnt=0; my $hostiadr; my $crate;
                if ( select( $rout=$rin, undef, undef, 0) ) {
                	$hostiadr=recv($S_RCV,$S_CR,$max_buf_length[$mkt_id],0);
                        $hostiadr=inet_ntoa(substr($hostiadr,4,4));
                        $crate=$host_crate{$hostiadr};
			$sock_cnt++; # ������� �� VME
                        if (!$sock_cnt) { # ���� ������ ���� ������
                        	if ($s_err==2) { # ����� N ��������� - ������
                	        	$base->bell; $vme_crash=1;  if ($log) { print Log "$s_err timeouts from vme\n" }
                                        SetErrTag($descr); ErrMessage($err[11]); $paused_flag=0 }
                                        
					else { $s_err++ } } # ������� ��������
                        else { # ���� ��������� ���������
                if ($log_trs) { PrintSock(\$S_IN[$mkt_id], $crate) }}}
		else { print "I/O error: interrupt w/o packet!\n"; return }
                my $erl=length($S_CR);
                my $numpack=unpack 'I', substr($S_CR,28,4); # ����� �� ������
                if (    $erl != $buf_length[$crate] ) { # ��������� ������� recv, ���� ������: 
                	$S_CR.=chr(0)x($buf_length[$crate]-$erl); # ���� ����� ��� ������ - ��������� "0"
                	if ($log) { print Log "buffer's length missmatch: requested - $buf_length[$crate], received - $erl\n" } }
                for my $i (0 .. $#{$buf_cr{$crate.$mkt_id}}) {
                	$shCR=64+($i<<2); $shBUF=64+(($buf_cr{$crate.$mkt_id}->[$i])<<2);
                        substr($S_IN[$mkt_id],$shBUF,4,substr($S_CR,$shCR,4)) }}
                
