#!/usr/bin/perl
# int_measurement.pl

# ������ 01.00
# ��������� ��������� ���������� ������� ����


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
use Time::HiRes qw(gettimeofday tv_interval);
use Time::HiRes qw(sleep);

my $IS_pause=0.02; # ����� ����� ��������� � �� (���)
my $N_parm_count=5; #������� ��� ���� ��������� ��������
my $dop_plus=3; #������, � �������� �������� ���������� ����������� ��������� �� �������� ������� �� ��������� �������
my $dop_minus=10; #������, � �������� �������� ���������� ����������� ��������� �� ������� ������� �� ��������� �������
my $start_recv_count=4; #� ������ ����� ������ ��������� ��������� (�� ����)
my $timeout_time=2; #������� ������ ����� ������ �� ������� �������� �� ������ ������ �� ��������
my $substitute_int=1000; #���� � �� �� ������ ������������ ��������, ���������� ��� ��������

my $brd_color='#00FF00'; # ���� ����� ������ run

my $fltr_flag=0;
my $palete;
my @measurment_time;
my @options;
my (@w_recieved_dev, @w_dev_dev, @w_recieved_in_line, @w_dev_in_line)=();
my $set_columns_flag=0;
my $colonoc_type=0;

my $pause; # � ������ ��� ��������� ��������� 
my $send_wtchr;
my $chanel_done=0; #������� ���������� �������, �� ������� ��������� ��� ���������
my $chanel_measuring_counter=0; #������� ��� �����������, �� ������ ������ ������ ������ �� ������ ���������

chomp(my $dir_name=$ENV{HOME});
$dir_name.='/cmk';
chdir $dir_name;
my $mysql_db=ltok($ENV{HOME});

# ��������� ini-�����
open (INI,'ssrp.ini');
my @ini=<INI>;
close (INI);
my %INI=();
my ($str,$hole,$name,$value);
foreach (@ini) {
   chomp;
   if (substr($_,0,1) eq '#') { next }
       if (!$_) { next }
       ($str,$hole)=split(/;/,$_,2);
       ($name,$value)=split(/=/,$str,2);
       $INI{$name}=$value }

# ���������� �������������
my $my_host=StationAtt();
my $my_station=substr($my_host,2);
my %mntr; # tied to shared memory hash
my $mysql_usr;
my $pack='';
my (%pack)=();
my (%chan_vme_id)=(); #���, ������� �������� �������� ������ ������� ����� ����������, ���������� �������� �������, �� ������� �������� ������
my (%sys_parm,%crate_sys, %chan_addres)=(); #hash ������/���������� � �������/������
my (%pack_for_buff)=();#���, ������� �������� �������� ������ ������� (�������� ����. ������), ���������� �������� ������ ����� ������;����� ���������
my (%chan_key)=(); #���, ������� �������� �������� ����� ���������������� (����� ��, ��� ������������� � ������� sname), ���������� �������� ������ ����� ������;����� ���������
my $mntr_pid;
my $shmem;
my $shmsg;
my ($port_vme_to,$port_vme_from,$sin_to,$sin_froim,$rout,$rin);
my @mes;  # for message packing

# ���������� �������� ������� �����������
 my ($rcount, $time1, $time2, $cnt, $scnt)=0;

my $log_time=0;
my $log_timeS='00:00:00';
my $RunFlag=0;
my $paused_flag=0;
my @err_cnt=(); #������� ������ ������ �� ��
my $sock_err=my $sock_err_i=0;
my $flashFlag=0; #���� ��� �������� ������ � �������� ������
my $time_wtchr; # ��������� ������
my $read1_wtchr;#������ ��� �� �������� ������� ���� � ����� �����
my $rcv_wtchr; # ������ ��ɣ����� ������ (��� �������� ������� ����� � ����� �����)
my @rcv_i_wtchr; #������ �������� �������� ������� (��� ��������� ����������)
my @port_busy_flag; #������ ������, ����� �� ���� � ������ ������ (���� ������ ���������), ��� ���
my @chan_measuring_flag; #������ ������, ��������� ��/�������� �� ��������� ���������� ���������� ������� ������
my @missing_parm_flag=0; #������ ������, ���������� �� �������� �������� ���������� (��� ������� ���), ���� ����==1, �������� ������������ � ����� �����

my $rcv_vis_wtchr; # ������ ������������ ������
my $sui_wtchr;
my $done_firstread=AnyEvent->condvar;#������� (�����������, ��������� �� ������ ������� Read1)
my $sleep_var=AnyEvent->condvar; #������� ������ �� ��� � StartReg 
my $stop_st_reg_flag=0;

my $new_t_wtchr;
my @buf_cr; # ������ ���������� �� ������� ��������� �������� �������
my $max_buf_length; #����� �������� ������
my (@iaddr, @sin_to, @sin_to_imi, $sin_from, @sin_from_i, @sin_to_i, @S_OUT, $S_IN, $sock_IN, $S_IN_UN, $S_RCV, @S_RCV_I, $S_RCV_SUI, @S_SND, $S_SND_I, $rout, $rin);
my (@crate_for_buff, @S_int, @S_int_cycle, @S_int_stop, @rin_i, @rout_i ,$S_stop , $port_vme_to_i, $port_vme_from_i); #������ ��� ����������������� ��������� ����������
my $prm_read_counter=0; #������� ��������� ����������
my $send_counter=0; #������� ������������ ��������
my %chanel_parm=(); #���, ������� �������� ������ ������������ ��������, �������� - ������  ����� ������;����� ��������� � ���� ������
my %max_int_for_buff;
my %missing_idx_for_chan=();#���, ������� �������� ������ ������� (������� �������� ���� ������), �������� - ����� ������������� ����������
my %dev_idx_for_chan=();#���, ������� �������� ������ ������� (������� �������� ���� ������), �������� - ����� ���������� � ������������
my %in_line_idx_for_chan=();
my %twin_in_set=();#��� ������� ���� ���������� (��� �� ��� � ������ �������� � ����� �� twin), ����������
my ($fltr_fdat_height, $fltr_fdat_width)=0;
my @interval_for_recv_int=(); #������ ���������� (�� �������� �� ����������� ������, ��� ����������� ����-����, ���� �� �������� ����� �������� ����� �����)

my @total_interval_value; #���������� ������ ��������� �������� ���������� @[i][j], ��� i-������ ������ � j-������ ��������� � ������, ������ ������ �� ������ ��������� ���������� ������� ��������� 
my $out_of_limits_prm_count = 0; #���������� ����, ���������� ��������� ������� ����� �� ������� + ������ 
my (@dev_fltr_chan, @dev_fltr_idx, @missing_fltr_chan, @missing_fltr_idx, @in_line_fltr_chan, @in_line_fltr_idx) = (); #(��� �������)������ �������� ������� � ����������, ���������� ��������� ������� ����� �� ���������� �������

my $missing_prm_count = 0; #���������� ����, ������������� � ����� �����
my $in_line_prm_count =0; #���������� ����, �������������� � ����� �����
my (@crate_reg, @crate_tot); #Macc��� ������� ������� ��� �������������� ������(�� ���������� ������ � ������ Distinct ������ �������  
my ( $x0, $x1 ); # ������� � ������� �������� ��������� � ������
my @buf_length; # ����� ������ ��������(=������)

# ����� ����������
my $rmenu; my $bln; my $bckg;
my $b_choice; my $b_step; my $b_run; my $b_columns; #������
 

my (@first_parm_number,@total_parm_count)=(); # � �������� � ������� ���������� ��������� � ������� ���������
my (@chan_addr,@v_type,@NDIG,@FSTBIT,@LSTBIT,@NC,@vme_prm_id,@vme_prm_id_0,@NCb,@NDIGb,@crate_prm,%min_int, %max_int, @utwin)=(); # �������� ����������
my (@sname,@pname,@punit,@punitb)=(); # ������������� �������� (�� �������� widgets)
my (@id_system,@id_compl)=(); # �������������� ������, ���������



# �������� ����������
my $dMAX=0; # ������������ ������ ������� ������
my $ScrollFlag=1; #���� ������� scrollbar
my ($current_row,$current_colon); # ������� ������/�������
my $base_width='870x'; #������ �������� ����
my ($nr,$nc); # �����, ������� � ������� �����
my $b_filter;
#

# Tk ����������
my (@wgs,@wgc0,@wgf0,@wgf1,@wgf2,@wgf3,@wgc1,@wgc2,@wgc3,@wgc4,@wgw0,@wgw1,@wgw2,@wgw3,@wgw4,@wgn_nm, @wg_db, @wg_rcv, @wg_dev)=(); # widget ������������ ������, ���.�������, �����., �-�,  ������ �������, ������ ������ ���., ������ ����������
# my $signvme; # ��������� �� ������ vme_prm_id,crate ���
# my @signword=(); # �������� ���
my (@sign_state,@sign_idx,@sign_bit)=(); # ������ ���������, ������ ��� ����� ��� � @signword, ����� ���� � ����� ��� 
my (@wgn,@wgm,@wgd,@wgu)=(); # widget ������������, �����, ������ � ��.���. ���������� 
my (@w_db_interval, @w_received_interval, @w_deviation_interval)=(); #������� ����������, ���������� �� ��, ���������� ����������, ���������� ���. �������� �� �������� � ��
# �������� ����� ������� "������������ �������(��������)"
 my (@sT)=(-background=>"$INI{sc_back}",-borderwidth=>1,-relief=>'flat',-font=>$INI{h_sys_font});
# # �������� ���� ������� "���, ��.���. ����������"
 my (@pT)=(-borderwidth=>1,-relief=>'ridge',-font=>$INI{sys_font});
# # �������� ���� ������� "�����, ������ ����������"
 my (@dT)=(-borderwidth=>1,-relief=>'sunken',-font=>$INI{data_font});

# ���������� ��������
 my (@ssT)=(@sT,-anchor=>'e',-pady=>$INI{spyr}); # �������
 my (@scT)=(@sT,-anchor=>'w'); # ��������
 my (@pnT)=(@pT,-anchor=>'w',-padx=>$INI{npx},-pady=>$INI{ppyr}); # ��� ���������
 my (@pmT)=(@dT,-anchor=>'center',-width=>2,-padx=>$INI{mpx}); # �����
 my (@pdT)=(@dT,-anchor=>'e',-padx=>$INI{dpx}); # ������
 my (@puT)=(@pT,-anchor=>'w',-width=>7,-padx=>$INI{upx}); # ��.���.
 my (@Tl_att)=(-borderwidth=>1, -relief=>'flat',  -takefocus=>0); # Toplevel attributes
 my (@Tb_att)=(-borderwidth=>2, -relief=>'flat'); # Table attributes
#


my @crate_tot; #������� ������
my $crate_cur; #������� �����
my $base; #������� ����
#my $port_vme_to_i;

my $proto;
my $port_vme_to_imi;
my $flashFlag=0; #���� ��������� ������ �����


my ($row,$ar_field); # ��������� �������� ������ DBI
my $log=1; my $log_trs=1;


if ($log or $log_trs) {
  $row='>/mnt/NFS/tmp/FtoDKPerl/log/I'.time.'.log';
  open (Log, "$row") }


#��������, ��������� �� ���� ����
if ($INI{UnderMonitor}) { # ���������� shmem, ���������� $mysql_usr
  unless (-e '/tmp/ssrp.pid') { NoShare() }
        open (PF,'/tmp/ssrp.pid');
        $shmsg=new IPC::Msg( 0x72746e6d,  0001666 );
  $SIG{USR2} = \&Suicide;
  RestoreShmem() }
else { $mysql_usr=$INI{mysql_usr} }
$SIG{USR1} = \&RefreshWindow;

#���������� �����
my $dbh=DBI->connect("DBI:mysql:cmk:$ENV{MYSQLHOST}",'CMKtest',undef) || die $DBI::errstr;
my $is_host=$dbh->selectcol_arrayref(qq(SELECT is_host.ip FROM is_host,host,user
  WHERE user.name="$mysql_db" AND user.parent=host.stand_base
  AND host.id_host=is_host.base_host_id ORDER BY is_host.crate));
unshift(@$is_host,$ENV{VMEHOST}); # ������ ������ ip-������� ������ ��
my %host_crate=(); # $host_crate{ip_address}=crate

$dbh = DBI->connect_cached("DBI:mysql:$mysql_db:$ENV{MYSQLHOST}","$mysql_usr",undef) || die $DBI::errstr;
my %cr_hash; # ��� ������� ����������. ���� - vme_prm_id, �������� - crate.
my $crate=$dbh->selectall_arrayref(qq(SELECT vme_prm_id,crate FROM reg));
foreach my $row (@$crate) { $cr_hash{$row->[0]}=$row->[1] }

my ($row,$ar_field); # ��������� �������� ������ DBI
my ($base, $pixpath);


if ($INI{SmallButtons}) { $pixpath='/usr/share/pixmaps/ssrp/small/' }
else { $pixpath='/usr/share/pixmaps/ssrp/' }

$nc=1;
my (@Tl_att)=(-borderwidth=>1, -relief=>'flat', -takefocus=>0); # Toplevel attributes


#Log

#if (substr($INI{log},0,1) eq '1') { $log=1 } else { $log=0 }
#if (substr($INI{log},1,1) eq '1') { $log_trs=1 } else { $log_trs=0 }


my $fdat; 
#= $base->Table(@Tb_att, -rows=>$nr, -columns=>$nc*5);
# if ( $ScrollFlag ) { $fdat->configure( -scrollbars=>'e') }
# else { $fdat->configure( -scrollbars=>'') }
# $fdat->pack(-padx=>5, -pady=>5);
my $empty;
#=$fdat->Label(-borderwidth=>1, -relief=>'flat', -width=>2);

# ���������� ������ � �������
my $packID=$ARGV[0];
GetPackData();
NewWindow();
SetTableVars();
$proto = getprotobyname('udp');
$port_vme_from=$port_vme_to+1;
PrepSockets();
CreateBuffers();
Set_S_OUT_S_IN();
$sock_IN=$S_IN;
ShowTable();
 
#���������� ������� ��� ��������� ��� + ��� �������� ������� ���� � ����� �����
sub PrepSockets {
@iaddr=@sin_to=@sin_to_imi=@S_SND=();
socket($S_RCV,PF_INET, SOCK_DGRAM, $proto);
$sin_from = sockaddr_in( $port_vme_from, INADDR_ANY );
bind($S_RCV, $sin_from);
$rin=''; vec($rin, fileno( $S_RCV ), 1) = 1;
#socket($S_SND, PF_INET, SOCK_DGRAM, $proto);
foreach my $crate (0 .. 3) { # ��� ���� �������
        $iaddr[$crate]=gethostbyname($is_host->[$crate]); # �������� ����c
        $host_crate{inet_ntoa($iaddr[$crate])}=$crate;
        socket($S_SND[$crate], PF_INET, SOCK_DGRAM, $proto);
        $sin_to[$crate] = sockaddr_in( $port_vme_to, $iaddr[$crate] ) } }

#���������� ������� ��� ��� �������� ������� ���� � ����� �����
sub Set_S_OUT_S_IN {
   for my $i (0 .. 3) { $buf_cr[$i]=[] }
   #$S_IN=chr(0)x64;
   foreach my $i (0 .. $#vme_prm_id) { # ��� ���� ����������
   $S_OUT[$crate_prm[$i]].=pack 'I', $vme_prm_id[$i]; # ��������� � ����� vme_prm_id �������. ����������
   push @{$buf_cr[$crate_prm[$i]]},$i; # idx ����� � ������ �������� ������ ������
   $buf_length[$crate_prm[$i]]=length $S_OUT[$crate_prm[$i]] }
   my $vme_prm_id_plus=$#vme_prm_id+1;
   foreach my $i (0 .. 3) { if ($crate_tot[$i]) { # ��� ���� ������������ �������
   substr($S_OUT[$i],4,4,(pack 'I',(length $S_OUT[$i]))); # ����� ������ � ����������
   substr($S_OUT[$i],40,4,(pack 'I',($buf_length[$i]-64)>>2))} };
   #for my $i (0..$#w_db_interval) { if ($v_type[$i] == RK) {print "\nRK\n"; $S_IN.=pack 'I',0xFFFFFFFF } else {print "\nNe RK\n"; $S_IN.=pack 'I',0 } } # ���������� ��. ������
#$max_buf_length=length $S_IN;
} # ������� �������
                                                                        

socket($S_SND_I, PF_INET, SOCK_DGRAM, $proto);

#�������� "��������" �� ����, ���� ��� �������-���������� ������ ���������
socket($S_RCV_SUI, PF_INET, SOCK_DGRAM, $proto);
my $sin_sui = sockaddr_in( $packID, INADDR_ANY );
bind($S_RCV_SUI, $sin_sui);
my $routs = my $rins = '';
vec($rins, fileno( $S_RCV_SUI ), 1) = 1;
my $sui_wtchr;
$sui_wtchr=AnyEvent->io(fh=>\*$S_RCV_SUI, poll=>"r", cb=>sub{ # ������������ ������ �� ������ ����������
        my $mes=''; my $max_len=100;
        while ( select( $routs = $rins, undef, undef, 0.005) ) { # ��������� ���������� ������
                recv($S_RCV_SUI,$mes,$max_len,0) } # ������� �� ����
        if ($mes eq 'stop') {
                system("zenity --info --text='������ ����������� ���������, ��� ��� �������� �������' > /dev/null &");
                Suicide() } } );

$|=1;
MainLoop;


#���������� ��� �������
sub StationAtt {
my ($hostname,$name,$aliases,$station);
chop($hostname = `hostname`);
($name,$aliases,undef,undef,undef) = gethostbyname($hostname);
my @al=split / /,$aliases;
unshift @al,$name;
foreach (@al) { if (/^ws\d+$/) { $station=$_ } }
return $station }

#�������� ��� ������������ ���� ����
sub RestoreShmem {
my @shmem=<PF>; close(PF);
($mysql_usr, $mntr_pid)=split(/\|/,$shmem[0]);}

#������� ������ �� ������� packs �� pack id
sub GetPackData {
($mysql_usr,$pack,$port_vme_to)=$dbh->selectrow_array(qq(SELECT user,dat,sock_in FROM packs  WHERE id=$packID));
my $pid=$$;
@missing_parm_flag=0;
$missing_prm_count=0;
$out_of_limits_prm_count=0;
%sys_parm=();
%crate_sys=();
$row=();
$max_buf_length=();
#$S_IN=();
$dbh->do(qq(UPDATE packs set state='stop',PID="$pid" WHERE id=$packID));
if ($INI{UnderMonitor}) {
  $mes[0]=$packID;
  $mes[1]='stop';
  PageMonitor() }
(@first_parm_number,@total_parm_count)=(); # � �������� � ������� ���������� ��������� � ������� ���������
(@chan_addr,@v_type,@NDIG,@FSTBIT,@LSTBIT,@NC,@vme_prm_id,@vme_prm_id_0,@NCb,@NDIGb,@crate_prm,%min_int, %max_int, @utwin)=(); # �������� ����������
(@sname,@pname,@punit,@punitb)=(); # ������������� �������� (�� �������� widgets)
(@id_system,@id_compl)=(); # �������������� ������, ���������
my ($name_system,$str_el,$existence_flag); # ��� �������, ������� ������ ����������/����������,���� ������� ���������
my ($parm_index,$compl_counter,$compl_parm_counter)=0; # ������ ����������, ������� ���������� �������, ������� ���������� ���������
my $dMAX2; # ����� ��� ��������� 2 ���� (� ���������)
my $int_ndig; # ������ ���� ������ (��� ���� - ���������, ��� �� - ����� �������)
$dMAX=0; # ������������ ������ ������� ������
%pack=split(/:/,$pack);
my $rkFlag = 0; #���� ������� � ������ ������� ������
my $sys=$dbh->selectall_arrayref(qq(SELECT id_system,name,freq FROM system ORDER BY v_id));
my $avail=$dbh->selectall_arrayref(qq(SELECT id_system,num_compl,avail FROM compl WHERE sim=0));
my $id_sys; my $freq;
my $chan_counter = 0; #������� ������� (�����������������)
for my $x (0..$#{$sys}) {
      if (exists $pack{$sys->[$x][0]}) { $name_system=$sys->[$x][1]; $id_sys=$sys->[$x][0]; $freq=$sys->[$x][2]; }
      else { next }
      $compl_counter=0; # ����������� ������� ����������
      while (1) { # �������� ���������
            ($str_el,$current_row)=split(/,/,$pack{$id_sys},2);
            if ($str_el=~/k/) {
                  $compl_parm_counter=substr($str_el,1,1);
                  if (grep { $_->[0]==$id_sys and $_->[1]==$compl_parm_counter and $_->[2]==1 } @$avail) { # ���� �������� � �������

                        push @id_system,$id_sys; push @id_compl,$compl_parm_counter; # ������ ��� ������������
                        $dbh->do(qq(UPDATE cmtr_chnl,cmtr_rgstr,cmtr_mdl,compl,vme_chan SET cmtr_chnl.busy=$packID
                                        WHERE compl.id_system=$id_sys AND compl.num_compl=$compl_parm_counter
                                        AND compl.id_vme_chan=vme_chan.id_vme_chan
                                        AND cmtr_mdl.id_vme_rcv=vme_chan.id_vme_card
                                        AND cmtr_chnl.name+(cmtr_mdl.n_in_pair-1)*16=vme_chan.num_chan
                                        AND cmtr_chnl.id_rgstr=cmtr_rgstr.id_rgstr
                                        AND cmtr_rgstr.id_mdl=cmtr_mdl.id_mdl
                                        AND NOT cmtr_chnl.busy)); # "������" �����������, ���� �� ������ �����
                        if (defined $freq) { push @sname,($name_system.'|�. '.substr($str_el,1,1).'|'.$freq) } # � ������� � ������
                        else { push @sname,($name_system.'|�. '.substr($str_el,1,1)) }
                        $compl_counter++ } # ��������� ��������
                  $pack{$id_sys}=$current_row } # �������� ������
            else { last } } # �������� ���������
  # �������� ���������
	$row=$dbh->selectall_arrayref(qq(SELECT id_parm,chan_addr,name,units,v_type,NDIG,FSTBIT,LSTBIT,NC,vme_prm_id, minint, maxint, utwin FROM parm WHERE id_system=$id_sys and (target&1) ORDER BY v_id ASC)) || die $DBI::errstr;
	my $crate=$dbh->selectall_arrayref(qq(SELECT DISTINCT crate FROM reg WHERE id_system=$id_sys));
	for my $compl_num (1..$compl_counter) { # ��� ���� ���������� ���� �������
			my @vme_prm_id_for_hash;
			%twin_in_set=();
    			push @first_parm_number, $parm_index; # ���� �������� ���������� � j-�� ���������
    			$compl_parm_counter=0; # ���������� � ������ ���������
                	$sname[$#sname-$compl_counter+$compl_num]=~/�. (\d)/; $str_el=$1; # ����� ���������
    			my @chan_addr_array=();	
			my $parm_in_set_counter=0;		
					for my $i2 ( 0 .. $#{$row} )  { # ��� ���� ���������� ������� ���������
					if ($row->[$i2][4]!=RK) {
						$utwin[$i2] = $dbh->selectrow_array(qq(SELECT twin FROM reg WHERE id_parm=$row->[$i2][0]));
						if (($utwin[$i2] eq "")||(!$twin_in_set{$utwin[$i2]})) {#���� � ��������� �� ���� ���������� � ����� ���� ��� ����� ���
						$twin_in_set{$utwin[$i2]}++; #�������� ������� �����
      						if ( $pack{$id_sys}=~/(^$row->[$i2][0]$|^$row->[$i2][0],|,$row->[$i2][0],|,$row->[$i2][0]$)/ ) { # ���� ���� �������� ������ � �����
						if ( $row->[$i2][1] ) { $pname[$parm_index]=$row->[$i2][1].' '.$row->[$i2][2] }
        					else { $pname[$parm_index]=$row->[$i2][2] }
        					$punit[$parm_index]=$row->[$i2][3];
        					$v_type[$parm_index]=$row->[$i2][4];
								  #$utwin[$parm_in_set_counter] = $dbh->selectrow_array(qq(SELECT twin FROM reg WHERE id_parm=$row->[$i2][0]));
								  #if ((defined $utwin[$parm_in_set_counter-1])&&($utwin[$parm_in_set_counter]==$utwin[$parm_in_set_counter-1])){
									 #print "parm_index $parm_in_set_counter twin $utwin[$parm_in_set_counter]";next;}
									if ($v_type[$parm_index]<RK) { $chan_addr[$parm_index]=revbit(oct($row->[$i2][1])); } # ���
							#print "\ni2 $i2 parm_index $parm_index comp_parm_counter $compl_parm_counter utwin $utwin[$parm_index] $\n";
							$chan_addr_array[$parm_in_set_counter]=$chan_addr[$parm_index];
						$NDIG[$parm_index]=$row->[$i2][5];
        					if ($NDIG[$parm_index] ne '') { $int_ndig=int($NDIG[$parm_index]) }
                                		else { $int_ndig=0 }
        					if ( $int_ndig>$dMAX ) { $dMAX=$int_ndig }
        					if ( $v_type[$parm_index]==DS00 or $v_type[$parm_index]==DS11 ) { # ������� ����� ���������  
          						$dMAX2=$NDIG[$parm_index]+(($NDIG[$parm_index]-1)>>2);
          						if ( $dMAX2>$dMAX ) { $dMAX=$dMAX2 } }
        					$FSTBIT[$parm_index]=$row->[$i2][6];
        					$LSTBIT[$parm_index]=$row->[$i2][7];
        					$NC[$parm_index]=$row->[$i2][8];
        					$NDIG[$parm_index]=getNDIG($v_type[$parm_index],$NDIG[$parm_index]);
        					$vme_prm_id_0[$parm_index]=$row->[$i2][9];
                                		$vme_prm_id[$parm_index]=$row->[$i2][9]+$str_el-1;
						$vme_prm_id_for_hash[$compl_parm_counter]=$row->[$i2][9];
						#$vme_prm_id_for_hash[$compl_parm_counter]=$vme_prm_id[$parm_index];
						$min_int{$vme_prm_id[$parm_index]}=$row->[$i2][10];
						if ($min_int{$vme_prm_id[$parm_index]} eq "") {
						$min_int{$vme_prm_id[$parm_index]}=0}
						$max_int{$vme_prm_id[$parm_index]}=$row->[$i2][11];
						$max_int_for_buff{$vme_prm_id_for_hash[$compl_parm_counter]}=$row->[$i2][11];
						if (($row->[$i2][11]==0)||($row->[$i2][11] eq "")) { $max_int{$vme_prm_id[$parm_index]}=$substitute_int;
                                                $max_int_for_buff{$vme_prm_id_for_hash[$compl_parm_counter]}=$substitute_int;}
						print "\nGET PACK $max_int{$vme_prm_id[$parm_index]} parm_index $parm_index compl_parm $compl_parm_counter vme $vme_prm_id_for_hash[$compl_parm_counter]\n";
						$crate_prm[$parm_index++]=$cr_hash{$vme_prm_id[$parm_index]}; # �����. ����� ������
						#$sys_parm{$sys_parm_key}						
#print "\nsys_id $sys->[$x][0] pindex $parm_index pname $pname[$parm_index-1] compl_counter $compl_counter crate $crate_prm[($parm_index-1)]\n";

						$parm_in_set_counter++;
						$compl_parm_counter++; # vme_prm_id � ������ ������ ���������, ��������� �������� �-��� ���������
					}
}
} # ���� ���� �������� ������ � ����� � �� �������� ������� ��������
    			
else {$rkFlag=1};
                        #push @total_parm_count, $compl_parm_counter; # ���������� � ���� ���������
                        #my $sys_parm_key = "$id_sys;$compl_num";
                        #$crate_sys{$sys_parm_key}=$crate->[$x][0];
			
                        #$sys_parm{$sys_parm_key} =@vme_prm_id_for_hash; 	
			} # ��� ���� ���������� ������� ���������
  			push @total_parm_count, $compl_parm_counter; # ���������� � ���� ���������
  			#print "\nTOTAL @total_parm_count COUNTER $compl_parm_counter\n";
			my $sys_parm_key = "$id_sys;$compl_num";
			$chan_key{$chan_counter}=$sys_parm_key;
			$crate_sys{$sys_parm_key}=$crate->[$x][0];
			$sys_parm{$sys_parm_key}=\@vme_prm_id_for_hash;
			$chan_addres{$sys_parm_key}=\@chan_addr_array; 
			#print "\n\nGetPackData chan_counter $chan_counter chan_addr_array @chan_addr_array key $sys_parm_key hash $chan_addres{$sys_parm_key} sys_parm @vme_prm_id_for_hash\n\n";
			$chan_counter++;
			} # ��� ���� ���������� ���� �������
	} # ��� ����� �������
	if ($rkFlag) {my $txt = "��������� ��������� ������� ������ �� ��������������!";
                                my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
                                $er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
                                $er_base->Message(-anchor=>'center', -font=>$INI{err_font}, -foreground=>"$INI{err_forg}", -justify=>'center', -padx=>35, -pady=>10, -text=>decode('koi8r',$txt), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
                                $er_base->bell   }
	if ($dMAX<12) { $dMAX=12 } # ����������� ������ ������ ������
	foreach my $key (keys %crate_sys) {push @crate_reg , $crate_sys{$key};}
	for my $i (0..3) {$crate_tot[$i]=grep(/$i/,@crate_reg); }
	$S_IN=chr(0)x64;
	my $vv=0;
	foreach (@vme_prm_id) {
	$S_IN.=pack 'I',0}; 
	$max_buf_length=length $S_IN;
}


#����� � ����������� �������� ������
sub PageMonitor {
my $c='';
foreach (@mes) { $c.=$_.'|' }
chop $c;
# �������� ������ � ����������� ������� ���������
$shmsg->snd(1, $c) or warn "choice to shmsg failed...\n";
# # ������������� ��������
kill 'USR1', $mntr_pid;
 }

#������� ������� ����
sub NewWindow {
$base = MainWindow->new(@Tl_att);
$base->title(decode('koi8r',"��������� ����������")); my $test_name='';
$rmenu = $base->Frame(-borderwidth=> 2, -relief=>  "groove");
$rmenu->pack(-anchor=> 'center', -expand=> 0, -fill=> 'x', -side=> 'top');
my $bln=$rmenu->Balloon(-state=>'balloon');
$bckg=$base->cget('-background');
$base->Pixmap('choice',-file=>$pixpath.'maxlist.xpm');
$base->Pixmap('step',-file=>$pixpath.'resume.xpm');
$base->Pixmap('run',-file=>$pixpath.'reload.xpm');
$base->Pixmap('stop',-file=>$pixpath.'stop.xpm');
$base->Pixmap('print',-file=>$pixpath.'print.xpm');
$base->Pixmap('f_flag',-file=>$pixpath.'filter.xpm');
$base->Pixmap('losecuK',-file=>$pixpath.'losecuK.xpm');
$base->Pixmap('losecu1',-file=>$pixpath.'losecu1.xpm');
$base->Pixmap('losecu2',-file=>$pixpath.'losecu2.xpm');
$base->Pixmap('losecu3',-file=>$pixpath.'losecu3.xpm');

 $fdat = $base->Table(@Tb_att, -rows=>$nr, -columns=>$nc*5);
 if ( $ScrollFlag ) { $fdat->configure( -scrollbars=>'e') }
 else { $fdat->configure( -scrollbars=>'') }
 $fdat->pack(-padx=>5, -pady=>5);
 $empty=$fdat->Label(-borderwidth=>1, -relief=>'flat', -width=>2);

$b_choice=$rmenu->Button( -activebackground=>"$bckg", -image=>'choice', -relief=>'flat', -command=>\&ChoiceRevision)->grid(-row=>0,-column=>0, -columnspan=>1, -padx=>$INI{bpx});
#$rmenu->Label(-font=>"symbol 13", -height=>1, -text=>decode('symbol', 'D'))->grid(-sticky=>'e',-row=>0,-column=>3);
#$rmenu->Label(-font=>$INI{but_menu_font}, -text=>'t: ' )->grid(-row=>0,-column=>4,-sticky=>'e');
$b_run=$rmenu->Button(-activebackground=>"$bckg",-image=>'run',-relief=>'flat',
-command=>\&StartReg,
-highlightthickness=>4,-highlightbackground=>$bckg)->grid(-row=>0,-column=>1,-padx=>$INI{bpx});
$rmenu->Label(-font=>$INI{ri_font}, -bg=>"$INI{back}", -fg=>"$INI{forg}", -padx=>1,-pady=>1,-borderwidth=>2,-textvariable=>\$log_timeS, -width=>8)->grid(-row=>0,-column=>2,-columnspan=>2, -padx=>$INI{bpx});

#$out_of_limits_prm_count= $missing_prm_count= 0;

my $label_out_of_limits = "��� �������� ";
my $label_missing = ", ����������� ";
my $label_prm = " ����������";

$label_out_of_limits = decode ('koi8r', $label_out_of_limits);
$label_missing = decode ('koi8r', $label_missing);
$label_prm = decode ('koi8r', $label_prm);

$rmenu->Label(-font=>$INI{sys_font}, -padx=>1,-pady=>1,-borderwidth=>2, -textvariable=>\$label_out_of_limits)->grid(-sticky=>'e',-row=>1,-column=>0, -columnspan=>2, -padx=>$INI{bpx});
$rmenu->Label(-font=>$INI{data_font}, -padx=>1,-pady=>1,-borderwidth=>2, -width=>3, -bg=>"white", -textvariable=>\$out_of_limits_prm_count)->grid(-sticky=>'e', -row=>1,-column=>2, -padx=>0);
$rmenu->Label(-font=>$INI{sys_font}, -padx=>1,-pady=>1,-borderwidth=>2, -textvariable=>\$label_missing)->grid(-sticky=>'e', -row=>1, -column=> 3,-columnspan=>2, -padx=>$INI{bpx});
$rmenu->Label(-font=>$INI{data_font}, -padx=>1,-pady=>1,-borderwidth=>2, -width=>3, -bg=>"white", -textvariable=>\$missing_prm_count)->grid(-row=>1,-column=>5,,-padx=>$INI{bpx});
$rmenu->Label(-font=>$INI{sys_font}, -padx=>1,-pady=>1,-borderwidth=>2, -textvariable=>\$label_prm)->grid(-row=>1,-column=>6,-columnspan=>1, -padx=>$INI{bpx});




#my @options;
#my $palete;
$options[0]=decode ('koi8r', "��� ���������");
#$options[1]=decode ('koi8r',"� ������������");
#$options[2]=decode ('koi8r', "�������������");
$b_filter=$rmenu->Optionmenu( -relief=>'flat',-highlightthickness=>2,
	-variable=>\$palete,
	-textvariable=>\$palete,
	-options=> [@options],
	-command => sub{my $text=shift; $palete=$text; $text=encode ('koi8r',$text); Fltr($text)} )->grid(-row=>0,-column=>5,-columnspan=>2,-padx=>$INI{bpx});
$bln->attach($b_filter, -msg=>decode('koi8r','������ �������������'));

my $b_print=$rmenu->Button( -activebackground=>"$bckg", -image=>'print', -relief=>'flat',
-command=> sub{my $text=encode ('koi8r',$palete); 
my $chan;
my @fltr_option;
$fltr_option[0]= "��� ���������";
$fltr_option[1]="��� ��������";
$fltr_option[2]="������������� � �����";
$fltr_option[3]="� ������� � �����";
if ($text eq $fltr_option[0]) {
	PrintPage($text) }
else {
	if ($text eq $fltr_option[1]) {
	$chan=\@dev_fltr_chan;}
	elsif ($text eq $fltr_option[2]) {
	$chan=\@missing_fltr_chan}
	elsif ($text eq $fltr_option[3]) {
	$chan=\@in_line_fltr_chan}
	PrintPage($text, $chan)}})->grid(-row=>0,-column=>4,-columnspan=>1,-padx=>$INI{bpx});




$b_columns=$rmenu->Button(-font=>$INI{but_menu_font},-command=> \&SetColumns,
-textvariable=>\$nc, -padx=>0, -pady=>0)->grid(-row=>0,-column=>7,-padx=>$INI{bpx});
$bln->attach($b_choice, -msg=>decode('koi8r','������������� �����'));
#TuneButtons();
$bln->attach($b_run, -msg=>decode('koi8r','����'));
$bln->attach($b_print, -msg=>decode('koi8r','�����������'));
$bln->attach($b_columns, -msg=>decode('koi8r','�������'));
$base->bind('<F1>'=> \&HelpPage);
$base->protocol('WM_DELETE_WINDOW', \&Suicide);
}

# ����� ������
sub ShowTable {
my ($s,$n,$j);
$j=0;
(@wgs,@wgc0,@wgf0,@wgf1,@wgf2,@wgf3,@wgc1,@wgc2,@wgn,@wgm,@wgd,@wgu,@wgw0,@wgw1,@wgw2,@wgw3,@wgw4,@wgn_nm,@wg_db,@wg_rcv,@wg_dev,@w_db_interval, @w_received_interval, @w_deviation_interval)=(); my $chan_num;

foreach (@sname) { # �� ���������� ����������
  
	($n,$s,my $fr)=split(/\|/,$_); # ������������, ��������, �������
	$wgs[$j]=$fdat->Label(@ssT, -text=>decode('koi8r',$n));
        $wgc0[$j]=$fdat->Frame(-borderwidth=>0,-relief=>"flat",-bg=>"$INI{sc_back}");
        $wgc1[$j]=$wgc0[$j]->Label(@scT, -text=>decode('koi8r',$s))->pack(-side=>'left');
        #$wgc3[$j]=$wgc0[$j]->Label(@scT, -text=>decode('koi8r',"������"))->pack(-side=>'right');
	if (defined $fr) { $wgc2[$j]=$wgc0[$j]->Label(@scT, -text=>decode('koi8r',"F$fr"))->pack(-side=>'right') }
  $wgw0[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
  $wgf0[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
  #$chan_num=ShowChanel($j); if (defined $chan_num) {
  #  $wgw2[$j]=$wgw0[$j]->Button(-highlightthickness=>0,-bg=>"$INI{sc_back}",-relief=>'flat',-command=>[\&Cmttn,Ev($j)])->pack(-side=>'right',-ipadx=>3);
  #  if ($chan_num==0) { $wgw2[$j]->configure(-image=>'losecuK') }
  #  elsif ($chan_num==1) { $wgw2[$j]->configure(-image=>'losecu1') }
  #  elsif ($chan_num==2) { $wgw2[$j]->configure(-image=>'losecu2') }
  #  elsif ($chan_num==3) { $wgw2[$j]->configure(-image=>'losecu3') }
  #  $bln->attach($wgw2[$j], -msg=>decode('koi8r','����������')) }
   $wgw2[$j]=$wgw0[$j]->Label(-bg=>"$INI{sc_back}")->pack(-side=>'right'); 
   $wgw3[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   $wgw4[$j]=$wgw0[$j]->Label(-bg=>"$INI{sc_back}")->pack(-side=>'right');  
   $wgn_nm[$j]=$wgf0[$j]->Label(@pnT, -text=>decode('koi8r',"������������"))->pack(-side=>'left');
   $wgf1[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   $wg_db[$j]=$wgf1[$j]->Label(@pnT, -text=>decode('koi8r', "�������� ��������"), -width=>19)->pack(-side=>'left');
   $wgf2[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   $wg_rcv[$j]=$wgf2[$j]->Label(@pdT, -text=>decode('koi8r', "���������� ��������"), -width=>19)->pack(-side=>'left');
   $wgf3[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   $wg_dev[$j]=$wgf3[$j]->Label(@pdT, -text=>decode('koi8r', "����������") ,-width=>11)->pack(-side=>'left');
	
$j++ }

$j=0;


foreach (@pname) {
	
  $wgn[$j]=$fdat->Label(@pnT, -text=>decode('koi8r',$_));
  if ($missing_parm_flag[$j]==1) {
         $w_db_interval[$j]=$fdat->Label(@pnT, -text=>"", -width=>11);
         $w_received_interval[$j]=$fdat->Label(@pdT, -width=>11, -text=>"");
         $w_deviation_interval[$j]=$fdat->Label(@pdT, -width=>11, -text=>(""));
        }
  else {
  $w_db_interval[$j]=$fdat->Label(@pnT, -text=>decode('koi8r', "[$min_int{$vme_prm_id[$j]} ; $max_int{$vme_prm_id[$j]}]"), -width=>11);
  $w_received_interval[$j]=$fdat->Label(@pdT, -width=>11);
  $w_deviation_interval[$j]=$fdat->Label(@pdT, -width=>11);}
$j++}
$current_row=0;

for my $i0 (0..$#wgs) { # ��� ������� ������ �������� ������
  if ( $nc<3 ) {
    $fdat->put($current_row,0,$wgs[$i0]);
    $fdat->put($current_row,1,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,2,$wgc0[$i0]);
    $fdat->put($current_row,3,$wgw0[$i0]);
    #$fdat->put($current_row+1,0,$wgf0[$i0]);
    #$fdat->put($current_row+1,1,$wgf1[$i0]);	
    #$fdat->put($current_row+1,2,$wgf2[$i0]);
    #$fdat->put($current_row+1,3,$wgf3[$i0]);
    } 

    #$fdat->put($current_row,4,$fdat->Label(@ssT,-text=>'  '));
    #$fdat->put($current_row+1,4,$fdat->Label(@ssT,-text=>'  '));

 if ( $nc==2 ) {
    $fdat->put($current_row,5,$fdat->Label(@ssT,-text=>'  ')); # empty
    $fdat->put($current_row,6,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,7,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,8,$fdat->Label(@ssT,-text=>'       ')) }
  if ( $nc==3 ) {
    $fdat->put($current_row,0,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,1,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,2,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,3,$fdat->Label(@ssT,-text=>'       '));
    $fdat->put($current_row,4,$fdat->Label(@ssT,-text=>'  ')); # empty
    $fdat->put($current_row,5,$wgs[$i0]);
    $fdat->put($current_row,6,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,7,$wgc0[$i0]);
    $fdat->put($current_row,8,$fdat->Label(@ssT,-text=>'       '));
    $fdat->put($current_row,9,$fdat->Label(@ssT,-text=>'  ')); # empty
    $fdat->put($current_row,10,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,11,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,12,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,13,$wgw0[$i0]); 
}
  $current_row=$current_row+1;
if ( $total_parm_count[$i0] ) { # ���� �� ������ �������
    $n=int($total_parm_count[$i0]/$nc)+(($total_parm_count[$i0]%$nc)?1:0); # ����� ����� ������� ���������
    $s=0; # ��� ����� ������� ��������� 
    $current_colon=0; # ��� ������� ������� ��������� 
    if ( $INI{GridType} ) { # ��� ������� �������-������
      for my $i1 ( $first_parm_number[$i0]..($first_parm_number[$i0]+$total_parm_count[$i0]-1) ) { # ��� ���������� ����� ���������
	$fdat->put($current_row+$s,$current_colon*5+0,$wgn[$i1]);
	$fdat->put($current_row+$s,$current_colon*5+1,$w_db_interval[$i1]);
	$fdat->put($current_row+$s,$current_colon*5+2,$w_received_interval[$i1]);
	$fdat->put($current_row+$s,$current_colon*5+3,$w_deviation_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+4,$wgu[$i1]);
        $s=(($s==($n-1))?0:$s+1); $current_colon+=($s==0)?1:0;
      } # ��� ���������� ����� ���������
      if ( $total_parm_count[$i0]<$n*$nc ) {# ���������� ������, ��� �������� ����
        for my $i3 ( ($current_row+$s)..($current_row+$n-1) ) { # "������" �������� ��������
	  $fdat->put($i3,($nc-1)*5+0,$fdat->Label(@pnT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+1,$fdat->Label(@pmT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+2,$fdat->Label(@pdT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+3,$fdat->Label(@puT,-text=>'       '));
        } # "������" �������� ��������
      } # ���������� ������, ��� �������� ����
      $current_row+=$n;
    } # ��� ������� �������-������
    else { # ��� ������� ������-�������
      for my $i1 ( $first_parm_number[$i0]..($first_parm_number[$i0]+$total_parm_count[$i0]-1) ) { # ��� ���������� ����� ���������
        $fdat->put($current_row+$s,$current_colon*5+0,$wgn[$i1]);
	$fdat->put($current_row+$s,$current_colon*5+1,$w_db_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+2,$w_received_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+3,$w_deviation_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+4,$wgu[$i1]);
	$current_colon=(($current_colon==($nc-1))?0:$current_colon+1); $s+=($current_colon==0)?1:0;
      } # ��� ���������� ����� ���������
      $current_row+=$n;
      if ( $total_parm_count[$i0]%$nc ) { #  ��������� ������ - �������� 
        for my $i3 ( ($total_parm_count[$i0]%$nc)..($nc-1) ) { # "������" �������� ��������
          $fdat->put($current_row-1,$i3*5+0,$fdat->Label(@pnT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+1,$fdat->Label(@pmT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+2,$fdat->Label(@pdT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+3,$fdat->Label(@puT,-text=>'       '));
        } # "������" �������� ��������
      } #  ��������� ������ - �������� 
    } # ��� ������� ������-�������
  } # ���� �� ������ �������
} 
}  # ����� ������������, ����� sub

sub Fltr {
my $fltr_mode=$_[0];
my @fltr_option;
$set_columns_flag=0;
$fltr_option[0]= "��� ���������";
$fltr_option[1]="��� ��������";
$fltr_option[2]="������������� � �����";
$fltr_option[3]="� ������� � �����";
if (($fltr_mode eq $fltr_option[0])&&($fltr_flag==0)) {
	#$fltr_fdat_width=0;
	#$fltr_flag=1;
	#my $num_rows=$fdat->totalRows;
	$fdat->clear;
	$fdat->destroy;
	SetTableVars();	
	$fdat = $base->Table(@Tb_att, -rows=>$nr, -columns=>$nc*5);
	if ( $ScrollFlag ) { $fdat->configure( -scrollbars=>'e') }
	else { $fdat->configure( -scrollbars=>'') }
	$fdat->pack(-padx=>5, -pady=>5);
	ShowTable();
	DisplayData();
	$fltr_fdat_height=$nr*30;
	if ( $nr>$INI{rMAXr} ){$fltr_fdat_height=$INI{rMAXr}*30; }
	$fltr_fdat_width = length ($wgn[0]->cget(-text));
	$fltr_fdat_width+=63*$nc;
	$fdat->configure(-height=>"$fltr_fdat_height", -width=>"$fltr_fdat_width");
}
elsif ($fltr_mode eq $fltr_option[1]) {
	$fltr_flag=0;
	ShowFltr(\@dev_fltr_chan, \@dev_fltr_idx, 1);
	}	
elsif ($fltr_mode eq $fltr_option[2]) {
	$fltr_flag=0;
	ShowFltr(\@missing_fltr_chan, \@missing_fltr_idx, 2);
	}
elsif ($fltr_mode eq $fltr_option[3]) {
        $fltr_flag=0;
        ShowFltr(\@in_line_fltr_chan, \@in_line_fltr_idx, 3);
	}

}

sub ShowFltr {
my (@wgsn, @wgsn0, @wgskn, @wgsfr, @wgpn, @wgp_db_interval, @wgp_received_interval, @wgp_deviation_interval)=();
print "\n\nSHOW\n\n";
my $current_row;
my ($chan, $idx, $fltr_type)=@_;
my @fltr_chan=@{$chan};
my @fltr_idx=@{$idx};
my @uniq_chnl=();
my $wg_count=0;
my %idx_for_chan=();
my @total_parm_count;
my @first_parm_number;
$first_parm_number[0]=0;

@uniq_chnl = do {my %seen; grep {!$seen{$_}++} @fltr_chan};
my $kline=$#uniq_chnl+1; # ����� ����������
$nr=0; # ����� ����������
foreach (@fltr_chan) { # ��� ���� ��������� ���������� � ����������
$nr+=int($_/$nc)+(($_%$nc)?1:0) }
$kline=int($kline*1.318);
$nr+=$kline;
if ( $nr>$INI{rMAXr} ) { $ScrollFlag=1 } else { $ScrollFlag=0 }

if ($fltr_type==1) {
	%idx_for_chan=%dev_idx_for_chan;}
elsif ($fltr_type==2) {
	%idx_for_chan=%missing_idx_for_chan}

elsif ($fltr_type==3) {
	%idx_for_chan=%in_line_idx_for_chan}

my ($s,$n,$j);

(@wgs,@wgc0,@wgf0,@wgf1,@wgf2,@wgf3,@wgc1,@wgc2,@wgn,@wgm,@wgd,@wgu,@wgw0,@wgw1,@wgw2,@wgw3,@wgw4,@wgn_nm,@wg_db,@wg_rcv,@wg_dev,@w_db_interval, @w_received_interval, @w_deviation_interval)=(); my $chan_num;


$current_row=0;
$fdat->clear;
$fdat->destroy;
SetTableVars();
$fdat = $base->Table(@Tb_att, -rows=>$nr, -columns=>$nc*5);
if ( $ScrollFlag ) { $fdat->configure( -scrollbars=>'e') }
else { $fdat->configure( -scrollbars=>'') }
$fdat->pack(-padx=>5, -pady=>5 );


$j=0;
foreach (@uniq_chnl) { # �� ���������� ����������
  ($n,$s,my $fr)=split(/\|/,$sname[$uniq_chnl[$j]]); # ������������, ��������, �������
        $wgs[$j]=$fdat->Label(@ssT, -text=>decode('koi8r',$n));
       	$wgc0[$j]=$fdat->Frame(-borderwidth=>0,-relief=>"flat",-bg=>"$INI{sc_back}");
        $wgc1[$j]=$wgc0[$j]->Label(@scT, -text=>decode('koi8r',$s))->pack(-side=>'left');
	if (defined $fr) { $wgc2[$j]=$wgc0[$j]->Label(@scT, -text=>decode('koi8r',"F$fr"))->pack(-side=>'right') }
	$wgw0[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
	$wgw2[$j]=$wgw0[$j]->Label(-bg=>"$INI{sc_back}")->pack(-side=>'right');
	$wgw3[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   	$wgw4[$j]=$wgw0[$j]->Label(-bg=>"$INI{sc_back}")->pack(-side=>'right');
	$total_parm_count[$j]=$idx_for_chan{$uniq_chnl[$j]};
	$first_parm_number[$j+1]=$first_parm_number[$j]+$idx_for_chan{$uniq_chnl[$j]}	;
	print "\n\nfirst $first_parm_number[$j] total $total_parm_count[$j] $j uniq @uniq_chnl\n\n";
	$j++}

$j=0;

foreach (@fltr_idx) {
  $wgn[$j]=$fdat->Label(@pnT, -text=>decode('koi8r',$pname[$fltr_idx[$j]]));
  if ($missing_parm_flag[$fltr_idx[$j]]==1) {
	 $w_db_interval[$j]=$fdat->Label(@pnT, -text=>"", -width=>11);
	 $w_received_interval[$j]=$fdat->Label(@pdT, -width=>11, -text=>"");
	 $w_deviation_interval[$j]=$fdat->Label(@pdT, -width=>11, -text=>(""));
	}
  elsif ($fltr_type==1) {
  	$w_db_interval[$j]=$fdat->Label(@pnT, -text=>decode('koi8r', "[$min_int{$vme_prm_id[$fltr_idx[$j]]} ; $max_int{$vme_prm_id[$fltr_idx[$j]]}]"), -width=>11);
  	$w_received_interval[$j]=$fdat->Label(@pdT, -width=>11, -text=>"$w_recieved_dev[$j]");
  	$w_deviation_interval[$j]=$fdat->Label(@pdT, -width=>11, -text=>"$w_dev_dev[$j]");}
  elsif ($fltr_type==3) {
 	$w_db_interval[$j]=$fdat->Label(@pnT, -text=>decode('koi8r', "[$min_int{$vme_prm_id[$fltr_idx[$j]]} ; $max_int{$vme_prm_id[$fltr_idx[$j]]}]"), -width=>11);
        $w_received_interval[$j]=$fdat->Label(@pdT, -width=>11, -text=>"$w_recieved_in_line[$j]");
        $w_deviation_interval[$j]=$fdat->Label(@pdT, -width=>11, -text=>"$w_dev_in_line[$j]");
	print "\n\nj=$j na,e=$pname[$fltr_idx[$j]] recieved=$w_recieved_in_line[$j]\n\n";}
	


$j++}


for my $i0 (0..$#wgs) { # ��� ������� ������ �������� ������
if ($nc<3) {
    $fdat->put($current_row,0,$wgs[$i0]);
    $fdat->put($current_row,1,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,2,$wgc0[$i0]);
    $fdat->put($current_row,3,$wgw0[$i0]);
 }
 if ( $nc==2 ) {
    $fdat->put($current_row,5,$fdat->Label(@ssT,-text=>'  ')); # empty
    $fdat->put($current_row,6,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,7,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,8,$fdat->Label(@ssT,-text=>'       ')) }
  if ( $nc==3 ) {
    $fdat->put($current_row,0,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,1,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,2,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,3,$fdat->Label(@ssT,-text=>'       '));
    $fdat->put($current_row,4,$fdat->Label(@ssT,-text=>'  ')); # empty
    $fdat->put($current_row,5,$wgs[$i0]);
    $fdat->put($current_row,6,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,7,$wgc0[$i0]);
    $fdat->put($current_row,8,$fdat->Label(@ssT,-text=>'       '));
    $fdat->put($current_row,9,$fdat->Label(@ssT,-text=>'  ')); # empty
    $fdat->put($current_row,10,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,11,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,12,$fdat->Label(@ssT,-text=>'  '));
    $fdat->put($current_row,13,$wgw0[$i0]);
}

$current_row++;
if ( $total_parm_count[$i0] ) { # ���� �� ������ �������
    $n=int($total_parm_count[$i0]/$nc)+(($total_parm_count[$i0]%$nc)?1:0); # ����� ����� ������� ���������
    $s=0; # ��� ����� ������� ��������� 
    $current_colon=0; # ��� ������� ������� ��������� 
    if ( $INI{GridType} ) { # ��� ������� �������-������
      for my $i1 ( $first_parm_number[$i0]..($first_parm_number[$i0]+$total_parm_count[$i0]-1) ) { # ��� ���������� ����� ���������
        $fdat->put($current_row+$s,$current_colon*5+0,$wgn[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+1,$w_db_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+2,$w_received_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+3,$w_deviation_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+4,$wgu[$i1]);
        $s=(($s==($n-1))?0:$s+1); $current_colon+=($s==0)?1:0;
      } # ��� ���������� ����� ���������
      if ( $total_parm_count[$i0]<$n*$nc ) {# ���������� ������, ��� �������� ����
        for my $i3 ( ($current_row+$s)..($current_row+$n-1) ) { # "������" �������� ��������
          $fdat->put($i3,($nc-1)*5+0,$fdat->Label(@pnT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+1,$fdat->Label(@pmT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+2,$fdat->Label(@pdT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+3,$fdat->Label(@puT,-text=>'       '));
        } # "������" �������� ��������
      } # ���������� ������, ��� �������� ����
      $current_row+=$n;
    } # ��� ������� �������-������
    else { # ��� ������� ������-�������
      for my $i1 ( $first_parm_number[$i0]..($first_parm_number[$i0]+$total_parm_count[$i0]-1) ) { # ��� ���������� ����� ���������
        $fdat->put($current_row+$s,$current_colon*5+0,$wgn[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+1,$w_db_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+2,$w_received_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+3,$w_deviation_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+4,$wgu[$i1]);
        $current_colon=(($current_colon==($nc-1))?0:$current_colon+1); $s+=($current_colon==0)?1:0;
      } # ��� ���������� ����� ���������
      $current_row+=$n;
      if ( $total_parm_count[$i0]%$nc ) { #  ��������� ������ - �������� 
        for my $i3 ( ($total_parm_count[$i0]%$nc)..($nc-1) ) { # "������" �������� ��������
          $fdat->put($current_row-1,$i3*5+0,$fdat->Label(@pnT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+1,$fdat->Label(@pmT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+2,$fdat->Label(@pdT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+3,$fdat->Label(@puT,-text=>'       '));
        } # "������" �������� ��������
      } #  ��������� ������ - �������� 
    } # ��� ������� ������-�������
  } # ���� �� ������ �������

}
#my $height=$j*60;
#if ( $j>$INI{rMAXr} ){$height=$INI{rMAXr}*60; }
$fltr_fdat_width=$fltr_fdat_width*($nc*1.6);
#print "\n\nwidht $fltr_fdat_width\n\n";
$fdat->configure(-height=>"$fltr_fdat_height", -width=>"$fltr_fdat_width");
my $base_width=550*($nc*1.2);
$base_width=int($base_width);
$fltr_fdat_height=$nr*30;
if ( $nr>$INI{rMAXr} ){$fltr_fdat_height=$INI{rMAXr}*30; }
$fltr_fdat_height=int($fltr_fdat_height*1.8);
my $geometry = $base_width.'x'.$fltr_fdat_height;
$base->geometry("$geometry");
}



#�������� �����
sub ChoiceRevision {
if ( $RunFlag ) { StopReg() } # ���������� ����� � VME
$dbh->do(qq(UPDATE packs set state='edit' WHERE id=$packID));
if ($INI{UnderMonitor}) {
  $mes[0]=$packID;
  $mes[1]='edit';
  PageMonitor()}
$dbh->do(qq(UPDATE cmtr_chnl set busy=0 WHERE busy=$packID));
open(STDERR, "|/mnt/NFS/tmp/FtoDKPerl/choice.pl_old I $packID");
}


sub FlashButton {
#������� ������ ������
  $time_wtchr = AnyEvent->timer ( after=>1, interval=>1, cb=>sub { # flash-������ 
    $log_time++; $log_timeS=TimeS($log_time);
     if ($flashFlag) { $b_run->configure(-bg=>"$INI{flash_back}"); $flashFlag=0 }
     else { $b_run->configure(-bg=>"$bckg"); $flashFlag=1 }
     }       );
}

#����� ��������� ����������
sub StartReg {

#��������� �������� � ��������
$stop_st_reg_flag=0;
$out_of_limits_prm_count= $missing_prm_count= 0;
@total_interval_value=();
@missing_parm_flag=0;
$missing_prm_count=0;
$out_of_limits_prm_count=0;
for my $idx (0..$#w_received_interval) {
	ShowData('','',$idx);}
ShowTable();
DisplayData();
$log_time=0;
$log_timeS='00:00:00';

#���������� ������� �� ������
TuneButtons();
#������� ������
FlashButton();

#��������� ���
RAMReset();
$RunFlag=1;
#����� 5 ���
undef $sleep_var;
undef $done_firstread;
$sleep_var=AnyEvent->condvar;
$new_t_wtchr = AnyEvent->timer(after=>5, cb=> sub{
	$sleep_var->send;});
my $sleep_timer = $sleep_var->recv;
#�������� ������� ���� � ����� �����
Read1();
$done_firstread=AnyEvent->condvar;
my $missing_comlete = $done_firstread->recv;
CreateBuffersForInt();
CreateSocketsForInt();
if ($stop_st_reg_flag==1) {
 
	return}
$chanel_done=0;
for my $i(0..$#port_busy_flag) { #�������� ������� ������ �� ���� ������
	RecvInt($i);}
	
#���������� ������� �� ���� �������
my $chan_num=0;
$chanel_measuring_counter=0;
for my $port_num(0..$#port_busy_flag) {
		SendToVME($chan_num,0,0,$port_num);
		$chan_num++;
		$chanel_measuring_counter++;
		}
#	});
$dbh->do(qq(UPDATE packs set state='run' WHERE id=$packID));
if ($INI{UnderMonitor}) {
        $mes[0]=$packID;
        $mes[1]='run';
        PageMonitor() }

}

#��������� ��� (������� ������ � ������� ��� ��������� ���������� ������)
sub RAMReset {
my $len=length($S_IN);
foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) { substr( $S_OUT[$crate],0,4,pack "I",0x240 ); #$base->bell 
} }
foreach my $crate (0 .. 3) {
        if ($crate_tot[$crate]) {# ������������ ������ �� ������ ������ �� 
	        if (!defined send($S_SND[$crate], $S_OUT[$crate], 0, $sin_to[$crate])) { # ������ � VME, �������?
         	       $base->bell; if ($log) { print Log "send fail\n------------------\n" } } # ���
                else { # �������
        	        if ($log_trs) { PrintSock(\$S_OUT[$crate],$crate) } } } }
if ($INI{UnderMonitor}) {
	$mes[0]=$packID;
        $mes[1]=++$rcount;
        PageMonitor() }
}

#������ ���������� ����� ��� �������/��������� ��� ����������� � ����
sub SetTableVars {
my $kline=$#sname+1; # ����� ����������
$nr=0; # ����� ����������
foreach (@total_parm_count) { # ��� ���� ��������� ���������� � ����������
$nr+=int($_/$nc)+(($_%$nc)?1:0) }
$kline=int($kline*1.318);
$nr+=$kline;
if ( $nr>$INI{rMAXr} ) { $ScrollFlag=1 } else { $ScrollFlag=0 }
@crate_tot=();
for my $i (0 .. 3) { $crate_tot[$i]=grep(/$i/,@crate_prm) } }

#�������
sub SetColumns {

my @received_text;
my @deviation_text;
my $draw_counter;
$nc=($nc==$INI{cMAXr})?1:$nc+1;
$base->destroy;
NewWindow();
SetTableVars();
#$fdat = $base->Table(@Tb_att, -rows=>$nr, -columns=>$nc*5);
#if ( $ScrollFlag ) { $fdat->configure( -scrollbars=>'e') }
#else { $fdat->configure( -scrollbars=>'') }
#$fdat->pack(-padx=>5, -pady=>5);
#ShowTable();
my $text=encode ('koi8r',$palete);
print "\ntext $text\n";
Fltr($text);
}

#���������� ������ 
sub ShowData {
my $received_text=$_[0];
my $deviation_text=$_[1];
my $idx=$_[2];
$w_received_interval[$idx]->configure(-text=>decode('koi8r', "$received_text"));
$w_deviation_interval[$idx]->configure(-text=>decode('koi8r', "$deviation_text"));
}

#���������� �������� ����, ���������� ��� �������������� ������
sub RefreshWindow {
print "\nREFRESHED\n";
$base->destroy;
GetPackData();
@options=();
$options[0]=decode ('koi8r', "��� ���������");
NewWindow();
SetTableVars();
$fdat = $base->Table(@Tb_att, -rows=>$nr, -columns=>$nc*5);
if ( $ScrollFlag ) { $fdat->configure( -scrollbars=>'e') }
else { $fdat->configure( -scrollbars=>'') }
$fdat->pack(-padx=>5, -pady=>5);
ShowTable();
PrepSockets();
CreateBuffers();
Set_S_OUT_S_IN();
}



#���������� ���������
sub Suicide {

print "\nSUICIDE\n";
undef $sui_wtchr;
if ( $RunFlag ) { 
StopReg(); } # ���������� ����� � VME
$dbh->do(qq(UPDATE cmtr_chnl set busy=0 WHERE busy=$packID));
$dbh->do(qq(UPDATE vme_ports set busy=0 WHERE port_in=$port_vme_to));
$dbh->do(qq(UPDATE reg SET port=0, flag=NULL  WHERE port=$port_vme_to));
for my $i(0..$#{$port_vme_to_i}){
	if (defined $port_vme_to_i->[$i][1]) {
$dbh->do(qq(UPDATE vme_ports set busy=0 WHERE port_in=$port_vme_to_i->[$i][1])); # ���������� ���� ����� ��������� ��������� 
undef $port_vme_to_i->[$i][1];}
}
for my $k(0..$#rcv_i_wtchr) {
	undef $rcv_i_wtchr[$k];}
undef $pause;
$dbh->do(qq(DELETE from packs WHERE id=$packID));
if ($log or $log_trs) { close(Log) }
if ($INI{UnderMonitor}) {
  $mes[0]=$packID;
  $mes[1]='kill';
  PageMonitor() }
unlink "$$.html";
undef $time_wtchr;
shutdown($S_RCV,2); close($S_RCV);
shutdown($S_RCV_SUI,2); close($S_RCV_SUI);
foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) { shutdown($S_SND[$crate],2); close($S_SND[$crate]) } }
$base->destroy; exit }

#������ ���������� ���������� ���������� �� ��������+������, ����������� ����������
sub DeviationInterval {
my $idx = $_[0];
my $max_interval=$_[1];
my $min_interval=$_[2];
my $chan = $_[3];
my $parm_max_int = $max_int{$vme_prm_id[$idx]};
my $parm_min_int = $min_int{$vme_prm_id[$idx]};

my $missing = $w_db_interval[$idx]->cget('-text');
if ($missing eq '') {
    $w_deviation_interval[$idx]->configure(-text=>'');}
else {
	if ($max_interval>($parm_max_int+$dop_plus)) {
		my $M = $max_interval-$parm_max_int-$dop_plus;
		$w_deviation_interval[$idx]->configure(-text=>decode('koi8r', "+$M"));
		$dev_fltr_chan[$out_of_limits_prm_count]=$chan;
		$dev_fltr_idx[$out_of_limits_prm_count]=$idx;
		$w_recieved_dev[$out_of_limits_prm_count] = $w_received_interval[$idx]->cget(-text);
        	$w_dev_dev[$out_of_limits_prm_count] = $w_deviation_interval[$idx]->cget(-text);
        	#print "\ndev  $w_dev_dev[$out_of_limits_prm_count] \n";
		$dev_idx_for_chan{$chan}++;
		$out_of_limits_prm_count++}
	
	elsif ($min_interval<($parm_min_int-$dop_minus)) {
		my $M = $parm_min_int-$min_interval-$dop_minus;
		$w_deviation_interval[$idx]->configure(-text=>decode('koi8r', "-$M"));
		$dev_fltr_chan[$out_of_limits_prm_count]=$chan;
		$dev_fltr_idx[$out_of_limits_prm_count]=$idx;
		$w_recieved_dev[$out_of_limits_prm_count] = $w_received_interval[$idx]->cget(-text);
                $w_dev_dev[$out_of_limits_prm_count] = $w_deviation_interval[$idx]->cget(-text);
		#print "\ndev  count idx $out_of_limits_prm_count $w_dev_dev[$out_of_limits_prm_count] $idx\n";
		$dev_idx_for_chan{$chan}++;
		$out_of_limits_prm_count++}
}
}

#������������ ���������� ����� � �����
sub FirstRead {
for my $i (0..$#w_db_interval) { # ��� ���� ����������
  $x0=unpack "I",substr($S_IN,64+$i*4,4);
  $x1 = $x0&0xFF;
	if (($v_type[$i]<RK) and (($x0&0xFF)!=$chan_addr[$i])) { # ������������ ���������� ������ ���
	#$wgm[$i]->configure(-text=>' ');
		$w_db_interval[$i]->configure(-text=>'');
	 	$missing_parm_flag[$i]=1;
		print "\nflag $i\n";
		#$missing_prm_count++;
	} } 
	$done_firstread->send;}

#�������� ������� ���� � ����� �����
sub VisScreen {
my $dif_flag=0;
$rcount++; #  ������� ������
for my $i (0..$#w_db_interval) { # ��� ���� ����������
        $x0=unpack "I",substr($S_IN,64+$i*4,4);
        $x1=unpack "I",substr($sock_IN,64+$i*4,4);
	if ( $x0!=$x1 ) { # �� ����������� �������� ����������
                $dif_flag++;
                if (($v_type[$i]<RK) and (($x1&0xFF)!=$chan_addr[$i])) { # ������������ ���������� ������ ���
                        $w_db_interval[$i]->configure(-text=>''); }
                }
        } # ��� ���� ����������
if ($dif_flag) { $S_IN=$sock_IN } # ���� �������: ��������� 1-� �����
return 1; } # ������ ���������� � ������� ����������



#����������� ������ ��� ����������� ������� ����� � �����
sub Read1 { # ����������� ������

foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) { $err_cnt[$crate]=1 } } # ���� ������ �� ���� - ��� ��� ������

my $len=length($S_IN);
foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) { substr( $S_OUT[$crate],0,4,pack "I",0x230 ); } } 
$read1_wtchr = AnyEvent->timer ( after=>1.0, cb=>sub { # timeout watcher
        foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) {
                if ($err_cnt[$crate]) { # ������� ���� ���� �� �������
ErrMessage("�� (����� $crate) �� �������� � ������� 1.0 ������!\n�������� ������� ������.\n���� ��� �������� \"�������\", ������� �������!!!\n���� ���� �������� ��������, ����� ��������� ������.\n� ������ ������ �� ������� ��, ������� ������� � ������������� ��������� ��.") } } }
        undef $read1_wtchr; undef $rcv_wtchr;
VisScreen(); 
FirstRead();  
} ); # ��������������� ��������� � ������ ������
#VisScreen();
$rcv_wtchr = AnyEvent->io ( fh=>\*$S_RCV, poll=>"r", cb=>sub{recvVME() } ); # ���������� ������ ��ɣ����� ������
foreach my $crate (0 .. 3) {
        if ($crate_tot[$crate]) {# ������������ ������ �� ������ ������ �� 
                if (!defined send($S_SND[$crate], $S_OUT[$crate], 0, $sin_to[$crate])) { # ������ � VME, �������?
                        $base->bell; if ($log) { print Log "send fail\n------------------\n" } } # ���
                else { # �������
	                if ($log_trs) { PrintSock(\$S_OUT[$crate],$crate) } } } }
#$time_wtchr = AnyEvent->timer ( after=>1.0, cb=>sub { #����� � �������
#undef $time_wtchr;} );# timeout watcher
if ($INI{UnderMonitor}) {
    $mes[0]=$packID;
    $mes[1]=++$rcount;
    PageMonitor() }
} # ����������� ������

#�������� ������� ��� ����������� ������ (��������� ���, �������� ������� ���� � ����� �����)
sub CreateBuffers {
for my $crate (0 .. 3) {
#        $S_OUT[$crate]=pack 'I', 0x200; # ��� �������� - ������ � ��
#        $S_OUT[$crate].=pack 'I', 0; # total length, shift - 4
#        $S_OUT[$crate].=pack 'a4','A1'; # ������������� ��������, shift - 8
#        $S_OUT[$crate].=pack 'a4','CP0'; # ������������� ����������, shift - 12
#        $S_OUT[$crate].=pack 'I', 0; # ������ ������ � ��� ��� ����. ������, shift - 16
#        $S_OUT[$crate].=chr(0)x20; # �� ������������
#        $S_OUT[$crate].=pack 'I', 0; # total_of_records, shift - 40
#        $S_OUT[$crate].=$mysql_db; # ��� ������ - � ���������
#        my $l=20-length($mysql_db);
#        $S_OUT[$crate].=chr(0)x$l;}  # ����������� ������ �� ������������� ��-�� ���������
# ���������� ��������� ������ $S_OUT
 $S_OUT[$crate]=pack 'I', 0x230; # u_int32 command, ��� �������� ������ - ������ �� ������� ������
 $S_OUT[$crate].=pack 'I', 0; # u_int32 total length, shift - 4
 $S_OUT[$crate].=pack 'a4',"A1"; # char sender_id[4], ������������� ��������, shift - 8
 $S_OUT[$crate].=pack 'a4',"CP0"; # char receiver_id[4], ������������� ����������, shift - 12
 $S_OUT[$crate].=pack 'I', 0; # u_int32 time_stamp - ������ ������ � ��� ��� ����. ������, shift - 16
 $S_OUT[$crate].=pack 'I', 0; # u_int32 jdate, �� ���., shift - 20
 $S_OUT[$crate].=pack 'I', 0; # u_int32 jtime, �� ���., shift - 24
 $S_OUT[$crate].=pack 'I', 0; # u_int32 message_no, �� ���., shift - 28
 $S_OUT[$crate].=pack 'I', 0; # u_int32 total_messages, �� ���., shift - 32
 $S_OUT[$crate].=pack 'I', 0; # u_int32 no_of_records, �� ���., shift - 36
 $S_OUT[$crate].=pack 'I', 0; # u_int32 total_of_records, shift - 40
 $S_OUT[$crate].=chr(0)x20 } # u_int32 reserved[5], �� ���., shift - 44
#


} 

#���������� ���������
sub StopReg {
$RunFlag=0;
$sock_err=0;
@port_busy_flag=();
$b_run->configure(-bg=>"$bckg"); $flashFlag=0;
TuneButtons();
undef $time_wtchr;
undef $new_t_wtchr;
$dbh->do(qq(UPDATE packs set state='stop' WHERE id=$packID));
$dbh->do(qq(UPDATE reg SET port=0, flag=NULL  WHERE port=$port_vme_to));
for my $i(0..$#{$port_vme_to_i}){
        if (defined $port_vme_to_i->[$i][1]) {
$dbh->do(qq(UPDATE vme_ports set busy=0 WHERE port_in=$port_vme_to_i->[$i][1])); # ���������� ���� ����� ��������� ��������� 
undef $port_vme_to_i->[$i][1];}
}
for my $i(0..$#S_int) {
	$dbh->do(qq(UPDATE vme_chan set busy=0, host='' WHERE vme_prm_id=$chan_vme_id{$i}));} 
for my $j(0..$#S_RCV_I){
	if (defined $S_RCV_I[$j]) {
		close $S_RCV_I[$j];}
}
for my $k(0..$#rcv_i_wtchr) {
	undef $rcv_i_wtchr[$k];}
if ($INI{UnderMonitor}) {
  $mes[0]=$packID;
  $mes[1]='stop';
  PageMonitor() }
}

#����������/������������� ������
sub TuneButtons {
if ($RunFlag) {
  $b_choice->configure(-state=>'disabled');
  $b_columns->configure(-state=>'disabled'); 
  }
else { 
  $b_choice->configure(-state=>'normal');
  $b_columns->configure(-state=>'normal'); 
  }
}

#����� ������� � ���
sub PrintSock {
(my $sock, my $crate)=@_;
if (defined $crate) { printf Log "crate  N $crate\n" }
my $c;
my $cmnd=unpack 'I', substr($$sock,0,4);
my $answer=unpack 'I', substr($$sock,56,4);
printf Log "command: 0x%03X ", $cmnd;
if ($cmnd==0x200) { printf Log "(������ � ��)\n" }
elsif ($cmnd==0x210) { printf Log "(������ ������������ ������)\n" }
elsif ($cmnd==0x220) { printf Log "(������ ������������ ������ � �����.)\n" }
elsif ($cmnd==0x230) { printf Log "(������ �������� ������)\n" }
elsif ($cmnd==0x240) { printf Log "(������ �������� ������ � �����.)\n" }
elsif ($cmnd==0x250) { printf Log "(������� ������������ ������)\n" }
elsif ($cmnd==0x260) { printf Log "(��ɣ� ������ �� ��: ";
        if ($answer==0x210) { printf Log "����������� ������)\n" }
        elsif ($answer==0x220) { printf Log "����������� ������ � �����.)\n" }
        elsif ($answer==0x230) { printf Log "������� ������)\n" }
        elsif ($answer==0x240) { printf Log "������� ������ � �����.)\n" } }
else  { printf Log "(������������������ �������)\n" }
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



sub ErrMessage {
my ($txt)=@_;
my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
$er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
$er_base->Message(-anchor=>'center', -font=>$INI{err_font}, -foreground=>"$INI{err_forg}", -justify=>'center', -padx=>35, -pady=>10, -text=>decode('koi8r',$txt), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
$base->bell }

sub TimeS {
my ($s)=@_;
return sprintf "%02u:%02u:%02u", int((int($s/60))/60), (int($s/60))%60, $s%60;
}

sub PrintPage {

my @print_first_parm_number;
$print_first_parm_number[0]=0;
my @print_total_parm_count;
my ($fltr_mode,$chan)=@_;
my @fltr_option;
my %idx_for_chan=();
my @fltr_chan;
my @uniq_chnl=();
$set_columns_flag=0;
$fltr_option[0]= "��� ���������";
$fltr_option[1]="��� ��������";
$fltr_option[2]="������������� � �����";
$fltr_option[3]="� ������� � �����";
my $k==0;

if ($fltr_mode eq $fltr_option[0]){
	@print_first_parm_number=@first_parm_number;
	@print_total_parm_count=@total_parm_count;
}
else {
	if ($fltr_mode eq $fltr_option[1]) {
		%idx_for_chan=%dev_idx_for_chan;
	}
	elsif ($fltr_mode eq $fltr_option[2]) {
		%idx_for_chan=%missing_idx_for_chan;
	}	
	elsif ($fltr_mode eq $fltr_option[3]) {	
	%idx_for_chan=%in_line_idx_for_chan;
	}
@fltr_chan=@{$chan};
@uniq_chnl = do {my %seen; grep {!$seen{$_}++} @fltr_chan};
foreach (@uniq_chnl) { # �� ���������� ����������
        $print_total_parm_count[$k]=$idx_for_chan{$uniq_chnl[$k]};
        $print_first_parm_number[$k+1]=$print_first_parm_number[$k]+$idx_for_chan{$uniq_chnl[$k]}   ;
        print "\n\nfirst $print_first_parm_number[$k] total $print_total_parm_count[$k] $k uniq @uniq_chnl\n\n";
        $k++}

}
my $er_base = MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
$er_base->title(decode('koi8r',"��������:"));
$er_base->geometry($INI{StandXY});
$er_base->Message(-anchor=>'center', -font=>$INI{err_font}, -foreground=>"$INI{err_forg}", -justify=>'center', -padx=>35, -pady=>10, -text=>decode('koi8r',qq(����������� ���������� ��������� � ������.\n�� �������� ��������� ��������� �������� (File->PageSetup) � ��������� �������� (File->Print->�������: ��������). ����������� ������������ ����������� (Print Prewiew).\n\n������� <OK>.)), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
$er_base->Button(-command=>sub{ $er_base->destroy; }, -state=>'normal', -borderwidth=>3, -font=>$INI{but_menu_font}, -text=>'OK ')->pack(-anchor=>'center', -pady=>10, -side=>'top');
my (@s,@c,@n,@m,@di,@r,@d,@f0,@f1,@f2,@f3);
my $lh=`date '+%-B, %-e. %-Y. %X'`; $lh=decode('koi8r',$lh);
my $ch='��e�� - '.$mysql_db.'  ��e����� - '.$mysql_usr.'.'; $ch=decode('koi8r',$ch);
my $fltr_txt=decode('koi8r', ' ������ - ');
$fltr_mode=decode('koi8r', $fltr_mode);
open (HTM, ">$ENV{HOME}/cmk/$$.html") or die "Error: $!" ;
print HTM qq(<HTML><HEAD><TITLE></TITLE>
             <STYLE>
             BODY {font-family: 'Arial';font-size: 14pt}
             TD {font-family: 'Courier New'; font-size: 10pt;}</STYLE>
             <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
             </HEAD>
             <FONT SIZE="-1" FACE="Courier new">$lh $ch $fltr_txt $fltr_mode</FONT>
             <BODY><HR COLOR="Black" NOSHADE><BR>\n);
#������� ������������ ����� ����� ��������� � ��� ��������
my $maxn=0;
my $maxd=0;
for my $i (0..$#wgs) {
  for my $j ($print_first_parm_number[$i]..($print_first_parm_number[$i]+$print_total_parm_count[$i]-1)) {
    $n[$j]=$wgn[$j]->cget('-text');
    $maxn= length($n[$j]) if length($n[$j])>$maxn;
    $d[$j]=$w_db_interval[$j]->cget('-text');
    $maxd= length($d[$j]) if length($d[$j])>$maxd;
  }
}
$maxn=$maxn*8 + 8 + 4;
$maxd=$maxd*8 + 8 + 4;# 8 �������� - ��������� ������ ������� + �� 2 ������� � ������ ������� - ������ �� ������ ������
my $chan_num; my $chan_char; my $line;
for my $i (0..$#wgs) {
  $s[$i]=$wgs[$i]->cget('-text');
  print HTM qq($s[$i] &nbsp;);
  $c[$i]=$wgc1[$i]->cget('-text');
  print HTM qq($c[$i] &nbsp;);
        #$line=decode('koi8r',"����� $chan_char <BR>"); print HTM $line;
  #$f0[$i]=$wgn_nm[$i]->cget('-text');
  #$f1[$i]=$wg_db[$i]->cget('-text');
  #$f2[$i]=$wg_rcv[$i]->cget('-text');
  #$f3[$i]=$wg_dev[$i]->cget('-text');
  $f0[$i]=decode('koi8r',"������������");
  $f1[$i]=decode('koi8r', "�������� ��������, ��");
  $f2[$i]=decode('koi8r', "���������� ��������, ��");
  $f3[$i]=decode('koi8r', "����������, ��");   
print HTM qq(<TABLE BORDER=1 CELLPADDING=2 CELLSPACING=0>);
   #$wgn_nm[$j]=$wgf0[$j]->Label(@pnT, -text=>decode('koi8r',"������������"))->pack(-side=>'left');
   #$wgf1[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   #$wg_db[$j]=$wgf1[$j]->Label(@pnT, -text=>decode('koi8r', "�������� ��������"), -width=>19)->pack(-side=>'left');
   #$wgf2[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   #$wg_rcv[$j]=$wgf2[$j]->Label(@pdT, -text=>decode('koi8r', "���������� ��������"), -width=>19)->pack(-side=>'left');
   #$wgf3[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   #$wg_dev[$j]=$wgf3[$j]->Label(@pdT, -text=>decode('koi8r', "����������") ,-width=>11)->pack(-side=>'left');
#��������� ������� 
  print HTM qq(<BR> </TR>);
  print HTM qq(<TD WIDTH=$maxn>$f0[$i]</TD>);
  print HTM qq(<TD WIDTH=$maxd align="center"> $f1[$i]</TD>);
  print HTM qq(<TD WIDTH=$maxd align="center"> $f2[$i]</TD>);
  print HTM qq(<TD WIDTH=$maxd align="center"> $f3[$i]</TD>);
  print HTM qq(</TR>);


 
  my $bgflag=0;
  for my $j ($print_first_parm_number[$i]..($print_first_parm_number[$i]+$print_total_parm_count[$i]-1)) {
    if ($bgflag==0) {$bgflag=1}
    else {$bgflag=0}
    $n[$j]=$wgn[$j]->cget('-text');
    #$m[$j]=$wgm[$j]->cget('-text');
                $n[$j]=~s/ /&nbsp;/g; #$m[$j]=~s/ /&nbsp;/g;
    $d[$j]=$w_db_interval[$j]->cget('-text'); if (!length($d[$j])) {$d[$j]='&nbsp;'}
    $r[$j]=$w_received_interval[$j]->cget('-text'); if (!length($r[$j])) {$r[$j]='&nbsp;'}
    $di[$j]=$w_deviation_interval[$j]->cget('-text'); if (!length($di[$j])) {$di[$j]='&nbsp;'}
    print HTM qq(<TR);
    if ($bgflag==0) {print HTM qq( BGCOLOR="Silver">)}
    else {print HTM qq(>)}
    print HTM qq(<TD WIDTH=$maxn>$n[$j]</TD>);
    #print HTM qq(<TD WIDTH=20 align="center"> $m[$j]</TD>);
    print HTM qq(<TD WIDTH=$maxd align="right"> $d[$j]</TD>);
    print HTM qq(<TD WIDTH=$maxd align="right"> $r[$j]</TD>);
    print HTM qq(<TD WIDTH=$maxd align="right"> $di[$j]</TD>);
    #print HTM qq(<TD WIDTH=50>$u[$j]</TD>);
    print HTM qq(</TR>);
  }

  print HTM qq(</TABLE><BR><BR>);
  print HTM qq(</BODY></HTML>);
}
close(HTM);
my (@arg) = ('opera -activetab'. " $ENV{HOME}/cmk/$$.html");
#my (@arg) = ('mozilla'. " $ENV{HOME}/cmk/$$.html");
my $child=fork;
unless ($child) { exec(@arg) }
return;
}


sub recvVME { # ������� � ���������� �����
my $crate; my $hostiadr;
my $cnt=0; my $S_CR=''; #current buffer
if ( select( $rout=$rin, undef, undef, 0) ) { # ������� ��� ������, ���� ��� ����
        $hostiadr=recv($S_RCV,$S_CR,$max_buf_length,0);
        $hostiadr=inet_ntoa(substr($hostiadr,4,4));
        $crate=$host_crate{$hostiadr};
        #print "\n Crate = $crate \n";
        $err_cnt[$crate]=0 } # ������� �� VME
else { print "I/O error: interrupt w/o packet!\n"; return }
my $erl=length($S_CR);
my $numpack=unpack 'I', substr($S_CR,28,4); # ����� �� ������
if (    $erl != $buf_length[$crate] ) { # ��������� ������� recv, ���� ������: 
        $S_CR.=chr(0)x($buf_length[$crate]-$erl); # ���� ����� ��� ������ - ��������� "0"
        if ($log) { print Log "buffer's length missmatch: requested - $buf_length[$crate], received - $erl\n" } }
my $shCR; my $shBUF;
if ($log_trs) { PrintSock(\$S_CR, $crate) }
for my $i (0 .. $#{$buf_cr[$crate]}) {
        $shCR=64+($i<<2); $shBUF=64+(($buf_cr[$crate]->[$i])<<2);
        substr($sock_IN,$shBUF,4,substr($S_CR,$shCR,4)) }
if ($INI{UnderMonitor}) {
        $mes[0]=$packID;
        $mes[1]=$rcount;
        PageMonitor() }
} # sub recvVME 

#���������� ������� ��� ��������� ����������, �� ������ ������ �� ������ ����� � ������ ������
sub CreateBuffersForInt {
	print "\nBUFFERS CREATED\n";
	my $chanel_counter=0;
	my $pack_counter=0; #�������-������������� ������������� ������
	my $vme_prm_buff;
	my $chan_addr_buff;
	
	@S_int=@S_int_cycle=@S_int_stop=();
	(%chan_vme_id)=();
	for my $compl_counter (0..$#sname) {
	        my $key;
		$measurment_time[$chanel_counter]=0;
		$key=$chan_key{$compl_counter};
		
		$vme_prm_buff = $sys_parm{$key};
		$chan_addr_buff = $chan_addres{$key};
		my $prm_counter=0;
		my ($sys, $num_compl) = split (/;/, $key);
		foreach my $i (0..$#{$sys_parm{$key}}) {#��� ������� ����� i � ������ chanel_counter
		if ($missing_parm_flag[$pack_counter]==1) { 
		print "\nmissing parm\n";}
		(my $vme_chan_addr_i,my $crate, my $chan_vme_prm_id, my $vme_prm_id_i)=$dbh->selectrow_array(qq(
	      SELECT vme_chan.vme_chan_addr,crate,vme_chan.vme_prm_id, vme_chan.vme_prm_id
	      FROM vme_card,compl,vme_chan,parm WHERE parm.vme_prm_id=$vme_prm_buff->[$prm_counter]
	      AND compl.id_system=parm.id_system AND num_compl=$num_compl
                        AND compl.id_vme_chan=vme_chan.id_vme_chan AND vme_chan.id_vme_card=vme_card.id_vme_card
                        AND compl.sim=0));
   		print "\n\nCHAN_VME_ID $chan_vme_prm_id\n\n";
			unless (defined $chan_vme_prm_id) { ErrMessage('��� ������� ������ ������ ����������� ��������� �� ��������������'); return }
	    	my $prm_name=$wgn[$pack_counter]->cget('-text'); 
		my $val=$chan_addr_buff->[$prm_counter];
		my $koi=encode('koi8r',$prm_name);
		#print "\nkey= $key prm_counter= $prm_counter chanel_counter val= $val vme_prm_buff=$vme_prm_buff->[$prm_counter] chan_buff $chan_addr_buff->[$prm_counter] name $koi arrary @{$chan_addr_buff}\n";

		if ($koi=~/\s(k|�|�|K)\.(1|2|3|4)$/) { # � ����� ���-�� ������������ dsi (data sourse identificator)
        	my $dsi=substr $koi,-1,1; $dsi&=0x3; $val|=($dsi<<8); $val|=0x400 }
		
		$chan_measuring_flag[$chanel_counter]=0;
 
		$S_int[$chanel_counter][$prm_counter]=substr( $S_OUT[$crate],0,72);
		substr( $S_int[$chanel_counter][$prm_counter], 0,4,pack "I",0x200 ); # ��� �������� - ������ � ��
		substr( $S_int[$chanel_counter][$prm_counter], 4,4,pack "I",72 ); # total length 
		substr( $S_int[$chanel_counter][$prm_counter],40,4,pack "I",1 ); # total_of_records
		substr( $S_int[$chanel_counter][$prm_counter],64,4,pack "I",$chan_vme_prm_id ); # vme_prm_id
		substr( $S_int[$chanel_counter][$prm_counter],68,4,pack "I",$val ); # new data (����������� ������������� ���-��)
		
		if (not defined $chan_vme_id{$chanel_counter}) {
			$chan_vme_id{$chanel_counter}=$vme_prm_id_i;}
		
		my $interval = $max_int_for_buff{$vme_prm_buff->[$prm_counter]};
		print "\nMAX INTERVAL $max_int_for_buff{$vme_prm_buff->[$prm_counter]}\n";
		$interval_for_recv_int[$pack_counter]=$interval;	
		print "\n\ninterval = $interval counter = $prm_counter vme $vme_prm_buff->[$prm_counter] \n\n";
		$S_int_cycle[$chanel_counter][$prm_counter] = $S_int[$chanel_counter][$prm_counter];
		substr( $S_int_cycle[$chanel_counter][$prm_counter], 0,4,pack "I",0x210 ); # ��� �������� - ������. ������ ��� ���������
		substr($S_int_cycle[$chanel_counter][$prm_counter],28,4,(pack 'I',$pack_counter));
		substr( $S_int_cycle[$chanel_counter][$prm_counter], 32,4,pack "I",$pack_counter); 
		substr( $S_int_cycle[$chanel_counter][$prm_counter], 4,4,pack "I",68 ); # total length, total_of_records - �������
		substr( $S_int_cycle[$chanel_counter][$prm_counter],16,4,pack "I",int($interval*1000) ); # ������ ����.������ (���� �������� � ���)
		
		$S_int_stop[$chanel_counter][$prm_counter] = $S_int_cycle[$chanel_counter][$prm_counter];
		substr( $S_int_stop[$chanel_counter][$prm_counter],0,4,pack "I",0x250 ); # ������� - � S_stop

		$crate_for_buff[$chanel_counter][$prm_counter]=$crate;
		$pack_for_buff{$pack_counter}="$chanel_counter;$prm_counter";
		$pack_counter++;
		$prm_counter++;
		$measurment_time[$chanel_counter]+=(($N_parm_count+1)+$start_recv_count)*($interval/1000)+2*$IS_pause;
		}
	my $chan_busy= $dbh->selectrow_array(qq(
	 SELECT vme_chan.busy FROM vme_chan
	 WHERE vme_chan.vme_prm_id=$chan_vme_id{$chanel_counter}));
	
	if ($chan_busy!=0) {
		ErrMessage("��������� ��������� ����������, �.�. ����� $chan_vme_id{$chanel_counter} �����");
		StopReg(); $stop_st_reg_flag=1; return}
	else {
		$dbh->do(qq(UPDATE vme_chan SET busy=1, host="$my_host" WHERE vme_prm_id=$chan_vme_id{$chanel_counter}))}
	$chanel_counter++;
my @ttext= sort { $a <=> $b } @measurment_time;
print "\n\n����� @ttext\n\n"	}
}

#�������� ������� ��� ����������������� ��������� ����������
sub CreateSocketsForInt {
        my $port_count;
	$port_vme_to_i=$dbh->selectall_arrayref(qq(SELECT id,port_in from vme_ports WHERE host="$my_host" and !busy ));
        if ($#S_int>=$#{$port_vme_to_i}) {
		$port_count=$#{$port_vme_to_i};}
	else {$port_count=$#S_int}
	print "\nport_count $port_count\n";
	if ($port_count<0) { # ��������� �� ���������� ���������� ����� ������ ���� ��� ��������� ������ (���������� ������ ��������� �� ������� ���������� �������� � port_vme_to_i, � ������ ���������� � ���� (0-����� ����), ��� ������ - port_count=-1)

                                ErrMessage('��� ������ ������� ��� ��������� ������ ������ � vme'); StopReg(); $stop_st_reg_flag=1; return }
	for my $i (0..$port_count) {
		
		if (defined $port_vme_to_i->[$i][1]) { # ���� ���� ��������� ���� 
        		$port_busy_flag[$i]=0;
			$port_vme_from_i->[$i][1]=$port_vme_to_i->[$i][1]+1;
                	$dbh->do(qq(UPDATE vme_ports set busy=1 WHERE id=$port_vme_to_i->[$i][0])); # ����������� ���
                	$sin_from_i[$i] = sockaddr_in( $port_vme_from_i->[$i][1], INADDR_ANY ); # �������������� �����: ��ɣ� �� ������ ����� �� ������� �����
			socket($S_RCV_I[$i], PF_INET, SOCK_DGRAM, $proto); # $S_RCV_I - filehandle for "interval mesurement exchange"
                	my $bind_answ=bind($S_RCV_I[$i],$sin_from_i[$i]); $rin_i[$i] = ''; vec($rin_i[$i], fileno( $S_RCV_I[$i] ), 1) = 1;
                	unless ($bind_answ) { print "unsuccessfully binded socket!\n" } 
			for my $crate (0..3) {
                		$sin_to_i[$crate][$i] = sockaddr_in( $port_vme_to_i->[$i][1], $iaddr[$crate] );}
			}
                        }
}

#�������� �������� � VME (�����/��������� ������������ ������, ����������� �� ������ ����� , ����� ����� � ��������)
sub SendToVME {
my $chanel_idx=$_[0];
my $parm_idx=$_[1];
my $stop_flag=$_[2];
my $sock_num=$_[3];
$port_busy_flag[$sock_num]=1;
$chan_measuring_flag[$chanel_idx]=1;
my $interval = unpack "I", substr( $S_int_cycle[$chanel_idx][$parm_idx],16,4 );
$interval=2*($interval/1000);
#print "\nsended! chan $chanel_idx parm $parm_idx stop $stop_flag \n";
if ($stop_flag==0) {
	
	#print "\nSend to VME crate $crate_for_buff[$chanel_idx][$parm_idx] chanel $chanel_idx parm $parm_idx\n";
	send($S_SND_I,$S_int[$chanel_idx][$parm_idx], 0, $sin_to_i[$crate_for_buff[$chanel_idx][$parm_idx]][$sock_num]); # ������ � VME
	if ($log_trs) { PrintSock(\$S_int[$chanel_idx][$parm_idx],$crate_for_buff[$chanel_idx][$parm_idx]) }
	#sleep($interval);
	#$send_wtchr = AnyEvent ->timer (after=>$interval, cb=>sub {
		send($S_SND_I,$S_int_cycle[$chanel_idx][$parm_idx], 0, $sin_to_i[$crate_for_buff[$chanel_idx][$parm_idx]][$sock_num]); # ������ � VME
		$chanel_parm{$send_counter} = "$chanel_idx;$parm_idx";
		if ($log_trs) {PrintSock(\$S_int_cycle[$chanel_idx][$parm_idx],$crate_for_buff[$chanel_idx][$parm_idx]);} 
		#print "\n\n\n\n send_counter $send_counter chanel_idx $chanel_idx ; $parm_idx sock_num $sock_num measuring $chanel_measuring_counter\n\n\n\n";
		$send_counter++;

		#});
	}
	
else {
	send($S_SND_I,$S_int_stop[$chanel_idx][$parm_idx], 0, $sin_to_i[$crate_for_buff[$chanel_idx][$parm_idx]][$sock_num]); # ������ � VME
	PrintSock(\$S_int_stop[$chanel_idx][$parm_idx],$crate_for_buff[$chanel_idx][$parm_idx]) 
	}	
}

#����������� ����������� ����������
sub DisplayData {
my $disp_idx=0;	   #������ ������� ��������� (� wgn)
my $options_idx=0; #������ ����� ��� �������
%missing_idx_for_chan=();
%dev_idx_for_chan=();
%in_line_idx_for_chan=();
(@w_recieved_dev, @w_dev_dev, @w_recieved_in_line, @w_dev_in_line)=();
(@dev_fltr_chan, @dev_fltr_idx, @missing_fltr_chan, @missing_fltr_idx, @in_line_fltr_chan, @in_line_fltr_idx) = ();
$out_of_limits_prm_count=0;
$missing_prm_count=0;
$in_line_prm_count=0;
for my $chan (0..$#total_interval_value) {
	print "\nCHAN $chan\n";
	$missing_idx_for_chan{$chan}=0;
	$in_line_idx_for_chan{$chan}=0;
	for my $parm (0..$#{$total_interval_value[$chan]}) {
		my $interval=$total_interval_value[$chan][$parm];
		my $max_interval;
		my $min_interval;
		for my $i (0..$#{$interval}) {
			if (!defined $max_interval) {
				 $max_interval = $interval->[$i];}
			elsif (!defined $min_interval) {
				 $min_interval = $interval->[$i];}
			else {
				if ($interval->[$i]>$max_interval) {
					$max_interval=$interval->[$i];}
				elsif ($interval->[$i]<$min_interval) {
					$min_interval=$interval->[$i];}
				}
			if ($i==$#{$interval}) {
			print "\n\nchan $chan parm $parm max $max_interval min $min_interval\n\n";
				 if (($max_interval==$min_interval)&&($max_interval==0)) {
              $missing_parm_flag[$disp_idx]=1;
				      $w_db_interval[$disp_idx]->configure(-text=>'');
							$missing_fltr_chan[$missing_prm_count]=$chan;
			        $missing_fltr_idx[$missing_prm_count]=$disp_idx;
			        $missing_idx_for_chan{$chan}++;
			        $missing_prm_count++;
							$disp_idx++;}
				 else { 
				 	my $missing = $w_db_interval[$disp_idx]->cget('-text');
					if ($missing eq '') {
                                                $w_received_interval[$disp_idx]->configure(-text=>'');
						$missing_fltr_chan[$missing_prm_count]=$chan;
						$missing_fltr_idx[$missing_prm_count]=$disp_idx;
						$missing_idx_for_chan{$chan}++;
						$missing_prm_count++;}
                                 				  
				 	else {
						
						if ($min_interval!=$max_interval) {
							$min_interval=sprintf("%i",$min_interval);
							$max_interval=sprintf("%i",$max_interval);
							if ($min_interval==0) {$w_received_interval[$disp_idx]->configure(-text=>decode('koi8r', "$max_interval"));}
							elsif ($max_interval==0) {$w_received_interval[$disp_idx]->configure(-text=>decode('koi8r', "$min_interval"));}
							else {
							$w_received_interval[$disp_idx]->configure(-text=>decode('koi8r', "$min_interval � $max_interval"));}
						}
						else {
							$max_interval=sprintf("%i",$max_interval);
							if ($max_interval==0) {$w_received_interval[$disp_idx]->configure(-text=>decode('koi8r', ""));}
							else {$w_received_interval[$disp_idx]->configure(-text=>decode('koi8r', "$max_interval"));}
						}
					
				 DeviationInterval($disp_idx,$max_interval,$min_interval,$chan);
				 $in_line_fltr_chan[$in_line_prm_count]=$chan;
                                 $in_line_fltr_idx[$in_line_prm_count]=$disp_idx;
				 $w_recieved_in_line[$in_line_prm_count] = $w_received_interval[$disp_idx]->cget(-text);
		                 $w_dev_in_line[$in_line_prm_count] = $w_deviation_interval[$disp_idx]->cget(-text);
				 $in_line_idx_for_chan{$chan}++;			 
				 $in_line_prm_count++;
				 #print "\ncount $in_line_prm_count chan $chan in_line_for_chan $in_line_idx_for_chan{$chan}\n";	
				}
				 $disp_idx++;
					
				 #$w_db_interval[$j]=$fdat->Label(@pnT, -text=>decode('koi8r', "$min_int{$vme_prm_id[$j]} ~_ $max_int{$vme_prm_id[$j]}"), -width=>11);
  				 #$w_received_interval[$j]=$fdat->Label(@pdT, -width=>11);
  				 #$w_deviation_interval[$j]=$fdat->Label(@pdT, -width=>11);
			}}
			
			#print "\n\n\nCHAN $chan PARM $parm INTERVAL $interval->[$i]\n\n\n";
			}
		}
	
}

 if ($in_line_prm_count > 0) {
        my $option=decode ('koi8r', "� ������� � �����");
        $options_idx++;
        $options[$options_idx]=$option;
        $b_filter->configure(-options => [@options]);}
        #���������� ��� ����������, �������� �� ������� � ��� �������������� � �����  

#���� ���� ������������� ��������� - ��������� �����. ����� � ������
 if ($missing_prm_count > 0) {
          my $option=decode ('koi8r', "������������� � �����");
          $options_idx++;
          $options[$options_idx]=$option;
          $b_filter->configure(-options => [@options]);
          }

if ($out_of_limits_prm_count > 0) {
        my $option=decode ('koi8r', "��� ��������");
        $options_idx++;
        $options[$options_idx]=$option;
        $b_filter->configure(-options => [@options]);}
}

#�/�, ����������� ������ � ����������� ���������� ����������, �������� ������� �� �� ������� ������ �������� ��������� � ��
#������ ���������� ��������� �� ���������� �����, � ����� ���������� ���������� ���������� ���������� �� ������� @total_interval_value
sub RecvInt {
my $sock_num=$_[0];
my $recv_counter=0; #����� �� ����� ������ ���������
my $count_for_start=0; #������� ��� ����������� �����, � �������� ���� ������ ��������� ���������
my @int; #��������� ��� ������ ��������� (���������� ����� ���� ��� ��������� �������� ������ ���������� ���)
my ($chan_num, $parm_num);
my $parm_read_counter=0; #������ ��������� ���������� ����������� ���������� �� �������
my $stop_flag; #����, 1 - ������� ������������ ������, 0 - ��������� ������
my $S_RCV_INT=$S_RCV_I[$sock_num];
my $val;
my $timeout_counter=0;
$rcv_i_wtchr[$sock_num]=AnyEvent->io(fh=>\*$S_RCV_INT, poll=>"r", cb=>sub { # ���������� ������ ��ɣ����� ������ ����������
        #print "\n�������� ������ ������\n";
	my $sock_IN; $val=0; 
	while ( select( $rout_i[$sock_num]=$rin_i[$sock_num], undef, undef, 0) ) { # ������� ��� ������, ���� ��� ����
                recv($S_RCV_INT,$sock_IN,68,0) } # ������� �� VME
        $sock_err_i=0; # �������� ���� ������ ������ ���������
        $val=unpack "I",substr($sock_IN,64,4);
        $val&=0xFFFF0000; $val>>=16;
        $val=sprintf "%04u",$val ;
        my $send_id=unpack "I", substr($sock_IN, 32,4);
	my $pack_id = unpack "I",substr($sock_IN,28,4);
	my $interval = $interval_for_recv_int[$send_id];
	
	$pack_id=$pack_id-1;
	#print "\nval $val  pack $pack_id send_id $send_id sock_num $sock_num chan_num $chan_num \n";
	($chan_num, $parm_num) =split /;/ ,$pack_for_buff{$send_id};
	#($chan_num, $parm_num) = split /;/, $chanel_parm{$recv_counter};
	print "\nval $val interval $interval pack $pack_id sen $send_id sock_num $sock_num chan_num $chan_num, parm_num $parm_num, recv_counter $recv_counter chanel_done $chanel_done\n";
	my $timeout=$timeout_time/($interval_for_recv_int[$send_id]/1000);
	$timeout=int($timeout);
	if ($count_for_start<$start_recv_count) {
	$count_for_start++;}
	else {#��� N_parm_count ������, ������� � count_for_start
			#if ($missing_parm_flag[$parm_num]==1) {
		        #print "\nWAS MISSING\n";
        		#for my $i (0..$N_parm_count) {
                	#	$total_interval_value[$chan_num][$parm_num][$i]=0;}
               		#	$count_for_start=$start_recv_count; $parm_read_counter=$N_parm_count;}

			if ($parm_read_counter<$N_parm_count) {
			#���� �������� ������������ � ����� �����, �� ��������� � ���������� ���������, � ������ ����� ���� 0
	  #���� �������� ��� � ������� � ����� �����, �� ������ 0, �� ����������� ������� ��������, ���� ������ ������� (������������
				#��� - ������� == ������� ���������� �����/�������� ����. ������), �� ���������� � ������ 0 (��������� ���������� ��������) � ��������� � ���������� ���������
				my $val_for_comp = sprintf ("%i", $val);
				if ($val_for_comp==0) {
					$timeout_counter++;
					print "\nrecieved 0 $timeout_counter $timeout\n";
					if ($timeout_counter>=$timeout) {
						print "\n\nTIMEOUT\n\n";
						$total_interval_value[$chan_num][$parm_num][$parm_read_counter]=$val;
						$parm_read_counter=$N_parm_count;}}
				else {				
					$total_interval_value[$chan_num][$parm_num][$parm_read_counter]=$val;
					$parm_read_counter++;}
				}
				#print "\nparm_read_counter $parm_read_counter\n";
		
		else {
			$parm_read_counter=0;
			$timeout_counter=0;
			#$total_interval_value[$chan_num][$parm_num]=\@int;
			@int=();
			$count_for_start=0;
			if ($parm_num<$#{$S_int[$chan_num]}) { #���� ��������� �� ��� ��������� � ���� ������
				$stop_flag=1;
				SendToVME($chan_num, $parm_num, $stop_flag, $sock_num);
				$stop_flag=0;
				$recv_counter++;
				my $next_parm_num=$parm_num+1;
				SendToVME($chan_num, $next_parm_num, $stop_flag, $sock_num);
			}	
			else {
				$stop_flag=1;
				$recv_counter++;
				SendToVME($chan_num, $parm_num, $stop_flag, $sock_num);
				#print "\n������ �� ������\n";
				$chanel_done++;
				$port_busy_flag[$sock_num]=0;
				if ($chanel_done<($#S_int+1)) {
					my $next_chan;
					for my $i ($chan_num..$#chan_measuring_flag) {
						if ($chan_measuring_flag[$i]==0) {
							$next_chan=$i;
							#print "\nnext_chan $next_chan\n";
							$stop_flag=0;
							SendToVME($next_chan,0,$stop_flag,$sock_num);
							$chanel_measuring_counter++;
							last}}	
				
				}
				else {
					#print "\n����� chan_done $chanel_done == ($#S_int+1)\n";
					StopReg();
					$RunFlag=0;
					DisplayData();
					}
			
			 
			}
		}
	}
	});
}
		



