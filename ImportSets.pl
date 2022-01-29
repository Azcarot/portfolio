#!/usr/bin/perl -w 
#Программа экспорта/импорта наборов данных ImportSets

#Версия 0.1

#Назначение: перенос наборов данных между виртуальными стендами, принадлежащими одной родительской ветви.

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

#Глобальные переменные;
my $current_user; #Имя текущего виртуального стенда
my $current_parent; #Имя базового стенда текущей родительской ветки
my $user; #Имя выбранного оператором виртуального стенда
my $Sets = {}; #Хэш наборов данных виртуального стенда, выбранного оператором
my %Stands = (); #Хэш со списком виртуальных стендов принадлежащих текущей родительской ветке 
my %Plates = (); #Заголовки колонок элемента Набор данных
my %MissingSys = (); #Список номеров и имен систем, присутствующих в наборе данных, но 
   #отсутствующих в текущем виртуальном стенде
my %MismatchingSys = (); #Хэш данных систем, количество комплектов в которых не соответствует 
   #количеству комплектов в стенде, из которого осуществляется импорт
my $dir_name; #Имя директории, в которой расположен файл ssrp.ini
my $shmsg; #Сообщение в область разделяемой памяти
my $target; #Значение поля sets.target
my $SSRPuser; #Имя текущего пользователя программы Ядро ССРП/СТКД
my $mntr_pid; #Идентификатор процесса для обмена с монитором
my (@Tl_att)=(-borderwidth => 1, -relief => 'flat',  -takefocus => 0); # Toplevel attributes
my $users_sets; #Наборы данных выбранного пользователем виртуального стенда
my $set_data; #значение поля sets.data выбранного оператором набора данных
my $set_comment=''; #Имя набора данных
my @UserSets_id_system = 0; #Массив номеров систем (номера систем могут повторяться) в 
   #наборе данных, выбранным оператором
my @UserSetsComplNum = 0; #Массив номеров комплектов систем в наборе данных, выбранном оператором
my @UserSets_id_parm = 0; #Массив значений id_parm параметров в наборе данных, выбранном оператором
my @User_id_system=0 ; #Массив уникальных значений id_system в наборе данных, выбранном оператором
my @Base_id_system = 0; #Массив уникальных значений id_system в базовом стенде текущей родительской ветки
my @Current_id_system = 0; #Массив уникальных значений id_system текущего виртуального стенда
my @CurrentSets_id_parm = 0; #Массив значений id_parm (значения могут повторяться) текущего виртуального стенда
my @CurrentSets_id_system = 0; #Массив значений id_system (значения могут повторяться) текущего виртуального стенда
my @CurrentSetsData = 0; #Массив значений параметров в новом наборе данных
my @CurrentSetsComplNum; #Массив номеров комплектов систем, для соответствующих систем
my $data; #Строка поля sets.data нового набора данных
my @UserSetsData = 0; # - Массив значений параметров в выбранном оператором наборе данных
my $Set_id = 0; #Индекс выбранного оператором набора данных
my $text; #Имя нового набора данных при выборе опции "Сохранить как" в окне 
my $born_time; #Значение поля sets.born_time
my $sql_var='ORDER BY born_time DESC,user ASC,comment ASC';
my $cmnt=my $usr=1; my $dt=0;
 
#Входные данные БД
#cmk - таблица базы данных, содержащая описание всех стендов
#cmk.user - имена виртуальных стендов
#sets - таблицы базы данных, содержащие описание всех наборов данных текущего и выбранного оператором виртуальных стендов
#sets.id - индекс набора данных
#sets.user - имя владельца набора данных
#sets.born_time - время создания набора данных
#sets.comment - название набора данных
#sets.target - назначение набора данных (Статика/Квазидинамика)
#sets.data - данные набора данных
#system - таблицы базы данных, содержащие описание всех систем выбранного оператором набора данных
#system.id_system - индекс системы
#system.name - имя системы
#system.n_s_s - количество комплектов имитаторов

###########################

#Определяем рабочий каталог
chomp($dir_name = $ENV{HOME});
$dir_name.='/cmk';
chdir $dir_name;

#2.1.   Открытие файла ssrp.ini, для приведения визуальных характеристик графического 
 #интерфейса к соответствию таковым для задач ССРП/СТКД.
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

#2.2.   При запуске программы проверяется, запущено ли управляющее Ядро ССРП/СТКД, 
#если ядро не запущено, вывод дополнительного окна с сообщением 
#"Пожалуйста, загрузите Ядро". 
  if ($INI{UnderMonitor}) { # подключить shmem, установить $SSRPuser
     unless (-e '/tmp/ssrp.pid') { NoShare() }
     open (PF,'/tmp/ssrp.pid');
     $shmsg = new IPC::Msg( 0x72746e6d,  0001666 );
     RestoreShmem();
     $SIG{USR2} = \&Suicide }

#ErrMessage
#Назначение - вывод дополнительного окна ошибок для п/п CheckName
sub ErrMessage {
my ($txt) = @_; # Текст сообщения
my $er_base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", 
   -highlightthickness => 5);
$er_base->title(decode('koi8r',"Внимание:")); $er_base->geometry($INI{StandXY});
$er_base->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", 
   -justify => 'center', -padx => 35, -pady => 10, -text => decode('koi8r',$txt), -width => 400)->pack(-anchor => 'center', 
   -pady => 10, -side => 'top');
} #конец ErrMessage

#RestoreShmem
#Назначение - получение от Ядра имени пользователя mysql 
sub RestoreShmem {
my @shmem = <PF>; close(PF);
($SSRPuser, $mntr_pid) = split(/\|/,$shmem[0]);
} #конец RestoreShmem

#NoShare
#Назначение - вывод дополнительного окна с сообщением "Пожалуйста, загрузите Ядро"
sub NoShare {
my $base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
$base->title(decode('koi8r',"Ошибка:"));
$base->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35, -pady => 10, 
   -text => decode('koi8r',qq(Пользователь не идентифицирован:\nпо-видимому, не загружено "Ядро".\nЗагрузите "Ядро ССРП/СТКД" \nи - зарегистрируйтесь.)),
   -width => 400)->pack(-anchor => 'center', -pady => 10, -side => 'top');
$base->Button(-command => sub{ $base->destroy; exit(0); }, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
   -text => 'OK')->pack(-anchor => 'center', -pady => 10, -side => 'top');
$base->protocol('WM_DELETE_WINDOW',sub{ $base->destroy; exit(0); } );
$base->grab;
MainLoop; 
}#конец NoShare

#2.3.   Создание пустого окна "Импорт наборов данных", для дальнейшего заполнения его 
   #элементами "Статика/Квазидинамика", "Стенд", "Набор данных". Создание 
   #статусной строки в нижней части этого окна.
my $mw = MainWindow->new;
$mw->geometry("820x620");
$mw->title(decode ('koi8r',"Импорт наборов данных"));

#По умолчанию устанавливается значение переменной target = "S", 
#что соответствует состоянию радиокнопки "Статика".
$target = "S";

#Фрейм под элемент "Набор данных"
my $setwin = $mw->Frame(@Tl_att); $setwin->Label(-text => decode('koi8r',"Выберите набор данных:"));
$setwin->pack(-anchor => 'center', -expand => 0 ,-padx => 10, -pady => 10, -fill => 'both', -side => 'right');

#Элемент "Набор данных"
my $setdata = $setwin->Scrolled('TableMatrix', -scrollbars => 'osoe', -rows => (12), -cols=>3,
   -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, -state => 'disabled', -selectmode => 'single',
   -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both', -padx => 5, -pady => 5, -selecttitles => 1);
$setdata->tagConfigure('NAME', -anchor => 'w');
$setdata->tagConfigure('title', -relief => 'raised');
$setdata->tagCol('NAME', 0);
$setdata->colWidth(0 => 18, 1 => 12, 2 => 15);
$setdata->pack(-expand => 1, -fill => 'none');

#Фрейм под элемент "Стенд"
my $standwin = $mw->Frame(@Tl_att);
$standwin->pack(-anchor => 'center', -expand => 1, -fill => 'both', -side => 'left');

#Элемент "Стенд"
my $Stand = $standwin->TableMatrix(-rows => 10, -cols => 3, -font => $INI{sys_font}, -bg => 'white', -roworigin => -1, -colorigin => 0, 
   -state=>'disabled', -selectmode => 'single', -titlerows => 1, -cursor => 'top_left_arrow', -resizeborders => 'both', -padx => 15, -selecttitles => 0);

#Фрейм элемента "Статика/Квазидинамика"
my $Radiobutton = $mw -> Frame();

#Фрейм кнопки "Импорт"
my $Button = $mw -> Frame();

#Кнопка "Импорт"
my $Import_button = $Button -> Button( -highlightthickness => 3, -font => $INI{data_font}, -state => 'disabled',
   -command => sub{DecodeSet($set_data)}, -text => decode('koi8r',"Импорт"));

#2.4.	Создаем радиокнопку с возможными состояниями "Статика" и "Квазидинамика". 
   #Переключение радиокнопки между состояниями "Статика" и "Квазидинамика" меняет 
   #значение переменной target с target = "S" (Статика) на target = "Q" (Квазидинамика).
#2.4.1.	По умолчанию устанавливается значение переменной target = "S", 
   #что соответствует состоянию радиокнопки "Статика".
#2.4.2.	При изменении состояния радиокнопки каждый раз вызывается функция MainStandSets.
my  $Static = $Radiobutton -> Radiobutton(-text => decode ('koi8r', "Статика"), -font => $INI{bi_font},  
   -value => "S", -variable => \$target, -command => \&MainStandSets);
my  $Quazi = $Radiobutton -> Radiobutton(-text => decode('koi8r',"Квазидинамика"), -font => $INI{bi_font},  
   -value => "Q", -variable => \$target, -command => (\&MainStandSets));
$Static -> grid (-row => 1, -columnspan => 10, -column => 1, -sticky => 'w');
$Quazi -> grid (-row => 2, -column => 1, -sticky => 'w');
$Import_button -> grid (-row => 1, -columnspan => 30, -column => 5);
$Radiobutton ->pack(-in => $standwin, -side => "bottom", -fill => 'x', -padx => 10, -anchor => 'w');
$Button->pack(-in => $setwin, -after => $setdata, -side => "bottom", -fill => 'both', -pady => 5);

#Статусная строка
my $status_str = $mw->Text(-width => 40, -height => 10, -state => 'disabled');
$status_str->pack(-side => 'bottom',-after => $setwin, -padx => 10, -pady => 10);
 
#MainStandSets
#Назначение -- создание/обновление основных элементов "Стенд" и "Набор данных" 
#графического окна "Импорт наборов данных".
sub MainStandSets {
my @Stand_list; #Список виртуальных стендов, принадлежащих одной родительской ветви с текущим виртуальным стендом 
my $stand_rows = 12; #Количество строк элемента Стенд
my $sets_rows = 12; #Количество строк элемента Набор данных
my $Plates = {}; #Хэш с заголовками столбцов элемента Набор данных
my $VirtualStandList->[0][0] = "Пусто"; #Список виртуальных стендов текущей родительской ветви, за исключением текущего виртуального стенда
my $previous_stand = 0; #Индекс предыдущего выбранного оператором стенда   

#Уничтожение всех созданных графических элементов, с последующим пересозданием 
$Stand->destroy; 
$setwin->destroy; 
$standwin->destroy;
$status_str->destroy;
$Import_button->destroy;
$Radiobutton->destroy;
$current_user = $ENV{USER};
   
#3.1.1.	Обращение к БД cmk с запросом на список уникальных имен стендов, поле 
#user.parent которых совпадает с полем user.parent текущего виртуального стенда. 
#Полученный список виртуальных стендов сохраняется в переменной VirtualStandsList. 
#Имя текущего виртуального стенда в список не заносится.  Значение поля user_parent 
#сохраняем в переменной current_parent
my $dbh = DBI->connect_cached("DBI:mysql:cmk:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
   $current_parent = $dbh->selectall_arrayref(qq(SELECT parent 
      FROM user WHERE
      user.name = "$current_user"));
   $VirtualStandList = $dbh->selectall_arrayref(qq(SELECT name 
      FROM user WHERE
      user.parent = "$current_parent->[0][0]" AND
      user.name != "$current_user"));

#3.1.2.	Создание списка виртуальных стендов, по одному ряду на каждый элемент массива VirtualStandsList.
#Визуально ряды содержат имена виртуальных стендов, содержащихся в массиве VirtualStandsList. 
#Каждый ряд содержит одно уникальное имя. Ряды располагаются в элементе "Стенд".
$standwin = $mw->Frame(@Tl_att); $standwin->Label(-text => decode('koi8r',"Выберите набор данных:")); 
$standwin->pack(-anchor => 'center', -expand => 0, -fill => 'both',-padx=>15, -pady=>20,  -side => 'left');
my  $Stands->{'-1,0'} = 'Стенд: ';
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
   if ($r >= 0) { # Выбор строки
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

#Создание пустого элемента "Набор даных"
$Plates->{'-1,0'} = 'Наименование набора'; $Plates->{'-1,1'} = 'Кто создал'; $Plates->{'-1,2'} = 'Дата создания';
foreach $key (keys %$Plates) { $Plates->{$key} = decode('koi8r', $Plates->{$key}) }
$setwin = $mw->Frame(@Tl_att); $setwin->Label(-text => decode('koi8r', "Выберите набор данных:")); 
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

#Повторное создание элементов :"Статика/Квазидинамика", кнопки "Импорт", статусной строки
$status_str = $mw->Text(-width => 80,  -height => 1, -bg => 'white', -state => 'disabled', 
   -highlightcolor => 'green', -pady => 5, -padx => 5, -font => $INI{err_font});
$status_str->pack(-side => 'bottom', -fill => 'x', -before => $standwin, -padx => 10, -pady => 10);
$Radiobutton = $mw -> Frame();
my $Button = $mw -> Frame();
$Import_button = $Button -> Button(-highlightthickness => 3, -font => $INI{data_font}, 
   -state => 'disabled', -command => sub{DecodeSet($set_data)}, -text => decode('koi8r',"Импорт"));
$Static = $Radiobutton -> Radiobutton(-text => decode ('koi8r', "Статика"), -font => $INI{bi_font},
   -value => "S", -variable => \$target, -command => \&MainStandSets);
$Quazi = $Radiobutton -> Radiobutton(-text => decode('koi8r',"Квазидинамика"), -font => $INI{bi_font},
   -value => "Q", -variable => \$target, -command => (\&MainStandSets));
$Static -> grid (-row => 1,-columnspan => 10, -column => 1, -sticky => 'w');
$Quazi -> grid (-row => 2, -column => 1, -sticky => 'w');
$Import_button -> grid (-row => 1, -columnspan => 30, -column => 5);
$Radiobutton -> pack(-in => $standwin, -side => "bottom", -fill => 'x', -padx => 10, -anchor => 'w');
$Button->pack(-in => $setwin, -after => $setdata, -side => "bottom", -fill => 'both', -pady => 5);
} #конец MainStandSets

#GetSets
#Назначение: Получение списка наборов данных выбранного оператором виртуального стенда user.
sub GetSets {
$Sets = {}; #Хэш с данными элемента Набор данных

#3.2.1.   Запрашиваем значения полей id, user, born_time, comment и data таблицы sets базы данных выбранного оператором 
#виртуального стенда user, у которых значение поля target совпадает со значением переменной target, установленным элементом 
#Статика/Квазидинамика. Полученные данные сохраняются в переменной Sets.
my $dbh = DBI->connect_cached("DBI:mysql:$user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
my $sql = qq(SELECT id,user,born_time,comment, data FROM sets WHERE target="$target");
$users_sets = $dbh->selectall_arrayref(qq($sql $sql_var)) || die $DBI::errstr;
$Sets->{'-1,0'} = 'Наименование набора'; $Sets->{'-1,1'} = 'Кто создал'; $Sets->{'-1,2'} = 'Дата создания';
my ($s,$t); for my $i (0...$#{$users_sets}) {
   $Sets->{"$i,0"} = $users_sets->[$i][3]; $Sets->{"$i,1"} = $users_sets->[$i][1]; $s = $users_sets->[$i][2];
   $t = substr($s,-4,2).':'.substr($s,-2,2).' '.substr($s,-6,2).'-'.substr($s,-8,2).'-'.substr($s,-10,2);
   $Sets->{"$i,2"} = $t } #конец for
foreach my $key (keys %$Sets) { $Sets->{$key} = decode('koi8r',$Sets->{$key}) }

#Если в выбранном оператором виртуальном стенде присутствовали наборы данных (переменная Sets не пуста), то:
#3.2.2.1.   Запускается функция DisplaySets,
#3.2.2.2.   Акцентируется кнопка "Импортировать"
if ($#{$users_sets}!=-1) {
   DisplaySets();}

#Если переменная Sets оказалась пуста, то:
#3.2.3.1.   Окно элемента "Набор данных" очищается.
#3.2.3.2.   Снимается акцент с кнопки "Импортировать"
else { 
$Import_button->configure(-state => 'disabled');}
DisplaySets();} #конец GetSets

#DisplaySets
#Назначение -- Отображение сохраненных в переменной Sets наборов данных в элементе 
#"Набор данных" аналогично программе "Статика".
sub DisplaySets {
my $sets_rows = 12; #Количество отображаемых единовременно строк элемента "Набор данных"
my $prev_row = 10; #Индекс предыдущей выбранной оператором строки
my $sql = qq(SELECT id,user,born_time,comment, data FROM sets WHERE target="$target");

#Очищаем элемент "Набор данных"
$setdata->destroy;
if ($sets_rows < $#{$users_sets}) {$sets_rows = $#{$users_sets};}

#Создаем и заполнаем элемент "Набор данных", при выборе строки содержащий набор данных акцентируется кнопка "Импортировать"
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
   if ($r >= 0) { # Если строка выбрана
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
      else { # выбор сортировки
         if ($c==0) { # наименование
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
} #конец DisplaySets

#DecodeSet
#Назначение - Дешифровка значений номеров систем, номеров комплектов, 
#id_parm и значений параметров.
#Выход - 4 массива, последовательно описывающие содержимое выбранного оператором набора данных:
#my @UserSets_id_system; # - массив номеров систем (номера систем могут повторяться)
#my @UserSetsComplNum; # - массив номеров комплектов систем
#my @UserSets_id_parm; # - массив значений id_parm параметров
#my @UserSetsData; # - массив значений параметроов;
sub DecodeSet {
my @UserSets = split /\n/ , $_[0];
@UserSets_id_system = 0;
@UserSetsComplNum = 0;
@UserSets_id_parm = 0;
@UserSetsData = 0;
my $c = 0; #Счетчик параметров
my $k = 0; #Счетчик уникальных систем
my $key; #Часть поля sets.data за исключеением значения параметра
my $Data; #Значение параметра
my %seenUser;
foreach (@UserSets) { 
#Для статики
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
#Для квазидинамики
   elsif ($target eq "Q") {
      chomp; ($key,$Data) = split /:/; $key=~/(....)(.+)/m; $key=$1.($2+0);
      $UserSets_id_system[$c] = substr($key,0,3);
      $UserSetsComplNum[$c] = substr($key,3,1);
      $UserSets_id_parm[$c] = substr($key,4,4);
      $UserSetsData[$c] = $Data;
      $c++;}}
#Выделение уникальных id_system 
$#User_id_system=-1;
foreach my $value (@UserSets_id_system) {
  if (! $seenUser{$value}) {
      push @User_id_system, $value;
      $seenUser{$value} = 1;}}
CheckSysCompl();
}#конец DecodeSet 

#CheckSysCompl
#Назначение:
#1) Определение наличия в текущем виртуальном стенде перечня 
   #системокомплектов, присутствующих в выбранном оператором наборе данных;
#2) Отображение в дополнительном графическом окне списка номеров и 
   #имен систем, присутствующих в наборе данных, но отсутствующих в текущем виртуальном стенде;
#3) Отображение в дополнительном графическом окне списка систем, 
   #количество комплектов в которых в текущем виртуальном стенде отличается от 
   #такового в стенде, из которого осуществляется импорт.
#Входные параметры:
#User_id_system[*] - список номеров систем, присутствующих в наборе данных, выбранном оператором
#current_user - имя текущего виртуального стенда.
#Входные данные БД: system - таблицы базы данных, содержащие описание всех систем 
#для выбранного оператором набора данных.
#Входные файлы:
#Pxx000@user - файл-описатель наследования выбранного оператором виртуального стенда user
#Pxx000@current_user - файл-описатель наследования текущего виртуального стенда.
#Выход:
#@UserCompl - количество комплектов систем, присутствующих в наборе данных, выбранном оператором
#@MissingSysNum - список номеров систем, присутствующих в наборе данных, 
   #но отсутствующих в текущем виртуальном стенде.
#@MissingSysName - список имен систем, присутствующих в наборе данных, но отсутствующих 
   #в текущем виртуальном стенде. В дополнительное окно оператору выводятся только имена систем.
#@MismatchingComplNum - список номеров систем, количество комплектов в которых больше 
   #чем в стенде, из которого осуществляется импорт.
#@MismatchingComplDiff - разница в количестве комплектов между системой в текущем виртуальном 
   #стенде и в виртуальном стенде, из которого осуществляется импорт.
#@MismatchingComplName - список имен систем, количество комплектов в которых больше чем в стенде, 
   #из которого осуществляется импорт. В дополнительное окно оператору выводятся только имена 
   #систем и разница в количестве комплектов между выбранным оператором и текущим виртуальным стендом.
sub CheckSysCompl {
my @UserCompl; 
my @MissingSysNum; 
my @MissingSysName;
my @MismatchingComplNum; 
my @MismatchingComplDiff; 
my @MismatchingComplName;
my $FILE1; #Манипулятор файла наследования Базовый стенд -> выбранный оператором виртуальный стенд
my $FILE2; #Манипулятор файла наследования Базовый стенд -> текущий виртуальный стенд
my @file1; #Содержимое файла 1
my @file2; #Содержимое файла 2
my @Base_id_systemF1; #Значение id_system системы в базовом стенде в файле 1
my @Base_id_systemF2; #Значение id_system системы в базовом стенде в файле 2
my @User_id_systemF1; #Значение id_system системы в виртуальном стенде, выбранном оператором, из файла 1
my @Current_id_systemF2; #Значение id_system в текущем вирутальном стенде, из файла 2
my $MissingSys = {}; #Хэш, содержащий имена не наследуемых в текущий виртуальный стенд систем
my $MismatchingSys = {}; #Хэш, содержащий имена, а также количество комплектов систем, 
 #количество комплектов которых отличается от количества комплектов в аналогичной системе 
 #в текущем виртуальном стенде 
my $missingsysfr; #Фрейм для отображения списка систем, не наследуемых в текущий виртуальный стенд
my $missingsyssc; #Элемент Список отсутсвующих ситем - список систем не наследуемых в текущий виртуальный стенд 
my $missing_rows = 4; #Количество строк элемента Список отсутствующих систем
my $mismatchingsysfr; #Фрейм для отображения списка систем, количество комплектов которых отличается 
 #от количества комплектов в аналогичной системе 
 #в текущем виртуальном стенде 
my $mismatchingsyssc; #Элемент - Список систем с несоответствующим количеством комплектов
my $mismatching_rows = 5; #Количество строк элемента Список систем с несоответствующим количеством комплектов
my $count1 = 0; #Счетчик id_system систем в Базовом стенде из файла 1
my $count2 = 0; #Счетчик id_system систем в текущем стенде
my $countM = 0; #Счетчик id_system отсутствующих систем
my $countMismatch = 0; #Количество систем, количество комплектов которых отличается от 
 #количества комплектов в аналогичной системе в текущем виртуальном стенде 
my $Not_I_counter = 0; #Счетчик количества систем, отсутствующих в базовом стенде
my $Not_I_Num_Counter = 0;
my @Not_Inherited_Num;
my %seen;
my %seen2;
my @CurrentCompl; #Количество комплектов соответствующих систем текущего виртуального стенда
my $Continue_B; #Кнопка "Продолжить" 
my $Cancel_B; #Кнопка "Отмена"
my @Mismatching_user; #Количество комплектов систем в выбранном оператором виртуальном стенде, 
 #для систем количество комплектов которых отличается от аналогичных систем в текущем виртуальном стенде 
my @Mismatching_current; #Количество комплектов систем в текущем виртуальном стенде, для систем число комплектов 
 #которых отличается от аналогичных систем в выбранном оператором виртуальном стенде

#3.5.1.   Подключение к БД виртуального стенда user. 
my $dbh = DBI->connect_cached("DBI:mysql:$user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;

#3.5.2.   В цикле по User_id_system[i], запрашиваем в БД user значение поля 
 #system.n_s_s (количество комплектов систем), при условии что system.id_system=User_id_system[i]. 
 #Полученное значение сохраняем в UserCompl[i].
###for my $i(0..$#User_id_system) {
###$UserCompl[$i] = $dbh->selectall_arrayref(qq(SELECT system.n_s_s FROM system WHERE system.id_system="$User_id_system[$i]" ));
### }

#3.5.4.   Открываем файл-описатель наследования Pxx000@user (cоздаем манипулятор файла FILE1).

#3.5.4.1.   Если файл отсутствует, вывод ошибки в статусную 
#    #строку : "Отсутствует файл-описатель наследования Pxx000@user".

if (not defined(open ($FILE1, "/mnt/Data/inheritance/P$current_parent->[0][0]\@$user"))){
   my $NoFile = decode ('koi8r', "Отсутствует файл-описатель наследования P$current_parent->[0][0]\@$user");
   Insert_status_str($NoFile);}

#3.5.4.2.   Если файл был найден, то в цикле по UserSets_id_system[i] ищем в файле, 
   #среди систем виртуального стенда user, данную систему. Поиск осуществляем в 
   #первой части файла (в правом столбце).
else {
   @file1 = <$FILE1>;
   close($FILE1);
   for my $i(1..$#file1) {
      chomp $file1[$i];
      if ($file1[$i] eq 'parm') {last;}
      ($Base_id_systemF1[$i-1] , $User_id_systemF1[$i-1])=split(/\t/,$file1[$i],2); 
   } #конец for
   @Base_id_system = 0;
   @Current_id_system = 0;
   @MismatchingComplName = 0;
   for (my $i = 0; $i <= $#UserSets_id_system; $i++) {
      if (($i<$#UserSets_id_system)&&($UserSets_id_system[$i]==$UserSets_id_system[$i+1])){next}
      else {
         for my $k(0..$#User_id_systemF1) {
         #3.5.4.3.   Если номер системы в файле найден, то определяем номер соответствующей 
          #системы базового стенда и записываем его в переменную Base_id_system[i]. 
          #Поиск осуществляем в первой части файла (в левом столбце).
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
         }#конец вложенного for
      }#конец else 
   }#конец for
   foreach my $value (@Not_Inherited_Num) {
      if (! $seen{$value}) {
         #push @unique, $value;
         $MissingSysName[$Not_I_counter] = $dbh->selectall_arrayref(qq(SELECT DISTINCT system.name FROM system WHERE system.id_system="$value" ));
	 $seen{$value} = 1; 
	 $Not_I_counter++;}}

#3.5.5.   Открываем файл Pxx000@current_user (создаем манипулятор файла FILE2).
#3.5.5.1.   Если файл отсутствует, вывод ошибки в статусную строку: 
 #"Отсутствует файл-описатель наследования Pxx000@current_user".
if (not defined (open ($FILE2, "/mnt/Data/inheritance/P$current_parent->[0][0]\@$current_user"))) {
   my $NoFile="Отсутствует файл-описатель наследования P$current_parent->[0][0]\@$current_user";
   Insert_status_str($NoFile);  }
else {   
   @file2 = <$FILE2>;
   close($FILE2);
   for my $i(1..$#file2) {
      chomp $file2[$i] ;
      if ($file2[$i] eq 'parm') {last;}
      ($Base_id_systemF2[$i-1], $Current_id_systemF2[$i-1]) = split(/\t/,$file2[$i],2);
   }#конец for
   
   #3.5.5.2.   Если файл найден, то в цикле по Base_id_system[i] ищем в файле, 
    #среди систем базового стенда xx000, данную систему. Поиск осуществляем в 
    #первой части файла (в левом столбце).
   for (my $i = 0; $i <= $#Base_id_system; $i++) {
   for my $k(0..$#Base_id_systemF2) {

       #3.5.5.3.   Если номер системы в файле найден, то ищем номер соответствующей системы 
        #в текущем виртуальном стенде и записываем его в переменную в Current_id_system[count2]. 
        #Поиск осуществляем в первой части файла (в правом столбце).
       if ($Base_id_system[$i]!=0) { 
          if ($Base_id_system[$i]==$Base_id_systemF2[$k]) {
               $Current_id_system[$count2] = $Current_id_systemF2[$k];
               $count2++;
               last; }#конец if
               #3.5.5.4.   Если номер системы в файле отсутствует, 
                #то в переменную Current_id_system[count2] сохраняем 0.
            elsif (($k==$#Base_id_systemF2)&&($Base_id_system[$i]!=$Base_id_systemF2[$k])) {
               $Current_id_system[$count2] = 0;
               $count2++;
               #3.5.5.4.1.   Номер соответствующий системы в базовом стенде 
                #(значение Base_id_system[i]) сохраняем в переменной MissingSysNum[countM].
               $MissingSysNum[$countM] = $Base_id_system[$i];
               $countM++;} #конец elsif
            
            else {next;}
      }
      if ($Base_id_system[$i]==0) {
          $Current_id_system[$count2] = 0;
          $count2++;
          last;}
      
   }}#конец for 

#3.5.5.4.2.   Для каждого номера системы в MissingSysNum[k], в БД базового стенда текущей 
 #родительской ветви находим имена систем - system.name, при условии что 
 #system.id_system = MissingSysNum[i], полученные имена систем записываем в MissingSysName[i].
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
    }#конец for
}#конец if

#3.5.6.   В цикле по переменной Current_id_system[i] запрашиваем в БД текущего виртуального 
 #стенда значение system.n_s_s (число комплектов), при условии, что system.id_system=Current_id_sytem[i].
 #Полученное значение сохраняем в переменной CurrentCompl[i].
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
      }#конец if
   else {$CurrentCompl[$i]->[0][0] = 0;}
          }#конец for

#Создаем массив значений id_system текущего виртуального стенда в соответствии со значениями 
#id_system  выбранного оператором виртуального стенда. Если система в текущем виртуальном стенде отсутствует, сохраняем 0.  
for my $i(0..$#UserSets_id_system) {
      for my $k(0..$#User_id_system) {
         if ($UserSets_id_system[$i]==$User_id_system[$k]) {
            $CurrentSets_id_system[$i] = $Current_id_system[$k];
            last;}#конец if
         elsif (($k==$#User_id_system)&&($UserSets_id_system[$i]!=$User_id_system[$k])) {
            $CurrentSets_id_system[$i] = 0;}
         else {next;}
      }# конец for
}#конец for

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

#3.5.6.1.   Если значение CurrentCompl[i] (число комплектов) отличается от значения 
 #UserCompl[i], то заносим номер системы в MismatchingComplNum[k], и разницу в количестве 
 #комплектов в MismatchingComplDiff[k].
for my $i(0..$#CurrentCompl) {
   if (($CurrentCompl[$i]->[0][0]!=0)&&($CurrentCompl[$i]->[0][0]!=$UserCompl[$i]->[0][0])) {
      $MismatchingComplNum[$countMismatch] = $UniqueCurrent_id_system[$i];
      $Mismatching_user[$countMismatch] = $UserCompl[$i]->[0][0];
      $Mismatching_current[$countMismatch] = $CurrentCompl[$i]->[0][0];
      $MismatchingComplDiff[$countMismatch] = ($CurrentCompl[$i]->[0][0]-$UserCompl[$i]->[0][0]);
      $countMismatch++;
      } #конец if
}#конец for

#3.5.6.2.   Также в БД текущего виртуального стенда находим имена всех систем, номера 
 #которых содержатся в MismatchingComplNum[k] - system.name, при условии что 
 #system.id_system = MismatchingComplNum[k], полученные имена систем записываем в MismatchingComplName[k].
$rc = $dbh->disconnect;
$dbh = DBI->connect_cached("DBI:mysql:$current_user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;

if ($#MismatchingComplNum!=-1) {
   for my $i(0..$#MismatchingComplNum) {
      $MismatchingComplName[$i] = $dbh->selectall_arrayref(qq(SELECT system.name FROM system WHERE system.id_system="$MismatchingComplNum[$i]" ));
   }#конец for
}#конец if

#
#3.5.7.   Если одна из переменных MissingSysNum или MismatchingComplNum не пуста, то выводится окно 
 #с заголовком "Ошибки импорта набора данных". 
if (($#MissingSysNum!=-1)||($#MismatchingComplNum!=-1)||($#MissingSysName!=-1)) {
   my $base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
   $base->title(decode('koi8r', "Ошибки импорта набора данных:"));
   $base->protocol('WM_DELETE_WINDOW', sub{ $base->destroy; } );
   if ($#MismatchingComplNum!=-1) { 
      $base->geometry("550x550");}
   else {$base->geometry("540x330");}
   my $Mframe=$base->Frame(@Tl_att);
	 $Mframe->pack(-anchor => 'center', -expand=>0,  -fill => 'none', -side => 'top');

#3.5.7.1.   Если переменная MissingSysNum не пуста, то в окне "Ошибки импорта набора данных" выводятся сообщения: "В текущем виртуальном 
 #стенде отсутствуют следующие системы:" далее в списке выводятся значения хэша MissingSys(включает в себя 
 #заголовок списка и имена отсутствующих систем)" .
   if ($#MissingSysName!=-1) {
       $MissingSys->{'-1,0'} = 'Имя системы: ';
       for my $i (0...$#MissingSysName) {
          $MissingSys->{"$i,0"} = $MissingSysName[$i]->[0][0];}
       foreach my $key (keys %$MissingSys) { $MissingSys->{$key} = decode('koi8r',$MissingSys->{$key}) }
       $Mframe->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 15,
       -pady => 10, -text => decode('koi8r',qq(В текущем виртуальном стенде отсутствуют следующие системы:)),
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
       }#конец if

#3.5.7.3.   Если переменная MismatchingComplNum не пуста, то выводится сообщение - : 
 #"Несоответствие количества комплектов в системе: MismatchingComplName[i], В стенде user - $Mismatching_user[$i] 
 #комплектов; в стенде current_user - $Mismatching_current комплектов".
   $MismatchingSys->{'-1,0'}= "Имя\nсистемы: "; $MismatchingSys->{'-1,1'} = "В стенде\n$user: "; $MismatchingSys->{'-1,2'} = "В стенде\n$current_user: ";
   if ($#MismatchingComplNum!=-1) {
      $Mframe->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35,
         -pady => 10, -text => decode('koi8r',qq(Несоответствие количества комплектов в системе :)),
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
   
   #3.5.7.4.   Далее оператор должен нажать одну из двух кнопок: "Продолжить" или "Отмена".

   #3.5.7.5.1.   Нажатие кнопки "Продолжить" вызывает функцию CheckSetsName с входным параметром 
   #$set_comment (имя выбранного оператором набора данных),  а также деактивирует кнопки "Продлжить" и "Отмена".
   $Continue_B = $Mframe->Button(-command => sub{ CheckSetsName($set_comment); $Continue_B->configure(-state => 'disabled'); 
   $Cancel_B->configure(-state => 'disabled'); }, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font},
   -text => decode('koi8r', qq(Продолжить)))->pack(-anchor => 'center', -pady => 25, -padx => 5, -side => 'left');
   
    #3.5.7.5.2.   Нажатие кнопки "Отмена" завершает работу функции, и пользователь возвращается в 
    #окно "Импорт наборов данных".
    $Cancel_B = $Mframe->Button(-command => sub{$base->destroy;}, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
    -text => decode('koi8r',qq(Отмена)))->pack(-anchor => 'e', -expand=>1, -pady => 25, -padx => 3, -side => 'right');
   
    #3.5.8.   Если переменные MismatchingComplNum и MissingSysNum обе пусты, то запускается функция 
    #CheckSetsName с входным параметром $set_comment (имя выбранного оператором набора данных).
   MainLoop;
}#конец if
else {CheckSetsName($set_comment)};
}} #конец else принадлежащих проверке наличия файлов-описателей наследования
}#конец CheckSysCompl

#CheckSetsName
#Назначение -- проверка наличия в текущем виртуальном стенде набора данных с именем, совпадающим с 
#именем импортируемого набора, с возможностью сохранить набор под новым именем.

#Входные параметры:
#set_comment - имя импортируемого набора данных
#current_user - имя текущего виртуального стенда
#Входные данные БД:
#sets - таблицы базы данных, содержащие описание всех наборов данных для текущего виртуального стенда.

#Выход:
#set_comment - новое имя импортируемого набора данных
sub CheckSetsName {

#3.6.1.   Проверяем наличие в БД текущего виртуального стенда набора данных с названием, 
#совпадающим с названием импортируемого набора данных, сохраненного под именем пользователя $SSRPuser

my $CheckName; #Переменная для проверки наличия в БД текущего виртуального стенда набора данных с названием, 
#совпадающим с названием импортируемого набора данных. В нее сохраняется sets.id набора данных с совпадающим именем, если такой 
#присутствовал в текущем виртуальном стенде. Если набора с совпадающем именем в текущем виртуальном 
#стенде не было, то значение переменной остается undef. 

my $Set_id = 0;
$text = decode('koi8r', $set_comment); #Переменная для сохранения имени при импорте набора под новым именем
my $dbh = DBI->connect_cached("DBI:mysql:$current_user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;
$CheckName = $dbh->selectall_arrayref(qq(SELECT sets.id FROM sets WHERE sets.comment="$set_comment" and target="$target" and sets.user="$SSRPuser"));
if ( $#{$CheckName}!=-1) {

   #3.6.2.   Если имя найдено, т.е. если есть поле sets.comment, значение которого совпадает 
    #со значением $sets_comment, то вызывается диалоговое графическое окно "Сохранить набор данных" .
   #Диалоговое окно "Сохранить набор данных" содержит следующую надпись: "В текущем виртуальном 
    #стенде уже есть набор данных с именем $sets_comment.". Окно содержит кнопки "Заменить", "Сохранить как" и "Отмена".
  my $base = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
  $base->title(decode('koi8r', "Сохранить набор данных"));
  $base->protocol('WM_DELETE_WINDOW', sub{ $base->destroy;});
  $base->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35, 
  -pady => 10, -text => decode('koi8r',qq(В текущем виртуальном стенде уже есть набор данных с именем $set_comment)), 
  -width => 400)->pack(-anchor => 'center', -pady => 10, -side => 'top');
   
   #3.6.2.1.   При нажатии кнопки "Заменить" происходит следующее:
   #3.6.2.1.1.   Сохраняем полученное ранее перемнной CheckName значение sets.id, при котором sets.comment = $set_comment в переменную Set_id.
   #3.6.2.1.2.   Вызывается функция Import с входным параметром Set_id.
   #3.6.2.1.3.   Закрывается диалоговое окно "Сохранить набор данных".
   $base->Button(-command => sub{$base->destroy; $Set_id = $CheckName->[0][0]; Import($Set_id); }, -state => 'normal', -borderwidth => 3, 
   -font => $INI{but_menu_font}, -text => decode('koi8r', qq(Заменить)))->pack(-anchor => 'w', -pady => 10, -padx => 20, -fill => 'x' ,-side => 'left');

   #3.6.2.2.   Нажатие кнопки "Сохранить как" диалогового окна "Сохранить набор данных" закрывает 
   #диалоговое окно "Сохранить набор данных" и выводит графическое окно "Придумайте новое имя импортируемому набору данных:".
   # Это окно содержит поле для ввода имени нового набора данных, а также кнопки "Сохранить" и "Отмена".
   $base->Button(-command => sub{NewName(); $base->destroy; }, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
   -text => decode('koi8r',qq(Сохранить как)))->pack(-anchor => 'center', -pady => 10, -padx => 20, -side => 'left');
   
   #Окно ввода нового имени набору данных
   sub NewName{ 
      my $newname = MainWindow->new(-borderwidth => 5, -relief => 'groove', -highlightcolor => "$INI{err_brd}", -highlightthickness => 5);
         $newname->title(decode('koi8r',"Введите имя набора данных"));
         $newname->protocol('WM_DELETE_WINDOW',sub{ $newname->destroy;});
         $newname->Message(-anchor => 'center', -font => $INI{err_font}, -foreground => "$INI{err_forg}", -justify => 'center', -padx => 35, 
         -pady => 5, -text => decode('koi8r',qq(Придумайте новое имя импортируемому набору данных:)), 
         -width => 400)->pack(-anchor => 'center', -pady => 5, -side => 'top');
         my $Newname = $newname->Entry(-justify => 'center', -borderwidth => 1, -textvariable => \$text, -font => $INI{ri_font}, 
         -state => 'normal', -background => 'white', -width => 15)->pack(-side => "top");
         $Newname->bind('<Return>'=> sub {
            
            #Если пользователь пытается сохранить пустую строку, 
             #вывод сообщения: "Нельзя сохранить набор данных, не задав комментарий для него!"
            unless (length($text)) { ErrMessage('Нельзя сохранить набор данных, не задав комментарий для него!'); return };
            $set_comment = encode('koi8r',$text); #koi8-r
            $newname->destroy; CheckSetsName($set_comment);});
         $newname->Button(-command => sub{
         unless (length($text)) { ErrMessage('Нельзя сохранить набор данных, не задав комментарий для него!'); return };
         $set_comment = encode('koi8r',$text); #koi8-r
         $newname->destroy; CheckSetsName($set_comment); }, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
         -text => decode('koi8r',qq(Сохранить)))->pack(-anchor => 'center', -pady => 15, -padx => 30, -side => 'left');
         
         #3.6.2.2.1.   После ввода оператором нового имени набора данных, при нажатии кнопки 
          #"Сохранить" происходит следующее:
         #3.6.2.2.1.1.   Введенное имя заносится в переменную set_comment.
         #3.6.2.2.1.2.   Закрывается графическое окно "Ввод имени набора данных".
         #3.6.2.2.1.3.   Рекурсивно вызывается функция CheckSetsName с новым значением входного параметра set_comment
         #3.6.2.2.2.   Нажатие кнопки "Отмена" графического окна  "Ввод имени набора данных" завершает 
          #работу функции, и пользователь возвращается в окно "Импорт наборов данных".
         $newname->Button(-command => sub{$newname->destroy;}, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
         -text => decode('koi8r',qq(Отмена)))->pack(-anchor => 'w', -pady => 15, -padx => 30, -fill => 'x', -side => 'right');
   }#конец NewName
   #3.6.2.3.   Нажатие кнопки "Отмена" в диалоговом окне "Сохранить набор данных" завершает работу функции, 
    #и оператор возвращается в окно "Импорт наборов данных".
   $base->Button(-command => sub{$base->destroy;}, -state => 'normal', -borderwidth => 3, -font => $INI{but_menu_font}, 
   -text => decode('koi8r',qq(Отмена)))->pack(-anchor => 'e', -pady => 10, -padx => 20, -side => 'left');
}#конец if

#3.6.3.   Если имя набора данных не найдено, то вызывается функция импорта набора данных Import с Set_id = 0.
else {$Set_id = 0; Import($Set_id);}
MainLoop;
}#конец CheckSetsName

#Import 
#Назначение -- формирование набора данных на базе импортируемого и запись его в БД текущего виртуального стенда.
sub Import {
my $Set_Index = $_[0];
Make4mass_for_current_set();

#3.7.1. Вызов функции Make4mass_for_current_set.
#3.7.2. Вызов функции CodeSet.
#3.7.3. Вызов функции InsertSet.
#
#3.8. Функция Make4mass_for_current_set.
#Назначение -- формирование набора массивов на базе импортируемого набора данных, для дальнейшего 
   #создания из них нового набора данных
#
#Входные параметры:
#SetsName -имя набора данных
#Set_id - id набора данных в текущем виртуальном стенде (0 или Old_set_id)
#current_user - имя текущего виртуального стенда
#SSRPuser - имя текущего пользователя программы Ядро ССРП/СТКД.
#xx000 - имя базового стенда текущей родительской ветви
#User_id_system[*] - список номеров систем, присутствующих в наборе данных, выбранном оператором
#Current_id_system[*] - список номеров систем текущего виртуального стенда, соответствующих массиву User_id_system[*]
#  
#В БД набор данных представлен в виде строки, где каждому параметру соответствуют 4 числа. В программе набор 
#данных описывается четырьмя соответствующими массивами.
#Набор данных, выбранный оператором, описывается следующими четырьмя массивами:
#1) UserSets_id_system[*] - список номеров систем, по одному значению на каждый параметр
#2) UserSetsComplNum[*] - список номеров комплектов систем, присутствующий в наборе данных, выбранном оператором
#3) UserSets_id_parm[*] - массив значений id_parm параметров, присутствующих в наборе данных, выбранном оператором
#4) UserSetsData[*] - массив значений параметра в выбранном оператором наборе данных
#
#Внутренние переменные:
#Для базового стенда текущей родительской ветви (используется только один массив из четырех):
#1) Base_id_parm[*] - массив значений id_parm соответствующих параметров
#
#Для текущего виртуального стенда:
#1)      CurrentSets_id_system[*] - список номеров соответствующих систем
#2)      CurrentSets_id_parm[*] - массив значений id_parm соответствующих параметров
#3)      CurrentSetsComplNum[*] - массив номеров комплектов соответствующих систем
#4)      CurrentSetsData[*] - массив значений параметров в новом наборе данных
sub Make4mass_for_current_set {
#3.8.1.  В функции CheckSysCompl было установлено соответствие между номерами систем в выбранном оператором и 
    #текущем виртуальном стенде соответственно (массивы User_id_system[*] и Current_id_system[*]). Используя это 
    #соответствие, в цикле по UserSets_id_system[i], заносим в переменную CurrentSets_id_system[i] номер системы 
    #текущего виртуального стенда, если система присутствует в импортируемом наборе данных. Если система отсутствует,
    #в переменную CurrentSets_id_system[i] записываем 0.
my @file3; #Значения id_parm парметров в выбранном оператором виртуальном стенде и базовом стенде, 
   #взятые из файла наследования Базовый стенд -> выбранный оператором вирутальный стенд  
my $FILE3; #Манипулятор файла наследования Базовый стенд -> выбранный оператором вирутальный стенд 
my @file4; #Значения id_parm парметров в выбранном оператором виртуальном стенде и базовом стенде, 
   #взятые из файла наследования Базовый стенд -> текущий вирутальный стенд  
my $FILE4; #Манипулятор файла наследования Базовый стенд -> текущий вирутальный стенд
my (@Base_id_parmF3, @User_id_parmF3); #Значения id_parm парметров в базовом стенде и выбранном оператором виртуальном стенде (из file3)
my (@Base_id_parmF4, @Current_id_parmF4); #Значения id_parm парметров в базовом стенде и текущем виртуальном стенде (из file4)
my $level; #Перенная для определения в какой части файла мы находимся. = 1 - Если находимся в части со значениями id_system и 
   #= 2 - Если находимся в части со значениями id_parm

   #Создаем массив значений id_system текущего виртуального стенда в соответствии со значениями 
   #id_system  выбранного оператором виртуального стенда. Если система в текущем виртуальном стенде отсутствует, сохраняем 0.  
   for my $i(0..$#UserSets_id_system) {
      for my $k(0..$#User_id_system) {
         if ($UserSets_id_system[$i]==$User_id_system[$k]) {
            $CurrentSets_id_system[$i] = $Current_id_system[$k];
            last;}#конец if
         elsif (($k==$#User_id_system)&&($UserSets_id_system[$i]!=$User_id_system[$k])) {
            $CurrentSets_id_system[$i] = 0;}
         else {next;}
      }# конец for
   }#конец for
                   
   #3.8.2.   Открываем файл-описатель наследования Pxx000@user (создаем манипулятор файла FILE3).
   if (defined(open ($FILE3, "/mnt/Data/inheritance/P$current_parent->[0][0]\@$user"))){
   @file3 = <$FILE3>;
   close($FILE3);
   my $file3counter = 0;
   (@Base_id_parmF3, @User_id_parmF3) = 0;
   my ($p,$c);
   for my $i(0..$#file3) {
      chomp $file3[$i] ;
      if ($file3[$i]=~/\d/) { # строка данных
          ($p,$c) = split /\t/,$file3[$i];
          if ($level==2) { 
             ($Base_id_parmF3[$file3counter], $User_id_parmF3[$file3counter]) = split(/\t/,$file3[$i],2);
              $file3counter++;
          }#конец if
       }#конец if 
       else { # строка-разделитель
             if ($file3[$i] eq 'system') { $level = 1 }
             elsif ($file3[$i] eq 'parm') { $level = 2 }
             elsif ($file3[$i] eq 'compl') { last } 
       }#конец else 
   }}#конец for
   
   #Если файл наследования отсутствовал выдача сообщения об ошибке в статусную строку: 
    #Отсутствует файл-описатель наследования Px000@user
   else {
      my $NoFile = "Отсутствует файл-описатель наследования P$current_parent->[0][0]\@$user";
      Insert_status_str($NoFile);}
      
   my $base = 0; #Счетчик числа параметров базового стенда в file3
   my @BaseSets_id_parm = 0; #Значение id_parm параметров в базовом стенде 
   
#3.8.2.1.   В цикле по UserSets_id_parm[i] ищем среди параметров виртуального стенда user (User_id_parmF3) id_parm данного параметра. 
    #Поиск осуществляем во второй части файла (в правом столбце).
    #3.8.2.2.   Если id_parm параметра в файле найден, то определяем id_parm соответствующего параметра базового стенда и 
    #записываем его в переменную BaseSets_id_parm[base]. Поиск осуществляем во второй части файла (в левом столбце).
   for my $i(0..$#UserSets_id_parm) {
      for my $k(0..$#User_id_parmF3) {
         if ($UserSets_id_parm[$i]==$User_id_parmF3[$k]) {
            $BaseSets_id_parm[$base] = $Base_id_parmF3[$k];
            $base++;
            last; }#конец if
         else {next;}
      }#конец for                 
   }#конец for             
   
   #3.8.4.   Открываем файл Pxx000@current_user (создаем манипулятор файла FILE4).
   open ($FILE4, "/mnt/Data/inheritance/P$current_parent->[0][0]\@$current_user");
   @file4 = <$FILE4>;
   close($FILE4);
   my $file4counter = 0;
   (@Base_id_parmF4, @Current_id_parmF4) = 0;
   my $count4 = 0;
   for my $i(0..$#file4) {
      chomp $file4[$i] ;
         if ($file4[$i]=~/\d/) { # строка данных
            if ($level==2) { 
               ($Base_id_parmF4[$file4counter], $Current_id_parmF4[$file4counter]) = split(/\t/,$file4[$i],2);
               $file4counter++;} #конец if
         }  #конец if 
         else { # строка-разделитель
            if ($file4[$i] eq 'system') { $level = 1 }
            elsif ($file4[$i] eq 'parm') { $level = 2 }
            elsif ($file4[$i] eq 'compl') { last } 
         }#конец else 
   }#конец for

   #3.8.4.1.   В цикле по BaseSets_id_parm[i] ищем среди параметров базового стенда xx000 id_parm данного параметра. 
      #Поиск осуществляем во второй части файла (в левом столбце).
   #3.8.4.2.   Если id_parm параметра в файле найден, то ищем id_parm соответствующего параметра в текущем виртуальном 
      #стенде и записываем его в переменную в CurrentSets_id_parm[count4].
   #3.8.4.3.   Если id_parm параметра в файле отсутствует, то в переменную CurrentSets_id_parm[count4] сохраняем 0.
   for (my $i = 0; $i <= $#BaseSets_id_parm; $i++) {
      for my $k(0..$#Base_id_parmF4) {
         if ($BaseSets_id_parm[$i]==$Base_id_parmF4[$k]) {
            $CurrentSets_id_parm[$count4] = $Current_id_parmF4[$k];
            $count4++;
            last; }#конец if
      elsif (($k==$#Base_id_parmF4)&&($BaseSets_id_parm[$i]!=$Base_id_parmF4[$k])) {
         $CurrentSets_id_parm[$count4] = 0;
         $count4++;
      }#конец elsif
      else {next;}
       }#конец for
   }#конец for
   
   #3.8.6.   Далее в цикле по i, для всех CurrentSets_id_parm[i] не равных 0, из соответствующих переменных, 
    #переносим значения номера комплекта (UserSetsComplNum[i]) и значения параметра (UserSetsData[i]) в 
    #CurrentSetsComplNum[i] и CurrentSetsData[i] соответственно.
   @CurrentSetsData = 0;
   @CurrentSetsComplNum = 0;
   for my $i(0..$#CurrentSets_id_parm) {
      if (($CurrentSets_id_parm[$i]!=0)&&(defined($UserSetsComplNum[$i])))   {
         $CurrentSetsComplNum[$i] = $UserSetsComplNum[$i];
         $CurrentSetsData[$i] = $UserSetsData[$i]; 
         }#конец if
	 else  {
            $CurrentSetsComplNum[$i] = 0;
            }#конец else
   }#конец for
   CodeSet();
   
#3.9.   Функция CodeSet
#Назначение - формирование строки нового набора данных для текущего виртуального стенда.
#Входные переменные:
#4 массива, описывающие содержимое импортируемого набора данных:
#CurrentSets_id_system[*] - массив номеров соответствующих систем текущего виртуального стенда
#CurrentSets_id_parm[*] - массив значений id_parm соответствующих параметров текущего виртуального стенда
#CurrentSetsComplNum[*] - массив номеров комплектов соответствующих систем текущего виртуального стенда
#CurrentSetsData[*] - массив значений параметра в новом наборе данных
#Выход:
#SetsData -  строка с новым набором данных.
   sub CodeSet {
       #3.9.1.   Из массивов CurrentSets_id_system[*], CurrentSetsComplNum[*], CurrentSets_id_parm[*], CurrentSetsData[*], 
       #при условии, что значение CurrentSets_id_parm[*] не равно 0, формируем строку нового набора данных SetsData.
      my $key;
      $data = '';
      for my $i (0..$#CurrentSetsData) {
         if($target eq "S") {
            if ((defined $CurrentSets_id_parm[$i])&&($CurrentSets_id_system[$i]!=0)&&($CurrentSets_id_parm[$i]!=0)&&($CurrentSetsComplNum[$i]!=0)) { 
               $key = Key($CurrentSets_id_system[$i], $CurrentSetsComplNum[$i], $CurrentSets_id_parm[$i]);
               $data.=sprintf("$key:%08X\n",($CurrentSetsData[$i]));}} #конец if
         elsif($target eq "Q") {
            if ((defined $CurrentSets_id_parm[$i])&&($CurrentSets_id_system[$i]!=0)&&($CurrentSets_id_parm[$i]!=0)&&($CurrentSetsComplNum[$i]!=0)) { 
            $key=Key($CurrentSets_id_system[$i],$CurrentSetsComplNum[$i],$CurrentSets_id_parm[$i]);
            $data.=sprintf("$key:$CurrentSetsData[$i]\n");}#конец if 
         }#конец elsif   
       else {next;}
      }#конец for 
   }#конец CodeSet

   sub Key {
      my ($sys,$set,$prm) = @_;
      return (sprintf('%03i',$sys).$set.sprintf('%i',$prm)) }
}#конец Make4mass_for_current_set

InsertSet($Set_Index);

#3.10.   Функция InsertSet.
#Назначение - создание новой записи в таблице sets БД текущего виртуального стенда.
#
#Входные переменные:
#target - значение поля sets.target ("S" или "Q")
#Set_id - значение поля sets.id нового набора данных в текущем виртуальном стенде
#SetsData - строка нового набора данных
#
#Выход: новая запись в таблице sets текущего виртуального стенда.
sub InsertSet {
my $Set_Index = $_[0];
my $dbh = DBI->connect_cached("DBI:mysql:$current_user:$ENV{MYSQLHOST}", 'CMKtest', undef) || die $DBI::errstr;

#Получаем значение текущего времени
my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();

#3.10.1.   Если значение переменной Set_id = 0, то создается новая запись в  таблице sets БД текущего виртуального стенда:
$born_time = sprintf ("%02d%02d%02d%02d%02d",($year-100), ($mon+1), $mday, $hour, $min) ;
if ($Set_Index==0) {
   #       в поле sets.born_time заносится текущее время
   #       в поле sets.target заносится значение переменной target
   #       в поле sets.user заносится значение переменной SSRPuser
   #       в поле sets.data заносится новый набор данных SetsData.
   
   if (defined($dbh->do(qq(INSERT INTO sets (id,user,born_time,comment,target,data) VALUES (0,"$SSRPuser","$born_time","$set_comment","$target","$data"))))) {
      my $ScRecord = "Импорт набора данных \"$set_comment\" из стенда $user успешно завершен!";
      Insert_status_str($ScRecord);} 
   else {
      my $Failed_rec="Не удалось записать набор данных \"$set_comment\" в таблицу $current_user.sets";
      Insert_status_str($Failed_rec);}
}#конец if

#3.10.2.   Если значение переменной Set_id != 0, то изменяется запись в таблице sets, для которой выполняется условие sets.id=Set_id:
else { 
   if(defined($dbh->do(qq(UPDATE sets SET user="$SSRPuser", born_time="$born_time", data="$data" WHERE id="$Set_Index" AND target="$target")))) {

   #       в поле sets.comment заносится значение переменной SetsName
   #       в поле sets.born_time заносится текущее время
   #       в поле sets.target заносится значение переменной target
   #       в поле sets.user заносится значение переменной SSRPuser
   #       в sets.data заносится новый набор данных SetsData.
  
  #3.10.3.   Если операция записи в БД завершена успешно, то выдается сообщение в статусную строку: 
  #"Импорт набора данных SetsName успешно завершен!" и оператор возвращается в окно "Импорт набора данных".
   my $ScRecord = "Импорт набора данных \"$set_comment\" из стенда $user успешно завершен!";
   Insert_status_str($ScRecord);}
   
  #3.10.4.   Если операция записи в БД не удалась, то выводится сообщение об ошибке в статусную строку: 
  #"Не удалось записать набор данных "SetsName" в таблицу "current_user".sets".
    else {
      my $Failed_rec = "Не удалось записать набор данных \"$set_comment\" в таблицу $current_user.sets";
      Insert_status_str($Failed_rec);}
   }#конец else
}#конец InsertSet
}#конец Import

#Подпрограмма очистки и ввода новой информации в статусную строку 
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
#Конец

