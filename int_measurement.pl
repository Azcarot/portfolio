#!/usr/bin/perl
# int_measurement.pl

# версия 01.00
# измерение интервала следования кодовых слов


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

my $IS_pause=0.02; # пауза между запросами к ИС (сек)
my $N_parm_count=5; #сколько раз надо прочитать параметр
my $dop_plus=3; #допуск, в пределах которого отклонение измеренного интервала от верхнего предела не считается ошибкой
my $dop_minus=10; #допуск, в пределах которого отклонение измеренного интервала от нижнего предела не считается ошибкой
my $start_recv_count=4; #с какого такта начать принимать интервалы (от нуля)
my $timeout_time=2; #сколько секунд ждать приема не нулевых значений на сокете приема до таймаута
my $substitute_int=1000; #если в БД не указан максимальный интервал, используем это значение

my $brd_color='#00FF00'; # цвет рамки бутона run

my $fltr_flag=0;
my $palete;
my @measurment_time;
my @options;
my (@w_recieved_dev, @w_dev_dev, @w_recieved_in_line, @w_dev_in_line)=();
my $set_columns_flag=0;
my $colonoc_type=0;

my $pause; # и таймер для измерения интервала 
my $send_wtchr;
my $chanel_done=0; #счетчик количества каналов, по которым прочитаны все параметры
my $chanel_measuring_counter=0; #счетчик для определения, по какому каналу выдаем запрос на чтение параметра

chomp(my $dir_name=$ENV{HOME});
$dir_name.='/cmk';
chdir $dir_name;
my $mysql_db=ltok($ENV{HOME});

# обработка ini-файла
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

# переменные инициализации
my $my_host=StationAtt();
my $my_station=substr($my_host,2);
my %mntr; # tied to shared memory hash
my $mysql_usr;
my $pack='';
my (%pack)=();
my (%chan_vme_id)=(); #Хэш, ключами которого являются адреса нулевых ячеек приемников, значениями являются индексы, по котором строятся буферы
my (%sys_parm,%crate_sys, %chan_addres)=(); #hash систем/параметров и крейтов/систем
my (%pack_for_buff)=();#Хэш, ключами которого являются номера пакетов (запросов цикл. чтения), значениями являются строки номер канала;номер параметра
my (%chan_key)=(); #Хэш, ключами которого являются номер системокомплекта (такой же, как идентификатор в массиве sname), значениями являются строки номер канала;номер параметра
my $mntr_pid;
my $shmem;
my $shmsg;
my ($port_vme_to,$port_vme_from,$sin_to,$sin_froim,$rout,$rin);
my @mes;  # for message packing

# переменные контроля времени регистрации
 my ($rcount, $time1, $time2, $cnt, $scnt)=0;

my $log_time=0;
my $log_timeS='00:00:00';
my $RunFlag=0;
my $paused_flag=0;
my @err_cnt=(); #счетчик ошибок чтение из ИС
my $sock_err=my $sock_err_i=0;
my $flashFlag=0; #флаг для мерцания кнопки в процессе чтения
my $time_wtchr; # секундный таймер
my $read1_wtchr;#вотчер для пп проверки наличия слов в линии связи
my $rcv_wtchr; # вотчер приёмного сокета (для проверки наличия слова в линии связи)
my @rcv_i_wtchr; #массив вотчеров приемных сокетов (для измерения интервалов)
my @port_busy_flag; #массив флагов, занят ли порт в данный момент (цикл чтение интервала), или нет
my @chan_measuring_flag; #массив флагов, проводили ли/проводим ли измерения интервалов параметров данного канала
my @missing_parm_flag=0; #массив флагов, индексация по индексам виджетов параметров (при фильтре Все), если флаг==1, параметр отстутствует в линии связи

my $rcv_vis_wtchr; # таймер визуализации данных
my $sui_wtchr;
my $done_firstread=AnyEvent->condvar;#условие (проверяется, завершена ли работа функции Read1)
my $sleep_var=AnyEvent->condvar; #условие выхода из сна в StartReg 
my $stop_st_reg_flag=0;

my $new_t_wtchr;
my @buf_cr; # массив указателей на массивы отношения индексов крейтов
my $max_buf_length; #Длина входного буфера
my (@iaddr, @sin_to, @sin_to_imi, $sin_from, @sin_from_i, @sin_to_i, @S_OUT, $S_IN, $sock_IN, $S_IN_UN, $S_RCV, @S_RCV_I, $S_RCV_SUI, @S_SND, $S_SND_I, $rout, $rin);
my (@crate_for_buff, @S_int, @S_int_cycle, @S_int_stop, @rin_i, @rout_i ,$S_stop , $port_vme_to_i, $port_vme_from_i); #Буферы для непосредственного измерения интервалов
my $prm_read_counter=0; #счетчик считанных параметров
my $send_counter=0; #счетчик отправленных запросов
my %chanel_parm=(); #Хэш, ключами являются номера отправленных запросов, значение - строка  номер канала;номер параметра в этом канала
my %max_int_for_buff;
my %missing_idx_for_chan=();#Хэш, ключами являются номера каналов (индексы виджетов имен систем), значение - число отсутствующих параметров
my %dev_idx_for_chan=();#Хэш, ключами являются номера каналов (индексы виджетов имен систем), значение - число параметров с отклонениями
my %in_line_idx_for_chan=();
my %twin_in_set=();#Хэш наличия твин параметров (был ли уже в наборе параметр с таким же twin), посистемно
my ($fltr_fdat_height, $fltr_fdat_width)=0;
my @interval_for_recv_int=(); #Массив интервалов (по запросам на циклическое чтение, для определения тайм-аута, если на приемный сокет получаем много нулей)

my @total_interval_value; #двухмерный массив считанных значений интервалов @[i][j], где i-индекс канала а j-индекс параметра в канале, хранит ссылку на массив считанных интервалов данного параметра 
my $out_of_limits_prm_count = 0; #количество слов, измеренные интервалы которых вышли за пределы + допуск 
my (@dev_fltr_chan, @dev_fltr_idx, @missing_fltr_chan, @missing_fltr_idx, @in_line_fltr_chan, @in_line_fltr_idx) = (); #(для фильтра)массив индексов каналов и параметров, измеренные интервалы которых вышли за допустимые пределы

my $missing_prm_count = 0; #количество слов, отсутствующих в линии связи
my $in_line_prm_count =0; #количество слов, присутствующих в линии связи
my (@crate_reg, @crate_tot); #Maccивы номеров крейтов для регистрируемых систем(по количеству систем и просто Distinct номера крейтов  
my ( $x0, $x1 ); # прошлое и текущее значения параметра в буфере
my @buf_length; # длины буфера передачи(=приема)

# фрейм управления
my $rmenu; my $bln; my $bckg;
my $b_choice; my $b_step; my $b_run; my $b_columns; #кнопки
 

my (@first_parm_number,@total_parm_count)=(); # с которого и сколько параметров относятся к данному комплекту
my (@chan_addr,@v_type,@NDIG,@FSTBIT,@LSTBIT,@NC,@vme_prm_id,@vme_prm_id_0,@NCb,@NDIGb,@crate_prm,%min_int, %max_int, @utwin)=(); # атрибуты параметров
my (@sname,@pname,@punit,@punitb)=(); # промежуточное хранение (до создания widgets)
my (@id_system,@id_compl)=(); # идентификаторы систем, комплекты



# экранные переменные
my $dMAX=0; # максимальная ширина колонки данных
my $ScrollFlag=1; #Флаг наличия scrollbar
my ($current_row,$current_colon); # текущие строка/колонка
my $base_width='870x'; #ширина главного окна
my ($nr,$nc); # строк, колонок в таблице всего
my $b_filter;
#

# Tk переменные
my (@wgs,@wgc0,@wgf0,@wgf1,@wgf2,@wgf3,@wgc1,@wgc2,@wgc3,@wgc4,@wgw0,@wgw1,@wgw2,@wgw3,@wgw4,@wgn_nm, @wg_db, @wg_rcv, @wg_dev)=(); # widget наименований систем, лев.фреймов, компл., ч-т,  правых фреймов, кнопок единиц изм., иконок коммутации
# my $signvme; # указатель на массив vme_prm_id,crate КВП
# my @signword=(); # значения КВП
my (@sign_state,@sign_idx,@sign_bit)=(); # статус комплекта, индекс его слова КВП в @signword, маска бита в слове КВП 
my (@wgn,@wgm,@wgd,@wgu)=(); # widget наименований, масок, данных и ед.изм. параметров 
my (@w_db_interval, @w_received_interval, @w_deviation_interval)=(); #Виджеты интервалов, полученных из БД, измеренных интервалов, отклонения изм. значения от значения в БД
# атрибуты ячеек таблицы "наименование системы(комплект)"
 my (@sT)=(-background=>"$INI{sc_back}",-borderwidth=>1,-relief=>'flat',-font=>$INI{h_sys_font});
# # атрибуты ячек таблицы "имя, ед.изм. параметров"
 my (@pT)=(-borderwidth=>1,-relief=>'ridge',-font=>$INI{sys_font});
# # атрибуты ячек таблицы "маска, данные параметров"
 my (@dT)=(-borderwidth=>1,-relief=>'sunken',-font=>$INI{data_font});

# уточненные атрибуты
 my (@ssT)=(@sT,-anchor=>'e',-pady=>$INI{spyr}); # система
 my (@scT)=(@sT,-anchor=>'w'); # комплект
 my (@pnT)=(@pT,-anchor=>'w',-padx=>$INI{npx},-pady=>$INI{ppyr}); # имя параметра
 my (@pmT)=(@dT,-anchor=>'center',-width=>2,-padx=>$INI{mpx}); # маска
 my (@pdT)=(@dT,-anchor=>'e',-padx=>$INI{dpx}); # данные
 my (@puT)=(@pT,-anchor=>'w',-width=>7,-padx=>$INI{upx}); # ед.изм.
 my (@Tl_att)=(-borderwidth=>1, -relief=>'flat',  -takefocus=>0); # Toplevel attributes
 my (@Tb_att)=(-borderwidth=>2, -relief=>'flat'); # Table attributes
#


my @crate_tot; #наличие крейта
my $crate_cur; #текущий крейт
my $base; #главное окно
#my $port_vme_to_i;

my $proto;
my $port_vme_to_imi;
my $flashFlag=0; #флаг мерцанаия кнопки старт


my ($row,$ar_field); # указатели массивов чтения DBI
my $log=1; my $log_trs=1;


if ($log or $log_trs) {
  $row='>/mnt/NFS/tmp/FtoDKPerl/log/I'.time.'.log';
  open (Log, "$row") }


#Проверка, загружено ли Ядро ССРП
if ($INI{UnderMonitor}) { # подключить shmem, установить $mysql_usr
  unless (-e '/tmp/ssrp.pid') { NoShare() }
        open (PF,'/tmp/ssrp.pid');
        $shmsg=new IPC::Msg( 0x72746e6d,  0001666 );
  $SIG{USR2} = \&Suicide;
  RestoreShmem() }
else { $mysql_usr=$INI{mysql_usr} }
$SIG{USR1} = \&RefreshWindow;

#Определяем хосты
my $dbh=DBI->connect("DBI:mysql:cmk:$ENV{MYSQLHOST}",'CMKtest',undef) || die $DBI::errstr;
my $is_host=$dbh->selectcol_arrayref(qq(SELECT is_host.ip FROM is_host,host,user
  WHERE user.name="$mysql_db" AND user.parent=host.stand_base
  AND host.id_host=is_host.base_host_id ORDER BY is_host.crate));
unshift(@$is_host,$ENV{VMEHOST}); # полный массив ip-адресов данной ИС
my %host_crate=(); # $host_crate{ip_address}=crate

$dbh = DBI->connect_cached("DBI:mysql:$mysql_db:$ENV{MYSQLHOST}","$mysql_usr",undef) || die $DBI::errstr;
my %cr_hash; # хэш крейтов параметров. Ключ - vme_prm_id, значение - crate.
my $crate=$dbh->selectall_arrayref(qq(SELECT vme_prm_id,crate FROM reg));
foreach my $row (@$crate) { $cr_hash{$row->[0]}=$row->[1] }

my ($row,$ar_field); # указатели массивов чтения DBI
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

# переменные работы с данными
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
 
#Подготовка сокетов для обнуления ОЗУ + для проверки наличия слов в линии связи
sub PrepSockets {
@iaddr=@sin_to=@sin_to_imi=@S_SND=();
socket($S_RCV,PF_INET, SOCK_DGRAM, $proto);
$sin_from = sockaddr_in( $port_vme_from, INADDR_ANY );
bind($S_RCV, $sin_from);
$rin=''; vec($rin, fileno( $S_RCV ), 1) = 1;
#socket($S_SND, PF_INET, SOCK_DGRAM, $proto);
foreach my $crate (0 .. 3) { # для всех крейтов
        $iaddr[$crate]=gethostbyname($is_host->[$crate]); # получить адреc
        $host_crate{inet_ntoa($iaddr[$crate])}=$crate;
        socket($S_SND[$crate], PF_INET, SOCK_DGRAM, $proto);
        $sin_to[$crate] = sockaddr_in( $port_vme_to, $iaddr[$crate] ) } }

#Наполнения буферов для для проверки наличия слов в линии связи
sub Set_S_OUT_S_IN {
   for my $i (0 .. 3) { $buf_cr[$i]=[] }
   #$S_IN=chr(0)x64;
   foreach my $i (0 .. $#vme_prm_id) { # для всех параметров
   $S_OUT[$crate_prm[$i]].=pack 'I', $vme_prm_id[$i]; # занесение в буфер vme_prm_id регистр. параметров
   push @{$buf_cr[$crate_prm[$i]]},$i; # idx общий в массив индексов буфера крейта
   $buf_length[$crate_prm[$i]]=length $S_OUT[$crate_prm[$i]] }
   my $vme_prm_id_plus=$#vme_prm_id+1;
   foreach my $i (0 .. 3) { if ($crate_tot[$i]) { # для всех используемых крейтов
   substr($S_OUT[$i],4,4,(pack 'I',(length $S_OUT[$i]))); # длина буфера с заголовком
   substr($S_OUT[$i],40,4,(pack 'I',($buf_length[$i]-64)>>2))} };
   #for my $i (0..$#w_db_interval) { if ($v_type[$i] == RK) {print "\nRK\n"; $S_IN.=pack 'I',0xFFFFFFFF } else {print "\nNe RK\n"; $S_IN.=pack 'I',0 } } # заполнение вх. буфера
#$max_buf_length=length $S_IN;
} # сколько записей
                                                                        

socket($S_SND_I, PF_INET, SOCK_DGRAM, $proto);

#Ожидание "рестарта" от Ядра, если был рестарт-завершение работы программы
socket($S_RCV_SUI, PF_INET, SOCK_DGRAM, $proto);
my $sin_sui = sockaddr_in( $packID, INADDR_ANY );
bind($S_RCV_SUI, $sin_sui);
my $routs = my $rins = '';
vec($rins, fileno( $S_RCV_SUI ), 1) = 1;
my $sui_wtchr;
$sui_wtchr=AnyEvent->io(fh=>\*$S_RCV_SUI, poll=>"r", cb=>sub{ # активировать чтение из сокета завершения
        my $mes=''; my $max_len=100;
        while ( select( $routs = $rins, undef, undef, 0.005) ) { # дождаться готовности сокета
                recv($S_RCV_SUI,$mes,$max_len,0) } # принять от Ядра
        if ($mes eq 'stop') {
                system("zenity --info --text='Задача регистрации завершена, так как выполнен Рестарт' > /dev/null &");
                Suicide() } } );

$|=1;
MainLoop;


#определяем имя станции
sub StationAtt {
my ($hostname,$name,$aliases,$station);
chop($hostname = `hostname`);
($name,$aliases,undef,undef,undef) = gethostbyname($hostname);
my @al=split / /,$aliases;
unshift @al,$name;
foreach (@al) { if (/^ws\d+$/) { $station=$_ } }
return $station }

#Получаем имя пользователя ядра ССРП
sub RestoreShmem {
my @shmem=<PF>; close(PF);
($mysql_usr, $mntr_pid)=split(/\|/,$shmem[0]);}

#Получем данные из таблицы packs по pack id
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
(@first_parm_number,@total_parm_count)=(); # с которого и сколько параметров относятся к данному комплекту
(@chan_addr,@v_type,@NDIG,@FSTBIT,@LSTBIT,@NC,@vme_prm_id,@vme_prm_id_0,@NCb,@NDIGb,@crate_prm,%min_int, %max_int, @utwin)=(); # атрибуты параметров
(@sname,@pname,@punit,@punitb)=(); # промежуточное хранение (до создания widgets)
(@id_system,@id_compl)=(); # идентификаторы систем, комплекты
my ($name_system,$str_el,$existence_flag); # имя системы, элемент строки комплектов/параметров,флаг наличия комплекта
my ($parm_index,$compl_counter,$compl_parm_counter)=0; # индекс параметров, счетчик комплектов системы, счетчик параметров комплекта
my $dMAX2; # длина для параметра 2 типа (с пробелами)
my $int_ndig; # ширина поля данных (для всех - буквально, для ДК - часть формата)
$dMAX=0; # максимальная ширина колонки данных
%pack=split(/:/,$pack);
my $rkFlag = 0; #флаг наличия в наборе разовых команд
my $sys=$dbh->selectall_arrayref(qq(SELECT id_system,name,freq FROM system ORDER BY v_id));
my $avail=$dbh->selectall_arrayref(qq(SELECT id_system,num_compl,avail FROM compl WHERE sim=0));
my $id_sys; my $freq;
my $chan_counter = 0; #счетчик каналов (системокомплектов)
for my $x (0..$#{$sys}) {
      if (exists $pack{$sys->[$x][0]}) { $name_system=$sys->[$x][1]; $id_sys=$sys->[$x][0]; $freq=$sys->[$x][2]; }
      else { next }
      $compl_counter=0; # оперативный счетчик комплектов
      while (1) { # выделяем комплекты
            ($str_el,$current_row)=split(/,/,$pack{$id_sys},2);
            if ($str_el=~/k/) {
                  $compl_parm_counter=substr($str_el,1,1);
                  if (grep { $_->[0]==$id_sys and $_->[1]==$compl_parm_counter and $_->[2]==1 } @$avail) { # если комплект в наличии

                        push @id_system,$id_sys; push @id_compl,$compl_parm_counter; # данные для коммутаторов
                        $dbh->do(qq(UPDATE cmtr_chnl,cmtr_rgstr,cmtr_mdl,compl,vme_chan SET cmtr_chnl.busy=$packID
                                        WHERE compl.id_system=$id_sys AND compl.num_compl=$compl_parm_counter
                                        AND compl.id_vme_chan=vme_chan.id_vme_chan
                                        AND cmtr_mdl.id_vme_rcv=vme_chan.id_vme_card
                                        AND cmtr_chnl.name+(cmtr_mdl.n_in_pair-1)*16=vme_chan.num_chan
                                        AND cmtr_chnl.id_rgstr=cmtr_rgstr.id_rgstr
                                        AND cmtr_rgstr.id_mdl=cmtr_mdl.id_mdl
                                        AND NOT cmtr_chnl.busy)); # "заняли" коммутаторы, если не заняты ранее
                        if (defined $freq) { push @sname,($name_system.'|к. '.substr($str_el,1,1).'|'.$freq) } # и заносим в массив
                        else { push @sname,($name_system.'|к. '.substr($str_el,1,1)) }
                        $compl_counter++ } # инкремент счетчика
                  $pack{$id_sys}=$current_row } # усечение строки
            else { last } } # выделяем комплекты
  # выделяем параметры
	$row=$dbh->selectall_arrayref(qq(SELECT id_parm,chan_addr,name,units,v_type,NDIG,FSTBIT,LSTBIT,NC,vme_prm_id, minint, maxint, utwin FROM parm WHERE id_system=$id_sys and (target&1) ORDER BY v_id ASC)) || die $DBI::errstr;
	my $crate=$dbh->selectall_arrayref(qq(SELECT DISTINCT crate FROM reg WHERE id_system=$id_sys));
	for my $compl_num (1..$compl_counter) { # для всех комплектов этой системы
			my @vme_prm_id_for_hash;
			%twin_in_set=();
    			push @first_parm_number, $parm_index; # этот комплект начинается с j-го параметра
    			$compl_parm_counter=0; # параметров в данном комплекте
                	$sname[$#sname-$compl_counter+$compl_num]=~/к. (\d)/; $str_el=$1; # номер комплекта
    			my @chan_addr_array=();	
			my $parm_in_set_counter=0;		
					for my $i2 ( 0 .. $#{$row} )  { # для всех параметров данного комплекта
					if ($row->[$i2][4]!=RK) {
						$utwin[$i2] = $dbh->selectrow_array(qq(SELECT twin FROM reg WHERE id_parm=$row->[$i2][0]));
						if (($utwin[$i2] eq "")||(!$twin_in_set{$utwin[$i2]})) {#если в комплекте не было параметров с таким твин или твина нет
						$twin_in_set{$utwin[$i2]}++; #отмечаем наличие твина
      						if ( $pack{$id_sys}=~/(^$row->[$i2][0]$|^$row->[$i2][0],|,$row->[$i2][0],|,$row->[$i2][0]$)/ ) { # если этот параметр входит в набор
						if ( $row->[$i2][1] ) { $pname[$parm_index]=$row->[$i2][1].' '.$row->[$i2][2] }
        					else { $pname[$parm_index]=$row->[$i2][2] }
        					$punit[$parm_index]=$row->[$i2][3];
        					$v_type[$parm_index]=$row->[$i2][4];
								  #$utwin[$parm_in_set_counter] = $dbh->selectrow_array(qq(SELECT twin FROM reg WHERE id_parm=$row->[$i2][0]));
								  #if ((defined $utwin[$parm_in_set_counter-1])&&($utwin[$parm_in_set_counter]==$utwin[$parm_in_set_counter-1])){
									 #print "parm_index $parm_in_set_counter twin $utwin[$parm_in_set_counter]";next;}
									if ($v_type[$parm_index]<RK) { $chan_addr[$parm_index]=revbit(oct($row->[$i2][1])); } # ПБК
							#print "\ni2 $i2 parm_index $parm_index comp_parm_counter $compl_parm_counter utwin $utwin[$parm_index] $\n";
							$chan_addr_array[$parm_in_set_counter]=$chan_addr[$parm_index];
						$NDIG[$parm_index]=$row->[$i2][5];
        					if ($NDIG[$parm_index] ne '') { $int_ndig=int($NDIG[$parm_index]) }
                                		else { $int_ndig=0 }
        					if ( $int_ndig>$dMAX ) { $dMAX=$int_ndig }
        					if ( $v_type[$parm_index]==DS00 or $v_type[$parm_index]==DS11 ) { # пробелы между тетрадами  
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
						$crate_prm[$parm_index++]=$cr_hash{$vme_prm_id[$parm_index]}; # соотв. номер крейта
						#$sys_parm{$sys_parm_key}						
#print "\nsys_id $sys->[$x][0] pindex $parm_index pname $pname[$parm_index-1] compl_counter $compl_counter crate $crate_prm[($parm_index-1)]\n";

						$parm_in_set_counter++;
						$compl_parm_counter++; # vme_prm_id с учетом номера комплекта, инкремент счетчика п-ров комплекта
					}
}
} # если этот параметр входит в набор и не является разовой командой
    			
else {$rkFlag=1};
                        #push @total_parm_count, $compl_parm_counter; # параметров в этом комплекте
                        #my $sys_parm_key = "$id_sys;$compl_num";
                        #$crate_sys{$sys_parm_key}=$crate->[$x][0];
			
                        #$sys_parm{$sys_parm_key} =@vme_prm_id_for_hash; 	
			} # для всех параметров данного комплекта
  			push @total_parm_count, $compl_parm_counter; # параметров в этом комплекте
  			#print "\nTOTAL @total_parm_count COUNTER $compl_parm_counter\n";
			my $sys_parm_key = "$id_sys;$compl_num";
			$chan_key{$chan_counter}=$sys_parm_key;
			$crate_sys{$sys_parm_key}=$crate->[$x][0];
			$sys_parm{$sys_parm_key}=\@vme_prm_id_for_hash;
			$chan_addres{$sys_parm_key}=\@chan_addr_array; 
			#print "\n\nGetPackData chan_counter $chan_counter chan_addr_array @chan_addr_array key $sys_parm_key hash $chan_addres{$sys_parm_key} sys_parm @vme_prm_id_for_hash\n\n";
			$chan_counter++;
			} # для всех комплектов этой системы
	} # для одной системы
	if ($rkFlag) {my $txt = "Измерение интервала разовых команд не осуществляется!";
                                my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
                                $er_base->title(decode('koi8r',"Внимание:")); $er_base->geometry($INI{StandXY});
                                $er_base->Message(-anchor=>'center', -font=>$INI{err_font}, -foreground=>"$INI{err_forg}", -justify=>'center', -padx=>35, -pady=>10, -text=>decode('koi8r',$txt), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
                                $er_base->bell   }
	if ($dMAX<12) { $dMAX=12 } # минимальная ширина ячейки данных
	foreach my $key (keys %crate_sys) {push @crate_reg , $crate_sys{$key};}
	for my $i (0..3) {$crate_tot[$i]=grep(/$i/,@crate_reg); }
	$S_IN=chr(0)x64;
	my $vv=0;
	foreach (@vme_prm_id) {
	$S_IN.=pack 'I',0}; 
	$max_buf_length=length $S_IN;
}


#Обмен с разделяемой областью памяти
sub PageMonitor {
my $c='';
foreach (@mes) { $c.=$_.'|' }
chop $c;
# записать данные в разделяемую очередь сообщений
$shmsg->snd(1, $c) or warn "choice to shmsg failed...\n";
# # сигнализируем монитору
kill 'USR1', $mntr_pid;
 }

#Создаем главное окно
sub NewWindow {
$base = MainWindow->new(@Tl_att);
$base->title(decode('koi8r',"Измерение интервалов")); my $test_name='';
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

my $label_out_of_limits = "Вне пределов ";
my $label_missing = ", отсутствуют ";
my $label_prm = " параметров";

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
$options[0]=decode ('koi8r', "Все параметры");
#$options[1]=decode ('koi8r',"С отклонениями");
#$options[2]=decode ('koi8r', "Отсутствующие");
$b_filter=$rmenu->Optionmenu( -relief=>'flat',-highlightthickness=>2,
	-variable=>\$palete,
	-textvariable=>\$palete,
	-options=> [@options],
	-command => sub{my $text=shift; $palete=$text; $text=encode ('koi8r',$text); Fltr($text)} )->grid(-row=>0,-column=>5,-columnspan=>2,-padx=>$INI{bpx});
$bln->attach($b_filter, -msg=>decode('koi8r','Фильтр представления'));

my $b_print=$rmenu->Button( -activebackground=>"$bckg", -image=>'print', -relief=>'flat',
-command=> sub{my $text=encode ('koi8r',$palete); 
my $chan;
my @fltr_option;
$fltr_option[0]= "Все параметры";
$fltr_option[1]="Вне пределов";
$fltr_option[2]="Отсутствующие в линии";
$fltr_option[3]="В наличии в линии";
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
$bln->attach($b_choice, -msg=>decode('koi8r','Редактировать макет'));
#TuneButtons();
$bln->attach($b_run, -msg=>decode('koi8r','Пуск'));
$bln->attach($b_print, -msg=>decode('koi8r','Распечатать'));
$bln->attach($b_columns, -msg=>decode('koi8r','Колонок'));
$base->bind('<F1>'=> \&HelpPage);
$base->protocol('WM_DELETE_WINDOW', \&Suicide);
}

# фрейм данных
sub ShowTable {
my ($s,$n,$j);
$j=0;
(@wgs,@wgc0,@wgf0,@wgf1,@wgf2,@wgf3,@wgc1,@wgc2,@wgn,@wgm,@wgd,@wgu,@wgw0,@wgw1,@wgw2,@wgw3,@wgw4,@wgn_nm,@wg_db,@wg_rcv,@wg_dev,@w_db_interval, @w_received_interval, @w_deviation_interval)=(); my $chan_num;

foreach (@sname) { # по количеству комплектов
  
	($n,$s,my $fr)=split(/\|/,$_); # наименование, комплект, частота
	$wgs[$j]=$fdat->Label(@ssT, -text=>decode('koi8r',$n));
        $wgc0[$j]=$fdat->Frame(-borderwidth=>0,-relief=>"flat",-bg=>"$INI{sc_back}");
        $wgc1[$j]=$wgc0[$j]->Label(@scT, -text=>decode('koi8r',$s))->pack(-side=>'left');
        #$wgc3[$j]=$wgc0[$j]->Label(@scT, -text=>decode('koi8r',"Привет"))->pack(-side=>'right');
	if (defined $fr) { $wgc2[$j]=$wgc0[$j]->Label(@scT, -text=>decode('koi8r',"F$fr"))->pack(-side=>'right') }
  $wgw0[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
  $wgf0[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
  #$chan_num=ShowChanel($j); if (defined $chan_num) {
  #  $wgw2[$j]=$wgw0[$j]->Button(-highlightthickness=>0,-bg=>"$INI{sc_back}",-relief=>'flat',-command=>[\&Cmttn,Ev($j)])->pack(-side=>'right',-ipadx=>3);
  #  if ($chan_num==0) { $wgw2[$j]->configure(-image=>'losecuK') }
  #  elsif ($chan_num==1) { $wgw2[$j]->configure(-image=>'losecu1') }
  #  elsif ($chan_num==2) { $wgw2[$j]->configure(-image=>'losecu2') }
  #  elsif ($chan_num==3) { $wgw2[$j]->configure(-image=>'losecu3') }
  #  $bln->attach($wgw2[$j], -msg=>decode('koi8r','Коммутация')) }
   $wgw2[$j]=$wgw0[$j]->Label(-bg=>"$INI{sc_back}")->pack(-side=>'right'); 
   $wgw3[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   $wgw4[$j]=$wgw0[$j]->Label(-bg=>"$INI{sc_back}")->pack(-side=>'right');  
   $wgn_nm[$j]=$wgf0[$j]->Label(@pnT, -text=>decode('koi8r',"Наименование"))->pack(-side=>'left');
   $wgf1[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   $wg_db[$j]=$wgf1[$j]->Label(@pnT, -text=>decode('koi8r', "Заданный интервал"), -width=>19)->pack(-side=>'left');
   $wgf2[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   $wg_rcv[$j]=$wgf2[$j]->Label(@pdT, -text=>decode('koi8r', "Измеренное значение"), -width=>19)->pack(-side=>'left');
   $wgf3[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   $wg_dev[$j]=$wgf3[$j]->Label(@pdT, -text=>decode('koi8r', "Отклонение") ,-width=>11)->pack(-side=>'left');
	
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

for my $i0 (0..$#wgs) { # имя системы всегда занимает строку
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
if ( $total_parm_count[$i0] ) { # если не пустая система
    $n=int($total_parm_count[$i0]/$nc)+(($total_parm_count[$i0]%$nc)?1:0); # всего строк данного комплекта
    $s=0; # уже строк данного комплекта 
    $current_colon=0; # уже колонок данного комплекта 
    if ( $INI{GridType} ) { # для порядка колонка-строка
      for my $i1 ( $first_parm_number[$i0]..($first_parm_number[$i0]+$total_parm_count[$i0]-1) ) { # для параметров этого комплекта
	$fdat->put($current_row+$s,$current_colon*5+0,$wgn[$i1]);
	$fdat->put($current_row+$s,$current_colon*5+1,$w_db_interval[$i1]);
	$fdat->put($current_row+$s,$current_colon*5+2,$w_received_interval[$i1]);
	$fdat->put($current_row+$s,$current_colon*5+3,$w_deviation_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+4,$wgu[$i1]);
        $s=(($s==($n-1))?0:$s+1); $current_colon+=($s==0)?1:0;
      } # для параметров этого комплекта
      if ( $total_parm_count[$i0]<$n*$nc ) {# параметров меньше, чем отведено мест
        for my $i3 ( ($current_row+$s)..($current_row+$n-1) ) { # "зашить" неполный комплект
	  $fdat->put($i3,($nc-1)*5+0,$fdat->Label(@pnT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+1,$fdat->Label(@pmT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+2,$fdat->Label(@pdT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+3,$fdat->Label(@puT,-text=>'       '));
        } # "зашить" неполный комплект
      } # параметров меньше, чем отведено мест
      $current_row+=$n;
    } # для порядка колонка-строка
    else { # для порядка строка-колонка
      for my $i1 ( $first_parm_number[$i0]..($first_parm_number[$i0]+$total_parm_count[$i0]-1) ) { # для параметров этого комплекта
        $fdat->put($current_row+$s,$current_colon*5+0,$wgn[$i1]);
	$fdat->put($current_row+$s,$current_colon*5+1,$w_db_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+2,$w_received_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+3,$w_deviation_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+4,$wgu[$i1]);
	$current_colon=(($current_colon==($nc-1))?0:$current_colon+1); $s+=($current_colon==0)?1:0;
      } # для параметров этого комплекта
      $current_row+=$n;
      if ( $total_parm_count[$i0]%$nc ) { #  последняя строка - неполная 
        for my $i3 ( ($total_parm_count[$i0]%$nc)..($nc-1) ) { # "зашить" неполный комплект
          $fdat->put($current_row-1,$i3*5+0,$fdat->Label(@pnT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+1,$fdat->Label(@pmT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+2,$fdat->Label(@pdT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+3,$fdat->Label(@puT,-text=>'       '));
        } # "зашить" неполный комплект
      } #  последняя строка - неполная 
    } # для порядка строка-колонка
  } # если не пустая система
} 
}  # конец визуализации, конец sub

sub Fltr {
my $fltr_mode=$_[0];
my @fltr_option;
$set_columns_flag=0;
$fltr_option[0]= "Все параметры";
$fltr_option[1]="Вне пределов";
$fltr_option[2]="Отсутствующие в линии";
$fltr_option[3]="В наличии в линии";
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
my $kline=$#uniq_chnl+1; # число комплектов
$nr=0; # число параметров
foreach (@fltr_chan) { # для всех счетчиков параметров в комплектах
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
foreach (@uniq_chnl) { # по количеству комплектов
  ($n,$s,my $fr)=split(/\|/,$sname[$uniq_chnl[$j]]); # наименование, комплект, частота
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


for my $i0 (0..$#wgs) { # имя системы всегда занимает строку
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
if ( $total_parm_count[$i0] ) { # если не пустая система
    $n=int($total_parm_count[$i0]/$nc)+(($total_parm_count[$i0]%$nc)?1:0); # всего строк данного комплекта
    $s=0; # уже строк данного комплекта 
    $current_colon=0; # уже колонок данного комплекта 
    if ( $INI{GridType} ) { # для порядка колонка-строка
      for my $i1 ( $first_parm_number[$i0]..($first_parm_number[$i0]+$total_parm_count[$i0]-1) ) { # для параметров этого комплекта
        $fdat->put($current_row+$s,$current_colon*5+0,$wgn[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+1,$w_db_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+2,$w_received_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+3,$w_deviation_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+4,$wgu[$i1]);
        $s=(($s==($n-1))?0:$s+1); $current_colon+=($s==0)?1:0;
      } # для параметров этого комплекта
      if ( $total_parm_count[$i0]<$n*$nc ) {# параметров меньше, чем отведено мест
        for my $i3 ( ($current_row+$s)..($current_row+$n-1) ) { # "зашить" неполный комплект
          $fdat->put($i3,($nc-1)*5+0,$fdat->Label(@pnT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+1,$fdat->Label(@pmT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+2,$fdat->Label(@pdT,-text=>'  '));
          $fdat->put($i3,($nc-1)*5+3,$fdat->Label(@puT,-text=>'       '));
        } # "зашить" неполный комплект
      } # параметров меньше, чем отведено мест
      $current_row+=$n;
    } # для порядка колонка-строка
    else { # для порядка строка-колонка
      for my $i1 ( $first_parm_number[$i0]..($first_parm_number[$i0]+$total_parm_count[$i0]-1) ) { # для параметров этого комплекта
        $fdat->put($current_row+$s,$current_colon*5+0,$wgn[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+1,$w_db_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+2,$w_received_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+3,$w_deviation_interval[$i1]);
        $fdat->put($current_row+$s,$current_colon*5+4,$wgu[$i1]);
        $current_colon=(($current_colon==($nc-1))?0:$current_colon+1); $s+=($current_colon==0)?1:0;
      } # для параметров этого комплекта
      $current_row+=$n;
      if ( $total_parm_count[$i0]%$nc ) { #  последняя строка - неполная 
        for my $i3 ( ($total_parm_count[$i0]%$nc)..($nc-1) ) { # "зашить" неполный комплект
          $fdat->put($current_row-1,$i3*5+0,$fdat->Label(@pnT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+1,$fdat->Label(@pmT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+2,$fdat->Label(@pdT,-text=>'  '));
          $fdat->put($current_row-1,$i3*5+3,$fdat->Label(@puT,-text=>'       '));
        } # "зашить" неполный комплект
      } #  последняя строка - неполная 
    } # для порядка строка-колонка
  } # если не пустая система

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



#Изменить макет
sub ChoiceRevision {
if ( $RunFlag ) { StopReg() } # остановить обмен с VME
$dbh->do(qq(UPDATE packs set state='edit' WHERE id=$packID));
if ($INI{UnderMonitor}) {
  $mes[0]=$packID;
  $mes[1]='edit';
  PageMonitor()}
$dbh->do(qq(UPDATE cmtr_chnl set busy=0 WHERE busy=$packID));
open(STDERR, "|/mnt/NFS/tmp/FtoDKPerl/choice.pl_old I $packID");
}


sub FlashButton {
#Мигание иконки чтения
  $time_wtchr = AnyEvent->timer ( after=>1, interval=>1, cb=>sub { # flash-таймер 
    $log_time++; $log_timeS=TimeS($log_time);
     if ($flashFlag) { $b_run->configure(-bg=>"$INI{flash_back}"); $flashFlag=0 }
     else { $b_run->configure(-bg=>"$bckg"); $flashFlag=1 }
     }       );
}

#Старт измерения интервалов
sub StartReg {

#обнуление значений в виджетах
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

#Блокировка нажатий на кнопки
TuneButtons();
#Мигание кнопки
FlashButton();

#Обнуление ОЗУ
RAMReset();
$RunFlag=1;
#Пауза 5 сек
undef $sleep_var;
undef $done_firstread;
$sleep_var=AnyEvent->condvar;
$new_t_wtchr = AnyEvent->timer(after=>5, cb=> sub{
	$sleep_var->send;});
my $sleep_timer = $sleep_var->recv;
#Проверка наличия слов в линии связи
Read1();
$done_firstread=AnyEvent->condvar;
my $missing_comlete = $done_firstread->recv;
CreateBuffersForInt();
CreateSocketsForInt();
if ($stop_st_reg_flag==1) {
 
	return}
$chanel_done=0;
for my $i(0..$#port_busy_flag) { #начинаем слушать сокеты по всем портам
	RecvInt($i);}
	
#Отправляем запросы по всем каналам
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

#Обнуления ОЗУ (разовое чтение с обнулем без обработки полученных данных)
sub RAMReset {
my $len=length($S_IN);
foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) { substr( $S_OUT[$crate],0,4,pack "I",0x240 ); #$base->bell 
} }
foreach my $crate (0 .. 3) {
        if ($crate_tot[$crate]) {# инициировать чтение из нужных хостов ИС 
	        if (!defined send($S_SND[$crate], $S_OUT[$crate], 0, $sin_to[$crate])) { # выдать в VME, успешно?
         	       $base->bell; if ($log) { print Log "send fail\n------------------\n" } } # нет
                else { # успешно
        	        if ($log_trs) { PrintSock(\$S_OUT[$crate],$crate) } } } }
if ($INI{UnderMonitor}) {
	$mes[0]=$packID;
        $mes[1]=++$rcount;
        PageMonitor() }
}

#Расчет количества строк под системы/параметры для отображения в окне
sub SetTableVars {
my $kline=$#sname+1; # число комплектов
$nr=0; # число параметров
foreach (@total_parm_count) { # для всех счетчиков параметров в комплектах
$nr+=int($_/$nc)+(($_%$nc)?1:0) }
$kline=int($kline*1.318);
$nr+=$kline;
if ( $nr>$INI{rMAXr} ) { $ScrollFlag=1 } else { $ScrollFlag=0 }
@crate_tot=();
for my $i (0 .. 3) { $crate_tot[$i]=grep(/$i/,@crate_prm) } }

#Колонок
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

#Отобразить данные 
sub ShowData {
my $received_text=$_[0];
my $deviation_text=$_[1];
my $idx=$_[2];
$w_received_interval[$idx]->configure(-text=>decode('koi8r', "$received_text"));
$w_deviation_interval[$idx]->configure(-text=>decode('koi8r', "$deviation_text"));
}

#Обновление главного окна, вызывается при редактировании макета
sub RefreshWindow {
print "\nREFRESHED\n";
$base->destroy;
GetPackData();
@options=();
$options[0]=decode ('koi8r', "Все параметры");
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



#выключение программы
sub Suicide {

print "\nSUICIDE\n";
undef $sui_wtchr;
if ( $RunFlag ) { 
StopReg(); } # остановить обмен с VME
$dbh->do(qq(UPDATE cmtr_chnl set busy=0 WHERE busy=$packID));
$dbh->do(qq(UPDATE vme_ports set busy=0 WHERE port_in=$port_vme_to));
$dbh->do(qq(UPDATE reg SET port=0, flag=NULL  WHERE port=$port_vme_to));
for my $i(0..$#{$port_vme_to_i}){
	if (defined $port_vme_to_i->[$i][1]) {
$dbh->do(qq(UPDATE vme_ports set busy=0 WHERE port_in=$port_vme_to_i->[$i][1])); # освободить порт после измерения интервала 
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

#Расчет отклонения измеренных интервалов от пределов+допуск, отображение отклонений
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

#визуализация отсутствия слова в линии
sub FirstRead {
for my $i (0..$#w_db_interval) { # для всех параметров
  $x0=unpack "I",substr($S_IN,64+$i*4,4);
  $x1 = $x0&0xFF;
	if (($v_type[$i]<RK) and (($x0&0xFF)!=$chan_addr[$i])) { # несовпадение канального адреса ПБК
	#$wgm[$i]->configure(-text=>' ');
		$w_db_interval[$i]->configure(-text=>'');
	 	$missing_parm_flag[$i]=1;
		print "\nflag $i\n";
		#$missing_prm_count++;
	} } 
	$done_firstread->send;}

#проверка наличия слов в линии связи
sub VisScreen {
my $dif_flag=0;
$rcount++; #  счетчик чтений
for my $i (0..$#w_db_interval) { # для всех параметров
        $x0=unpack "I",substr($S_IN,64+$i*4,4);
        $x1=unpack "I",substr($sock_IN,64+$i*4,4);
	if ( $x0!=$x1 ) { # не совпадающие значения параметров
                $dif_flag++;
                if (($v_type[$i]<RK) and (($x1&0xFF)!=$chan_addr[$i])) { # несовпадение канального адреса ПБК
                        $w_db_interval[$i]->configure(-text=>''); }
                }
        } # для всех параметров
if ($dif_flag) { $S_IN=$sock_IN } # были отличия: обновляем 1-й буфер
return 1; } # чтение состоялось и счетчик правильный



#однократное чтение для определения наличия слова в линии
sub Read1 { # однократное чтение

foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) { $err_cnt[$crate]=1 } } # если чтения не было - это уже ошибка

my $len=length($S_IN);
foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) { substr( $S_OUT[$crate],0,4,pack "I",0x230 ); } } 
$read1_wtchr = AnyEvent->timer ( after=>1.0, cb=>sub { # timeout watcher
        foreach my $crate (0 .. 3) { if ($crate_tot[$crate]) {
                if ($err_cnt[$crate]) { # минимум один хост не ответил
ErrMessage("ИС (крейт $crate) не ответила в течение 1.0 секунд!\nВыясните причину отказа.\nЕсли был выполнен \"Рестарт\", снимите задание!!!\nЕсли была запущена динамика, вновь выполните чтение.\nВ случае отказа со стороны ИС, снимите задание и перезагрузите процессор ИС.") } } }
        undef $read1_wtchr; undef $rcv_wtchr;
VisScreen(); 
FirstRead();  
} ); # визуализировать результат в случае успеха
#VisScreen();
$rcv_wtchr = AnyEvent->io ( fh=>\*$S_RCV, poll=>"r", cb=>sub{recvVME() } ); # инициируем вотчер приёмного сокета
foreach my $crate (0 .. 3) {
        if ($crate_tot[$crate]) {# инициировать чтение из нужных хостов ИС 
                if (!defined send($S_SND[$crate], $S_OUT[$crate], 0, $sin_to[$crate])) { # выдать в VME, успешно?
                        $base->bell; if ($log) { print Log "send fail\n------------------\n" } } # нет
                else { # успешно
	                if ($log_trs) { PrintSock(\$S_OUT[$crate],$crate) } } } }
#$time_wtchr = AnyEvent->timer ( after=>1.0, cb=>sub { #Пауза в секунду
#undef $time_wtchr;} );# timeout watcher
if ($INI{UnderMonitor}) {
    $mes[0]=$packID;
    $mes[1]=++$rcount;
    PageMonitor() }
} # однократное чтение

#Создание буферов для однократных чтений (Обнуление ОЗУ, проверка наличия слов в линии связи)
sub CreateBuffers {
for my $crate (0 .. 3) {
#        $S_OUT[$crate]=pack 'I', 0x200; # код операции - запись в ИС
#        $S_OUT[$crate].=pack 'I', 0; # total length, shift - 4
#        $S_OUT[$crate].=pack 'a4','A1'; # идентификатор абонента, shift - 8
#        $S_OUT[$crate].=pack 'a4','CP0'; # идентификатор получателя, shift - 12
#        $S_OUT[$crate].=pack 'I', 0; # период обмена в мкс для цикл. чтения, shift - 16
#        $S_OUT[$crate].=chr(0)x20; # не используется
#        $S_OUT[$crate].=pack 'I', 0; # total_of_records, shift - 40
#        $S_OUT[$crate].=$mysql_db; # имя стенда - в заголовок
#        my $l=20-length($mysql_db);
#        $S_OUT[$crate].=chr(0)x$l;}  # дополненное нулями не используемого пр-ва заголовка
# подготовка выходного буфера $S_OUT
 $S_OUT[$crate]=pack 'I', 0x230; # u_int32 command, код операции обмена - запрос на разовое чтение
 $S_OUT[$crate].=pack 'I', 0; # u_int32 total length, shift - 4
 $S_OUT[$crate].=pack 'a4',"A1"; # char sender_id[4], идентификатор абонента, shift - 8
 $S_OUT[$crate].=pack 'a4',"CP0"; # char receiver_id[4], идентификатор получателя, shift - 12
 $S_OUT[$crate].=pack 'I', 0; # u_int32 time_stamp - период обмена в мкс для цикл. чтения, shift - 16
 $S_OUT[$crate].=pack 'I', 0; # u_int32 jdate, не исп., shift - 20
 $S_OUT[$crate].=pack 'I', 0; # u_int32 jtime, не исп., shift - 24
 $S_OUT[$crate].=pack 'I', 0; # u_int32 message_no, не исп., shift - 28
 $S_OUT[$crate].=pack 'I', 0; # u_int32 total_messages, не исп., shift - 32
 $S_OUT[$crate].=pack 'I', 0; # u_int32 no_of_records, не исп., shift - 36
 $S_OUT[$crate].=pack 'I', 0; # u_int32 total_of_records, shift - 40
 $S_OUT[$crate].=chr(0)x20 } # u_int32 reserved[5], не исп., shift - 44
#


} 

#Завершение измерений
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
$dbh->do(qq(UPDATE vme_ports set busy=0 WHERE port_in=$port_vme_to_i->[$i][1])); # освободить порт после измерения интервала 
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

#блокировка/разблокировка кнопок
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

#вывод буферов в лог
sub PrintSock {
(my $sock, my $crate)=@_;
if (defined $crate) { printf Log "crate  N $crate\n" }
my $c;
my $cmnd=unpack 'I', substr($$sock,0,4);
my $answer=unpack 'I', substr($$sock,56,4);
printf Log "command: 0x%03X ", $cmnd;
if ($cmnd==0x200) { printf Log "(Запись в ИС)\n" }
elsif ($cmnd==0x210) { printf Log "(Запрос циклического чтения)\n" }
elsif ($cmnd==0x220) { printf Log "(Запрос циклического чтения с обнул.)\n" }
elsif ($cmnd==0x230) { printf Log "(Запрос разового чтения)\n" }
elsif ($cmnd==0x240) { printf Log "(Запрос разового чтения с обнул.)\n" }
elsif ($cmnd==0x250) { printf Log "(Останов циклического чтения)\n" }
elsif ($cmnd==0x260) { printf Log "(Приём данных от ИС: ";
        if ($answer==0x210) { printf Log "циклическое чтение)\n" }
        elsif ($answer==0x220) { printf Log "циклическое чтение с обнул.)\n" }
        elsif ($answer==0x230) { printf Log "разовое чтение)\n" }
        elsif ($answer==0x240) { printf Log "разовое чтение с обнул.)\n" } }
else  { printf Log "(Неидентифицируемая команда)\n" }
printf Log "total length[4]: %i\n", (unpack 'I', substr($$sock,4,4));
printf Log "time_stamp(мкс)[16]: %i\n", (unpack 'I', substr($$sock,16,4));
my $cnt=unpack 'I', substr($$sock,40,4);
printf Log "total_of_records[40]: %i\n", $cnt;
$cnt--;
if ( $cmnd>0x200 and $cmnd<0x250 ) { # для команд запросов
  for my $i (0..$cnt) {
    $c=unpack 'I', substr($$sock,64+$i*4,4);
    printf Log "prm_id: %u // 0x%X\n", $c, $c; } }
elsif ( $cmnd==0x200 ) { # запись данных в ИС
  for my $i (0..$cnt) {
    $c=unpack 'I', substr($$sock,64+$i*8,4);
    printf Log "prm_id: %u // 0x%X\t", $c, $c;
    $c=unpack 'I', substr($$sock,68+$i*8,4);
    printf Log "value: 0x%08X\n", $c; } }
elsif ( $cmnd==0x260 ) { # приём из vme
  for my $i (0..$cnt) {
    $c=unpack 'I', substr($$sock,64+$i*4,4);
    printf Log "value: 0x%08X\n", $c; } }
print Log "------------------\n" }



sub ErrMessage {
my ($txt)=@_;
my $er_base=MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
$er_base->title(decode('koi8r',"Внимание:")); $er_base->geometry($INI{StandXY});
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
$fltr_option[0]= "Все параметры";
$fltr_option[1]="Вне пределов";
$fltr_option[2]="Отсутствующие в линии";
$fltr_option[3]="В наличии в линии";
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
foreach (@uniq_chnl) { # по количеству комплектов
        $print_total_parm_count[$k]=$idx_for_chan{$uniq_chnl[$k]};
        $print_first_parm_number[$k+1]=$print_first_parm_number[$k]+$idx_for_chan{$uniq_chnl[$k]}   ;
        print "\n\nfirst $print_first_parm_number[$k] total $print_total_parm_count[$k] $k uniq @uniq_chnl\n\n";
        $k++}

}
my $er_base = MainWindow->new(-borderwidth=>5, -relief=>'groove', -highlightcolor=>"$INI{err_brd}", -highlightthickness=>5);
$er_base->title(decode('koi8r',"Внимание:"));
$er_base->geometry($INI{StandXY});
$er_base->Message(-anchor=>'center', -font=>$INI{err_font}, -foreground=>"$INI{err_forg}", -justify=>'center', -padx=>35, -pady=>10, -text=>decode('koi8r',qq(Выполняется подготовка документа к печати.\nНе забудьте проверить параметры страницы (File->PageSetup) и настройки принтера (File->Print->Принтер: Свойства). Пользуйтесь возможностью предосмотра (Print Prewiew).\n\nНажмите <OK>.)), -width=>400)->pack(-anchor=>'center', -pady=>10, -side=>'top');
$er_base->Button(-command=>sub{ $er_base->destroy; }, -state=>'normal', -borderwidth=>3, -font=>$INI{but_menu_font}, -text=>'OK ')->pack(-anchor=>'center', -pady=>10, -side=>'top');
my (@s,@c,@n,@m,@di,@r,@d,@f0,@f1,@f2,@f3);
my $lh=`date '+%-B, %-e. %-Y. %X'`; $lh=decode('koi8r',$lh);
my $ch='стeнд - '.$mysql_db.'  опeратор - '.$mysql_usr.'.'; $ch=decode('koi8r',$ch);
my $fltr_txt=decode('koi8r', ' Фильтр - ');
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
#считаем максимальную длину имени параметра и его значения
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
$maxd=$maxd*8 + 8 + 4;# 8 пикселей - примерная ширина символа + по 2 символа с каждой стороны - отступ от границ ячейки
my $chan_num; my $chan_char; my $line;
for my $i (0..$#wgs) {
  $s[$i]=$wgs[$i]->cget('-text');
  print HTM qq($s[$i] &nbsp;);
  $c[$i]=$wgc1[$i]->cget('-text');
  print HTM qq($c[$i] &nbsp;);
        #$line=decode('koi8r',"Линия $chan_char <BR>"); print HTM $line;
  #$f0[$i]=$wgn_nm[$i]->cget('-text');
  #$f1[$i]=$wg_db[$i]->cget('-text');
  #$f2[$i]=$wg_rcv[$i]->cget('-text');
  #$f3[$i]=$wg_dev[$i]->cget('-text');
  $f0[$i]=decode('koi8r',"Наименование");
  $f1[$i]=decode('koi8r', "Заданный интервал, мс");
  $f2[$i]=decode('koi8r', "Измеренное значение, мс");
  $f3[$i]=decode('koi8r', "Отклонение, мс");   
print HTM qq(<TABLE BORDER=1 CELLPADDING=2 CELLSPACING=0>);
   #$wgn_nm[$j]=$wgf0[$j]->Label(@pnT, -text=>decode('koi8r',"Наименование"))->pack(-side=>'left');
   #$wgf1[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   #$wg_db[$j]=$wgf1[$j]->Label(@pnT, -text=>decode('koi8r', "Заданный интервал"), -width=>19)->pack(-side=>'left');
   #$wgf2[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   #$wg_rcv[$j]=$wgf2[$j]->Label(@pdT, -text=>decode('koi8r', "Измеренное значение"), -width=>19)->pack(-side=>'left');
   #$wgf3[$j]=$fdat->Frame(-borderwidth=>1,-relief=>"flat",-bg=>"$INI{sc_back}");
   #$wg_dev[$j]=$wgf3[$j]->Label(@pdT, -text=>decode('koi8r', "Отклонение") ,-width=>11)->pack(-side=>'left');
#Заголовки колонок 
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


sub recvVME { # принять и обработать пакет
my $crate; my $hostiadr;
my $cnt=0; my $S_CR=''; #current buffer
if ( select( $rout=$rin, undef, undef, 0) ) { # считать все пакеты, если они есть
        $hostiadr=recv($S_RCV,$S_CR,$max_buf_length,0);
        $hostiadr=inet_ntoa(substr($hostiadr,4,4));
        $crate=$host_crate{$hostiadr};
        #print "\n Crate = $crate \n";
        $err_cnt[$crate]=0 } # принять от VME
else { print "I/O error: interrupt w/o packet!\n"; return }
my $erl=length($S_CR);
my $numpack=unpack 'I', substr($S_CR,28,4); # номер из пакета
if (    $erl != $buf_length[$crate] ) { # проверить счетчик recv, если ошибка: 
        $S_CR.=chr(0)x($buf_length[$crate]-$erl); # если буфер был короче - заполнить "0"
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

#Наполнение буферов для измерения интервалов, по одному буферу на каждое слово в каждом канале
sub CreateBuffersForInt {
	print "\nBUFFERS CREATED\n";
	my $chanel_counter=0;
	my $pack_counter=0; #счетчик-идентификатор отправленного пакета
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
		foreach my $i (0..$#{$sys_parm{$key}}) {#для каждого слова i в канале chanel_counter
		if ($missing_parm_flag[$pack_counter]==1) { 
		print "\nmissing parm\n";}
		(my $vme_chan_addr_i,my $crate, my $chan_vme_prm_id, my $vme_prm_id_i)=$dbh->selectrow_array(qq(
	      SELECT vme_chan.vme_chan_addr,crate,vme_chan.vme_prm_id, vme_chan.vme_prm_id
	      FROM vme_card,compl,vme_chan,parm WHERE parm.vme_prm_id=$vme_prm_buff->[$prm_counter]
	      AND compl.id_system=parm.id_system AND num_compl=$num_compl
                        AND compl.id_vme_chan=vme_chan.id_vme_chan AND vme_chan.id_vme_card=vme_card.id_vme_card
                        AND compl.sim=0));
   		print "\n\nCHAN_VME_ID $chan_vme_prm_id\n\n";
			unless (defined $chan_vme_prm_id) { ErrMessage('Для данного канала модуля регистрация интервала не поддерживается'); return }
	    	my $prm_name=$wgn[$pack_counter]->cget('-text'); 
		my $val=$chan_addr_buff->[$prm_counter];
		my $koi=encode('koi8r',$prm_name);
		#print "\nkey= $key prm_counter= $prm_counter chanel_counter val= $val vme_prm_buff=$vme_prm_buff->[$prm_counter] chan_buff $chan_addr_buff->[$prm_counter] name $koi arrary @{$chan_addr_buff}\n";

		if ($koi=~/\s(k|к|К|K)\.(1|2|3|4)$/) { # в имени пар-ра присутствует dsi (data sourse identificator)
        	my $dsi=substr $koi,-1,1; $dsi&=0x3; $val|=($dsi<<8); $val|=0x400 }
		
		$chan_measuring_flag[$chanel_counter]=0;
 
		$S_int[$chanel_counter][$prm_counter]=substr( $S_OUT[$crate],0,72);
		substr( $S_int[$chanel_counter][$prm_counter], 0,4,pack "I",0x200 ); # код операции - запись в ИС
		substr( $S_int[$chanel_counter][$prm_counter], 4,4,pack "I",72 ); # total length 
		substr( $S_int[$chanel_counter][$prm_counter],40,4,pack "I",1 ); # total_of_records
		substr( $S_int[$chanel_counter][$prm_counter],64,4,pack "I",$chan_vme_prm_id ); # vme_prm_id
		substr( $S_int[$chanel_counter][$prm_counter],68,4,pack "I",$val ); # new data (определение интересующего пар-ра)
		
		if (not defined $chan_vme_id{$chanel_counter}) {
			$chan_vme_id{$chanel_counter}=$vme_prm_id_i;}
		
		my $interval = $max_int_for_buff{$vme_prm_buff->[$prm_counter]};
		print "\nMAX INTERVAL $max_int_for_buff{$vme_prm_buff->[$prm_counter]}\n";
		$interval_for_recv_int[$pack_counter]=$interval;	
		print "\n\ninterval = $interval counter = $prm_counter vme $vme_prm_buff->[$prm_counter] \n\n";
		$S_int_cycle[$chanel_counter][$prm_counter] = $S_int[$chanel_counter][$prm_counter];
		substr( $S_int_cycle[$chanel_counter][$prm_counter], 0,4,pack "I",0x210 ); # код операции - циклич. чтение без обнуления
		substr($S_int_cycle[$chanel_counter][$prm_counter],28,4,(pack 'I',$pack_counter));
		substr( $S_int_cycle[$chanel_counter][$prm_counter], 32,4,pack "I",$pack_counter); 
		substr( $S_int_cycle[$chanel_counter][$prm_counter], 4,4,pack "I",68 ); # total length, total_of_records - прежнее
		substr( $S_int_cycle[$chanel_counter][$prm_counter],16,4,pack "I",int($interval*1000) ); # период цикл.чтения (макс интервал в мкс)
		
		$S_int_stop[$chanel_counter][$prm_counter] = $S_int_cycle[$chanel_counter][$prm_counter];
		substr( $S_int_stop[$chanel_counter][$prm_counter],0,4,pack "I",0x250 ); # команду - в S_stop

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
		ErrMessage("Измерение интервала недоступно, т.к. канал $chan_vme_id{$chanel_counter} занят");
		StopReg(); $stop_st_reg_flag=1; return}
	else {
		$dbh->do(qq(UPDATE vme_chan SET busy=1, host="$my_host" WHERE vme_prm_id=$chan_vme_id{$chanel_counter}))}
	$chanel_counter++;
my @ttext= sort { $a <=> $b } @measurment_time;
print "\n\nвремя @ttext\n\n"	}
}

#Создание сокетов для непосредственного измерения интервалов
sub CreateSocketsForInt {
        my $port_count;
	$port_vme_to_i=$dbh->selectall_arrayref(qq(SELECT id,port_in from vme_ports WHERE host="$my_host" and !busy ));
        if ($#S_int>=$#{$port_vme_to_i}) {
		$port_count=$#{$port_vme_to_i};}
	else {$port_count=$#S_int}
	print "\nport_count $port_count\n";
	if ($port_count<0) { # сообщение об отсутствии свободного порта обмена если нет свободных портов (количество портов считается по индексу последнего элемента в port_vme_to_i, а значит начинается с нуля (0-однин порт), нет портов - port_count=-1)

                                ErrMessage('Для данной станции нет свободных портов обмена с vme'); StopReg(); $stop_st_reg_flag=1; return }
	for my $i (0..$port_count) {
		
		if (defined $port_vme_to_i->[$i][1]) { # если есть свободный порт 
        		$port_busy_flag[$i]=0;
			$port_vme_from_i->[$i][1]=$port_vme_to_i->[$i][1]+1;
                	$dbh->do(qq(UPDATE vme_ports set busy=1 WHERE id=$port_vme_to_i->[$i][0])); # захватываем его
                	$sin_from_i[$i] = sockaddr_in( $port_vme_from_i->[$i][1], INADDR_ANY ); # подготавливаем обмен: приём от любого хоста по нужному порту
			socket($S_RCV_I[$i], PF_INET, SOCK_DGRAM, $proto); # $S_RCV_I - filehandle for "interval mesurement exchange"
                	my $bind_answ=bind($S_RCV_I[$i],$sin_from_i[$i]); $rin_i[$i] = ''; vec($rin_i[$i], fileno( $S_RCV_I[$i] ), 1) = 1;
                	unless ($bind_answ) { print "unsuccessfully binded socket!\n" } 
			for my $crate (0..3) {
                		$sin_to_i[$crate][$i] = sockaddr_in( $port_vme_to_i->[$i][1], $iaddr[$crate] );}
			}
                        }
}

#Отправка запросов в VME (Старт/остановка циклического чтение, указывается по какому порту , какой канал и параметр)
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
	send($S_SND_I,$S_int[$chanel_idx][$parm_idx], 0, $sin_to_i[$crate_for_buff[$chanel_idx][$parm_idx]][$sock_num]); # выдать в VME
	if ($log_trs) { PrintSock(\$S_int[$chanel_idx][$parm_idx],$crate_for_buff[$chanel_idx][$parm_idx]) }
	#sleep($interval);
	#$send_wtchr = AnyEvent ->timer (after=>$interval, cb=>sub {
		send($S_SND_I,$S_int_cycle[$chanel_idx][$parm_idx], 0, $sin_to_i[$crate_for_buff[$chanel_idx][$parm_idx]][$sock_num]); # выдать в VME
		$chanel_parm{$send_counter} = "$chanel_idx;$parm_idx";
		if ($log_trs) {PrintSock(\$S_int_cycle[$chanel_idx][$parm_idx],$crate_for_buff[$chanel_idx][$parm_idx]);} 
		#print "\n\n\n\n send_counter $send_counter chanel_idx $chanel_idx ; $parm_idx sock_num $sock_num measuring $chanel_measuring_counter\n\n\n\n";
		$send_counter++;

		#});
	}
	
else {
	send($S_SND_I,$S_int_stop[$chanel_idx][$parm_idx], 0, $sin_to_i[$crate_for_buff[$chanel_idx][$parm_idx]][$sock_num]); # выдать в VME
	PrintSock(\$S_int_stop[$chanel_idx][$parm_idx],$crate_for_buff[$chanel_idx][$parm_idx]) 
	}	
}

#Отображение прочитанных интервалов
sub DisplayData {
my $disp_idx=0;	   #индекс виджета параметра (в wgn)
my $options_idx=0; #индекс опции для фильтра
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
							$w_received_interval[$disp_idx]->configure(-text=>decode('koi8r', "$min_interval ÷ $max_interval"));}
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
        my $option=decode ('koi8r', "В наличии в линии");
        $options_idx++;
        $options[$options_idx]=$option;
        $b_filter->configure(-options => [@options]);}
        #аналогично для параметров, вышедших за пределы и для присутствующих в линии  

#если есть отсутствующие параметры - добавляем соотв. опцию в фильтр
 if ($missing_prm_count > 0) {
          my $option=decode ('koi8r', "Отсутствующие в линии");
          $options_idx++;
          $options[$options_idx]=$option;
          $b_filter->configure(-options => [@options]);
          }

if ($out_of_limits_prm_count > 0) {
        my $option=decode ('koi8r', "Вне пределов");
        $options_idx++;
        $options[$options_idx]=$option;
        $b_filter->configure(-options => [@options]);}
}

#П/п, принимающая пакеты с измеренными значениями интервалов, выдающая запросы на на останов чтения текущего параметра и на
#чтение следующего параметра из свободного порта, а также дальнейшая сортировка полученных интервалов по массиву @total_interval_value
sub RecvInt {
my $sock_num=$_[0];
my $recv_counter=0; #какой по счету запрос прочитали
my $count_for_start=0; #счетчик для определения такта, с которого надо начать принимать интервалы
my @int; #интервалы для одного параметра (обнуляется после того как прочитали параметр нужное количество раз)
my ($chan_num, $parm_num);
my $parm_read_counter=0; #Массив счетчиков количества прочитанных параметров по каналам
my $stop_flag; #флаг, 1 - останов циклического чтения, 0 - следующий запрос
my $S_RCV_INT=$S_RCV_I[$sock_num];
my $val;
my $timeout_counter=0;
$rcv_i_wtchr[$sock_num]=AnyEvent->io(fh=>\*$S_RCV_INT, poll=>"r", cb=>sub { # инициируем вотчер приёмного сокета интервалов
        #print "\nсработал вотчер сокета\n";
	my $sock_IN; $val=0; 
	while ( select( $rout_i[$sock_num]=$rin_i[$sock_num], undef, undef, 0) ) { # считать все пакеты, если они есть
                recv($S_RCV_INT,$sock_IN,68,0) } # принять от VME
        $sock_err_i=0; # обнуляем флаг ошибок чтения интервала
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
	else {#Для N_parm_count чтений, начиная с count_for_start
			#if ($missing_parm_flag[$parm_num]==1) {
		        #print "\nWAS MISSING\n";
        		#for my $i (0..$N_parm_count) {
                	#	$total_interval_value[$chan_num][$parm_num][$i]=0;}
               		#	$count_for_start=$start_recv_count; $parm_read_counter=$N_parm_count;}

			if ($parm_read_counter<$N_parm_count) {
			#Если параметр отсутствовал в линии связи, то переходим к следующему параметру, в массив пишем один 0
	  #Если параметр был в наличии в линии связи, но пришел 0, то увеличиваем счетчик таймаута, если настал таймаут (определяется
				#так - счетчик == сколько собираемся ждать/интервал цикл. чтения), то записываем в массив 0 (последнее полученное значение) и переходим к следующему параметру
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
			if ($parm_num<$#{$S_int[$chan_num]}) { #Если прочитали не все параметры в этом канале
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
				#print "\nПрошли по каналу\n";
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
					#print "\nКонец chan_done $chanel_done == ($#S_int+1)\n";
					StopReg();
					$RunFlag=0;
					DisplayData();
					}
			
			 
			}
		}
	}
	});
}
		



