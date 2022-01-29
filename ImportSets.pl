#!/usr/bin/perl -w 
#��������� ��������/������� ������� ������ ImportSets

#������ 0.1

#����������: ������� ������� ������ ����� ������������ ��������, �������������� ����� ������������ �����.

use Encode;
use Tk;
use DBI;
use Tk::Table;
use Tk::Dialog;
use SSRP;
use IPC::Msg;
use Tk::TableMatrix;
use Tk::Balloon;
use bytes;
use strict;

#���������� ����������;
my $current_user; #��� �������� ������������ ������
my $current_parent; #��� �������� ������ ������� ������������ �����
my $user; #��� ���������� ���������� ������������ ������
my $Sets = {}; #��� ������� ������ ������������ ������, ���������� ����������
my %Stands = (); #��� �� ������� ����������� ������� ������������� ������� ������������ ����� 
my %Plates = (); #��������� ������� �������� ����� ������
my %MissingSys = (); #������ ������� � ���� ������, �������������� � ������ ������, �� 
   #������������� � ������� ����������� ������
my %MismatchingSys = (); #��� ������ ������, ���������� ���������� � ������� �� ������������� 
   #���������� ���������� � ������, �� �������� �������������� ������
my $dir_name; #��� ����������, � ������� ���������� ���� ssrp.ini
my $shmsg; #��������� � ������� ����������� ������
my $target; #�������� ���� sets.target
my $SSRPuser; #��� �������� ������������ ��������� ���� ����/����
my $mntr_pid; #������������� �������� ��� ������ � ���������
my (@Tl_att)=(-borderwidth => 1, -relief => 'flat',  -takefocus => 0); # Toplevel attributes
my $users_sets; #������ ������ ���������� ������������� ������������ ������
my $set_data; #�������� ���� sets.data ���������� ���������� ������ ������
my $set_comment=''; #��� ������ ������
my @UserSets_id_system = 0; #������ ������� ������ (������ ������ ����� �����������) � 
   #������ ������, ��������� ����������
my @UserSetsComplNum = 0; #������ ������� ���������� ������ � ������ ������, ��������� ����������
my @UserSets_id_parm = 0; #������ �������� id_parm ���������� � ������ ������, ��������� ����������
my @User_id_system=0 ; #������ ���������� �������� id_system � ������ ������, ��������� ����������
my @Base_id_system = 0; #������ ���������� �������� id_system � ������� ������ ������� ������������ �����
my @Current_id_system = 0; #������ ���������� �������� id_system �������� ������������ ������
my @CurrentSets_id_parm = 0; #������ �������� id_parm (�������� ����� �����������) �������� ������������ ������
my @CurrentSets_id_system = 0; #������ �������� id_system (�������� ����� �����������) �������� ������������ ������
my @CurrentSetsData = 0; #������ �������� ���������� � ����� ������ ������
my @CurrentSetsComplNum; #������ ������� ���������� ������, ��� ��������������� ������
my $data; #������ ���� sets.data ������ ������ ������
my @UserSetsData = 0; # - ������ �������� ���������� � ��������� ���������� ������ ������
my $Set_id = 0; #������ ���������� ���������� ������ ������
my $text; #��� ������ ������ ������ ��� ������ ����� "��������� ���" � ���� 
my $born_time; #�������� ���� sets.born_time
my $sql_var='ORDER BY born_time DESC,user ASC,comment ASC';
my $cmnt=my $usr=1; my $dt=0;
 
#������� ������ ��
#cmk - ������� ���� ������, ���������� �������� ���� �������
#cmk.user - ����� ����������� �������
#sets - ������� ���� ������, ���������� �������� ���� ������� ������ �������� � ���������� ���������� ����������� �������
#sets.id - ������ ������ ������
#sets.user - ��� ��������� ������ ������
#sets.born_time - ����� �������� ������ ������
#sets.comment - �������� ������ ������
#sets.target - ���������� ������ ������ (�������/�������������)
#sets.data - ������ ������ ������
#system - ������� ���� ������, ���������� �������� ���� ������ ���������� ���������� ������ ������
#system.id_system - ������ �������
#system.name - ��� �������
#system.n_s_s - ���������� ���������� ����������

###########################

#���������� ������� �������
chomp($dir_name = $ENV{HOME});
$dir_name.='/cmk';
chdir $dir_name;

#2.1.   �������� ����� ssrp.ini, ��� ���������� ���������� ������������� ������������ 
 #���������� � ������������ ������� ��� ����� ����/����.
open (INI,'ssrp.ini');
my @ini = <INI>;
close (INI);
my %INI = ();
my ($str,$hole,$name,$value);
foreach (@ini) {
   chomp;
   if (substr($_,0,1) eq '#') { next }
   if (!$_) { next }
   ($str,$hole) = split(/;/,$_,2);
   ($name,$value) = split(/=/,$str,2);
   $INI{$name} = $value }

#2.2.   ��� ������� ��������� �����������, �������� �� ����������� ���� ����/����, 
#���� ���� �� ��������, ����� ��������������� ���� � ���������� 
#"����������, ��������� ����". 
  if ($INI{UnderMonitor}) { # ���������� shmem, ���������� $SSRPuser
     unless (-e '/tmp/ssrp.pid') { NoShare() }
     open (PF,'/tmp/ssrp.pid');
     $shmsg = new IPC::Msg( 0x72746e6d,  0001666 );
     RestoreShmem();
     $SIG{USR2} = \&Suicide }

#ErrMessage
#���������� - ����� ��������������� ���� ������ ��� �/� CheckName
sub ErrMessage {
my ($txt) = @_; # ����� ���������
my $er_base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", 
   -highlightthickness => 5);
$er_base->title(decode('koi8r',"��������:")); $er_base->geometry($INI{StandXY});
$er_base->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", 
   -justify => 'center', -padx => 35, -pady => 10, -text => decode('koi8r',$txt), -width => 400)->pack(-anchor => 'center', 
   -pady => 10, -side => 'top');
} #����� ErrMessage

#RestoreShmem
#���������� - ��������� �� ���� ����� ������������ mysql 
sub RestoreShmem {
my @shmem = <PF>; close(PF);
($SSRPuser, $mntr_pid) = split(/\|/,$shmem[0]);
} #����� RestoreShmem

#NoShare
#���������� - ����� ��������������� ���� � ���������� "����������, ��������� ����"
sub NoShare {
my $base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
$base->title(decode('koi8r',"������:"));
$base->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35, -pady => 10, 
   -text => decode('koi8r',qq(������������ �� ���������������:\n��-��������, �� ��������� "����".\n��������� "���� ����/����" \n� - �����������������.)),
   -width => 400)->pack(-anchor => 'center', -pady => 10, -side => 'top');
$base->Button(-command => sub{ $base->destroy; exit(0); }, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
   -text => 'OK')->pack(-anchor => 'center', -pady => 10, -side => 'top');
$base->protocol('WM_DELETE_WINDOW',sub{ $base->destroy; exit(0); } );
$base->grab;
MainLoop; 
}#����� NoShare

#2.3.   �������� ������� ���� "������ ������� ������", ��� ����������� ���������� ��� 
   #���������� "�������/�������������", "�����", "����� ������". �������� 
   #��������� ������ � ������ ����� ����� ����.
my $mw = MainWindow->new;
$mw->geometry("820x620");
$mw->title(decode ('koi8r',"������ ������� ������"));

#�� ��������� ��������������� �������� ���������� target = "S", 
#��� ������������� ��������� ����������� "�������".
$target = "S";

#����� ��� ������� "����� ������"
my $setwin = $mw->Frame(@Tl_att); $setwin->Label(-text => decode('koi8r',"�������� ����� ������:"));
$setwin->pack(-anchor => 'center', -expand => 0 ,-padx => 10, -pady => 10, -fill => 'both', -side => 'right');

#������� "����� ������"
my $setdata = $setwin->Scrolled('TableMatrix', -scrollbars => 'osoe', -rows => (12), -cols=>3,
   -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, -state => 'disabled', -selectmode => 'single',
   -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both', -padx => 5, -pady => 5, -selecttitles => 1);
$setdata->tagConfigure('NAME', -anchor => 'w');
$setdata->tagConfigure('title', -relief => 'raised');
$setdata->tagCol('NAME', 0);
$setdata->colWidth(0 => 18, 1 => 12, 2 => 15);
$setdata->pack(-expand => 1, -fill => 'none');

#����� ��� ������� "�����"
my $standwin = $mw->Frame(@Tl_att);
$standwin->pack(-anchor => 'center', -expand => 1, -fill => 'both', -side => 'left');

#������� "�����"
my $Stand = $standwin->TableMatrix(-rows => 10, -cols => 3, -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, 
   -state=>'disabled', -selectmode => 'single', -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both', -padx => 15, -selecttitles => 0);

#����� �������� "�������/�������������"
my $Radiobutton = $mw -> Frame();

#����� ������ "������"
my $Button = $mw -> Frame();

#������ "������"
my $Import_button = $Button -> Button( -highlightthickness => 3, -font => $INI{data_font}, -state => 'disabled',
   -command => sub{DecodeSet($set_data)}, -text => decode('koi8r',"������"));

#2.4.	������� ����������� � ���������� ����������� "�������" � "�������������". 
   #������������ ����������� ����� ����������� "�������" � "�������������" ������ 
   #�������� ���������� target � target = "S" (�������) �� target = "Q" (�������������).
#2.4.1.	�� ��������� ��������������� �������� ���������� target = "S", 
   #��� ������������� ��������� ����������� "�������".
#2.4.2.	��� ��������� ��������� ����������� ������ ��� ���������� ������� MainStandSets.
my  $Static = $Radiobutton -> Radiobutton(-text => decode ('koi8r', "�������"), -font => $INI{bi_font},  
   -value => "S", -variable => \$target, -command => \&MainStandSets);
my  $Quazi = $Radiobutton -> Radiobutton(-text => decode('koi8r',"�������������"), -font => $INI{bi_font},  
   -value => "Q", -variable => \$target, -command => (\&MainStandSets));
$Static -> grid (-row => 1, -columnspan => 10, -column => 1, -sticky => 'w');
$Quazi -> grid (-row => 2, -column => 1, -sticky => 'w');
$Import_button -> grid (-row => 1, -columnspan => 30, -column => 5);
$Radiobutton ->pack(-in => $standwin, -side => "bottom", -fill => 'x', -padx => 10, -anchor => 'w');
$Button->pack(-in => $setwin, -after => $setdata, -side => "bottom", -fill => 'both', -pady => 5);

#��������� ������
my $status_str = $mw->Text(-width => 40, -height => 10, -state => 'disabled');
$status_str->pack(-side => 'bottom',-after => $setwin, -padx => 10, -pady => 10);
 
#MainStandSets
#���������� -- ��������/���������� �������� ��������� "�����" � "����� ������" 
#������������ ���� "������ ������� ������".
sub MainStandSets {
my @Stand_list; #������ ����������� �������, ������������� ����� ������������ ����� � ������� ����������� ������� 
my $stand_rows = 12; #���������� ����� �������� �����
my $sets_rows = 12; #���������� ����� �������� ����� ������
my $Plates = {}; #��� � ����������� �������� �������� ����� ������
my $VirtualStandList->[0][0] = "�����"; #������ ����������� ������� ������� ������������ �����, �� ����������� �������� ������������ ������
my $previous_stand = 0; #������ ����������� ���������� ���������� ������   

#����������� ���� ��������� ����������� ���������, � ����������� ������������� 
$Stand->destroy; 
$setwin->destroy; 
$standwin->destroy;
$status_str->destroy;
$Import_button->destroy;
$Radiobutton->destroy;
$current_user = $ENV{USER};
   
#3.1.1.	��������� � �� cmk � �������� �� ������ ���������� ���� �������, ���� 
#user.parent ������� ��������� � ����� user.parent �������� ������������ ������. 
#���������� ������ ����������� ������� ����������� � ���������� VirtualStandsList. 
#��� �������� ������������ ������ � ������ �� ���������.  �������� ���� user_parent 
#��������� � ���������� current_parent
my $dbh = DBI->connect_cached("DBI:mysql:cmk:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
   $current_parent = $dbh->selectall_arrayref(qq(SELECT parent 
      FROM user WHERE
      user.name = "$current_user"));
   $VirtualStandList = $dbh->selectall_arrayref(qq(SELECT name 
      FROM user WHERE
      user.parent = "$current_parent->[0][0]" AND
      user.name != "$current_user"));

#3.1.2.	�������� ������ ����������� �������, �� ������ ���� �� ������ ������� ������� VirtualStandsList.
#��������� ���� �������� ����� ����������� �������, ������������ � ������� VirtualStandsList. 
#������ ��� �������� ���� ���������� ���. ���� ������������� � �������� "�����".
$standwin = $mw->Frame(@Tl_att); $standwin->Label(-text => decode('koi8r',"�������� ����� ������:")); 
$standwin->pack(-anchor => 'center', -expand => 0, -fill => 'both',-padx=>15, -pady=>20,  -side => 'left');
my  $Stands->{'-1,0'} = '�����: ';
for my $i (0...$#{$VirtualStandList}) {
   $Stands->{"$i,0"} = $VirtualStandList->[$i][0];}
my $key;
foreach $key (keys %$Stands) { $Stands->{$key} = decode('koi8r', $Stands->{$key}) }
if ($stand_rows < $#{$VirtualStandList}) {$stand_rows = $#{$VirtualStandList};}
$Stand = $standwin->Scrolled('TableMatrix', -scrollbars => 'osoe', -rows => ($stand_rows+2), -cols => 1,
     -variable => $Stands, -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, -state => 'disabled',
     -selectmode => 'single', -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both',-padx=>15, -pady => 5, -selecttitles => 1);
$Stand->tagConfigure('NAME', -anchor => 'w');
$Stand->tagConfigure('title', -relief => 'raised');
$Stand->tagCol('NAME', 0);
$Stand->colWidth(0 => 15);
$Stand->pack(-expand => 0, -fill => 'x');
$Stand->bind('<Motion>', sub {
   my $w = shift; my $Ev = $w->XEvent; 
   my $r = $w->index('@'.$Ev->x.','.$Ev->y); ($r, my $c) = split /\,/,$r;
  } );
$Stand->bind('<1>', sub {
   my $w = shift; my $Ev = $w->XEvent;
   my $r = $w->index('@'.$Ev->x.','.$Ev->y); ($r,my $c) = split /\,/,$r;
   if ($r >= 0) { # ����� ������
      $status_str->delete("1.0","2.0");
      $user = $VirtualStandList->[$r][0];
      if (defined $user) {
         GetSets($user);
         $w->selectionClear('all');
         $Stand->tagRow('Previous', $previous_stand);
         $Stand->tagRow('Select', $r);
         $Stand->tagConfigure('Select', -bg => 'gray');
         $Stand->tagConfigure('Previous', -bg => 'white');
         $previous_stand = $r;}
      $Import_button->configure(-state => 'disabled'); }
});

#�������� ������� �������� "����� �����"
$Plates->{'-1,0'} = '������������ ������'; $Plates->{'-1,1'} = '��� ������'; $Plates->{'-1,2'} = '���� ��������';
foreach $key (keys %$Plates) { $Plates->{$key} = decode('koi8r', $Plates->{$key}) }
$setwin = $mw->Frame(@Tl_att); $setwin->Label(-text => decode('koi8r', "�������� ����� ������:")); 
$setwin->pack(-anchor => 'center', -expand=>0, -padx => 25, -pady => 20, -fill => 'both', -side => 'top');
if ($sets_rows<$#{$users_sets}) {$sets_rows = $#{$users_sets};}
$setdata = $setwin->Scrolled('TableMatrix', -scrollbars => 'osoe', -rows => ($sets_rows+2), -cols => 3, 
   -variable => $Plates, -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, -state => 'disabled',
   -selectmode => 'single', -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both', -padx => 15, -pady => 5, -selecttitles => 1);
$setdata->tagConfigure('NAME', -anchor => 'w');
$setdata->tagConfigure('title', -relief => 'raised');
$setdata->tagCol('NAME', 0);
$setdata->colWidth(0 => 25, 1 => 10, 2 => 13);
$setdata->pack(-expand => 0, -fill => 'x');

#��������� �������� ��������� :"�������/�������������", ������ "������", ��������� ������
$status_str = $mw->Text(-width => 80,  -height => 1, -bg => 'white', -state => 'disabled', 
   -highlightcolor => 'green', -pady => 5, -padx => 5, -font => $INI{err_font});
$status_str->pack(-side => 'bottom', -fill => 'x', -before => $standwin, -padx => 10, -pady => 10);
$Radiobutton = $mw -> Frame();
my $Button = $mw -> Frame();
$Import_button = $Button -> Button(-highlightthickness => 3, -font => $INI{data_font}, 
   -state => 'disabled', -command => sub{DecodeSet($set_data)}, -text => decode('koi8r',"������"));
$Static = $Radiobutton -> Radiobutton(-text => decode ('koi8r', "�������"), -font => $INI{bi_font},
   -value => "S", -variable => \$target, -command => \&MainStandSets);
$Quazi = $Radiobutton -> Radiobutton(-text => decode('koi8r',"�������������"), -font => $INI{bi_font},
   -value => "Q", -variable => \$target, -command => (\&MainStandSets));
$Static -> grid (-row => 1,-columnspan => 10, -column => 1, -sticky => 'w');
$Quazi -> grid (-row => 2, -column => 1, -sticky => 'w');
$Import_button -> grid (-row => 1, -columnspan => 30, -column => 5);
$Radiobutton -> pack(-in => $standwin, -side => "bottom", -fill => 'x', -padx => 10, -anchor => 'w');
$Button->pack(-in => $setwin, -after => $setdata, -side => "bottom", -fill => 'both', -pady => 5);
} #����� MainStandSets

#GetSets
#����������: ��������� ������ ������� ������ ���������� ���������� ������������ ������ user.
sub GetSets {
$Sets = {}; #��� � ������� �������� ����� ������

#3.2.1.   ����������� �������� ����� id, user, born_time, comment � data ������� sets ���� ������ ���������� ���������� 
#������������ ������ user, � ������� �������� ���� target ��������� �� ��������� ���������� target, ������������� ��������� 
#�������/�������������. ���������� ������ ����������� � ���������� Sets.
my $dbh = DBI->connect_cached("DBI:mysql:$user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
my $sql = qq(SELECT id,user,born_time,comment, data FROM sets WHERE target="$target");
$users_sets = $dbh->selectall_arrayref(qq($sql $sql_var)) || die $DBI::errstr;
$Sets->{'-1,0'} = '������������ ������'; $Sets->{'-1,1'} = '��� ������'; $Sets->{'-1,2'} = '���� ��������';
my ($s,$t); for my $i (0...$#{$users_sets}) {
   $Sets->{"$i,0"} = $users_sets->[$i][3]; $Sets->{"$i,1"} = $users_sets->[$i][1]; $s = $users_sets->[$i][2];
   $t = substr($s,-4,2).':'.substr($s,-2,2).' '.substr($s,-6,2).'-'.substr($s,-8,2).'-'.substr($s,-10,2);
   $Sets->{"$i,2"} = $t } #����� for
foreach my $key (keys %$Sets) { $Sets->{$key} = decode('koi8r',$Sets->{$key}) }

#���� � ��������� ���������� ����������� ������ �������������� ������ ������ (���������� Sets �� �����), ��:
#3.2.2.1.   ����������� ������� DisplaySets,
#3.2.2.2.   ������������� ������ "�������������"
if ($#{$users_sets}!=-1) {
   DisplaySets();}

#���� ���������� Sets ��������� �����, ��:
#3.2.3.1.   ���� �������� "����� ������" ���������.
#3.2.3.2.   ��������� ������ � ������ "�������������"
else { 
$Import_button->configure(-state => 'disabled');}
DisplaySets();} #����� GetSets

#DisplaySets
#���������� -- ����������� ����������� � ���������� Sets ������� ������ � �������� 
#"����� ������" ���������� ��������� "�������".
sub DisplaySets {
my $sets_rows = 12; #���������� ������������ ������������� ����� �������� "����� ������"
my $prev_row = 10; #������ ���������� ��������� ���������� ������
my $sql = qq(SELECT id,user,born_time,comment, data FROM sets WHERE target="$target");

#������� ������� "����� ������"
$setdata->destroy;
if ($sets_rows < $#{$users_sets}) {$sets_rows = $#{$users_sets};}

#������� � ��������� ������� "����� ������", ��� ������ ������ ���������� ����� ������ ������������� ������ "�������������"
$setdata = $setwin->Scrolled('TableMatrix',-scrollbars => 'osoe', -rows => ($sets_rows+2), -cols => 3,
   -variable => $Sets, -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, -state => 'disabled',
   -selectmode => 'single', -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both', -padx => 12, -pady => 5, -selecttitles => 1);
$setdata->tagConfigure('NAME', -anchor => 'w');
$setdata->tagConfigure('title',-relief => 'raised');
$setdata->tagCol('NAME', 0);
$setdata->colWidth(0 => 25, 1 => 10, 2 => 14);
$setdata->pack(-expand => 1, -fill => 'x');
$setdata->bind('<Motion>', sub {
   my $w = shift; my $Ev = $w->XEvent; 
   my $r = $w->index('@'.$Ev->x.','.$Ev->y); ($r,my $c) = split /\,/,$r;
 } );
$setdata->bind('<1>', sub {
   my $w = shift; my $Ev = $w->XEvent; 
   my $r = $w->index('@'.$Ev->x.','.$Ev->y); ($r,my $c) = split /\,/,$r;
   if ($r >= 0) { # ���� ������ �������
      $set_data = $users_sets->[$r][4];
      $set_comment = $users_sets->[$r][3];
      my $koi8rname = $set_comment;
      if (defined $koi8rname) {
         $Import_button->configure(-state=>'active');
         $born_time = $users_sets->[$r][2];  
          $w->selectionClear("$prev_row,0", "$prev_row,2");
          $w->selectionSet("$r,0", "$r,2");
          $prev_row = $r; Tk->break }
      else {$Import_button->configure(-state => 'disabled');}  } 
      else { # ����� ����������
         if ($c==0) { # ������������
            if ($cmnt==1) { $sql_var='ORDER BY comment ASC,born_time DESC'; $cmnt=0 }
            else { $sql_var='ORDER BY comment DESC,born_time DESC'; $cmnt=1 }
                    &GetSets($sql_var) }
         elsif ($c==1) { # user
            if ($usr==1) { $sql_var='ORDER BY user ASC,born_time DESC'; $usr=0 }
            else { $sql_var='ORDER BY user DESC,born_time DESC'; $usr=1 }
                    &GetSets($sql_var) }
         elsif ($c==2) { # born_time
            if ($dt==1) { $sql_var='ORDER BY born_time DESC,user ASC,comment ASC'; $dt=0 }
            else { $sql_var='ORDER BY born_time ASC,user ASC,comment ASC'; $dt=1 }
                    &GetSets($sql_var) } } })
} #����� DisplaySets

#DecodeSet
#���������� - ���������� �������� ������� ������, ������� ����������, 
#id_parm � �������� ����������.
#����� - 4 �������, ��������������� ����������� ���������� ���������� ���������� ������ ������:
#my @UserSets_id_system; # - ������ ������� ������ (������ ������ ����� �����������)
#my @UserSetsComplNum; # - ������ ������� ���������� ������
#my @UserSets_id_parm; # - ������ �������� id_parm ����������
#my @UserSetsData; # - ������ �������� �����������;
sub DecodeSet {
my @UserSets = split /\n/ , $_[0];
@UserSets_id_system = 0;
@UserSetsComplNum = 0;
@UserSets_id_parm = 0;
@UserSetsData = 0;
my $c = 0; #������� ����������
my $k = 0; #������� ���������� ������
my $key; #����� ���� sets.data �� ������������ �������� ���������
my $Data; #�������� ���������
my %seenUser;
foreach (@UserSets) { 
#��� �������
   if ($target eq "S") {
      chomp; ($key,$Data) = split /:/; $key=~/(....)(.+)/m; $key=$1.($2+0);
      #print " Data - $Data  ";
      $Data = hex($Data);
      $UserSets_id_system[$c] = substr($key,0,3);
      $UserSetsComplNum[$c] = substr($key,3,1);
      $UserSets_id_parm[$c] = substr($key,4,4);
      $UserSetsData[$c] = $Data;
      #print "Id - $UserSets_id_system[$c], Compl - $UserSetsComplNum[$c], Parm - $UserSets_id_parm[$c]\n";
      $c++;}
#��� �������������
   elsif ($target eq "Q") {
      chomp; ($key,$Data) = split /:/; $key=~/(....)(.+)/m; $key=$1.($2+0);
      $UserSets_id_system[$c] = substr($key,0,3);
      $UserSetsComplNum[$c] = substr($key,3,1);
      $UserSets_id_parm[$c] = substr($key,4,4);
      $UserSetsData[$c] = $Data;
      $c++;}}
#��������� ���������� id_system 
$#User_id_system=-1;
foreach my $value (@UserSets_id_system) {
  if (! $seenUser{$value}) {
      push @User_id_system, $value;
      $seenUser{$value} = 1;}}
CheckSysCompl();
}#����� DecodeSet 

#CheckSysCompl
#����������:
#1) ����������� ������� � ������� ����������� ������ ������� 
   #�����������������, �������������� � ��������� ���������� ������ ������;
#2) ����������� � �������������� ����������� ���� ������ ������� � 
   #���� ������, �������������� � ������ ������, �� ������������� � ������� ����������� ������;
#3) ����������� � �������������� ����������� ���� ������ ������, 
   #���������� ���������� � ������� � ������� ����������� ������ ���������� �� 
   #�������� � ������, �� �������� �������������� ������.
#������� ���������:
#User_id_system[*] - ������ ������� ������, �������������� � ������ ������, ��������� ����������
#current_user - ��� �������� ������������ ������.
#������� ������ ��: system - ������� ���� ������, ���������� �������� ���� ������ 
#��� ���������� ���������� ������ ������.
#������� �����:
#Pxx000@user - ����-��������� ������������ ���������� ���������� ������������ ������ user
#Pxx000@current_user - ����-��������� ������������ �������� ������������ ������.
#�����:
#@UserCompl - ���������� ���������� ������, �������������� � ������ ������, ��������� ����������
#@MissingSysNum - ������ ������� ������, �������������� � ������ ������, 
   #�� ������������� � ������� ����������� ������.
#@MissingSysName - ������ ���� ������, �������������� � ������ ������, �� ������������� 
   #� ������� ����������� ������. � �������������� ���� ��������� ��������� ������ ����� ������.
#@MismatchingComplNum - ������ ������� ������, ���������� ���������� � ������� ������ 
   #��� � ������, �� �������� �������������� ������.
#@MismatchingComplDiff - ������� � ���������� ���������� ����� �������� � ������� ����������� 
   #������ � � ����������� ������, �� �������� �������������� ������.
#@MismatchingComplName - ������ ���� ������, ���������� ���������� � ������� ������ ��� � ������, 
   #�� �������� �������������� ������. � �������������� ���� ��������� ��������� ������ ����� 
   #������ � ������� � ���������� ���������� ����� ��������� ���������� � ������� ����������� �������.
sub CheckSysCompl {
my @UserCompl; 
my @MissingSysNum; 
my @MissingSysName;
my @MismatchingComplNum; 
my @MismatchingComplDiff; 
my @MismatchingComplName;
my $FILE1; #����������� ����� ������������ ������� ����� -> ��������� ���������� ����������� �����
my $FILE2; #����������� ����� ������������ ������� ����� -> ������� ����������� �����
my @file1; #���������� ����� 1
my @file2; #���������� ����� 2
my @Base_id_systemF1; #�������� id_system ������� � ������� ������ � ����� 1
my @Base_id_systemF2; #�������� id_system ������� � ������� ������ � ����� 2
my @User_id_systemF1; #�������� id_system ������� � ����������� ������, ��������� ����������, �� ����� 1
my @Current_id_systemF2; #�������� id_system � ������� ����������� ������, �� ����� 2
my $MissingSys = {}; #���, ���������� ����� �� ����������� � ������� ����������� ����� ������
my $MismatchingSys = {}; #���, ���������� �����, � ����� ���������� ���������� ������, 
 #���������� ���������� ������� ���������� �� ���������� ���������� � ����������� ������� 
 #� ������� ����������� ������ 
my $missingsysfr; #����� ��� ����������� ������ ������, �� ����������� � ������� ����������� �����
my $missingsyssc; #������� ������ ������������ ����� - ������ ������ �� ����������� � ������� ����������� ����� 
my $missing_rows = 4; #���������� ����� �������� ������ ������������� ������
my $mismatchingsysfr; #����� ��� ����������� ������ ������, ���������� ���������� ������� ���������� 
 #�� ���������� ���������� � ����������� ������� 
 #� ������� ����������� ������ 
my $mismatchingsyssc; #������� - ������ ������ � ����������������� ����������� ����������
my $mismatching_rows = 5; #���������� ����� �������� ������ ������ � ����������������� ����������� ����������
my $count1 = 0; #������� id_system ������ � ������� ������ �� ����� 1
my $count2 = 0; #������� id_system ������ � ������� ������
my $countM = 0; #������� id_system ������������� ������
my $countMismatch = 0; #���������� ������, ���������� ���������� ������� ���������� �� 
 #���������� ���������� � ����������� ������� � ������� ����������� ������ 
my $Not_I_counter = 0; #������� ���������� ������, ������������� � ������� ������
my $Not_I_Num_Counter = 0;
my @Not_Inherited_Num;
my %seen;
my %seen2;
my @CurrentCompl; #���������� ���������� ��������������� ������ �������� ������������ ������
my $Continue_B; #������ "����������" 
my $Cancel_B; #������ "������"
my @Mismatching_user; #���������� ���������� ������ � ��������� ���������� ����������� ������, 
 #��� ������ ���������� ���������� ������� ���������� �� ����������� ������ � ������� ����������� ������ 
my @Mismatching_current; #���������� ���������� ������ � ������� ����������� ������, ��� ������ ����� ���������� 
 #������� ���������� �� ����������� ������ � ��������� ���������� ����������� ������

#3.5.1.   ����������� � �� ������������ ������ user. 
my $dbh = DBI->connect_cached("DBI:mysql:$user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;

#3.5.2.   � ����� �� User_id_system[i], ����������� � �� user �������� ���� 
 #system.n_s_s (���������� ���������� ������), ��� ������� ��� system.id_system=User_id_system[i]. 
 #���������� �������� ��������� � UserCompl[i].
###for my $i(0..$#User_id_system) {
###$UserCompl[$i] = $dbh->selectall_arrayref(qq(SELECT system.n_s_s FROM system WHERE system.id_system="$User_id_system[$i]" ));
### }

#3.5.4.   ��������� ����-��������� ������������ Pxx000@user (c������ ����������� ����� FILE1).

#3.5.4.1.   ���� ���� �����������, ����� ������ � ��������� 
#    #������ : "����������� ����-��������� ������������ Pxx000@user".

if (not defined(open ($FILE1, "/mnt/Data/inheritance/P$current_parent->[0][0]\@$user"))){
   my $NoFile = decode ('koi8r', "����������� ����-��������� ������������ P$current_parent->[0][0]\@$user");
   Insert_status_str($NoFile);}

#3.5.4.2.   ���� ���� ��� ������, �� � ����� �� UserSets_id_system[i] ���� � �����, 
   #����� ������ ������������ ������ user, ������ �������. ����� ������������ � 
   #������ ����� ����� (� ������ �������).
else {
   @file1 = <$FILE1>;
   close($FILE1);
   for my $i(1..$#file1) {
      chomp $file1[$i];
      if ($file1[$i] eq 'parm') {last;}
      ($Base_id_systemF1[$i-1] , $User_id_systemF1[$i-1])=split(/\t/,$file1[$i],2); 
   } #����� for
   @Base_id_system = 0;
   @Current_id_system = 0;
   @MismatchingComplName = 0;
   for (my $i = 0; $i <= $#UserSets_id_system; $i++) {
      if (($i<$#UserSets_id_system)&&($UserSets_id_system[$i]==$UserSets_id_system[$i+1])){next}
      else {
         for my $k(0..$#User_id_systemF1) {
         #3.5.4.3.   ���� ����� ������� � ����� ������, �� ���������� ����� ��������������� 
          #������� �������� ������ � ���������� ��� � ���������� Base_id_system[i]. 
          #����� ������������ � ������ ����� ����� (� ����� �������).
             if ($UserSets_id_system[$i]==$User_id_systemF1[$k]) {
                $Base_id_system[$count1] = $Base_id_systemF1[$k];
                $count1++;
                last; }
             elsif (($k==$#User_id_systemF1)&&($UserSets_id_system[$i]!=$User_id_systemF1[$k])) {
                   $Not_Inherited_Num[$Not_I_Num_Counter] = $UserSets_id_system[$i];
                   $Base_id_system[$count1] = 0;
                   $count1++; 
                   $Not_I_Num_Counter++;
                   next;}
             else {next;} 
         }#����� ���������� for
      }#����� else 
   }#����� for
   foreach my $value (@Not_Inherited_Num) {
      if (! $seen{$value}) {
         #push @unique, $value;
         $MissingSysName[$Not_I_counter] = $dbh->selectall_arrayref(qq(SELECT DISTINCT system.name FROM system WHERE system.id_system="$value" ));
	 $seen{$value} = 1; 
	 $Not_I_counter++;}}

#3.5.5.   ��������� ���� Pxx000@current_user (������� ����������� ����� FILE2).
#3.5.5.1.   ���� ���� �����������, ����� ������ � ��������� ������: 
 #"����������� ����-��������� ������������ Pxx000@current_user".
if (not defined (open ($FILE2, "/mnt/Data/inheritance/P$current_parent->[0][0]\@$current_user"))) {
   my $NoFile="����������� ����-��������� ������������ P$current_parent->[0][0]\@$current_user";
   Insert_status_str($NoFile);  }
else {   
   @file2 = <$FILE2>;
   close($FILE2);
   for my $i(1..$#file2) {
      chomp $file2[$i] ;
      if ($file2[$i] eq 'parm') {last;}
      ($Base_id_systemF2[$i-1], $Current_id_systemF2[$i-1]) = split(/\t/,$file2[$i],2);
   }#����� for
   
   #3.5.5.2.   ���� ���� ������, �� � ����� �� Base_id_system[i] ���� � �����, 
    #����� ������ �������� ������ xx000, ������ �������. ����� ������������ � 
    #������ ����� ����� (� ����� �������).
   for (my $i = 0; $i <= $#Base_id_system; $i++) {
   for my $k(0..$#Base_id_systemF2) {

       #3.5.5.3.   ���� ����� ������� � ����� ������, �� ���� ����� ��������������� ������� 
        #� ������� ����������� ������ � ���������� ��� � ���������� � Current_id_system[count2]. 
        #����� ������������ � ������ ����� ����� (� ������ �������).
       if ($Base_id_system[$i]!=0) { 
          if ($Base_id_system[$i]==$Base_id_systemF2[$k]) {
               $Current_id_system[$count2] = $Current_id_systemF2[$k];
               $count2++;
               last; }#����� if
               #3.5.5.4.   ���� ����� ������� � ����� �����������, 
                #�� � ���������� Current_id_system[count2] ��������� 0.
            elsif (($k==$#Base_id_systemF2)&&($Base_id_system[$i]!=$Base_id_systemF2[$k])) {
               $Current_id_system[$count2] = 0;
               $count2++;
               #3.5.5.4.1.   ����� ��������������� ������� � ������� ������ 
                #(�������� Base_id_system[i]) ��������� � ���������� MissingSysNum[countM].
               $MissingSysNum[$countM] = $Base_id_system[$i];
               $countM++;} #����� elsif
            
            else {next;}
      }
      if ($Base_id_system[$i]==0) {
          $Current_id_system[$count2] = 0;
          $count2++;
          last;}
      
   }}#����� for 

#3.5.5.4.2.   ��� ������� ������ ������� � MissingSysNum[k], � �� �������� ������ ������� 
 #������������ ����� ������� ����� ������ - system.name, ��� ������� ��� 
 #system.id_system = MissingSysNum[i], ���������� ����� ������ ���������� � MissingSysName[i].
my $rc = $dbh->disconnect;
my @UniqueMissingSys;
$dbh = DBI->connect_cached("DBI:mysql:$current_parent->[0][0]:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
my $MissingNameCounter = 0;
if ($#MissingSysNum!=-1){
   foreach my $value (@MissingSysNum) {
      if (!  $seen2{$value}) {
      push @UniqueMissingSys, $value;
      $seen2{$value} = 1;
      }}
   
   for my $i($Not_I_counter..($#UniqueMissingSys+$Not_I_counter)) {
      $MissingSysName[$i] = $dbh->selectall_arrayref(qq(SELECT system.name FROM system WHERE system.id_system=$UniqueMissingSys[$MissingNameCounter]));
      $MissingNameCounter++;
    }#����� for
}#����� if

#3.5.6.   � ����� �� ���������� Current_id_system[i] ����������� � �� �������� ������������ 
 #������ �������� system.n_s_s (����� ����������), ��� �������, ��� system.id_system=Current_id_sytem[i].
 #���������� �������� ��������� � ���������� CurrentCompl[i].
my @UniqueCurrent_id_system;
my %seen3;
foreach my $value (@Current_id_system) {
  if (!  $seen3{$value}) {
       push @UniqueCurrent_id_system, $value;
       $seen3{$value}=1;
}}
$rc = $dbh->disconnect;
$dbh = DBI->connect_cached("DBI:mysql:$current_user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
for my $i(0..$#UniqueCurrent_id_system) {
   
   if ($UniqueCurrent_id_system[$i]!=0) {
      $CurrentCompl[$i] = $dbh->selectall_arrayref(qq(SELECT system.n_s_s FROM system WHERE system.id_system=$UniqueCurrent_id_system[$i] ));
      }#����� if
   else {$CurrentCompl[$i]->[0][0] = 0;}
          }#����� for

#������� ������ �������� id_system �������� ������������ ������ � ������������ �� ���������� 
#id_system  ���������� ���������� ������������ ������. ���� ������� � ������� ����������� ������ �����������, ��������� 0.  
for my $i(0..$#UserSets_id_system) {
      for my $k(0..$#User_id_system) {
         if ($UserSets_id_system[$i]==$User_id_system[$k]) {
            $CurrentSets_id_system[$i] = $Current_id_system[$k];
            last;}#����� if
         elsif (($k==$#User_id_system)&&($UserSets_id_system[$i]!=$User_id_system[$k])) {
            $CurrentSets_id_system[$i] = 0;}
         else {next;}
      }# ����� for
}#����� for

my $uc=0;
my @UniqueUser_id_system;
for my $i(0..$#UniqueCurrent_id_system) {
   for my $k(0..$#CurrentSets_id_system) {
      if ($UniqueCurrent_id_system[$i]==$CurrentSets_id_system[$k]) {
         $UniqueUser_id_system[$uc]=$UserSets_id_system[$k];
         $uc++;
         last;}
      else {next;}
}}
$rc = $dbh->disconnect;
$dbh = DBI->connect_cached("DBI:mysql:$user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
for my $i(0..$#UniqueUser_id_system) {
$UserCompl[$i] = $dbh->selectall_arrayref(qq(SELECT system.n_s_s FROM system WHERE system.id_system="$UniqueUser_id_system[$i]" ));
}

#3.5.6.1.   ���� �������� CurrentCompl[i] (����� ����������) ���������� �� �������� 
 #UserCompl[i], �� ������� ����� ������� � MismatchingComplNum[k], � ������� � ���������� 
 #���������� � MismatchingComplDiff[k].
for my $i(0..$#CurrentCompl) {
   if (($CurrentCompl[$i]->[0][0]!=0)&&($CurrentCompl[$i]->[0][0]!=$UserCompl[$i]->[0][0])) {
      $MismatchingComplNum[$countMismatch] = $UniqueCurrent_id_system[$i];
      $Mismatching_user[$countMismatch] = $UserCompl[$i]->[0][0];
      $Mismatching_current[$countMismatch] = $CurrentCompl[$i]->[0][0];
      $MismatchingComplDiff[$countMismatch] = ($CurrentCompl[$i]->[0][0]-$UserCompl[$i]->[0][0]);
      $countMismatch++;
      } #����� if
}#����� for

#3.5.6.2.   ����� � �� �������� ������������ ������ ������� ����� ���� ������, ������ 
 #������� ���������� � MismatchingComplNum[k] - system.name, ��� ������� ��� 
 #system.id_system = MismatchingComplNum[k], ���������� ����� ������ ���������� � MismatchingComplName[k].
$rc = $dbh->disconnect;
$dbh = DBI->connect_cached("DBI:mysql:$current_user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;

if ($#MismatchingComplNum!=-1) {
   for my $i(0..$#MismatchingComplNum) {
      $MismatchingComplName[$i] = $dbh->selectall_arrayref(qq(SELECT system.name FROM system WHERE system.id_system="$MismatchingComplNum[$i]" ));
   }#����� for
}#����� if

#
#3.5.7.   ���� ���� �� ���������� MissingSysNum ��� MismatchingComplNum �� �����, �� ��������� ���� 
 #� ���������� "������ ������� ������ ������". 
if (($#MissingSysNum!=-1)||($#MismatchingComplNum!=-1)||($#MissingSysName!=-1)) {
   my $base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
   $base->title(decode('koi8r', "������ ������� ������ ������:"));
   $base->protocol('WM_DELETE_WINDOW', sub{ $base->destroy; } );
   if ($#MismatchingComplNum!=-1) { 
      $base->geometry("550x550");}
   else {$base->geometry("540x330");}
   my $Mframe=$base->Frame(@Tl_att);
	 $Mframe->pack(-anchor => 'center', -expand=>0,  -fill => 'none', -side => 'top');

#3.5.7.1.   ���� ���������� MissingSysNum �� �����, �� � ���� "������ ������� ������ ������" ��������� ���������: "� ������� ����������� 
 #������ ����������� ��������� �������:" ����� � ������ ��������� �������� ���� MissingSys(�������� � ���� 
 #��������� ������ � ����� ������������� ������)" .
   if ($#MissingSysName!=-1) {
       $MissingSys->{'-1,0'} = '��� �������: ';
       for my $i (0...$#MissingSysName) {
          $MissingSys->{"$i,0"} = $MissingSysName[$i]->[0][0];}
       foreach my $key (keys %$MissingSys) { $MissingSys->{$key} = decode('koi8r',$MissingSys->{$key}) }
       $Mframe->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 15,
       -pady => 10, -text => decode('koi8r',qq(� ������� ����������� ������ ����������� ��������� �������:)),
       -width => 400)->pack(-anchor => 'center', -pady => 2, -side => 'top');
       ###$missingsysfr = $base->Frame(@Tl_att);
       ###$missingsysfr->pack(-anchor => 'center', -expand=>0, -padx => 25,  -fill => 'both', -side => 'top');
       if ($missing_rows < $#MissingSysName ) {$missing_rows = $#MissingSysName;}
       $missingsyssc = $Mframe->Scrolled( 'TableMatrix', -scrollbars => 'osoe', -rows => ($missing_rows+2), -cols => 1,
       -variable => $MissingSys, -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, -state => 'disabled',
       -selectmode => 'single', -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both',  
       -selecttitles => 1, -anchor => 'center');
       $missingsyssc->tagConfigure('NAME', -anchor => 'center');
       $missingsyssc->tagConfigure('title', -relief => 'raised');
       $missingsyssc->tagCol('NAME', 0);
       $missingsyssc->colWidth(0 => 52);
       $missingsyssc->configure( -height=>6);
       $missingsyssc->pack(-expand => 1, -fill => 'x');
       }#����� if

#3.5.7.3.   ���� ���������� MismatchingComplNum �� �����, �� ��������� ��������� - : 
 #"�������������� ���������� ���������� � �������: MismatchingComplName[i], � ������ user - $Mismatching_user[$i] 
 #����������; � ������ current_user - $Mismatching_current ����������".
   $MismatchingSys->{'-1,0'}= "���\n�������: "; $MismatchingSys->{'-1,1'} = "� ������\n$user: "; $MismatchingSys->{'-1,2'} = "� ������\n$current_user: ";
   if ($#MismatchingComplNum!=-1) {
      $Mframe->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35,
         -pady => 10, -text => decode('koi8r',qq(�������������� ���������� ���������� � ������� :)),
         -width => 400)->pack(-anchor => 'center', -pady => 2, -side => 'top');
      for my $i (0...$#MismatchingComplNum) {
         $MismatchingSys->{"$i,0"} = $MismatchingComplName[$i]->[0][0];
         $MismatchingSys->{"$i,1"} = $Mismatching_user[$i];
         $MismatchingSys->{"$i,2"} = $Mismatching_current[$i]; 
         }
      foreach my $key (keys %$MismatchingSys) { $MismatchingSys->{$key} = decode('koi8r',$MismatchingSys->{$key}) }
      if ($mismatching_rows < $#MismatchingComplNum) {$mismatching_rows = $#MismatchingComplNum;}
      $mismatchingsyssc = $Mframe->Scrolled('TableMatrix', -scrollbars => 'osoe', -padx => 10, -rows => $mismatching_rows, -cols => 3,
      -variable => $MismatchingSys, -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, -state => 'disabled',
      -selectmode => 'single', -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both',  -selecttitles => 1);
      $mismatchingsyssc->tagConfigure('NAME', -anchor => 'center');
      $mismatchingsyssc->tagConfigure('title', -relief => 'raised' );
      $mismatchingsyssc->tagCol('NAME', 0);
      $mismatchingsyssc->rowHeight(-1 => 2);
      $mismatchingsyssc->colWidth(0 => 29, 1 => 8, 2 => 8);
      $mismatchingsyssc->configure(-width=>5, -height=>5);
      $mismatchingsyssc->pack(-expand => 1, -fill => 'x');}
   
   #3.5.7.4.   ����� �������� ������ ������ ���� �� ���� ������: "����������" ��� "������".

   #3.5.7.5.1.   ������� ������ "����������" �������� ������� CheckSetsName � ������� ���������� 
   #$set_comment (��� ���������� ���������� ������ ������),  � ����� ������������ ������ "���������" � "������".
   $Continue_B = $Mframe->Button(-command => sub{ CheckSetsName($set_comment); $Continue_B->configure(-state => 'disabled'); 
   $Cancel_B->configure(-state => 'disabled'); }, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font},
   -text => decode('koi8r', qq(����������)))->pack(-anchor => 'center', -pady => 25, -padx => 5, -side => 'left');
   
    #3.5.7.5.2.   ������� ������ "������" ��������� ������ �������, � ������������ ������������ � 
    #���� "������ ������� ������".
    $Cancel_B = $Mframe->Button(-command => sub{$base->destroy;}, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
    -text => decode('koi8r',qq(������)))->pack(-anchor => 'e', -expand=>1, -pady => 25, -padx => 3, -side => 'right');
   
    #3.5.8.   ���� ���������� MismatchingComplNum � MissingSysNum ��� �����, �� ����������� ������� 
    #CheckSetsName � ������� ���������� $set_comment (��� ���������� ���������� ������ ������).
   MainLoop;
}#����� if
else {CheckSetsName($set_comment)};
}} #����� else ������������� �������� ������� ������-���������� ������������
}#����� CheckSysCompl

#CheckSetsName
#���������� -- �������� ������� � ������� ����������� ������ ������ ������ � ������, ����������� � 
#������ �������������� ������, � ������������ ��������� ����� ��� ����� ������.

#������� ���������:
#set_comment - ��� �������������� ������ ������
#current_user - ��� �������� ������������ ������
#������� ������ ��:
#sets - ������� ���� ������, ���������� �������� ���� ������� ������ ��� �������� ������������ ������.

#�����:
#set_comment - ����� ��� �������������� ������ ������
sub CheckSetsName {

#3.6.1.   ��������� ������� � �� �������� ������������ ������ ������ ������ � ���������, 
#����������� � ��������� �������������� ������ ������, ������������ ��� ������ ������������ $SSRPuser

my $CheckName; #���������� ��� �������� ������� � �� �������� ������������ ������ ������ ������ � ���������, 
#����������� � ��������� �������������� ������ ������. � ��� ����������� sets.id ������ ������ � ����������� ������, ���� ����� 
#������������� � ������� ����������� ������. ���� ������ � ����������� ������ � ������� ����������� 
#������ �� ����, �� �������� ���������� �������� undef. 

my $Set_id = 0;
$text = decode('koi8r', $set_comment); #���������� ��� ���������� ����� ��� ������� ������ ��� ����� ������
my $dbh = DBI->connect_cached("DBI:mysql:$current_user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
$CheckName = $dbh->selectall_arrayref(qq(SELECT sets.id FROM sets WHERE sets.comment="$set_comment" and target="$target" and sets.user="$SSRPuser"));
if ( $#{$CheckName}!=-1) {

   #3.6.2.   ���� ��� �������, �.�. ���� ���� ���� sets.comment, �������� �������� ��������� 
    #�� ��������� $sets_comment, �� ���������� ���������� ����������� ���� "��������� ����� ������" .
   #���������� ���� "��������� ����� ������" �������� ��������� �������: "� ������� ����������� 
    #������ ��� ���� ����� ������ � ������ $sets_comment.". ���� �������� ������ "��������", "��������� ���" � "������".
  my $base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
  $base->title(decode('koi8r', "��������� ����� ������"));
  $base->protocol('WM_DELETE_WINDOW', sub{ $base->destroy;});
  $base->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35, 
  -pady => 10, -text => decode('koi8r',qq(� ������� ����������� ������ ��� ���� ����� ������ � ������ $set_comment)), 
  -width => 400)->pack(-anchor => 'center', -pady => 10, -side => 'top');
   
   #3.6.2.1.   ��� ������� ������ "��������" ���������� ���������:
   #3.6.2.1.1.   ��������� ���������� ����� ��������� CheckName �������� sets.id, ��� ������� sets.comment = $set_comment � ���������� Set_id.
   #3.6.2.1.2.   ���������� ������� Import � ������� ���������� Set_id.
   #3.6.2.1.3.   ����������� ���������� ���� "��������� ����� ������".
   $base->Button(-command => sub{$base->destroy; $Set_id = $CheckName->[0][0]; Import($Set_id); }, -state => 'normal', -borderwidth => 3, 
   -font => $INI{but_menu_font}, -text => decode('koi8r', qq(��������)))->pack(-anchor => 'w', -pady => 10, -padx => 20, -fill => 'x' ,-side => 'left');

   #3.6.2.2.   ������� ������ "��������� ���" ����������� ���� "��������� ����� ������" ��������� 
   #���������� ���� "��������� ����� ������" � ������� ����������� ���� "���������� ����� ��� �������������� ������ ������:".
   # ��� ���� �������� ���� ��� ����� ����� ������ ������ ������, � ����� ������ "���������" � "������".
   $base->Button(-command => sub{NewName(); $base->destroy; }, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
   -text => decode('koi8r',qq(��������� ���)))->pack(-anchor => 'center', -pady => 10, -padx => 20, -side => 'left');
   
   #���� ����� ������ ����� ������ ������
   sub NewName{ 
      my $newname = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
         $newname->title(decode('koi8r',"������� ��� ������ ������"));
         $newname->protocol('WM_DELETE_WINDOW',sub{ $newname->destroy;});
         $newname->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35, 
         -pady => 5, -text => decode('koi8r',qq(���������� ����� ��� �������������� ������ ������:)), 
         -width => 400)->pack(-anchor => 'center', -pady => 5, -side => 'top');
         my $Newname = $newname->Entry(-justify => 'center', -borderwidth => 1, -textvariable => \$text, -font => $INI{ri_font}, 
         -state => 'normal', -background => 'white', -width => 15)->pack(-side => "top");
         $Newname->bind('<Return>'=> sub {
            
            #���� ������������ �������� ��������� ������ ������, 
             #����� ���������: "������ ��������� ����� ������, �� ����� ����������� ��� ����!"
            unless (length($text)) { ErrMessage('������ ��������� ����� ������, �� ����� ����������� ��� ����!'); return };
            $set_comment = encode('koi8r',$text); #koi8-r
            $newname->destroy; CheckSetsName($set_comment);});
         $newname->Button(-command => sub{
         unless (length($text)) { ErrMessage('������ ��������� ����� ������, �� ����� ����������� ��� ����!'); return };
         $set_comment = encode('koi8r',$text); #koi8-r
         $newname->destroy; CheckSetsName($set_comment); }, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
         -text => decode('koi8r',qq(���������)))->pack(-anchor => 'center', -pady => 15, -padx => 30, -side => 'left');
         
         #3.6.2.2.1.   ����� ����� ���������� ������ ����� ������ ������, ��� ������� ������ 
          #"���������" ���������� ���������:
         #3.6.2.2.1.1.   ��������� ��� ��������� � ���������� set_comment.
         #3.6.2.2.1.2.   ����������� ����������� ���� "���� ����� ������ ������".
         #3.6.2.2.1.3.   ���������� ���������� ������� CheckSetsName � ����� ��������� �������� ��������� set_comment
         #3.6.2.2.2.   ������� ������ "������" ������������ ����  "���� ����� ������ ������" ��������� 
          #������ �������, � ������������ ������������ � ���� "������ ������� ������".
         $newname->Button(-command => sub{$newname->destroy;}, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
         -text => decode('koi8r',qq(������)))->pack(-anchor => 'w', -pady => 15, -padx => 30, -fill => 'x', -side => 'right');
   }#����� NewName
   #3.6.2.3.   ������� ������ "������" � ���������� ���� "��������� ����� ������" ��������� ������ �������, 
    #� �������� ������������ � ���� "������ ������� ������".
   $base->Button(-command => sub{$base->destroy;}, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
   -text => decode('koi8r',qq(������)))->pack(-anchor => 'e', -pady => 10, -padx => 20, -side => 'left');
}#����� if

#3.6.3.   ���� ��� ������ ������ �� �������, �� ���������� ������� ������� ������ ������ Import � Set_id = 0.
else {$Set_id = 0; Import($Set_id);}
MainLoop;
}#����� CheckSetsName

#Import 
#���������� -- ������������ ������ ������ �� ���� �������������� � ������ ��� � �� �������� ������������ ������.
sub Import {
my $Set_Index = $_[0];
Make4mass_for_current_set();

#3.7.1. ����� ������� Make4mass_for_current_set.
#3.7.2. ����� ������� CodeSet.
#3.7.3. ����� ������� InsertSet.
#
#3.8. ������� Make4mass_for_current_set.
#���������� -- ������������ ������ �������� �� ���� �������������� ������ ������, ��� ����������� 
   #�������� �� ��� ������ ������ ������
#
#������� ���������:
#SetsName -��� ������ ������
#Set_id - id ������ ������ � ������� ����������� ������ (0 ��� Old_set_id)
#current_user - ��� �������� ������������ ������
#SSRPuser - ��� �������� ������������ ��������� ���� ����/����.
#xx000 - ��� �������� ������ ������� ������������ �����
#User_id_system[*] - ������ ������� ������, �������������� � ������ ������, ��������� ����������
#Current_id_system[*] - ������ ������� ������ �������� ������������ ������, ��������������� ������� User_id_system[*]
#  
#� �� ����� ������ ����������� � ���� ������, ��� ������� ��������� ������������� 4 �����. � ��������� ����� 
#������ ����������� �������� ���������������� ���������.
#����� ������, ��������� ����������, ����������� ���������� �������� ���������:
#1) UserSets_id_system[*] - ������ ������� ������, �� ������ �������� �� ������ ��������
#2) UserSetsComplNum[*] - ������ ������� ���������� ������, �������������� � ������ ������, ��������� ����������
#3) UserSets_id_parm[*] - ������ �������� id_parm ����������, �������������� � ������ ������, ��������� ����������
#4) UserSetsData[*] - ������ �������� ��������� � ��������� ���������� ������ ������
#
#���������� ����������:
#��� �������� ������ ������� ������������ ����� (������������ ������ ���� ������ �� �������):
#1) Base_id_parm[*] - ������ �������� id_parm ��������������� ����������
#
#��� �������� ������������ ������:
#1)      CurrentSets_id_system[*] - ������ ������� ��������������� ������
#2)      CurrentSets_id_parm[*] - ������ �������� id_parm ��������������� ����������
#3)      CurrentSetsComplNum[*] - ������ ������� ���������� ��������������� ������
#4)      CurrentSetsData[*] - ������ �������� ���������� � ����� ������ ������
sub Make4mass_for_current_set {
#3.8.1.  � ������� CheckSysCompl ���� ����������� ������������ ����� �������� ������ � ��������� ���������� � 
    #������� ����������� ������ �������������� (������� User_id_system[*] � Current_id_system[*]). ��������� ��� 
    #������������, � ����� �� UserSets_id_system[i], ������� � ���������� CurrentSets_id_system[i] ����� ������� 
    #�������� ������������ ������, ���� ������� ������������ � ������������� ������ ������. ���� ������� �����������,
    #� ���������� CurrentSets_id_system[i] ���������� 0.
my @file3; #�������� id_parm ��������� � ��������� ���������� ����������� ������ � ������� ������, 
   #������ �� ����� ������������ ������� ����� -> ��������� ���������� ����������� �����  
my $FILE3; #����������� ����� ������������ ������� ����� -> ��������� ���������� ����������� ����� 
my @file4; #�������� id_parm ��������� � ��������� ���������� ����������� ������ � ������� ������, 
   #������ �� ����� ������������ ������� ����� -> ������� ����������� �����  
my $FILE4; #����������� ����� ������������ ������� ����� -> ������� ����������� �����
my (@Base_id_parmF3, @User_id_parmF3); #�������� id_parm ��������� � ������� ������ � ��������� ���������� ����������� ������ (�� file3)
my (@Base_id_parmF4, @Current_id_parmF4); #�������� id_parm ��������� � ������� ������ � ������� ����������� ������ (�� file4)
my $level; #�������� ��� ����������� � ����� ����� ����� �� ���������. = 1 - ���� ��������� � ����� �� ���������� id_system � 
   #= 2 - ���� ��������� � ����� �� ���������� id_parm

   #������� ������ �������� id_system �������� ������������ ������ � ������������ �� ���������� 
   #id_system  ���������� ���������� ������������ ������. ���� ������� � ������� ����������� ������ �����������, ��������� 0.  
   for my $i(0..$#UserSets_id_system) {
      for my $k(0..$#User_id_system) {
         if ($UserSets_id_system[$i]==$User_id_system[$k]) {
            $CurrentSets_id_system[$i] = $Current_id_system[$k];
            last;}#����� if
         elsif (($k==$#User_id_system)&&($UserSets_id_system[$i]!=$User_id_system[$k])) {
            $CurrentSets_id_system[$i] = 0;}
         else {next;}
      }# ����� for
   }#����� for
                   
   #3.8.2.   ��������� ����-��������� ������������ Pxx000@user (������� ����������� ����� FILE3).
   if (defined(open ($FILE3, "/mnt/Data/inheritance/P$current_parent->[0][0]\@$user"))){
   @file3 = <$FILE3>;
   close($FILE3);
   my $file3counter = 0;
   (@Base_id_parmF3, @User_id_parmF3) = 0;
   my ($p,$c);
   for my $i(0..$#file3) {
      chomp $file3[$i] ;
      if ($file3[$i]=~/\d/) { # ������ ������
          ($p,$c) = split /\t/,$file3[$i];
          if ($level==2) { 
             ($Base_id_parmF3[$file3counter], $User_id_parmF3[$file3counter]) = split(/\t/,$file3[$i],2);
              $file3counter++;
          }#����� if
       }#����� if 
       else { # ������-�����������
             if ($file3[$i] eq 'system') { $level = 1 }
             elsif ($file3[$i] eq 'parm') { $level = 2 }
             elsif ($file3[$i] eq 'compl') { last } 
       }#����� else 
   }}#����� for
   
   #���� ���� ������������ ������������ ������ ��������� �� ������ � ��������� ������: 
    #����������� ����-��������� ������������ Px000@user
   else {
      my $NoFile = "����������� ����-��������� ������������ P$current_parent->[0][0]\@$user";
      Insert_status_str($NoFile);}
      
   my $base = 0; #������� ����� ���������� �������� ������ � file3
   my @BaseSets_id_parm = 0; #�������� id_parm ���������� � ������� ������ 
   
#3.8.2.1.   � ����� �� UserSets_id_parm[i] ���� ����� ���������� ������������ ������ user (User_id_parmF3) id_parm ������� ���������. 
    #����� ������������ �� ������ ����� ����� (� ������ �������).
    #3.8.2.2.   ���� id_parm ��������� � ����� ������, �� ���������� id_parm ���������������� ��������� �������� ������ � 
    #���������� ��� � ���������� BaseSets_id_parm[base]. ����� ������������ �� ������ ����� ����� (� ����� �������).
   for my $i(0..$#UserSets_id_parm) {
      for my $k(0..$#User_id_parmF3) {
         if ($UserSets_id_parm[$i]==$User_id_parmF3[$k]) {
            $BaseSets_id_parm[$base] = $Base_id_parmF3[$k];
            $base++;
            last; }#����� if
         else {next;}
      }#����� for                 
   }#����� for             
   
   #3.8.4.   ��������� ���� Pxx000@current_user (������� ����������� ����� FILE4).
   open ($FILE4, "/mnt/Data/inheritance/P$current_parent->[0][0]\@$current_user");
   @file4 = <$FILE4>;
   close($FILE4);
   my $file4counter = 0;
   (@Base_id_parmF4, @Current_id_parmF4) = 0;
   my $count4 = 0;
   for my $i(0..$#file4) {
      chomp $file4[$i] ;
         if ($file4[$i]=~/\d/) { # ������ ������
            if ($level==2) { 
               ($Base_id_parmF4[$file4counter], $Current_id_parmF4[$file4counter]) = split(/\t/,$file4[$i],2);
               $file4counter++;} #����� if
         }  #����� if 
         else { # ������-�����������
            if ($file4[$i] eq 'system') { $level = 1 }
            elsif ($file4[$i] eq 'parm') { $level = 2 }
            elsif ($file4[$i] eq 'compl') { last } 
         }#����� else 
   }#����� for

   #3.8.4.1.   � ����� �� BaseSets_id_parm[i] ���� ����� ���������� �������� ������ xx000 id_parm ������� ���������. 
      #����� ������������ �� ������ ����� ����� (� ����� �������).
   #3.8.4.2.   ���� id_parm ��������� � ����� ������, �� ���� id_parm ���������������� ��������� � ������� ����������� 
      #������ � ���������� ��� � ���������� � CurrentSets_id_parm[count4].
   #3.8.4.3.   ���� id_parm ��������� � ����� �����������, �� � ���������� CurrentSets_id_parm[count4] ��������� 0.
   for (my $i = 0; $i <= $#BaseSets_id_parm; $i++) {
      for my $k(0..$#Base_id_parmF4) {
         if ($BaseSets_id_parm[$i]==$Base_id_parmF4[$k]) {
            $CurrentSets_id_parm[$count4] = $Current_id_parmF4[$k];
            $count4++;
            last; }#����� if
      elsif (($k==$#Base_id_parmF4)&&($BaseSets_id_parm[$i]!=$Base_id_parmF4[$k])) {
         $CurrentSets_id_parm[$count4] = 0;
         $count4++;
      }#����� elsif
      else {next;}
       }#����� for
   }#����� for
   
   #3.8.6.   ����� � ����� �� i, ��� ���� CurrentSets_id_parm[i] �� ������ 0, �� ��������������� ����������, 
    #��������� �������� ������ ��������� (UserSetsComplNum[i]) � �������� ��������� (UserSetsData[i]) � 
    #CurrentSetsComplNum[i] � CurrentSetsData[i] ��������������.
   @CurrentSetsData = 0;
   @CurrentSetsComplNum = 0;
   for my $i(0..$#CurrentSets_id_parm) {
      if (($CurrentSets_id_parm[$i]!=0)&&(defined($UserSetsComplNum[$i])))   {
         $CurrentSetsComplNum[$i] = $UserSetsComplNum[$i];
         $CurrentSetsData[$i] = $UserSetsData[$i]; 
         }#����� if
	 else  {
            $CurrentSetsComplNum[$i] = 0;
            }#����� else
   }#����� for
   CodeSet();
   
#3.9.   ������� CodeSet
#���������� - ������������ ������ ������ ������ ������ ��� �������� ������������ ������.
#������� ����������:
#4 �������, ����������� ���������� �������������� ������ ������:
#CurrentSets_id_system[*] - ������ ������� ��������������� ������ �������� ������������ ������
#CurrentSets_id_parm[*] - ������ �������� id_parm ��������������� ���������� �������� ������������ ������
#CurrentSetsComplNum[*] - ������ ������� ���������� ��������������� ������ �������� ������������ ������
#CurrentSetsData[*] - ������ �������� ��������� � ����� ������ ������
#�����:
#SetsData -  ������ � ����� ������� ������.
   sub CodeSet {
       #3.9.1.   �� �������� CurrentSets_id_system[*], CurrentSetsComplNum[*], CurrentSets_id_parm[*], CurrentSetsData[*], 
       #��� �������, ��� �������� CurrentSets_id_parm[*] �� ����� 0, ��������� ������ ������ ������ ������ SetsData.
      my $key;
      $data = '';
      for my $i (0..$#CurrentSetsData) {
         if($target eq "S") {
            if ((defined $CurrentSets_id_parm[$i])&&($CurrentSets_id_system[$i]!=0)&&($CurrentSets_id_parm[$i]!=0)&&($CurrentSetsComplNum[$i]!=0)) { 
               $key = Key($CurrentSets_id_system[$i], $CurrentSetsComplNum[$i], $CurrentSets_id_parm[$i]);
               $data.=sprintf("$key:%08X\n",($CurrentSetsData[$i]));}} #����� if
         elsif($target eq "Q") {
            if ((defined $CurrentSets_id_parm[$i])&&($CurrentSets_id_system[$i]!=0)&&($CurrentSets_id_parm[$i]!=0)&&($CurrentSetsComplNum[$i]!=0)) { 
            $key=Key($CurrentSets_id_system[$i],$CurrentSetsComplNum[$i],$CurrentSets_id_parm[$i]);
            $data.=sprintf("$key:$CurrentSetsData[$i]\n");}#����� if 
         }#����� elsif   
       else {next;}
      }#����� for 
   }#����� CodeSet

   sub Key {
      my ($sys,$set,$prm) = @_;
      return (sprintf('%03i',$sys).$set.sprintf('%i',$prm)) }
}#����� Make4mass_for_current_set

InsertSet($Set_Index);

#3.10.   ������� InsertSet.
#���������� - �������� ����� ������ � ������� sets �� �������� ������������ ������.
#
#������� ����������:
#target - �������� ���� sets.target ("S" ��� "Q")
#Set_id - �������� ���� sets.id ������ ������ ������ � ������� ����������� ������
#SetsData - ������ ������ ������ ������
#
#�����: ����� ������ � ������� sets �������� ������������ ������.
sub InsertSet {
my $Set_Index = $_[0];
my $dbh = DBI->connect_cached("DBI:mysql:$current_user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;

#�������� �������� �������� �������
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();

#3.10.1.   ���� �������� ���������� Set_id = 0, �� ��������� ����� ������ �  ������� sets �� �������� ������������ ������:
$born_time = sprintf ("%02d%02d%02d%02d%02d",($year-100), ($mon+1), $mday, $hour, $min) ;
if ($Set_Index==0) {
   #       � ���� sets.born_time ��������� ������� �����
   #       � ���� sets.target ��������� �������� ���������� target
   #       � ���� sets.user ��������� �������� ���������� SSRPuser
   #       � ���� sets.data ��������� ����� ����� ������ SetsData.
   
   if (defined($dbh->do(qq(INSERT INTO sets (id,user,born_time,comment,target,data) VALUES (0,"$SSRPuser","$born_time","$set_comment","$target","$data"))))) {
      my $ScRecord = "������ ������ ������ \"$set_comment\" �� ������ $user ������� ��������!";
      Insert_status_str($ScRecord);} 
   else {
      my $Failed_rec="�� ������� �������� ����� ������ \"$set_comment\" � ������� $current_user.sets";
      Insert_status_str($Failed_rec);}
}#����� if

#3.10.2.   ���� �������� ���������� Set_id != 0, �� ���������� ������ � ������� sets, ��� ������� ����������� ������� sets.id=Set_id:
else { 
   if(defined($dbh->do(qq(UPDATE sets SET user="$SSRPuser", born_time="$born_time", data="$data" WHERE id="$Set_Index" AND target="$target")))) {

   #       � ���� sets.comment ��������� �������� ���������� SetsName
   #       � ���� sets.born_time ��������� ������� �����
   #       � ���� sets.target ��������� �������� ���������� target
   #       � ���� sets.user ��������� �������� ���������� SSRPuser
   #       � sets.data ��������� ����� ����� ������ SetsData.
  
  #3.10.3.   ���� �������� ������ � �� ��������� �������, �� �������� ��������� � ��������� ������: 
  #"������ ������ ������ SetsName ������� ��������!" � �������� ������������ � ���� "������ ������ ������".
   my $ScRecord = "������ ������ ������ \"$set_comment\" �� ������ $user ������� ��������!";
   Insert_status_str($ScRecord);}
   
  #3.10.4.   ���� �������� ������ � �� �� �������, �� ��������� ��������� �� ������ � ��������� ������: 
  #"�� ������� �������� ����� ������ "SetsName" � ������� "current_user".sets".
    else {
      my $Failed_rec = "�� ������� �������� ����� ������ \"$set_comment\" � ������� $current_user.sets";
      Insert_status_str($Failed_rec);}
   }#����� else
}#����� InsertSet
}#����� Import

#������������ ������� � ����� ����� ���������� � ��������� ������ 
sub Insert_status_str {
$status_str->configure(-state=>'normal');
my $text = $_[0];
chomp $text;
$status_str->delete("1.0","2.0");
$text = decode ('koi8r', "$text");
$status_str->insert("1.0", "$text");
$status_str->configure(-state=>'disabled');
 }
MainStandSets();
MainLoop;
#�����

